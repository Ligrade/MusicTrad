import Foundation

enum TranslationStatus: Equatable {
    case idle
    case translating
    case partial([String])       // en cours, lignes déjà traduites (les autres vides)
    case done([String])          // aligné sur Lyrics.lines
    case alreadyFrench
    case needsDownload(Locale.Language, Locale.Language)   // source, cible
    case failed(String)
}

/// Traductions : cache disque, appel au moteur choisi et index de la bibliothèque.
/// Ne touche jamais à l'affichage : c'est AppState qui décide de ce qui est montré.
final class TranslationStore {
    enum Outcome {
        case french
        case translated([String])
    }

    private let cache = DiskCache(folder: "translations")
    private var tasks: [String: Task<[String], Error>] = [:]

    static func key(_ t: TrackInfo, _ lyrics: Lyrics, _ engine: TranslationEngine,
                    _ target: Locale.Language = .french) -> String {
        "\(engine.rawValue)|\(target.languageCode?.identifier ?? "fr")|v2|\(LyricsStore.key(for: t))|\(lyrics.fullText.hashValueStable)"
    }

    /// Traduction déjà en cache et alignée sur les paroles, notée au passage dans la bibliothèque
    /// (si la langue d'origine est connue).
    func cached(_ track: TrackInfo, lyrics: Lyrics, engine: TranslationEngine,
                target: Locale.Language, source: Locale.Language?) -> [String]? {
        let key = Self.key(track, lyrics, engine, target)
        guard let lines = cache.load([String].self, key: key), lines.count == lyrics.lines.count else { return nil }
        if let source {
            Self.index(track, key: key, lines: lines, source: source, target: target)
        }
        return lines
    }

    /// Traduction depuis le cache ou le moteur choisi, sans toucher à l'affichage.
    func fetch(_ track: TrackInfo, lyrics: Lyrics, engine: TranslationEngine,
               target: Locale.Language = .french,
               onLine: (@MainActor (Int, String) -> Void)? = nil) async throws -> Outcome {
        guard let source = LanguageDetector.detect(lyrics.fullText) else { throw TranslationFailure.languageNotDetected }
        if source.sameLanguage(as: target) { return .french }

        if let hit = cached(track, lyrics: lyrics, engine: engine, target: target, source: source) {
            return .translated(hit)
        }
        let key = Self.key(track, lyrics, engine, target)
        if let running = tasks[key] { return .translated(try await running.value) }

        // On ne traduit que les lignes non vides, en gardant la correspondance.
        let indices = lyrics.lines.indices.filter { !lyrics.lines[$0].isBlank }
        let input = indices.map { lyrics.lines[$0].text }
        let count = lyrics.lines.count
        let task = Task { [cache] () throws -> [String] in
            let translator: LyricsTranslator = engine == .deepl ? DeepLTranslator() : AppleTranslator()
            let output = try await translator.translate(lines: input, from: source, to: target) { i, text in
                guard let onLine, indices.indices.contains(i) else { return }
                let line = indices[i]
                Task { @MainActor in onLine(line, text) }
            }
            var aligned = Array(repeating: "", count: count)
            for (i, idx) in indices.enumerated() { aligned[idx] = output[i] }
            cache.save(aligned, key: key, label: "\(track.artist) – \(track.title) [\(engine.rawValue), \(source.minimalIdentifier) → \(target.minimalIdentifier)]")
            Self.index(track, key: key, lines: aligned, source: source, target: target)
            return aligned
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        return .translated(try await task.value)
    }

    /// Bibliothèque des sons traduits : note cette traduction dans l'index (enregistrée ou relue depuis le cache).
    private static func index(_ track: TrackInfo, key: String, lines: [String],
                              source: Locale.Language, target: Locale.Language) {
        guard lines.contains(where: { !$0.isEmpty }) else { return }
        LibraryIndex.shared.record(artist: track.artist, title: track.title, album: track.album,
                                   lyricsFile: DiskCache.fileName(for: LyricsStore.key(for: track)),
                                   translationFile: DiskCache.fileName(for: key),
                                   source: source.minimalIdentifier.lowercased(),
                                   target: target.minimalIdentifier.lowercased())
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
