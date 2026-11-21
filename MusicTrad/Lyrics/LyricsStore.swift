import Foundation

enum LyricsStatus: Equatable {
    case idle
    case loading
    case loaded(Lyrics)
    case notFound
    case failed(String)
}

/// Paroles : cache disque, recherche (LRCLIB puis NetEase) et décalage propre à chaque morceau.
/// Ne touche jamais à l'affichage : c'est AppState qui décide de ce qui est montré.
final class LyricsStore {
    private let finder = LyricsFinder()
    private let cache = DiskCache(folder: "lyrics")
    private var tasks: [String: Task<Lyrics?, Error>] = [:]
    /// Paroles déjà revérifiées pendant cette session (une seule fois par morceau).
    private var refreshedKeys: Set<String> = []
    private static let songOffsetsKey = "songSyncOffsets"

    /// Clé indépendante de l'artiste et de la durée, pour que le morceau préchargé
    /// (titre venant de Deezer) retombe sur la même entrée que celui lu par Musique.
    static func key(for t: TrackInfo) -> String {
        "\(t.album.normalizedForMatch)|\(t.title.normalizedForMatch)"
    }

    /// Paroles en cache, sans aucune requête.
    func cached(_ track: TrackInfo) -> Lyrics? {
        cache.load(Lyrics.self, key: Self.key(for: track))?.withInstrumentalBreaks()
    }

    /// Paroles depuis le cache ou LRCLIB. Les requêtes identiques en cours sont partagées
    /// (morceau préchargé qui devient le morceau en cours).
    func fetch(_ track: TrackInfo) async throws -> Lyrics? {
        let key = Self.key(for: track)
        if let cached = cache.load(Lyrics.self, key: key) { return cached.withInstrumentalBreaks() }
        if let running = tasks[key] { return try await running.value }
        let task = Task { [finder, cache] () throws -> Lyrics? in
            let result = try await finder.best(for: track)
            if let result { cache.save(result, key: key, label: "\(track.artist) – \(track.title)") }
            return result
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }

    /// Toutes les versions trouvées sur LRCLIB (album, radio edit, live…).
    func allVersions(for track: TrackInfo) async -> [Lyrics] {
        await finder.allVersions(for: track)
    }

    /// Paroles en cache non synchronisées ou au timing douteux : une fois par session,
    /// on regarde si LRCLIB a mieux (cas des caches faits avant la vérification).
    /// Renvoie la meilleure version, sans l'enregistrer.
    func betterVersionIfDoubtful(_ cached: Lyrics, track: TrackInfo) async -> Lyrics? {
        let key = Self.key(for: track)
        // Aussi les caches faits avant le choix par consensus (revision < 2), une seule fois.
        let outdated = (cached.revision ?? 0) < Lyrics.currentRevision
        guard !cached.isInstrumental, outdated || cached.syncCheck(duration: track.duration) != .synced,
              refreshedKeys.insert(key).inserted,
              let fresh = try? await finder.best(for: track),
              fresh.syncCheck(duration: track.duration) == .synced else { return nil }
        return fresh
    }

    /// Remplace les paroles en cache (autre version, meilleur timing) et prévient la bibliothèque.
    func replace(_ lyrics: Lyrics, for track: TrackInfo) {
        let key = Self.key(for: track)
        cache.save(lyrics, key: key, label: "\(track.artist) – \(track.title)")
        LibraryIndex.shared.lyricsChanged(file: DiskCache.fileName(for: key))
    }

    // MARK: Décalage propre au morceau

    static func savedOffset(for track: TrackInfo) -> Double {
        (UserDefaults.standard.dictionary(forKey: songOffsetsKey) as? [String: Double])?[key(for: track)] ?? 0
    }

    static func saveOffset(_ offset: Double, for track: TrackInfo) {
        var all = UserDefaults.standard.dictionary(forKey: songOffsetsKey) as? [String: Double] ?? [:]
        all[key(for: track)] = offset == 0 ? nil : offset
        UserDefaults.standard.set(all, forKey: songOffsetsKey)
    }
}
