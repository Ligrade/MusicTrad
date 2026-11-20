import AppKit
import Foundation
import Observation
import OSLog

enum LyricsStatus: Equatable {
    case idle
    case loading
    case loaded(Lyrics)
    case notFound
    case failed(String)
}

enum TranslationStatus: Equatable {
    case idle
    case translating
    case done([String])          // aligné sur Lyrics.lines
    case alreadyFrench
    case needsDownload(Locale.Language)
    case failed(String)
}

/// Coordonne lecteur → paroles → traduction.
@Observable
final class AppState {
    private(set) var playback: PlaybackState = .musicNotRunning
    private(set) var lyricsStatus: LyricsStatus = .idle
    private(set) var translationStatus: TranslationStatus = .idle
    private(set) var sourceLanguage: Locale.Language?
    private(set) var artwork: NSImage?
    /// Valeur affichée tout de suite après un clic, en attendant que Musique la confirme.
    private var favoriteOverride: (id: String, value: Bool)?
    private(set) var favoriteError: String?

    private let monitor = MusicPlayerMonitor()
    private let lrclib = LRCLIBClient()
    private let lyricsCache = DiskCache(folder: "lyrics")
    private let translationCache = DiskCache(folder: "translations")
    private var currentTrackID: String?
    private var loadTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private let artworkService: ArtworkService
    @ObservationIgnored private let nextTrackPredictor: NextTrackPredictor
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var protectionSignature: String?
    @ObservationIgnored private var lyricsTasks: [String: Task<Lyrics?, Error>] = [:]
    @ObservationIgnored private var translationTasks: [String: Task<[String], Error>] = [:]
    private static let log = Logger(subsystem: "fr.dynamicagence.MusicTrad", category: "prefetch")

    var track: TrackInfo? { playback.track }

    var lyrics: Lyrics? {
        if case .loaded(let l) = lyricsStatus { return l }
        return nil
    }

    var translations: [String]? {
        if case .done(let t) = translationStatus { return t }
        return nil
    }

    /// Légère avance pour que la ligne s'allume au moment où elle est chantée.
    var currentLineIndex: Int? { lyrics?.lineIndex(at: playback.position + Preferences.syncOffset) }

