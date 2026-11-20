import Foundation

/// Traduction via l'API DeepL (clé gratuite « …:fx » ou clé Pro).
nonisolated struct DeepLTranslator: LyricsTranslator {
    /// Langues sources acceptées par DeepL (sinon détection automatique).
    private static let sourceLanguages: Set<String> = [
        "AR", "BG", "CS", "DA", "DE", "EL", "EN", "ES", "ET", "FI", "HE", "HU", "ID", "IT", "JA",
        "KO", "LT", "LV", "NB", "NL", "PL", "PT", "RO", "RU", "SK", "SL", "SV", "TH", "TR", "UK", "VI", "ZH",
    ]
    private static let batchSize = 50   // limite DeepL par requête

    func translate(lines: [String], from source: Locale.Language,
                   progress: (@Sendable (Int, String) -> Void)?) async throws -> [String] {
        guard let key = KeychainStore.load(), !key.isEmpty else { throw TranslationFailure.missingAPIKey }

        let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        let code = (source.languageCode?.identifier ?? "").uppercased()
        let sourceLang = Self.sourceLanguages.contains(code) ? code : nil
        // Le morceau entier sert de contexte (non facturé) pour garder le sens d'une ligne à l'autre.
        let context = lines.joined(separator: "\n")

        var result: [String] = []
        for start in stride(from: 0, to: lines.count, by: Self.batchSize) {
            let chunk = Array(lines[start..<min(start + Self.batchSize, lines.count)])
            result += try await request(chunk, key: key, host: host, sourceLang: sourceLang, context: context)
        }
        return result
    }

    /// Consommation du mois : (caractères utilisés, limite). Sert aussi à tester la clé.
    static func usage(key: String) async throws -> (used: Int, limit: Int) {
        let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        var request = URLRequest(url: URL(string: "https://\(host)/v2/usage")!)
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw TranslationFailure.api(status == 403 ? "Clé refusée par DeepL." : "DeepL a répondu \(status).")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (json?["character_count"] as? Int ?? 0, json?["character_limit"] as? Int ?? 0)
    }

    private func request(_ texts: [String], key: String, host: String, sourceLang: String?, context: String) async throws -> [String] {
        var body: [String: Any] = [
            "text": texts,
            "target_lang": "FR",
            "context": context,
            "preserve_formatting": true,
            "split_sentences": "nonewlines",
        ]
        if let sourceLang { body["source_lang"] = sourceLang }

        var request = URLRequest(url: URL(string: "https://\(host)/v2/translate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 403: throw TranslationFailure.api("DeepL : clé API refusée.")
        case 429: throw TranslationFailure.api("DeepL : trop de requêtes, réessaie dans un instant.")
        case 456: throw TranslationFailure.api("DeepL : quota mensuel épuisé.")
        default:
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw TranslationFailure.api("DeepL : \(json?["message"] as? String ?? "erreur HTTP \(status)")")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let translations = (json?["translations"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        guard translations.count == texts.count else {
            throw TranslationFailure.lineCountMismatch(expected: texts.count, got: translations.count)
        }
        return translations
    }
}
