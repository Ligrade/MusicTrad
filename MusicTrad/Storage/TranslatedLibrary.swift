import Foundation

/// Un son déjà traduit, retrouvé dans le cache : paroles + traduction alignées ligne à ligne.
nonisolated struct LibraryEntry: Identifiable, Hashable, Sendable {
    let id: String            // « Artiste – Titre »
    let artist: String
    let title: String
    let lyrics: Lyrics
    let translation: [String]
    let source: String        // code de la langue d'origine (« en », « fr »…)
    let target: String        // code de la langue de traduction
    let lastUsed: Date
    /// Fichiers du cache de ce son (paroles, traduction, pochette), à protéger s'il est en favori.
    let files: [String]
    /// Fichiers de traduction de ce son, toutes versions (pour la supprimer depuis la bibliothèque).
    var translationFiles: [String]

    var pair: String { "\(source.uppercased()) → \(target.uppercased())" }
    var sourceIsFrench: Bool { source == "fr" }
}

/// Bibliothèque des sons traduits, reconstruite à partir des dossiers « lyrics » et « translations » du cache.
/// Lecture seule : n'écrit rien et ne touche pas aux dates d'écoute.
nonisolated enum TranslatedLibrary {
    static func load() -> [LibraryEntry] {
        let fm = FileManager.default
        func files(_ folder: String) -> [URL] {
            let dir = DiskCache.root.appending(path: folder, directoryHint: .isDirectory)
            return (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "json" } ?? []
        }

        // Paroles, par libellé « Artiste – Titre ».
        var lyricsByLabel: [String: Lyrics] = [:]
        var lyricsFile: [String: String] = [:]
        for url in files("lyrics") {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? DiskCache.decoder.decode(CacheEnvelope<Lyrics>.self, from: data),
                  let label = entry.label, !entry.value.isInstrumental, !entry.value.lines.isEmpty else { continue }
            lyricsByLabel[label] = entry.value
            lyricsFile[label] = url.lastPathComponent
        }

        var best: [String: LibraryEntry] = [:]
        var allTranslations: [String: [String]] = [:]
        for url in files("translations") {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? DiskCache.decoder.decode(CacheEnvelope<[String]>.self, from: data),
                  let label = entry.label,
                  let open = label.range(of: " [", options: .backwards), label.hasSuffix("]") else { continue }
            let base = String(label[..<open.lowerBound])
            // « apple, en → fr »
            let meta = label[open.upperBound...].dropLast()
            let languages = meta.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
            let parts = languages.components(separatedBy: " → ")
            guard parts.count == 2, let raw = lyricsByLabel[base],
                  entry.value.contains(where: { !$0.isEmpty }) else { continue }

            // La traduction suit les paroles avec les pauses « ♪ » ajoutées (ou, pour les anciens caches, sans).
            let withBreaks = raw.withInstrumentalBreaks()
            let lyrics: Lyrics
            if entry.value.count == withBreaks.lines.count { lyrics = withBreaks }
            else if entry.value.count == raw.lines.count { lyrics = raw }
            else { continue }

            let separator = base.range(of: " – ")
            let artist = separator.map { String(base[..<$0.lowerBound]) } ?? ""
            let title = separator.map { String(base[$0.upperBound...]) } ?? base
            let item = LibraryEntry(
                id: base,
                artist: artist,
                title: title,
                lyrics: lyrics,
                translation: entry.value,
                source: parts[0].lowercased(),
                target: parts[1].lowercased(),
                lastUsed: entry.lastUsedAt,
                files: [lyricsFile[base], url.lastPathComponent].compactMap { $0 }
                    + [DiskCache.fileName(for: "library|\(artist)|\(title)")],   // pochette de la bibliothèque
                translationFiles: []
            )
            allTranslations[base, default: []].append(url.lastPathComponent)
            if let existing = best[base], existing.lastUsed >= item.lastUsed { continue }
            best[base] = item
        }
        return best.values.map { entry in
            var entry = entry
            entry.translationFiles = allTranslations[entry.id] ?? []
            return entry
        }
        .sorted { $0.lastUsed > $1.lastUsed }
    }
}
