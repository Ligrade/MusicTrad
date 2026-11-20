import CryptoKit
import Foundation

/// Une entrée du cache, datée : création et dernière écoute (pour le nettoyage),
/// plus un libellé lisible (« Artiste – Titre ») pour s'y retrouver dans le dossier.
nonisolated struct CacheEnvelope<Value: Codable>: Codable {
    var createdAt: Date
    var lastUsedAt: Date
    var label: String?
    var value: Value
}

/// Seulement les dates, pour le nettoyage (sans décoder le contenu).
nonisolated struct CacheDates: Decodable {
    let createdAt: Date
    let lastUsedAt: Date
}

/// Cache JSON sur disque : ~/Library/Application Support/MusicTrad/Cache/<dossier>/<sha256>.json
nonisolated struct DiskCache: Sendable {
    let folder: String

    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "MusicTrad/Cache", directoryHint: .isDirectory)
    }

    static let folders = ["lyrics", "translations", "artwork"]

    /// La date de dernière écoute n'est réécrite qu'une fois par jour au plus.
    private static let touchInterval: TimeInterval = 24 * 3600

    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var directory: URL { Self.root.appending(path: folder, directoryHint: .isDirectory) }
    private func url(for key: String) -> URL { directory.appending(path: Self.fileName(for: key)) }

    func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        let url = url(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }

        if var entry = try? Self.decoder.decode(CacheEnvelope<T>.self, from: data) {
            if Date().timeIntervalSince(entry.lastUsedAt) > Self.touchInterval {
                entry.lastUsedAt = Date()
                write(entry, to: url)
            }
            return entry.value
        }

        // Ancien format (valeur brute, sans dates) : on le convertit au passage.
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        write(CacheEnvelope(createdAt: created, lastUsedAt: Date(), label: nil, value: value), to: url)
        return value
    }

    func save<T: Codable>(_ value: T, key: String, label: String? = nil) {
        let now = Date()
        write(CacheEnvelope(createdAt: now, lastUsedAt: now, label: label, value: value), to: url(for: key))
    }

    private func write<T: Codable>(_ entry: CacheEnvelope<T>, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(entry).write(to: url, options: .atomic)
        } catch {
            print("Cache: écriture impossible – \(error)")
        }
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
