import Foundation

/// Règles du nettoyage du cache, sans accès disque (testables) :
/// 1. supprime ce qui n'a pas été écouté depuis `maxAgeDays` (0 : pas de limite d'âge) ;
/// 2. au-delà de `limitBytes`, supprime d'abord le moins récemment écouté ;
/// 3. ne touche jamais aux fichiers protégés (favoris), qui comptent quand même dans la taille.
nonisolated enum CachePruning {
    struct Item: Equatable, Sendable {
        let name: String
        let size: Int64
        let lastUse: Date
    }

    /// Indices (dans `items`) des fichiers à supprimer.
    static func filesToRemove(_ items: [Item], protected: Set<String>,
                              limitBytes: Int64, maxAgeDays: Int, now: Date) -> Set<Int> {
        var removed = Set<Int>()

        // 1. Pas écouté depuis trop longtemps
        let cutoff = maxAgeDays > 0 ? now.addingTimeInterval(-Double(maxAgeDays) * 86400) : .distantPast
        for (i, item) in items.enumerated() where item.lastUse < cutoff && !protected.contains(item.name) {
            removed.insert(i)
        }

        // 2. Trop gros : le moins récemment écouté part en premier
        var total = items.indices.filter { !removed.contains($0) }.reduce(Int64(0)) { $0 + items[$1].size }
        guard total > limitBytes else { return removed }
        let candidates = items.indices
            .filter { !removed.contains($0) && !protected.contains(items[$0].name) }
            .sorted { (items[$0].lastUse, $0) < (items[$1].lastUse, $1) }
        for i in candidates {
            guard total > limitBytes else { break }
            removed.insert(i)
            total -= items[i].size
        }
        return removed
    }
}
