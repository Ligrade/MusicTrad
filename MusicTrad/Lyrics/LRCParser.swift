import Foundation

/// Parse le format LRC : « [mm:ss.xx]texte », éventuellement plusieurs horodatages par ligne.
nonisolated enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [(TimeInterval, String)] = []
        let tag = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/

        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while let m = rest.prefixMatch(of: tag) {
                let minutes = Double(m.1) ?? 0
                let seconds = Double(m.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                times.append(minutes * 60 + seconds)
                rest = rest[m.range.upperBound...]
            }
            guard !times.isEmpty else { continue } // métadonnées [ar:], [ti:]… ignorées
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times { entries.append((t, text)) }
        }

        return entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    static func plain(_ text: String) -> [LyricLine] {
        text.components(separatedBy: .newlines)
            .enumerated()
            .map { LyricLine(id: $0.offset, time: nil, text: $0.element.trimmingCharacters(in: .whitespaces)) }
    }
}
