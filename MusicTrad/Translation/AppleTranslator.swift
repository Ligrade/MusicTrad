import Foundation
import Translation

/// Traduction sur l'appareil via le framework Translation d'Apple.
nonisolated struct AppleTranslator: LyricsTranslator {
    @concurrent func translate(lines: [String], from source: Locale.Language,
                               progress: (@Sendable (Int, String) -> Void)?) async throws -> [String] {
        let status = await LanguageAvailability().status(from: source, to: .french)
        switch status {
        case .installed: break
        case .supported: throw TranslationFailure.needsDownload(source)
        case .unsupported: throw TranslationFailure.unsupportedPair(source.displayName)
        @unknown default: throw TranslationFailure.unsupportedPair(source.displayName)
        }

        let session = TranslationSession(installedSource: source, target: .french)
        var out = Array(repeating: "", count: lines.count)

        // Strophes de 4 lignes : assez de contexte pour les phrases coupées, et les premières
        // traductions s'affichent en moins d'une seconde (le morceau entier prend ~10 s).
        let chunkSize = 4
        let chunks = stride(from: 0, to: lines.count, by: chunkSize).map { $0..<min($0 + chunkSize, lines.count) }
        let requests = chunks.enumerated().map {
            TranslationSession.Request(sourceText: lines[$0.element].joined(separator: "\n"),
                                       clientIdentifier: String($0.offset))
        }
        var leftovers: [Int] = []
        for try await response in session.translate(batch: requests) {
            guard let id = response.clientIdentifier, let c = Int(id), chunks.indices.contains(c) else { continue }
            let range = chunks[c]
            let parts = response.targetText
                .components(separatedBy: "\n")          // Apple double parfois les retours à la ligne
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if parts.count == range.count {
                for (k, i) in range.enumerated() {
                    out[i] = parts[k]
                    progress?(i, parts[k])
                }
            } else {
                leftovers += Array(range)
            }
        }

        // Strophes dont le découpage n'est pas retombé juste : ligne par ligne.
        if !leftovers.isEmpty {
            let single = leftovers.map {
                TranslationSession.Request(sourceText: lines[$0], clientIdentifier: String($0))
            }
            for try await response in session.translate(batch: single) {
                guard let id = response.clientIdentifier, let i = Int(id), out.indices.contains(i) else { continue }
                out[i] = response.targetText
                progress?(i, response.targetText)
            }
        }
        return out
    }
}
