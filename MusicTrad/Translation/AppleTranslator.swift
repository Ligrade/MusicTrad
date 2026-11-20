import Foundation
import Translation

/// Traduction sur l'appareil via le framework Translation d'Apple.
nonisolated struct AppleTranslator: LyricsTranslator {
    @concurrent func translate(lines: [String], from source: Locale.Language) async throws -> [String] {
        let status = await LanguageAvailability().status(from: source, to: .french)
        switch status {
        case .installed: break
        case .supported: throw TranslationFailure.needsDownload(source)
        case .unsupported: throw TranslationFailure.unsupportedPair(source.displayName)
        @unknown default: throw TranslationFailure.unsupportedPair(source.displayName)
        }

        let session = TranslationSession(installedSource: source, target: .french)
        let requests = lines.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        let responses = try await session.translations(from: requests)

        var out = lines
        for r in responses {
            if let id = r.clientIdentifier, let i = Int(id), out.indices.contains(i) {
                out[i] = r.targetText
            }
        }
        return out
    }
}
