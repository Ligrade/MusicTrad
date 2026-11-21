import Foundation
import OSLog

/// Garde le cache sous contrôle :
/// 1. supprime ce qui n'a pas été écouté depuis la durée choisie (3 mois par défaut) ;
/// 2. au-delà de la limite de taille, supprime d'abord le moins récemment écouté ;
/// 3. ne touche jamais aux fichiers des titres favoris.
nonisolated final class CacheManager: @unchecked Sendable {
    static let shared = CacheManager()

    static let limitChoices = [25, 50, 100, 250, 500]   // Mo
    static let defaultLimitMB = 50
    /// Durées de conservation sans écoute, en jours (3 mois au plus ; les favoris restent toujours).
    static let maxAgeChoices: [(days: Int, label: String)] = [
        (14, "2 semaines"), (30, "1 mois"), (60, "2 mois"), (90, "3 mois"),
    ]
    static let defaultMaxAgeDays = 90

    struct Stats: Sendable {
        let bytes: Int64
        let songs: Int
        let protectedSongs: Int
        let oldestUse: Date?
    }

    private let queue = DispatchQueue(label: "fr.dynamicagence.MusicTrad.cache", qos: .utility)
    private let log = Logger(subsystem: "fr.dynamicagence.MusicTrad", category: "cache")
    private var protectedFiles: [String: [String]] = [:]   // clé du titre → noms de fichiers
    private var loaded = false

    /// Dossier du cache, pour l'ouvrir dans le Finder.
    var folderURL: URL { DiskCache.root }

    private var protectedURL: URL { DiskCache.root.appending(path: "favorites.json") }

    // MARK: Favoris

    /// Protège (ou libère) les fichiers d'un titre selon qu'il est en favori.
    func setProtected(_ protected: Bool, song: String, cacheKeys: [String]) {
        queue.async {
            self.loadIfNeeded()
            let files = cacheKeys.map(DiskCache.fileName(for:))
            if protected {
                guard self.protectedFiles[song].map(Set.init) != Set(files) else { return }
                self.protectedFiles[song] = files
            } else {
                guard self.protectedFiles.removeValue(forKey: song) != nil else { return }
            }
            self.persist()
        }
    }

    /// Protège (ou libère) des fichiers précis du cache : paroles favorites de la bibliothèque.
    func setProtected(_ protected: Bool, song: String, files: [String]) {
        queue.async {
            self.loadIfNeeded()
            if protected {
                guard self.protectedFiles[song].map(Set.init) != Set(files) else { return }
                self.protectedFiles[song] = files
            } else {
                guard self.protectedFiles.removeValue(forKey: song) != nil else { return }
            }
            self.persist()
        }
    }

    /// Supprime des fichiers précis du dossier « translations » (traduction refusée depuis la bibliothèque).
    func removeTranslations(_ files: [String]) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                let dir = DiskCache.root.appending(path: "translations", directoryHint: .isDirectory)
                for name in files { try? FileManager.default.removeItem(at: dir.appending(path: name)) }
                LibraryIndex.shared.removeTranslations(files)
                cont.resume()
            }
        }
    }

    // MARK: Nettoyage

    func prune(limitMB: Int, maxAgeDays: Int) async -> Stats {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: self.pruneSync(limitBytes: Int64(limitMB) * 1_000_000, maxAgeDays: maxAgeDays))
            }
        }
    }

    func stats() async -> Stats {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.computeStats(self.scan())) }
        }
    }

    /// Vide le cache sauf les fichiers protégés (titres likés dans Musique, paroles favorites).
    func clearAll() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                self.loadIfNeeded()
                let protected = Set(self.protectedFiles.values.flatMap { $0 })
                let fm = FileManager.default
                var removed = 0
                for e in self.scan() where !protected.contains(e.name) {
                    try? fm.removeItem(at: e.url)
                    removed += 1
                }
                self.log.info("Cache vidé : \(removed) fichier(s) supprimé(s), \(protected.count) protégé(s) gardé(s)")
                LibraryIndex.shared.dropMissing()
                cont.resume()
            }
        }
    }

    // MARK: Interne (file dédiée)

    private struct Entry {
        let url: URL
        let name: String
        let folder: String
        let size: Int64
        let lastUse: Date
    }

    private func pruneSync(limitBytes: Int64, maxAgeDays: Int) -> Stats {
        loadIfNeeded()
        let protected = Set(protectedFiles.values.flatMap { $0 })
        let entries = scan()
        let items = entries.map { CachePruning.Item(name: $0.name, size: $0.size, lastUse: $0.lastUse) }
        let toRemove = CachePruning.filesToRemove(items, protected: protected,
                                                  limitBytes: limitBytes, maxAgeDays: maxAgeDays, now: Date())
        let fm = FileManager.default
        for i in toRemove { try? fm.removeItem(at: entries[i].url) }
        let removed = toRemove.count
        let kept = entries.indices.filter { !toRemove.contains($0) }.map { entries[$0] }

        if removed > 0 { LibraryIndex.shared.dropMissing() }   // la bibliothèque oublie les sons supprimés
        let stats = computeStats(kept)
        log.info("Nettoyage : \(removed) fichier(s) supprimé(s), \(stats.bytes) octets, \(stats.songs) titre(s)")
        return stats
    }

    private func scan() -> [Entry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey]
        return DiskCache.folders.flatMap { folder -> [Entry] in
            let dir = DiskCache.root.appending(path: folder, directoryHint: .isDirectory)
            let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
            return urls.compactMap { url in
                guard url.pathExtension == "json", let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                // Date de dernière écoute enregistrée dans l'entrée ; sinon (ancien format) date du fichier.
                let dates = (try? Data(contentsOf: url)).flatMap { try? DiskCache.decoder.decode(CacheDates.self, from: $0) }
                return Entry(url: url, name: url.lastPathComponent, folder: folder,
                             size: Int64(v.totalFileAllocatedSize ?? 0),
                             lastUse: dates?.lastUsedAt ?? v.contentModificationDate ?? .distantPast)
            }
        }
    }

    private func computeStats(_ entries: [Entry]) -> Stats {
        Stats(bytes: entries.reduce(0) { $0 + $1.size },
              songs: entries.filter { $0.folder == "lyrics" }.count,
              protectedSongs: protectedFiles.count,
              oldestUse: entries.map(\.lastUse).min())
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: protectedURL),
           let value = try? JSONDecoder().decode([String: [String]].self, from: data) {
            protectedFiles = value
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: DiskCache.root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(protectedFiles).write(to: protectedURL, options: .atomic)
    }
}
