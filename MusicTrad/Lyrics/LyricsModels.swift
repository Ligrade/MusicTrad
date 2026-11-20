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
