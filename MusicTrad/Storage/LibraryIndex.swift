import Foundation
import OSLog

/// Index des sons traduits (Cache/library.json) : la bibliothèque s'ouvre sans décoder tout le cache.
/// Seuls les noms de fichiers et les métadonnées y sont ; paroles et traductions restent dans
/// leurs fichiers, lus seulement à l'ouverture d'un son.
///
/// Toujours à jour : traduction enregistrée ou relue, paroles changées, traduction supprimée,
/// nettoyage du cache. Autoréparé à chaque ouverture : une entrée dont les fichiers ont disparu
/// est retirée, une traduction du dossier encore inconnue est ajoutée (c'est aussi la migration :
/// sans index, tout le cache est relu une fois, comme avant).
nonisolated final class LibraryIndex: @unchecked Sendable {
    static let shared = LibraryIndex(root: DiskCache.root)

    /// Une version traduite d'un son (moteur ou langue différents).
    struct Version: Codable, Sendable {
        var file: String
        var source: String
        var target: String
        var lastUsed: Date
    }

    /// Un son traduit : ses paroles et ses traductions, par nom de fichier du cache.
    struct Record: Codable, Sendable {
        var id: String            // « Artiste – Titre »
        var artist: String
        var title: String
        var album: String?
        var lyricsFile: String
        var translations: [Version]

        /// La traduction affichée : la plus récemment écoutée.
        var best: Version? { translations.max { $0.lastUsed < $1.lastUsed } }
    }

    private struct Stored: Codable {
        var version: Int
        var songs: [Record]
        /// Traductions déjà examinées et écartées (paroles absentes ou lignes décalées) : pas relues à chaque ouverture.
        var ignored: [String]
    }

    private static let formatVersion = 1
    /// Une simple réécoute ne réécrit l'index qu'au-delà de cet écart.
    private static let touchInterval: TimeInterval = 60

    let root: URL
    private let queue = DispatchQueue(label: "fr.dynamicagence.MusicTrad.library", qos: .utility)
    private let log = Logger(subsystem: "fr.dynamicagence.MusicTrad", category: "library")
    private var songs: [String: Record] = [:]
    private var ignored: Set<String> = []
    private var loaded = false

    init(root: URL) { self.root = root }

    private var indexURL: URL { root.appending(path: "library.json") }
    private func folder(_ name: String) -> URL { root.appending(path: name, directoryHint: .isDirectory) }

    // MARK: Lecture

    /// Les sons traduits, du plus récemment écouté au plus ancien (index réparé au passage).
    func entries() async -> [LibraryEntry] {
        await withCheckedContinuation { cont in
            queue.async {
                self.loadIfNeeded()
                if self.heal(reconcile: true) { self.persist() }
                cont.resume(returning: self.songs.values.compactMap(LibraryEntry.init(record:))
                    .sorted { $0.lastUsed > $1.lastUsed })
            }
        }
    }

    // MARK: Mises à jour

    /// Traduction enregistrée ou relue depuis le cache pour le son en cours : ajoutée, ou datée de maintenant.
    func record(artist: String, title: String, album: String?, lyricsFile: String,
                translationFile: String, source: String, target: String) {
        queue.async {
            self.loadIfNeeded()
            let id = "\(artist) – \(title)"
            let now = Date()
            var changed = false
            var rec = self.songs[id] ?? {
                changed = true
                return Record(id: id, artist: artist, title: title, album: nil, lyricsFile: lyricsFile, translations: [])
            }()
            if let album, !album.isEmpty, rec.album != album { rec.album = album; changed = true }
            if rec.lyricsFile != lyricsFile {
                // Autres paroles (autre album) : les anciennes traductions ne les suivent plus.
                self.ignored.formUnion(rec.translations.map(\.file))
                rec.lyricsFile = lyricsFile
                rec.translations = []
                changed = true
            }
            if let i = rec.translations.firstIndex(where: { $0.file == translationFile }) {
                if rec.translations[i].source != source || rec.translations[i].target != target {
                    rec.translations[i].source = source
                    rec.translations[i].target = target
                    changed = true
                }
                if now.timeIntervalSince(rec.translations[i].lastUsed) > Self.touchInterval {
                    rec.translations[i].lastUsed = now
                    changed = true
                }
            } else {
                rec.translations.append(Version(file: translationFile, source: source, target: target, lastUsed: now))
                changed = true
            }
            if self.ignored.remove(translationFile) != nil { changed = true }
            guard changed else { return }
            self.songs[id] = rec
            self.persist()
        }
    }

    /// Paroles remplacées (autre version, meilleure synchro) : on garde seulement les traductions qui les suivent encore.
    func lyricsChanged(file: String) {
        queue.async {
            self.loadIfNeeded()
            var changed = false
            for (id, var rec) in self.songs where rec.lyricsFile == file {
                let lyrics = self.decodeLyrics(file)
                let kept = rec.translations.filter { version in
                    guard let lyrics, let lines = self.decodeTranslation(version.file)?.value else { return false }
                    return TranslatedLibrary.aligned(lyrics, lines) != nil
                }
                guard kept.count != rec.translations.count else { continue }
                self.ignored.formUnion(rec.translations.map(\.file).filter { f in !kept.contains { $0.file == f } })
                rec.translations = kept
                self.songs[id] = kept.isEmpty ? nil : rec
                changed = true
            }
            if changed { self.persist() }
        }
    }

    /// Traductions supprimées depuis la bibliothèque.
    func removeTranslations(_ files: [String]) {
        let removed = Set(files)
        queue.async {
            self.loadIfNeeded()
            // Écartées aussi : un fichier resté sur le disque ne revient pas à la prochaine ouverture
            // (une nouvelle traduction du son le réenregistre normalement).
            self.ignored.formUnion(removed)
            var changed = true
            for (id, var rec) in self.songs where rec.translations.contains(where: { removed.contains($0.file) }) {
                rec.translations.removeAll { removed.contains($0.file) }
                self.songs[id] = rec.translations.isEmpty ? nil : rec
                changed = true
            }
            if changed { self.persist() }
        }
    }

    /// Après un nettoyage du cache : retire ce dont les fichiers ont disparu.
    func dropMissing() {
        queue.async {
            self.loadIfNeeded()
            if self.heal(reconcile: false) { self.persist() }
        }
    }

    // MARK: Interne (file dédiée)

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? DiskCache.decoder.decode(Stored.self, from: data),
              stored.version == Self.formatVersion else {
            log.info("Bibliothèque : pas d'index, il sera construit à partir du cache")
            return
        }
        songs = Dictionary(stored.songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        ignored = Set(stored.ignored)
    }

    private func persist() {
        let stored = Stored(version: Self.formatVersion,
                            songs: songs.values.sorted { $0.id < $1.id },
                            ignored: ignored.sorted())
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try DiskCache.encoder.encode(stored).write(to: indexURL, options: .atomic)
        } catch {
            log.error("Bibliothèque : écriture de l'index impossible – \(error.localizedDescription, privacy: .public)")
        }
    }

    private func listing(_ name: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(at: folder(name), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .map(\.lastPathComponent)
    }

    /// Retire les entrées dont les fichiers ont disparu ; avec `reconcile`, ajoute les traductions encore inconnues.
    /// Vrai si l'index a changé.
    private func heal(reconcile: Bool) -> Bool {
        let lyricsNames = Set(listing("lyrics"))
        let translationOrder = listing("translations")
        let translationNames = Set(translationOrder)
        var changed = false

        for (id, var rec) in songs {
            guard lyricsNames.contains(rec.lyricsFile) else { songs[id] = nil; changed = true; continue }
            let kept = rec.translations.filter { translationNames.contains($0.file) }
            guard kept.count != rec.translations.count else { continue }
            rec.translations = kept
            songs[id] = kept.isEmpty ? nil : rec
            changed = true
        }
        let stillThere = ignored.intersection(translationNames)
        if stillThere.count != ignored.count { ignored = stillThere; changed = true }

        guard reconcile else { return changed }
        let known = Set(songs.values.flatMap { $0.translations.map(\.file) })
        let unknown = translationOrder.filter { !known.contains($0) && !ignored.contains($0) }
        guard !unknown.isEmpty else { return changed }

        // Paroles, par libellé « Artiste – Titre » (même règle qu'avant l'index : le dernier lu l'emporte).
        var lyricsByFile: [String: Lyrics] = [:]
        var lyricsFileByLabel: [String: String] = [:]
        for name in listing("lyrics") {
            guard let entry = decodeLyricsEnvelope(name), !entry.value.isInstrumental, !entry.value.lines.isEmpty else { continue }
            lyricsByFile[name] = entry.value
            if let label = entry.label { lyricsFileByLabel[label] = name }
        }

        var added = 0
        for name in unknown {
            guard let entry = decodeTranslation(name), let label = entry.label,
                  let open = label.range(of: " [", options: .backwards), label.hasSuffix("]") else {
                ignored.insert(name); changed = true; continue
            }
            let base = String(label[..<open.lowerBound])
            // « apple, en → fr »
            let meta = label[open.upperBound...].dropLast()
            let languages = meta.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
            let parts = languages.components(separatedBy: " → ")
            guard parts.count == 2,
                  let lyricsFile = songs[base]?.lyricsFile ?? lyricsFileByLabel[base],
                  let lyrics = lyricsByFile[lyricsFile],
                  TranslatedLibrary.aligned(lyrics, entry.value) != nil else {
                ignored.insert(name); changed = true; continue
            }
            let separator = base.range(of: " – ")
            var rec = songs[base] ?? Record(
                id: base,
                artist: separator.map { String(base[..<$0.lowerBound]) } ?? "",
                title: separator.map { String(base[$0.upperBound...]) } ?? base,
                album: nil, lyricsFile: lyricsFile, translations: []
            )
            rec.translations.append(Version(file: name, source: parts[0].lowercased(),
                                            target: parts[1].lowercased(), lastUsed: entry.lastUsedAt))
            songs[base] = rec
            added += 1
            changed = true
        }
        log.info("Bibliothèque : \(added) traduction(s) ajoutée(s) à l'index, \(unknown.count - added) écartée(s)")
        return changed
    }

    private func decodeLyricsEnvelope(_ name: String) -> CacheEnvelope<Lyrics>? {
        (try? Data(contentsOf: folder("lyrics").appending(path: name)))
            .flatMap { try? DiskCache.decoder.decode(CacheEnvelope<Lyrics>.self, from: $0) }
    }

    private func decodeLyrics(_ name: String) -> Lyrics? { decodeLyricsEnvelope(name)?.value }

    private func decodeTranslation(_ name: String) -> CacheEnvelope<[String]>? {
        (try? Data(contentsOf: folder("translations").appending(path: name)))
            .flatMap { try? DiskCache.decoder.decode(CacheEnvelope<[String]>.self, from: $0) }
    }
}
