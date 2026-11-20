import Foundation

/// Client de l'API publique https://lrclib.net (sans clé).
nonisolated struct LRCLIBClient: Sendable {
    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    enum Failure: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self { case .http(let c): "LRCLIB a répondu \(c)" }
        }
    }

    private let base = URL(string: "https://lrclib.net/api")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "MusicTrad/1.0 (usage personnel)"]
        return URLSession(configuration: config)
    }()

    /// Renvoie les paroles, ou nil si rien n'a été trouvé.
    /// Si la réponse directe n'est pas synchronisée (ou que son timing ne colle pas à la durée),
    /// on cherche une meilleure version parmi les autres enregistrements.
    /// Quand plusieurs versions synchronisées existent, on prend celle sur laquelle la majorité
    /// s'accorde (la réponse directe est parfois une copie décalée).
    func lyrics(for track: TrackInfo) async throws -> Lyrics? {
        let direct = try await get(track).flatMap(Self.convert)
        if let direct, direct.isInstrumental { return direct }
        // Copies identiques gardées : elles comptent comme des « votes » pour le bon timing.
        let others = (try? await alternatives(for: track, unique: false)) ?? []
        let good = others.filter { $0.syncCheck(duration: track.duration) == .synced }
        if let direct, direct.syncCheck(duration: track.duration) == .synced {
            return Lyrics.consensus([direct] + good) ?? direct
        }
        return Lyrics.consensus(good) ?? good.first ?? direct ?? others.first
    }

    /// Toutes les versions trouvées, de la plus fiable à la moins fiable, sans doublons.
    func alternatives(for track: TrackInfo, unique: Bool = true) async throws -> [Lyrics] {
        let all = try await search(track).compactMap(Self.convert)
        guard unique else { return all }
        var seen = Set<String>()
        return all.filter { seen.insert($0.fullText).inserted }
    }

    private func get(_ track: TrackInfo) async throws -> Record? {
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        return try await fetch(path: "get", items: items, as: Record.self)
    }

    private func search(_ track: TrackInfo) async throws -> [Record] {
        let items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        var results = try await fetch(path: "search", items: items, as: [Record].self) ?? []
        if results.isEmpty {
            let q = [URLQueryItem(name: "q", value: "\(track.artist) \(track.title)")]
            results = try await fetch(path: "search", items: q, as: [Record].self) ?? []
        }
        // Durée proche (±10 s si connue).
        let candidates = results.filter { r in
            guard track.duration > 0, let d = r.duration else { return true }
            return abs(d - track.duration) <= 10
        }
        // Classement : synchro cohérente > texte brut > synchro douteuse > instrumental,
        // puis durée la plus proche (une autre version décale tout le timing).
        func rank(_ r: Record) -> (Int, Double) {
            let gap = track.duration > 0 ? abs((r.duration ?? .infinity) - track.duration) : 0
            guard let lyrics = Self.convert(r) else { return (9, gap) }
            if lyrics.isInstrumental { return (3, gap) }
            switch lyrics.syncCheck(duration: track.duration) {
            case .synced: return (0, gap)
            case .unsynced: return (1, gap)
            case .tooLong, .endsEarly: return (2, gap)
            }
        }
        return candidates.sorted { rank($0) < rank($1) }
    }

    private func fetch<T: Decodable>(path: String, items: [URLQueryItem], as: T.Type) async throws -> T? {
        let url = base.appending(path: path).appending(queryItems: items)
        let (data, response) = try await session.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func convert(_ r: Record) -> Lyrics? {
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return Lyrics(lines: lines, isSynced: true, isInstrumental: false, source: "LRCLIB", revision: Lyrics.currentRevision) }
        }
        if let plain = r.plainLyrics, !plain.isEmpty {
            return Lyrics(lines: LRCParser.plain(plain), isSynced: false, isInstrumental: false, source: "LRCLIB", revision: Lyrics.currentRevision)
        }
        if r.instrumental == true {
            return Lyrics(lines: [], isSynced: false, isInstrumental: true)
        }
        return nil
    }
}
