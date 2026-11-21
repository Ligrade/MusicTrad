import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func item(_ name: String, size: Int64 = 1_000, daysAgo: Double) -> CachePruning.Item {
    CachePruning.Item(name: name, size: size, lastUse: now.addingTimeInterval(-daysAgo * 86400))
}

private func removedNames(_ items: [CachePruning.Item], protected: Set<String> = [],
                          limitBytes: Int64 = .max, maxAgeDays: Int = 90) -> Set<String> {
    let indices = CachePruning.filesToRemove(items, protected: protected, limitBytes: limitBytes,
                                             maxAgeDays: maxAgeDays, now: now)
    return Set(indices.map { items[$0].name })
}

@Suite("Nettoyage du cache")
struct CachePruningTests {
    @Test func rienASupprimer() {
        let items = [item("a", daysAgo: 1), item("b", daysAgo: 10)]
        #expect(removedNames(items, limitBytes: 10_000).isEmpty)
    }

    @Test func fichiersTropAnciensSupprimes() {
        let items = [item("récent", daysAgo: 5), item("vieux", daysAgo: 120), item("limite", daysAgo: 89)]
        #expect(removedNames(items, maxAgeDays: 90) == ["vieux"])
    }

    @Test func sansLimiteDAge() {
        let items = [item("très vieux", daysAgo: 3_000)]
        #expect(removedNames(items, maxAgeDays: 0).isEmpty)
    }

    @Test func favorisJamaisSupprimesMemeAnciens() {
        let items = [item("favori", daysAgo: 400), item("vieux", daysAgo: 400)]
        #expect(removedNames(items, protected: ["favori"]) == ["vieux"])
    }

    @Test func tropGrosLeMoinsRecentPartEnPremier() {
        let items = [item("hier", daysAgo: 1), item("semaine", daysAgo: 7), item("mois", daysAgo: 30), item("aujourdhui", daysAgo: 0)]
        // 4 000 octets pour 2 500 autorisés : il faut en retirer deux, les plus anciens.
        #expect(removedNames(items, limitBytes: 2_500) == ["mois", "semaine"])
    }

    @Test func tailleRespecteeExactement() {
        let items = [item("a", daysAgo: 3), item("b", daysAgo: 2), item("c", daysAgo: 1)]
        #expect(removedNames(items, limitBytes: 2_000) == ["a"])
    }

    @Test func favorisComptentDansLaTailleMaisRestent() {
        let items = [item("favori", size: 5_000, daysAgo: 60), item("a", daysAgo: 2), item("b", daysAgo: 1)]
        // Même en supprimant tout le reste on reste au-dessus : seul le favori survit.
        #expect(removedNames(items, protected: ["favori"], limitBytes: 1_000) == ["a", "b"])
    }

    @Test func ageEtTailleCombines() {
        let items = [item("vieux", size: 3_000, daysAgo: 200), item("a", daysAgo: 20), item("b", daysAgo: 1)]
        // Le vieux part pour l'âge ; il reste 2 000 octets, sous la limite : rien d'autre.
        #expect(removedNames(items, limitBytes: 2_000) == ["vieux"])
    }

    @Test func memeNomDansDeuxDossiers() {
        // Le même nom de fichier peut exister dans « lyrics » et « translations » : les indices les distinguent.
        let items = [item("x.json", daysAgo: 200), item("x.json", daysAgo: 1)]
        let indices = CachePruning.filesToRemove(items, protected: [], limitBytes: .max, maxAgeDays: 90, now: now)
        #expect(indices == [0])
    }
}
