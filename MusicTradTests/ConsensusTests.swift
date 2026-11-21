import Foundation
import Testing

/// Version synchronisée fabriquée à partir d'horodatages ; `source` sert d'étiquette.
private func version(_ name: String, shift: TimeInterval = 0, count: Int = 15) -> Lyrics {
    let lines = (0..<count).map { i in
        LyricLine(id: i, time: 10 + Double(i) * 12 + shift, text: "ligne \(i)")
    }
    return Lyrics(lines: lines, isSynced: true, isInstrumental: false, source: name)
}

/// Durée du morceau compatible avec `version` (dernière ligne à ~178 s).
private let duration: TimeInterval = 190

@Suite("Choix de version par consensus")
struct ConsensusTests {
    @Test func moinsDeTroisVersionsPasDeConsensus() {
        #expect(Lyrics.consensus([]) == nil)
        #expect(Lyrics.consensus([version("A"), version("B")]) == nil)
    }

    @Test func versionsTropCourtesIgnorees() {
        let short = [version("A", count: 3), version("B", count: 3), version("C", count: 3)]
        #expect(Lyrics.consensus(short) == nil)
    }

    @Test func versionDecaleeEcartee() {
        let candidates = [version("décalée", shift: 4), version("A"), version("B", shift: 0.1), version("C", shift: -0.1)]
        let chosen = Lyrics.consensus(candidates)
        #expect(chosen != nil)
        #expect(chosen?.source != "décalée")
    }

    @Test func versionMedianeChoisie() {
        let candidates = [version("tôt", shift: -0.3), version("milieu"), version("tard", shift: 0.3)]
        #expect(Lyrics.consensus(candidates)?.source == "milieu")
    }

    @Test func lignesVidesNeComptentPas() {
        // Une version avec des « ♪ » vides intercalés garde les mêmes horodatages chantés.
        var lines = version("avec pauses").lines.map { ($0.time, $0.text) }
        lines.insert((0, ""), at: 0)
        lines.insert((50, ""), at: 5)
        let padded = Lyrics(lines: lines.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) },
                            isSynced: true, isInstrumental: false, source: "avec pauses")
        #expect(padded.leadingTimes() == version("x").leadingTimes())
    }

    @Test func reponseDirecteInstrumentaleGardee() {
        let instrumental = Lyrics(lines: [], isSynced: false, isInstrumental: true, source: "direct")
        let chosen = Lyrics.best(direct: instrumental, others: [version("A"), version("B"), version("C")], duration: duration)
        #expect(chosen?.source == "direct")
    }

    @Test func reponseDirecteDecaleeRemplaceeParLaMajorite() {
        let direct = version("direct", shift: 4)
        let others = [version("A"), version("B"), version("C")]
        let chosen = Lyrics.best(direct: direct, others: others, duration: duration)
        #expect(chosen?.source != "direct")
    }

    @Test func reponseDirecteGardeeSansAssezDeVotes() {
        let direct = version("direct")
        let chosen = Lyrics.best(direct: direct, others: [version("A", shift: 2)], duration: duration)
        #expect(chosen?.source == "direct")
    }

    @Test func versionsHorsDureeIgnorees() {
        // La réponse directe n'est pas synchronisée ; les versions trop longues pour le morceau ne votent pas.
        let plain = Lyrics(lines: LRCParser.plain("A\nB"), isSynced: false, isInstrumental: false, source: "texte")
        let tooLong = version("trop longue", shift: 60)
        let good = version("bonne")
        let chosen = Lyrics.best(direct: plain, others: [tooLong, good], duration: duration)
        #expect(chosen?.source == "bonne")
    }

    @Test func repliSurLaReponseDirectePuisLesAutres() {
        let plain = Lyrics(lines: LRCParser.plain("A"), isSynced: false, isInstrumental: false, source: "texte")
        let tooLong = version("trop longue", shift: 60)
        #expect(Lyrics.best(direct: plain, others: [tooLong], duration: duration)?.source == "texte")
        #expect(Lyrics.best(direct: nil, others: [tooLong], duration: duration)?.source == "trop longue")
        #expect(Lyrics.best(direct: nil, others: [], duration: duration) == nil)
    }
}
