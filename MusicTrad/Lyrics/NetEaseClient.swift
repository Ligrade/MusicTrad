import Foundation

/// Deuxième source de paroles synchronisées : l'API publique de NetEase Cloud Music (sans clé).
/// Utile quand LRCLIB n'a qu'un timing faux ou pas de version synchronisée.
nonisolated struct NetEaseClient: Sendable {
    private struct SearchResponse: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        let result: Result?
    }
    private struct Song: Decodable {
        struct Artist: Decodable { let name: String }
        let id: Int
        let name: String
        let artists: [Artist]
        let duration: Int   // millisecondes
    }
    private struct LyricResponse: Decodable {
        struct Body: Decodable { let lyric: String? }
        let lrc: Body?
    }

    private let session: URLSession = {
        // Sans cookies : avec un cookie de session, NetEase renvoie des résultats sans rapport.
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 4   // source de secours : ne jamais faire attendre les paroles
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh)", "Referer": "https://music.163.com/"]
        return URLSession(configuration: config)
    }()

    /// Versions synchronisées trouvées (3 au plus), de la durée la plus proche à la plus éloignée.
    func versions(for track: TrackInfo) async -> [Lyrics] {
        var components = URLComponents(string: "https://music.163.com/api/search/get")!
        components.queryItems = [
            URLQueryItem(name: "s", value: "\(track.artist) \(track.title)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "15"),
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let songs = (try? JSONDecoder().decode(SearchResponse.self, from: data))?.result?.songs else { return [] }

        let title = track.title.normalizedForMatch
        let artist = track.artist.normalizedForMatch
        let matches = songs.filter { song in
            guard song.name.normalizedForMatch == title,
                  song.artists.contains(where: { $0.name.normalizedForMatch == artist }) else { return false }
            guard track.duration > 0 else { return true }
            return abs(Double(song.duration) / 1000 - track.duration) <= 10
        }
        .sorted { abs(Double($0.duration) / 1000 - track.duration) < abs(Double($1.duration) / 1000 - track.duration) }
        .prefix(3)

        var result: [Lyrics] = []
        for song in matches {
            if let lyrics = await lyrics(id: song.id) { result.append(lyrics) }
        }
        return result
    }

    private func lyrics(id: Int) async -> Lyrics? {
        guard let url = URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=1"),
              let (data, _) = try? await session.data(from: url),
              let lrc = (try? JSONDecoder().decode(LyricResponse.self, from: data))?.lrc?.lyric,
              !lrc.isEmpty else { return nil }
        // Lignes de crédits (« 作词 : … », « 作曲 : … ») retirées, puis renumérotées.
        let credit = /^\s*[^\x00-\x7F]{1,8}\s*[:：]/
        let lines = LRCParser.parse(lrc)
            .filter { $0.text.prefixMatch(of: credit) == nil }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
        guard lines.filter({ !$0.isBlank }).count >= 3 else { return nil }   // « musique pure », vide…
        return Lyrics(lines: lines, isSynced: true, isInstrumental: false, source: "NetEase", revision: Lyrics.currentRevision)
    }
}

/// Regroupe les sources : LRCLIB d'abord, NetEase si LRCLIB n'a rien de cohérent.
nonisolated struct LyricsFinder: Sendable {
    private let lrclib = LRCLIBClient()
    private let netease = NetEaseClient()

    func best(for track: TrackInfo) async throws -> Lyrics? {
        // NetEase interrogé en même temps que LRCLIB : s'il faut s'en servir, la réponse est déjà là.
        async let fromNetEase = netease.versions(for: track)
        let fromLRCLIB: Lyrics?
        do { fromLRCLIB = try await lrclib.lyrics(for: track) } catch { fromLRCLIB = nil }
        if let l = fromLRCLIB, l.isInstrumental || l.syncCheck(duration: track.duration) == .synced {
            return l.withInstrumentalBreaks()
        }
        let other = await fromNetEase
        if let good = other.first(where: { $0.syncCheck(duration: track.duration) == .synced }) {
            return good.withInstrumentalBreaks()
        }
        return (fromLRCLIB ?? other.first)?.withInstrumentalBreaks()
    }

    /// Toutes les versions, toutes sources confondues, sans doublons.
    func allVersions(for track: TrackInfo) async -> [Lyrics] {
        async let a = (try? await lrclib.alternatives(for: track)) ?? []
        async let b = netease.versions(for: track)
        var seen = Set<String>()
        return (await a + b).filter { seen.insert($0.fullText).inserted }.map { $0.withInstrumentalBreaks() }
    }
}
