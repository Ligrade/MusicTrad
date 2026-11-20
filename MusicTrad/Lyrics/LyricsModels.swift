import Foundation

nonisolated struct LyricLine: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let time: TimeInterval?   // nil si paroles non synchronisées
    let text: String

    var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

nonisolated struct Lyrics: Codable, Hashable, Sendable {
    let lines: [LyricLine]
    let isSynced: Bool
    let isInstrumental: Bool

    var fullText: String { lines.map(\.text).joined(separator: "\n") }

    /// Index de la ligne en cours pour une position donnée (paroles synchronisées).
    func lineIndex(at position: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        var result: Int?
        for line in lines {
            guard let t = line.time else { continue }
            if t <= position { result = line.id } else { break }
        }
        return result
    }
}

/// Résultat de la vérification de synchro : le timing des paroles colle-t-il au morceau ?
nonisolated enum SyncCheck: Equatable, Sendable {
    case synced      // timing cohérent avec la durée du morceau
    case tooLong     // les paroles durent plus que le morceau : autre version (album / radio…)
    case endsEarly   // elles s'arrêtent bien avant la fin
    case unsynced    // texte brut, sans horodatage
}

extension Lyrics {
    nonisolated func syncCheck(duration: TimeInterval) -> SyncCheck {
        guard isSynced else { return .unsynced }
        guard duration > 0, let last = lines.compactMap(\.time).last else { return .synced }
        if last > duration + 3 { return .tooLong }
        if last < duration * 0.5 { return .endsEarly }
        return .synced
    }
}
