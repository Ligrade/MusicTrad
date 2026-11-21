import AppKit
import Foundation

/// Pochette du morceau : d'abord celle fournie par Musique, sinon l'API publique iTunes Search.
nonisolated struct ArtworkService: Sendable {
    let runner: AppleScriptRunner
    private let cache = DiskCache(folder: "artwork")
    private let memory = LastArtwork()

    func artwork(for track: TrackInfo) async -> Data? {
        let album = "\(track.artist)|\(track.album)".normalizedForMatch
        if let data = await runner.artworkData(), NSImage(data: data) != nil {
            // Pour les morceaux en streaming (« URL track »), Musique renvoie parfois encore la
            // pochette du morceau précédent : mêmes octets pour un autre album → on l'ignore.
            if memory.isStale(data, album: album) == false {
                memory.remember(data, album: album)
                return data
            }
        }
        let key = "\(track.artist)|\(track.album)"
        if let cached = cache.load(Data.self, key: key) { return cached }
        guard let data = await searchITunes(track) else { return nil }
        cache.save(data, key: key, label: "\(track.artist) – \(track.album)")
        return data
    }

    /// Pochette d'un son de la bibliothèque (sans passer par Musique, qui donnerait celle du son en cours).
    func libraryArtwork(artist: String, title: String) async -> Data? {
        let key = "library|\(artist)|\(title)"
        if let cached = cache.load(Data.self, key: key) { return cached }
        guard let item = await searchSong(artist: artist, title: title),
              let small = item.artworkUrl100,
              let url = URL(string: small.replacingOccurrences(of: "100x100bb", with: "200x200bb")),
              let (data, _) = try? await URLSession.shared.data(from: url),
              NSImage(data: data) != nil else { return nil }
        cache.save(data, key: key, label: "\(artist) – \(title)")
        return data
    }

    /// Lien « music:// » vers le son dans Apple Music (quand il n'est pas dans la bibliothèque).
    func songURL(artist: String, title: String) async -> URL? {
        guard let link = await searchSong(artist: artist, title: title)?.trackViewUrl else { return nil }
        return URL(string: link.replacingOccurrences(of: "https://", with: "music://"))
    }

    private func searchSong(artist: String, title: String) async -> SearchResponse.Item? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "FR"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        let a = artist.normalizedForMatch, t = title.normalizedForMatch
        let sameArtist = response.results.filter { ($0.artistName ?? "").normalizedForMatch == a }
        return sameArtist.first { ($0.trackName ?? "").normalizedForMatch == t }
            ?? sameArtist.first ?? response.results.first
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let artistName: String?
            let collectionName: String?
            let artworkUrl100: String?
            let collectionViewUrl: String?
            var trackName: String? = nil
            var trackViewUrl: String? = nil
        }
        let results: [Item]
    }

    private struct ArtistResponse: Decodable {
        struct Item: Decodable { let artistName: String?; let artistLinkUrl: String? }
        let results: [Item]
    }

    /// Lien « music:// » vers la page de l'artiste dans l'app Musique (via iTunes Search).
    func artistURL(for track: TrackInfo) async -> URL? {
        // Artiste principal seulement (« A & B », « A feat. B » → A).
        let main = track.artist
            .components(separatedBy: CharacterSet(charactersIn: "&,")).first?
            .components(separatedBy: " feat").first?
            .trimmingCharacters(in: .whitespaces) ?? track.artist
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: main),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "FR"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(ArtistResponse.self, from: data) else { return nil }
        let wanted = main.normalizedForMatch
        let item = response.results.first { ($0.artistName ?? "").normalizedForMatch == wanted } ?? response.results.first
        guard let link = item?.artistLinkUrl else { return nil }
        return URL(string: link.replacingOccurrences(of: "https://", with: "music://"))
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
        let artist = track.artist.normalizedForMatch
        let album = track.album.normalizedForMatch
        let sameArtist = response.results.filter { ($0.artistName ?? "").normalizedForMatch == artist }
        let item = sameArtist.first { ($0.collectionName ?? "").normalizedForMatch == album }
            ?? sameArtist.first ?? response.results.first
        guard let small = item?.artworkUrl100,
              let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
              let (image, _) = try? await URLSession.shared.data(from: big),
              NSImage(data: image) != nil else { return nil }
        return image
    }
}

/// Dernière pochette acceptée venant de Musique, pour repérer une pochette restée bloquée.
nonisolated final class LastArtwork: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var album: String?

    func isStale(_ new: Data, album newAlbum: String) -> Bool {
        lock.withLock { data == new && album != newAlbum }
    }

    func remember(_ new: Data, album newAlbum: String) {
        lock.withLock { data = new; album = newAlbum }
    }
}
