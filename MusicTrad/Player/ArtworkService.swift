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
    func libraryArtwork(artist: String, title: String, album: String? = nil) async -> Data? {
        let key = "library|\(artist)|\(title)"
        if let cached = cache.load(Data.self, key: key) { return cached }
        // Pochette déjà gardée quand le son a joué (fournie par Musique).
        if let album, !album.isEmpty, let cached = cache.load(Data.self, key: "\(artist)|\(album)") { return cached }
        // Sinon iTunes (même artiste exigé), puis Deezer, qui a beaucoup de groupes absents d'iTunes en France.
        var data: Data?
        if let item = await searchSong(artist: artist, title: title),
           (item.artistName ?? "").normalizedForMatch == artist.normalizedForMatch,
           let small = item.artworkUrl100,
           let url = URL(string: small.replacingOccurrences(of: "100x100bb", with: "200x200bb")) {
            data = try? await URLSession.shared.data(from: url).0
        }
        if data.flatMap(NSImage.init(data:)) == nil {
            data = await deezerCover(artist: artist, title: title)
        }
        guard let data, NSImage(data: data) != nil else { return nil }
        cache.save(data, key: key, label: "\(artist) – \(title)")
        return data
    }

    private struct DeezerResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let cover_medium: String? }
            let title: String
            let artist: Artist
            let album: Album
        }
        let data: [Item]
    }

    /// Pochette via l'API publique Deezer (sans compte), même artiste exigé.
    private func deezerCover(artist: String, title: String) async -> Data? {
        var components = URLComponents(string: "https://api.deezer.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(artist) \(title)"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(DeezerResponse.self, from: data) else { return nil }
        let a = artist.normalizedForMatch, t = title.normalizedForMatch
        let sameArtist = response.data.filter { $0.artist.name.normalizedForMatch == a }
        guard let item = sameArtist.first(where: { $0.title.normalizedForMatch == t }) ?? sameArtist.first,
              let cover = item.album.cover_medium, let coverURL = URL(string: cover) else { return nil }
        return try? await URLSession.shared.data(from: coverURL).0
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
        guard let link = await albumItem(for: track)?.collectionViewUrl else { return nil }
        return URL(string: link.replacingOccurrences(of: "https://", with: "music://"))
    }

    private func albumItem(for track: TrackInfo, exactAlbum: Bool = false) async -> SearchResponse.Item? {
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
        if let item = sameArtist.first(where: { ($0.collectionName ?? "").normalizedForMatch == album }) { return item }
        if exactAlbum {
            // Variantes du nom (« Deluxe », « First Pressing »…) : l'un contient l'autre.
            return sameArtist.first {
                let name = ($0.collectionName ?? "").normalizedForMatch
                return !name.isEmpty && !album.isEmpty && (name.contains(album) || album.contains(name))
            }
        }
        return sameArtist.first ?? response.results.first
    }

    /// Pochette animée de l'album (vidéo HLS d'Apple Music), lue sur la page publique de l'album.
    /// nil si l'album n'en a pas. Le résultat (même « aucune ») est gardé en cache.
    func motionArtwork(for track: TrackInfo) async -> URL? {
        let key = "motion|\(track.artist)|\(track.album)"
        if let cached = cache.load(String.self, key: key) { return cached.isEmpty ? nil : URL(string: cached) }
        guard let link = await albumItem(for: track, exactAlbum: true)?.collectionViewUrl,
              let page = URL(string: link) else { return nil }
        var request = URLRequest(url: page)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let found = Self.motionVideo(in: html)
        cache.save(found?.absoluteString ?? "", key: key, label: "Pochette animée \(track.artist) – \(track.album)")
        return found
    }

    /// Cherche « "motionDetailSquare":{… "video":"https://….m3u8" » dans les données de la page.
    static func motionVideo(in html: String) -> URL? {
        guard let square = html.range(of: "\"motionDetailSquare\"") else { return nil }
        let rest = html[square.upperBound...].prefix(4000)
        guard let video = rest.range(of: "\"video\":\"") else { return nil }
        let tail = rest[video.upperBound...]
        guard let end = tail.firstIndex(of: "\"") else { return nil }
        let link = String(tail[..<end]).replacingOccurrences(of: "\\u002F", with: "/")
        guard link.hasPrefix("https://"), link.contains(".m3u8") else { return nil }
        return URL(string: link)
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
