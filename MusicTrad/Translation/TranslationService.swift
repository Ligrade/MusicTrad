import Foundation
import NaturalLanguage

/// Traduction ligne à ligne : renvoie exactement autant de lignes qu'en entrée.
nonisolated protocol LyricsTranslator: Sendable {
    func translate(lines: [String], from source: Locale.Language) async throws -> [String]
}

nonisolated enum TranslationFailure: LocalizedError {
    case languageNotDetected
    case unsupportedPair(String)
    case needsDownload(Locale.Language)
    case missingAPIKey
    case api(String)
    case lineCountMismatch(expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .languageNotDetected: "Langue des paroles non reconnue."
        case .unsupportedPair(let l): "La traduction \(l) → français n'est pas prise en charge par Apple."
        case .needsDownload: "Le modèle de langue doit être téléchargé."
        case .missingAPIKey: "Aucune clé API DeepL enregistrée (Réglages)."
        case .api(let m): m
        case .lineCountMismatch(let e, let g): "Traduction incomplète (\(g) lignes au lieu de \(e))."
        }
    }
}

nonisolated enum LanguageDetector {
    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage, lang != .undetermined else { return nil }
        return Locale.Language(identifier: lang.rawValue)
    }
}

nonisolated extension Locale.Language {
    static let french = Locale.Language(identifier: "fr")
    var isFrench: Bool { languageCode?.identifier == "fr" }
    var displayName: String {
        Locale.current.localizedString(forLanguageCode: languageCode?.identifier ?? "") ?? minimalIdentifier
    }
}