    var engine: TranslationEngine {
        TranslationEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.engine) ?? "") ?? .apple
    }

    init() {
        artworkService = ArtworkService(runner: monitor.runner)
        nextTrackPredictor = NextTrackPredictor(runner: monitor.runner)
        monitor.onUpdate = { [weak self] state in self?.handle(state) }
        monitor.start()
        // Nettoyage du cache au lancement puis une fois par jour.
        maintenanceTask = Task {
            while !Task.isCancelled {
                _ = await CacheManager.shared.prune(limitMB: Preferences.cacheLimitMB,
                                                    maxAgeDays: Preferences.cacheMaxAgeDays)
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    /// Les titres favoris gardent paroles, traduction et pochette même quand le cache est plein.
    private func updateFavoriteProtection() {
        guard let track, let lyrics else { return }
        let favorite = isFavorited
        let translationKey = Self.translationKey(track, lyrics, engine)
        let signature = "\(track.id)|\(favorite)|\(translationKey)|\(translations != nil)"
        guard signature != protectionSignature else { return }
        protectionSignature = signature
        CacheManager.shared.setProtected(favorite, song: Self.lyricsKey(track),
                                         cacheKeys: [Self.lyricsKey(track), translationKey, "\(track.artist)|\(track.album)"])
    }

    var isFavorited: Bool {
        guard let track else { return false }
        if let o = favoriteOverride, o.id == track.id { return o.value }
        return track.isFavorited
    }

    func toggleFavorite() {
        guard let track else { return }
        let newValue = !isFavorited
        favoriteOverride = (track.id, newValue)
        favoriteError = nil
        Task {
            if let error = await monitor.runner.setFavorited(newValue) {
                favoriteOverride = nil
                favoriteError = "Impossible de modifier le favori : \(error)"
                try? await Task.sleep(for: .seconds(4))
                favoriteError = nil
            }
        }
    }

    private func handle(_ state: PlaybackState) {
        playback = state
        if let o = favoriteOverride, state.track?.id != o.id || state.track?.isFavorited == o.value {
            favoriteOverride = nil   // Musique a confirmé (ou le morceau a changé)
        }
        defer { updateFavoriteProtection() }
        let id = state.track?.id
        guard id != currentTrackID else { return }
        currentTrackID = id
        loadTask?.cancel()
        lyricsStatus = .idle
        translationStatus = .idle
        sourceLanguage = nil
        artworkTask?.cancel()
        if let track = state.track {
            loadTask = Task { await load(track) }
            artworkTask = Task {
                let data = await artworkService.artwork(for: track)
                guard !Task.isCancelled, currentTrackID == track.id else { return }
                artwork = data.flatMap(NSImage.init(data:))
            }
        } else {
            artwork = nil
        }
    }

    // MARK: Lecture

    func send(_ command: PlayerCommand) { monitor.send(command) }

    // MARK: Paroles

    private func load(_ track: TrackInfo) async {
        if let cached = lyricsCache.load(Lyrics.self, key: Self.lyricsKey(track)) {
            lyricsStatus = .loaded(cached)
        } else {
            lyricsStatus = .loading
            do {
                let result = try await fetchLyrics(track)
                guard !Task.isCancelled else { return }
                guard let result else { lyricsStatus = .notFound; return }
                lyricsStatus = .loaded(result)
            } catch {
                guard !Task.isCancelled else { return }
                lyricsStatus = .failed(error.localizedDescription)
                return
            }
        }
        await translate(track)
        guard !Task.isCancelled else { return }
        prefetchNext(after: track)
    }

    /// Clé indépendante de l'artiste et de la durée, pour que le morceau préchargé
    /// (titre venant de Deezer) retombe sur la même entrée que celui lu par Musique.
    private static func lyricsKey(_ t: TrackInfo) -> String {
        "\(t.album.normalizedForMatch)|\(t.title.normalizedForMatch)"
    }

    /// Paroles depuis le cache ou LRCLIB. Les requêtes identiques en cours sont partagées
    /// (morceau préchargé qui devient le morceau en cours).
    private func fetchLyrics(_ track: TrackInfo) async throws -> Lyrics? {
        let key = Self.lyricsKey(track)
        if let cached = lyricsCache.load(Lyrics.self, key: key) { return cached }
        if let running = lyricsTasks[key] { return try await running.value }
        let task = Task { [lrclib, lyricsCache] () throws -> Lyrics? in
            let result = try await lrclib.lyrics(for: track)
            if let result { lyricsCache.save(result, key: key, label: "\(track.artist) – \(track.title)") }
            return result
        }
        lyricsTasks[key] = task
        defer { lyricsTasks[key] = nil }
        return try await task.value
    }

    // MARK: Traduction

    /// Relance la traduction du morceau en cours (changement de moteur, langue téléchargée…).
    func retranslate() {
        guard let track, lyrics != nil else { return }
        loadTask?.cancel()
        loadTask = Task { await translate(track) }
    }

    private enum TranslationOutcome {
        case french
        case translated([String])
    }

    private func translate(_ track: TrackInfo) async {
        guard let lyrics, !lyrics.isInstrumental else { return }
        let engine = self.engine
        if let cached = translationCache.load([String].self, key: Self.translationKey(track, lyrics, engine)),
           cached.count == lyrics.lines.count {
            sourceLanguage = LanguageDetector.detect(lyrics.fullText)
            translationStatus = .done(cached)
            return
        }
        sourceLanguage = LanguageDetector.detect(lyrics.fullText)
        if sourceLanguage?.isFrench != true { translationStatus = .translating }

        do {
            let outcome = try await fetchTranslation(track, lyrics: lyrics, engine: engine)
            guard !Task.isCancelled, currentTrackID == track.id else { return }
            switch outcome {
            case .french: translationStatus = .alreadyFrench
            case .translated(let lines): translationStatus = .done(lines)
            }
        } catch TranslationFailure.needsDownload(let lang) {
            translationStatus = .needsDownload(lang)
        } catch {
            guard !Task.isCancelled else { return }
            translationStatus = .failed(error.localizedDescription)
        }
    }

    private static func translationKey(_ t: TrackInfo, _ lyrics: Lyrics, _ engine: TranslationEngine) -> String {
        "\(engine.rawValue)|fr|\(lyricsKey(t))|\(lyrics.fullText.hashValueStable)"
    }

    /// Traduction depuis le cache ou le moteur choisi, sans toucher à l'affichage.
    private func fetchTranslation(_ track: TrackInfo, lyrics: Lyrics, engine: TranslationEngine) async throws -> TranslationOutcome {
        guard let source = LanguageDetector.detect(lyrics.fullText) else { throw TranslationFailure.languageNotDetected }
        if source.isFrench { return .french }

        let key = Self.translationKey(track, lyrics, engine)
        if let cached = translationCache.load([String].self, key: key), cached.count == lyrics.lines.count {
            return .translated(cached)
        }
        if let running = translationTasks[key] { return .translated(try await running.value) }

        // On ne traduit que les lignes non vides, en gardant la correspondance.
        let indices = lyrics.lines.indices.filter { !lyrics.lines[$0].isBlank }
        let input = indices.map { lyrics.lines[$0].text }
        let count = lyrics.lines.count
        let task = Task { [translationCache] () throws -> [String] in
            let translator: LyricsTranslator = engine == .deepl ? DeepLTranslator() : AppleTranslator()
            let output = try await translator.translate(lines: input, from: source)
            var aligned = Array(repeating: "", count: count)
            for (i, idx) in indices.enumerated() { aligned[idx] = output[i] }
            translationCache.save(aligned, key: key, label: "\(track.artist) – \(track.title) [\(engine.rawValue), \(source.minimalIdentifier) → fr]")
            return aligned
        }
        translationTasks[key] = task
        defer { translationTasks[key] = nil }
        return .translated(try await task.value)
    }

    // MARK: Préchargement

    /// Prépare paroles et traduction du morceau suivant pendant que celui-ci joue.
    private func prefetchNext(after track: TrackInfo) {
        prefetchTask?.cancel()
        guard Preferences.prefetchNext else { return }
        let engine = self.engine
        prefetchTask = Task {
            guard let next = await nextTrackPredictor.next(after: track), !Task.isCancelled else {
                Self.log.info("Préchargement : morceau suivant inconnu après « \(track.title, privacy: .public) »")
                return
            }
            Self.log.info("Préchargement : « \(next.title, privacy: .public) » (\(next.artist, privacy: .public))")
            do {
                guard let lyrics = try await fetchLyrics(next), !lyrics.isInstrumental else {
                    Self.log.info("Préchargement : pas de paroles pour « \(next.title, privacy: .public) »")
                    return
                }
                _ = try await fetchTranslation(next, lyrics: lyrics, engine: engine)
                Self.log.info("Préchargement terminé : « \(next.title, privacy: .public) » est en cache")
            } catch {
                Self.log.error("Préchargement échoué : \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension String {
    /// Empreinte stable entre les lancements (hashValue est aléatoire à chaque lancement).
    var hashValueStable: String {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }
}
