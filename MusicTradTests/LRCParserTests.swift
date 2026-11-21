import Foundation
import Testing

@Suite("Parsing LRC")
struct LRCParserTests {
    @Test func ligneSimple() {
        let lines = LRCParser.parse("[00:12.34]Hello world")
        #expect(lines.count == 1)
        #expect(abs((lines[0].time ?? 0) - 12.34) < 0.001)
        #expect(lines[0].text == "Hello world")
        #expect(lines[0].id == 0)
    }

    @Test func minutesConvertiesEnSecondes() {
        let lines = LRCParser.parse("[02:05.50]Refrain")
        #expect(abs((lines[0].time ?? 0) - 125.5) < 0.001)
    }

    @Test func separateurDeuxPointsPourLesCentiemes() {
        let lines = LRCParser.parse("[01:02:50]Variante")
        #expect(abs((lines[0].time ?? 0) - 62.5) < 0.001)
    }

    @Test func secondesSansDecimales() {
        let lines = LRCParser.parse("[00:07]Court")
        #expect(abs((lines[0].time ?? 0) - 7) < 0.001)
    }

    @Test func plusieursHorodatagesSurUneLigne() {
        let lines = LRCParser.parse("[00:10.00][00:40.00]Refrain\n[00:20.00]Couplet")
        #expect(lines.map(\.text) == ["Refrain", "Couplet", "Refrain"])
        #expect(lines.compactMap(\.time) == [10, 20, 40])
    }

    @Test func lignesTrieesEtRenumerotees() {
        let lines = LRCParser.parse("[00:30.00]C\n[00:10.00]A\n[00:20.00]B")
        #expect(lines.map(\.text) == ["A", "B", "C"])
        #expect(lines.map(\.id) == [0, 1, 2])
    }

    @Test func metadonneesEtTexteLibreIgnores() {
        let lrc = """
        [ar:Artiste]
        [ti:Titre]
        [length:03:20]
        texte sans horodatage
        [00:05.00]Première ligne
        """
        let lines = LRCParser.parse(lrc)
        #expect(lines.map(\.text) == ["Première ligne"])
    }

    @Test func ligneVideGardeeEtEspacesRetires() {
        let lines = LRCParser.parse("[00:05.00]   Bonjour  \n[00:09.00]")
        #expect(lines.map(\.text) == ["Bonjour", ""])
        #expect(lines[1].isBlank)
    }

    @Test func retoursChariotWindows() {
        let lines = LRCParser.parse("[00:01.00]Un\r\n[00:02.00]Deux\r\n")
        #expect(lines.map(\.text) == ["Un", "Deux"])
    }

    @Test func texteBrutSansHorodatage() {
        let lines = LRCParser.plain("Un\n  Deux \nTrois")
        #expect(lines.map(\.text) == ["Un", "Deux", "Trois"])
        #expect(lines.allSatisfy { $0.time == nil })
        #expect(lines.map(\.id) == [0, 1, 2])
    }
}

@Suite("Paroles synchronisées")
struct LyricsTimingTests {
    private let lyrics = Lyrics(lines: LRCParser.parse("[00:10.00]A\n[00:20.00]B\n[00:30.00]C"),
                                isSynced: true, isInstrumental: false)

    @Test func ligneEnCours() {
        #expect(lyrics.lineIndex(at: 5) == nil)
        #expect(lyrics.lineIndex(at: 10) == 0)
        #expect(lyrics.lineIndex(at: 25) == 1)
        #expect(lyrics.lineIndex(at: 300) == 2)
    }

    @Test func pasDeLigneEnCoursSansSynchro() {
        let plain = Lyrics(lines: LRCParser.plain("A\nB"), isSynced: false, isInstrumental: false)
        #expect(plain.lineIndex(at: 10) == nil)
    }

    @Test func verificationDeSynchro() {
        #expect(lyrics.syncCheck(duration: 40) == .synced)
        #expect(lyrics.syncCheck(duration: 20) == .tooLong)   // finit après la fin du morceau
        #expect(lyrics.syncCheck(duration: 100) == .endsEarly) // s'arrête avant la moitié
        #expect(lyrics.syncCheck(duration: 0) == .synced)
        let plain = Lyrics(lines: LRCParser.plain("A"), isSynced: false, isInstrumental: false)
        #expect(plain.syncCheck(duration: 40) == .unsynced)
    }

    @Test func pausesInstrumentalesAjoutees() {
        // Intro de 12 s et trou de 30 s entre B et C : deux « ♪ » ajoutés.
        let gaps = Lyrics(lines: LRCParser.parse("[00:12.00]A\n[00:15.00]B\n[00:45.00]C"),
                          isSynced: true, isInstrumental: false).withInstrumentalBreaks()
        #expect(gaps.lines.map(\.text) == ["", "A", "B", "", "C"])
        #expect(gaps.lines.first?.time == 0)
        #expect(gaps.lines.map(\.id) == [0, 1, 2, 3, 4])
    }

    @Test func pasDePauseQuandLesLignesSeSuivent() {
        let tight = Lyrics(lines: LRCParser.parse("[00:05.00]A\n[00:10.00]B\n[00:15.00]C"),
                           isSynced: true, isInstrumental: false)
        #expect(tight.withInstrumentalBreaks() == tight)
    }
}
