import AppKit
import Foundation

/// Pochette du morceau : d'abord celle fournie par Musique, sinon l'API publique iTunes Search.
nonisolated struct ArtworkService: Sendable {
    let runner: AppleScriptRunner
    private let cache = DiskCache(folder: "artwork")

    func artwork(for track: TrackInfo) async -> Data? {
        if let data = await runner.artworkData(), NSImage(data: data) != nil { return data }
        let key = "\(track.artist)|\(track.album)"
        if let cached = cache.load(Data.self, key: key) { return cached }
        guard let data = await searchITunes(track) else { return nil }
        cache.save(data, key: key, label: "\(track.artist) – \(track.album)")
        return data
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let artistName: String?
            let collectionName: String?
            let artworkUrl100: String?
            let collectionViewUrl: String?
        }
        let results: [Item]
    }

    /// Lien « music:// » vers l'album du morceau dans l'app Musique (via iTunes Search).
    func albumURL(for track: TrackInfo) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "FR"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        let artist = track.artist.normalizedForMatch
        let album = track.album.normalizedForMatch
        let sameArtist = response.results.filter { ($0.artistName ?? "").normalizedForMatch == artist }
        let item = sameArtist.first { ($0.collectionName ?? "").normalizedForMatch == album }
            ?? sameArtist.first ?? response.results.first
        guard let link = item?.collectionViewUrl else { return nil }
        return URL(string: link.replacingOccurrences(of: "https://", with: "music://"))
    }

    private func searchITunes(_ track: TrackInfo) async -> Data? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        let artist = track.artist.lowercased()
        let item = response.results.first { ($0.artistName ?? "").lowercased() == artist } ?? response.results.first
        guard let small = item?.artworkUrl100,
              let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
              let (image, _) = try? await URLSession.shared.data(from: big),
              NSImage(data: image) != nil else { return nil }
        return image
    }
}
