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
    case partial([String])       // en cours, lignes déjà traduites (les autres vides)
    case done([String])          // aligné sur Lyrics.lines
    case alreadyFrench
    case needsDownload(Locale.Language, Locale.Language)   // source, cible
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
    /// Morceau auquel appartient la pochette affichée : la pochette ne change (et ne s'anime)
    /// qu'une fois la nouvelle chargée, pour qu'elle prenne directement la place de l'ancienne.
    private(set) var artworkID: String?
    /// Sens de l'animation de la pochette : vrai après ⏮ (arrive par la gauche).
    private(set) var artworkFromLeading = false
    /// Valeur affichée tout de suite après un clic, en attendant que Musique la confirme.
    private var favoriteOverride: (id: String, value: Bool)?
    private(set) var favoriteError: String?

    private let monitor = MusicPlayerMonitor()
    private let finder = LyricsFinder()
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
        switch translationStatus {
        case .done(let t), .partial(let t): return t
        default: return nil
        }
    }

    /// Ligne chantée, recalculée 20 fois par seconde à partir d'une horloge locale
    /// (Musique n'est interrogée que toutes les 0,5 s). Légère avance réglable.
    private(set) var currentLineIndex: Int?
    /// Nombre de vues de paroles ouvertes (bulle, fenêtre flottante) : sans elles, l'app ralentit.
    @ObservationIgnored private var visibleViews = 0
    /// Dernière fois que la bulle ou la fenêtre était à l'écran (pour la mise en veille automatique).
    @ObservationIgnored private var lastUse = Date()

    func viewAppeared() {
        visibleViews += 1
        lastUse = .now
        monitor.interval = .milliseconds(500)
    }

    func viewDisappeared() {
        visibleViews = max(0, visibleViews - 1)
        lastUse = .now
        if visibleViews == 0 { monitor.interval = .milliseconds(1500) }
    }

    /// Dernière position lue dans Musique et l'instant de la lecture.
    @ObservationIgnored private var anchor = (position: TimeInterval(0), at: Date(), playing: false)
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Position estimée maintenant : dernière position lue + temps écoulé depuis.
    private var livePosition: TimeInterval {
        anchor.playing ? anchor.position + Date().timeIntervalSince(anchor.at) : anchor.position
    }

    @ObservationIgnored private var seekGuardUntil = Date.distantPast

    private func updateAnchor(_ state: PlaybackState, sameTrack: Bool) {
        let polled = state.position
        // Juste après un saut, une lecture partie avant le saut ne doit pas ramener en arrière.
        if sameTrack, Date() < seekGuardUntil, abs(polled - livePosition) > 1 { return }
        if sameTrack, state.isPlaying, anchor.playing {
            // Petit écart (latence d'AppleScript) : on se rapproche en douceur de la position de Musique,
            // dans les deux sens. Avant, l'horloge ne reculait jamais et finissait légèrement en avance.
            let estimate = livePosition
            let error = polled - estimate
            if abs(error) < 0.4 {
                anchor = (estimate + error * 0.3, Date(), true)
                return
            }
        }
        anchor = (polled, Date(), state.isPlaying)
    }

    /// Avancement (0 → 1) du passage instrumental en cours, pour l'animation ♪♪♪.
    private(set) var breakProgress: Double = 0

    private func refreshCurrentLine() {
        let position = livePosition + Preferences.syncOffset + songOffset
        let index = lyrics?.lineIndex(at: position)
        if index != currentLineIndex { currentLineIndex = index }
        if let index, let lines = lyrics?.lines, lines[index].isBlank, let start = lines[index].time,
           index + 1 < lines.count, let end = lines[index + 1].time, end > start {
            let p = min(max((position - start) / (end - start), 0), 1)
            if abs(p - breakProgress) >= 0.01 { breakProgress = p }
        } else if breakProgress != 0 {
            breakProgress = 0
        }
    }

    // MARK: AirPlay

    private(set) var airPlayDevices: [AirPlayDevice] = []
    /// Vrai si le son part ailleurs que sur le Mac (icône AirPlay colorée).
    var airPlayActive: Bool { airPlayDevices.contains { $0.selected && !$0.isComputer } }

    func refreshAirPlay() {
        Task { airPlayDevices = await monitor.runner.airPlayDevices() }
    }

    /// Clic sur une sortie : elle seule. Avec `addToGroup`, on l'ajoute ou la retire du groupe.
    func selectAirPlay(_ device: AirPlayDevice, addToGroup: Bool = false) {
        Task {
            if addToGroup {
                // On garde toujours au moins une sortie.
                if device.selected, airPlayDevices.filter(\.selected).count <= 1 { return }
                await monitor.runner.selectAirPlay(device.name, exclusive: false, selected: !device.selected)
            } else {
                await monitor.runner.selectAirPlay(device.name, exclusive: true)
            }
            airPlayDevices = await monitor.runner.airPlayDevices()
        }
    }

    // MARK: Lancer Musique

    /// Musique fermée : bouton « Ouvrir Musique ».
    func openMusic() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    /// Lien de « Ma station » collé dans les Réglages (Musique ne permet pas de la lancer par script).
    var myStationLink: URL? {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.myStationURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              raw.contains("music.apple.com"), raw.contains("/station/") else { return nil }
        return URL(string: raw.replacingOccurrences(of: "https://", with: "music://"))
    }

    /// Rien en lecture : ouvre « Ma station » grâce au lien enregistré dans les Réglages
    /// (Musique ne donne aucun autre moyen d'atteindre la station personnelle).
    func openMyStation() {
        guard let link = myStationLink else { return }
        NSWorkspace.shared.open(link)
    }

    /// Rien en lecture : lance les morceaux likés.
    func playFavorites() {
        Task { await monitor.runner.playFavorites() }
    }

    /// Paroles favorites de la bibliothèque (« Artiste – Titre ») : jamais supprimées par le nettoyage du cache.
    private(set) var libraryFavorites = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.libraryFavorites) ?? [])

    func toggleLibraryFavorite(_ entry: LibraryEntry) {
        let on = !libraryFavorites.contains(entry.id)
        if on { libraryFavorites.insert(entry.id) } else { libraryFavorites.remove(entry.id) }
        UserDefaults.standard.set(Array(libraryFavorites).sorted(), forKey: SettingsKey.libraryFavorites)
        CacheManager.shared.setProtected(on, song: "library|\(entry.id)", files: entry.files)
    }

    /// Son en cours dans les paroles favorites (cœur à côté de l'étoile) ?
    var currentLyricsFavorited: Bool {
        guard let track else { return false }
        return libraryFavorites.contains("\(track.artist) – \(track.title)")
    }

    /// Cœur : garde pour toujours les paroles, la traduction et la pochette du son en cours.
    func toggleCurrentLyricsFavorite() {
        guard let track, let lyrics, !lyrics.isInstrumental else { return }
        let id = "\(track.artist) – \(track.title)"
        let on = !libraryFavorites.contains(id)
        if on { libraryFavorites.insert(id) } else { libraryFavorites.remove(id) }
        UserDefaults.standard.set(Array(libraryFavorites).sorted(), forKey: SettingsKey.libraryFavorites)
        let keys = [Self.lyricsKey(track), Self.translationKey(track, lyrics, engine, translationTarget),
                    "\(track.artist)|\(track.album)", "library|\(track.artist)|\(track.title)"]
        CacheManager.shared.setProtected(on, song: "library|\(id)", files: keys.map(DiskCache.fileName(for:)))
    }

    /// Poubelle de la bibliothèque : supprime la traduction de ce son (et le retire des favoris).
    /// Elle sera refaite à la prochaine écoute.
    func deleteLibraryTranslation(_ entry: LibraryEntry) async {
        if libraryFavorites.remove(entry.id) != nil {
            UserDefaults.standard.set(Array(libraryFavorites).sorted(), forKey: SettingsKey.libraryFavorites)
            CacheManager.shared.setProtected(false, song: "library|\(entry.id)", files: [])
        }
        await CacheManager.shared.removeTranslations(entry.translationFiles)
    }

    /// Remet à jour la protection des favoris (les fichiers changent si un son est retraduit).
    func refreshLibraryProtection(_ entries: [LibraryEntry]) {
        for entry in entries where libraryFavorites.contains(entry.id) {
            CacheManager.shared.setProtected(true, song: "library|\(entry.id)", files: entry.files)
        }
    }

    /// Pochette d'un son de la bibliothèque des traductions.
    func libraryArtwork(_ entry: LibraryEntry) async -> NSImage? {
        await artworkService.libraryArtwork(artist: entry.artist, title: entry.title).flatMap(NSImage.init(data:))
    }

    /// Bibliothèque : lance le son tout de suite et revient aux paroles en direct.
    /// S'il n'est pas dans la bibliothèque Musique, ouvre sa page Apple Music.
    func playFromLibrary(_ entry: LibraryEntry) {
        libraryOpen = false   // retour immédiat aux paroles en direct
        Task {
            if await monitor.runner.play(title: entry.title, artist: entry.artist) {
                return
            } else if let url = await artworkService.songURL(artist: entry.artist, title: entry.title) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Clic sur l'artiste : ouvre sa page dans Musique.
    func openArtist() {
        guard let track else { return }
        Task {
            if let url = await artworkService.artistURL(for: track), NSWorkspace.shared.open(url) { return }
            await monitor.runner.revealCurrentTrack()
        }
    }

    /// Clic sur la pochette : ouvre l'album dans Musique.
    func openAlbum() {
        guard let track else { return }
        Task {
            if let url = await artworkService.albumURL(for: track), NSWorkspace.shared.open(url) { return }
            await monitor.runner.revealCurrentTrack()
        }
    }

    /// Mode « recaler » : le prochain clic sur une ligne indique ce qu'on entend en ce moment.
    private(set) var calibrating = false

    func startCalibration() { calibrating = true }
    func cancelCalibration() { calibrating = false }

    /// Clic sur une ligne : Musique repart au début de ce passage
    /// (ou, en mode recalage, la ligne devient celle chantée maintenant).
    func seek(to line: LyricLine) {
        guard let time = line.time, track != nil else { return }
        if calibrating {
            calibrating = false
            setSongOffset(time - livePosition - Preferences.syncOffset + 0.05)
            refreshCurrentLine()
            return
        }
        let target = max(0, time - songOffset)
        anchor = (target, Date(), anchor.playing)
        seekGuardUntil = Date().addingTimeInterval(1.5)
        refreshCurrentLine()
        monitor.seek(to: target)
    }

    // MARK: Vérification de la synchro

    /// Le timing des paroles colle-t-il à la durée du morceau ?
    var syncCheck: SyncCheck? {
        guard let track, let lyrics, !lyrics.isInstrumental else { return nil }
        return lyrics.syncCheck(duration: track.duration)
    }

    /// Décalage propre au morceau en cours (s'ajoute au réglage général).
    private(set) var songOffset: Double = 0
    private(set) var searchingVersion = false
    /// « version 2 sur 5 » après avoir essayé une autre version.
    private(set) var versionInfo: (index: Int, count: Int)?
    @ObservationIgnored private var versions: [Lyrics] = []
    @ObservationIgnored private var refreshedKeys: Set<String> = []
    private static let songOffsetsKey = "songSyncOffsets"

    func setSongOffset(_ value: Double) {
        guard let track else { return }
        songOffset = (value * 10).rounded() / 10
        var all = UserDefaults.standard.dictionary(forKey: Self.songOffsetsKey) as? [String: Double] ?? [:]
        all[Self.lyricsKey(track)] = songOffset == 0 ? nil : songOffset
        UserDefaults.standard.set(all, forKey: Self.songOffsetsKey)
    }

    private static func savedSongOffset(_ track: TrackInfo) -> Double {
        (UserDefaults.standard.dictionary(forKey: songOffsetsKey) as? [String: Double])?[lyricsKey(track)] ?? 0
    }

    /// Passe à la version suivante des paroles sur LRCLIB (album, radio edit, live…).
    func tryOtherVersion() {
        guard let track, let current = lyrics, !searchingVersion else { return }
        searchingVersion = true
        Task {
            defer { searchingVersion = false }
            if versions.isEmpty {
                versions = await finder.allVersions(for: track)
            }
            guard currentTrackID == track.id, !versions.isEmpty else { return }
            let start = versions.firstIndex { $0.fullText == current.fullText } ?? -1
            let next = (start + 1) % versions.count
            let chosen = versions[next]
            versionInfo = (next + 1, versions.count)
            guard chosen.fullText != current.fullText else { return }
            lyricsCache.save(chosen, key: Self.lyricsKey(track), label: "\(track.artist) – \(track.title)")
            LibraryIndex.shared.lyricsChanged(file: DiskCache.fileName(for: Self.lyricsKey(track)))
            lyricsStatus = .loaded(chosen)
            retranslate()
        }
    }

    var engine: TranslationEngine {
        TranslationEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.engine) ?? "") ?? .apple
    }

    init() {
        artworkService = ArtworkService(runner: monitor.runner)
        nextTrackPredictor = NextTrackPredictor(runner: monitor.runner)
        monitor.onUpdate = { [weak self] state in self?.handle(state) }
        monitor.interval = .milliseconds(1500)
        if !ecoMode { startWork() }
        // Nettoyage du cache au lancement puis une fois par jour.
        maintenanceTask = Task {
            while !Task.isCancelled {
                _ = await CacheManager.shared.prune(limitMB: Preferences.cacheLimitMB,
                                                    maxAgeDays: Preferences.cacheMaxAgeDays)
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    // MARK: Mode éco

    /// Mode éco : l'app reste dans la barre des menus mais ne fait plus rien
    /// (plus de lecture de Musique, d'horloge, de traduction ni de préchargement).
    private(set) var ecoMode = Preferences.ecoAtLaunch || UserDefaults.standard.bool(forKey: SettingsKey.ecoMode)

    func setEcoMode(_ on: Bool) {
        guard on != ecoMode else { return }
        ecoMode = on
        UserDefaults.standard.set(on, forKey: SettingsKey.ecoMode)
        if on {
            monitor.stop()
            ticker?.cancel(); ticker = nil
            loadTask?.cancel(); artworkTask?.cancel(); prefetchTask?.cancel()
            currentTrackID = nil
            playback = .stopped
            lyricsStatus = .idle
            translationStatus = .idle
            sourceLanguage = nil
            artwork = nil
            artworkID = nil
            currentLineIndex = nil
            calibrating = false
        } else {
            startWork()
        }
    }

    private func startWork() {
        monitor.start()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Mode éco automatique quand l'app n'a pas été regardée depuis le délai choisi.
                let idle = Preferences.autoEcoMinutes
                if idle > 0, self.visibleViews == 0, Date.now.timeIntervalSince(self.lastUse) > Double(idle) * 60 {
                    self.setEcoMode(true)
                    return
                }
                self.refreshCurrentLine()
                // 20 fois par seconde seulement quand on regarde des paroles synchronisées.
                let fast = self.visibleViews > 0 && self.playback.isPlaying && self.lyrics?.isSynced == true
                try? await Task.sleep(for: .milliseconds(fast ? 50 : 500))
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
        guard !ecoMode else { return }   // lecture partie juste avant le passage en éco
        updateAnchor(state, sameTrack: state.track?.id == currentTrackID)
        if state.withoutPosition != playback.withoutPosition { playback = state }
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
        versions = []
        versionInfo = nil
        calibrating = false
        songOffset = state.track.map(Self.savedSongOffset) ?? 0
        artworkTask?.cancel()
        if let track = state.track {
            loadTask = Task { await load(track) }
            artworkTask = Task {
                let data = await artworkService.artwork(for: track)
                guard !Task.isCancelled, currentTrackID == track.id else { return }
                artwork = data.flatMap(NSImage.init(data:))
                artworkID = track.id
                // Après l'animation, retour au sens normal (enchaînement auto = par la droite).
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { artworkFromLeading = false }
            }
        } else {
            artwork = nil
            artworkID = nil
        }
    }

    // MARK: Lecture

    func send(_ command: PlayerCommand) {
        // Le sens est fixé AVANT le changement de pochette : l'ancienne pochette doit déjà
        // porter la bonne transition au moment où elle sort.
        if command == .previous { artworkFromLeading = true }
        if command == .next { artworkFromLeading = false }
        monitor.send(command)
    }

    // MARK: Paroles

    private func load(_ track: TrackInfo) async {
        if let cached = lyricsCache.load(Lyrics.self, key: Self.lyricsKey(track))?.withInstrumentalBreaks() {
            lyricsStatus = .loaded(cached)
            await refreshIfDoubtful(cached, track: track)
            guard !Task.isCancelled else { return }
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

    /// Paroles en cache non synchronisées ou au timing douteux : une fois par session,
    /// on regarde si LRCLIB a mieux (cas des caches faits avant la vérification).
    private func refreshIfDoubtful(_ cached: Lyrics, track: TrackInfo) async {
        let key = Self.lyricsKey(track)
        // Aussi les caches faits avant le choix par consensus (revision < 2), une seule fois.
        let outdated = (cached.revision ?? 0) < Lyrics.currentRevision
        guard !cached.isInstrumental, outdated || cached.syncCheck(duration: track.duration) != .synced,
              refreshedKeys.insert(key).inserted,
              let fresh = try? await finder.best(for: track),
              fresh.syncCheck(duration: track.duration) == .synced,
              !Task.isCancelled, currentTrackID == track.id else { return }
        lyricsCache.save(fresh, key: key, label: "\(track.artist) – \(track.title)")
        LibraryIndex.shared.lyricsChanged(file: DiskCache.fileName(for: key))
        lyricsStatus = .loaded(fresh)
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
        if let cached = lyricsCache.load(Lyrics.self, key: key) { return cached.withInstrumentalBreaks() }
        if let running = lyricsTasks[key] { return try await running.value }
        let task = Task { [finder, lyricsCache] () throws -> Lyrics? in
            let result = try await finder.best(for: track)
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


    /// Pilule « EN → FR » barrée : aucune traduction, paroles originales seules (re-clic : on retraduit).
    private(set) var translationHidden = UserDefaults.standard.bool(forKey: SettingsKey.translationHidden)

    func toggleTranslationHidden() {
        translationHidden.toggle()
        UserDefaults.standard.set(translationHidden, forKey: SettingsKey.translationHidden)
        if translationHidden {
            // Arrête une traduction en cours (seulement si les paroles sont déjà là, pour ne pas couper leur chargement).
            if lyrics != nil { loadTask?.cancel() }
            if sourceLanguage?.isFrench != true { translationStatus = .idle }
        } else {
            retranslate()
        }
    }

    /// Bibliothèque des sons déjà traduits (pilule disque dur) : remplace les paroles par la liste.
    var libraryOpen = false

    /// Langue vers laquelle on traduit le morceau en cours.
    var translationTarget: Locale.Language {
        sourceLanguage?.isFrench == true && Preferences.frenchToEnglish ? .english : .french
    }

    /// Réglage « chansons en français → anglais » changé : on retraduit si le son en cours est en français.
    func frenchToEnglishChanged() {
        guard sourceLanguage?.isFrench == true else { return }
        retranslate()
    }

    private func translate(_ track: TrackInfo) async {
        guard let lyrics, !lyrics.isInstrumental else { return }
        let engine = self.engine
        sourceLanguage = LanguageDetector.detect(lyrics.fullText)
        let target = translationTarget
        // Traduction désactivée (pilule barrée) : rien à faire pour une chanson étrangère.
        if translationHidden, sourceLanguage?.isFrench != true {
            translationStatus = .idle
            return
        }
        let cachedKey = Self.translationKey(track, lyrics, engine, target)
        if let cached = translationCache.load([String].self, key: cachedKey), cached.count == lyrics.lines.count {
            if let sourceLanguage {
                Self.indexTranslation(track, key: cachedKey, lines: cached, source: sourceLanguage, target: target)
            }
            translationStatus = .done(cached)
            return
        }
        if sourceLanguage.map({ $0.sameLanguage(as: target) }) != true { translationStatus = .translating }

        do {
            let outcome = try await fetchTranslation(track, lyrics: lyrics, engine: engine, target: target) { [weak self] line, text in
                self?.showPartial(trackID: track.id, line: line, text: text, count: lyrics.lines.count)
            }
            guard !Task.isCancelled, currentTrackID == track.id else { return }
            switch outcome {
            case .french: translationStatus = .alreadyFrench
            case .translated(let lines): translationStatus = .done(lines)
            }
        } catch TranslationFailure.needsDownload(let lang) {
            translationStatus = .needsDownload(lang, target)
        } catch {
            guard !Task.isCancelled else { return }
            translationStatus = .failed(error.localizedDescription)
        }
    }

    /// Affiche une ligne traduite dès qu'elle arrive.
    private func showPartial(trackID: String, line: Int, text: String, count: Int) {
        guard currentTrackID == trackID else { return }
        var lines: [String]
        switch translationStatus {
        case .translating: lines = Array(repeating: "", count: count)
        case .partial(let current): lines = current
        default: return
        }
        guard lines.indices.contains(line) else { return }
        lines[line] = text
        translationStatus = .partial(lines)
    }

    private static func translationKey(_ t: TrackInfo, _ lyrics: Lyrics, _ engine: TranslationEngine,
                                       _ target: Locale.Language = .french) -> String {
        "\(engine.rawValue)|\(target.languageCode?.identifier ?? "fr")|v2|\(lyricsKey(t))|\(lyrics.fullText.hashValueStable)"
    }

    /// Traduction depuis le cache ou le moteur choisi, sans toucher à l'affichage.
    private func fetchTranslation(_ track: TrackInfo, lyrics: Lyrics, engine: TranslationEngine,
                                  target: Locale.Language = .french,
                                  onLine: (@MainActor (Int, String) -> Void)? = nil) async throws -> TranslationOutcome {
        guard let source = LanguageDetector.detect(lyrics.fullText) else { throw TranslationFailure.languageNotDetected }
        if source.sameLanguage(as: target) { return .french }

        let key = Self.translationKey(track, lyrics, engine, target)
        if let cached = translationCache.load([String].self, key: key), cached.count == lyrics.lines.count {
            Self.indexTranslation(track, key: key, lines: cached, source: source, target: target)
            return .translated(cached)
        }
        if let running = translationTasks[key] { return .translated(try await running.value) }

        // On ne traduit que les lignes non vides, en gardant la correspondance.
        let indices = lyrics.lines.indices.filter { !lyrics.lines[$0].isBlank }
        let input = indices.map { lyrics.lines[$0].text }
        let count = lyrics.lines.count
        let task = Task { [translationCache] () throws -> [String] in
            let translator: LyricsTranslator = engine == .deepl ? DeepLTranslator() : AppleTranslator()
            let output = try await translator.translate(lines: input, from: source, to: target) { i, text in
                guard let onLine, indices.indices.contains(i) else { return }
                let line = indices[i]
                Task { @MainActor in onLine(line, text) }
            }
            var aligned = Array(repeating: "", count: count)
            for (i, idx) in indices.enumerated() { aligned[idx] = output[i] }
            translationCache.save(aligned, key: key, label: "\(track.artist) – \(track.title) [\(engine.rawValue), \(source.minimalIdentifier) → \(target.minimalIdentifier)]")
            Self.indexTranslation(track, key: key, lines: aligned, source: source, target: target)
            return aligned
        }
        translationTasks[key] = task
        defer { translationTasks[key] = nil }
        return .translated(try await task.value)
    }

    /// Bibliothèque des sons traduits : note cette traduction dans l'index (enregistrée ou relue depuis le cache).
    private static func indexTranslation(_ track: TrackInfo, key: String, lines: [String],
                                         source: Locale.Language, target: Locale.Language) {
        guard lines.contains(where: { !$0.isEmpty }) else { return }
        LibraryIndex.shared.record(artist: track.artist, title: track.title, album: track.album,
                                   lyricsFile: DiskCache.fileName(for: lyricsKey(track)),
                                   translationFile: DiskCache.fileName(for: key),
                                   source: source.minimalIdentifier.lowercased(),
                                   target: target.minimalIdentifier.lowercased())
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
                if self.translationHidden { return }   // traduction désactivée : paroles seulement
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
