import Foundation

/// Devine le morceau suivant pour préparer ses paroles et sa traduction à l'avance.
/// Musique ne donne pas sa file d'attente aux scripts : on prend la playlist en cours quand elle
/// est accessible, sinon le titre suivant de l'album via l'API publique Deezer (sans clé).
nonisolated struct NextTrackPredictor: Sendable {
    let runner: AppleScriptRunner

    func next(after track: TrackInfo) async -> TrackInfo? {
        if let fromPlaylist = await runner.nextInPlaylist() { return fromPlaylist }
        return await nextOnAlbum(after: track)
    }

    // MARK: Deezer

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let id: Int; let title: String }
            let title: String
            let artist: Artist
            let album: Album
        }
        let data: [Item]?
    }

    private struct AlbumTracks: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            let title: String
            let duration: Int
            let track_position: Int
            let disk_number: Int
            let artist: Artist
        }
        let data: [Item]?
    }

    private func nextOnAlbum(after track: TrackInfo) async -> TrackInfo? {
        let title = track.title.normalizedForMatch
        let artist = track.artist.normalizedForMatch
        let album = track.album.normalizedForMatch

        var search = URLComponents(string: "https://api.deezer.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: "\(track.artist) \(title)"),
                             URLQueryItem(name: "limit", value: "10")]
        guard let results: SearchResponse = await get(search.url),
              let match = results.data?.first(where: {
                  $0.album.title.normalizedForMatch == album && $0.artist.name.normalizedForMatch == artist
              }) ?? results.data?.first(where: { $0.album.title.normalizedForMatch == album })
        else { return nil }

        guard let tracks: AlbumTracks = await get(URL(string: "https://api.deezer.com/album/\(match.album.id)/tracks?limit=200")),
              let list = tracks.data?.sorted(by: { ($0.disk_number, $0.track_position) < ($1.disk_number, $1.track_position) }),
              let index = list.firstIndex(where: { $0.title.normalizedForMatch == title }),
              list.indices.contains(index + 1)
        else { return nil }

        let next = list[index + 1]
        return TrackInfo(id: "prédit|\(next.title)", title: next.title, artist: next.artist.name,
                         album: track.album, duration: TimeInterval(next.duration))
    }

    private func get<T: Decodable>(_ url: URL?) async -> T? {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

nonisolated extension String {
    /// Forme simplifiée pour comparer des titres entre Musique, LRCLIB et Deezer :
    /// minuscules, sans accents, sans « (feat. …) », « [Remastered] » ni « - Single ».
    var normalizedForMatch: String {
        var s = lowercased().folding(options: .diacriticInsensitive, locale: nil)
        s = s.replacing(/\s*[\(\[][^\)\]]*[\)\]]/, with: "")
        s = s.replacing(/\s+-\s+.*$/, with: "")
        return s.trimmingCharacters(in: .whitespaces)
    }
}
