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
    /// Source des paroles (« LRCLIB », « NetEase »…) ; absente des anciens caches.
    var source: String? = nil

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

extension Lyrics {
    /// Ajoute un « ♪ » pendant les passages sans chant (intro, solos) quand le fichier LRC
    /// n'en a pas : sinon la dernière ligne chantée reste allumée pendant tout le solo.
    /// Sans effet si les pauses sont déjà marquées (ligne vide).
    nonisolated func withInstrumentalBreaks() -> Lyrics {
        guard isSynced, !lines.isEmpty else { return self }
        var out: [(TimeInterval?, String)] = []
        if let first = lines.first?.time, first >= 8, !lines[0].isBlank { out.append((0, "")) }
        for (i, line) in lines.enumerated() {
            out.append((line.time, line.text))
            guard !line.isBlank, let t = line.time, i + 1 < lines.count,
                  let next = lines[i + 1].time, !lines[i + 1].isBlank else { continue }
            // Durée chantée estimée d'après la longueur de la ligne ; au-delà de 7 s de plus, c'est une pause.
            let sung = min(max(Double(line.text.count) * 0.12 + 1, 2), 6)
            if next - t > sung + 7 { out.append((t + sung, "")) }
        }
        guard out.count != lines.count else { return self }
        let renumbered = out.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
        return Lyrics(lines: renumbered, isSynced: isSynced, isInstrumental: isInstrumental, source: source)
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
