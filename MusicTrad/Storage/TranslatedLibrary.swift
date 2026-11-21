import Foundation

/// Un son déjà traduit, tel que listé par l'index de la bibliothèque (sans le texte, lu à l'ouverture).
nonisolated struct LibraryEntry: Identifiable, Hashable, Sendable {
    let id: String            // « Artiste – Titre »
    let artist: String
    let title: String
    let album: String?
    let source: String        // code de la langue d'origine (« en », « fr »…)
    let target: String        // code de la langue de traduction
    let lastUsed: Date
    /// Fichier des paroles et de la traduction affichée (la plus récemment écoutée).
    let lyricsFile: String
    let translationFile: String
    /// Fichiers de traduction de ce son, toutes versions (pour la supprimer depuis la bibliothèque).
    let translationFiles: [String]

    /// Fichiers du cache de ce son (paroles, traduction, pochette), à protéger s'il est en favori.
    var files: [String] {
        [lyricsFile, translationFile, DiskCache.fileName(for: "library|\(artist)|\(title)")]   // pochette de la bibliothèque
    }

    var pair: String { "\(Locale.Language.pillCode(source)) → \(Locale.Language.pillCode(target))" }
    var sourceIsFrench: Bool { source == "fr" }

    init?(record: LibraryIndex.Record) {
        guard let best = record.best else { return nil }
        id = record.id
        artist = record.artist
        title = record.title
        album = record.album
        source = best.source
        target = best.target
        lastUsed = best.lastUsed
        lyricsFile = record.lyricsFile
        translationFile = best.file
        translationFiles = record.translations.map(\.file)
    }
}

/// Paroles et traduction d'un son de la bibliothèque, alignées ligne à ligne.
nonisolated struct LibraryContent: Sendable {
    let lyrics: Lyrics
    let translation: [String]
}

nonisolated enum TranslatedLibrary {
    /// Les paroles que suit cette traduction : avec les pauses « ♪ » ajoutées (ou, pour les anciens caches, sans).
    /// Nil si elles ne correspondent pas (ou si rien n'est traduit).
    static func aligned(_ raw: Lyrics, _ translation: [String]) -> Lyrics? {
        guard !raw.isInstrumental, !raw.lines.isEmpty, translation.contains(where: { !$0.isEmpty }) else { return nil }
        let withBreaks = raw.withInstrumentalBreaks()
        if translation.count == withBreaks.lines.count { return withBreaks }
        if translation.count == raw.lines.count { return raw }
        return nil
    }

    /// Lit les paroles et la traduction d'un son (hors du fil principal).
    /// Lecture seule : ne touche pas aux dates d'écoute.
    @concurrent
    static func content(for entry: LibraryEntry, root: URL = DiskCache.root) async -> LibraryContent? {
        func read<T: Codable>(_ type: T.Type, _ folder: String, _ name: String) -> T? {
            let url = root.appending(path: folder, directoryHint: .isDirectory).appending(path: name)
            return (try? Data(contentsOf: url))
                .flatMap { try? DiskCache.decoder.decode(CacheEnvelope<T>.self, from: $0) }?.value
        }
        guard let raw = read(Lyrics.self, "lyrics", entry.lyricsFile),
              let translation = read([String].self, "translations", entry.translationFile),
              let lyrics = aligned(raw, translation) else { return nil }
        return LibraryContent(lyrics: lyrics, translation: translation)
    }
}
