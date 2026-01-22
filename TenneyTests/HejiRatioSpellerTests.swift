//
//  HejiRatioSpellerTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiRatioSpellerTests {
    private let anchor = RootAnchor(fifthsFromC: 3, diatonicNumber: 33) // A4

    private func context() -> PitchContext {
        PitchContext(
            a4Hz: 440,
            rootHz: 440,
            rootAnchor: anchor,
            accidentalPreference: .auto,
            maxPrime: 13
        )
    }

    @Test func a4AnchorSpellsUnison() {
        let spelling = spellRatio(p: 1, q: 1, context: context())
        #expect(spelling.letter == "A")
        #expect(spelling.scientificOctave == 4)
        #expect(spelling.helmholtzText == "a′")
    }

    @Test func threeLimitRatiosHoldRegister() {
        let ctx = context()

        let perfectFifth = spellRatio(p: 3, q: 2, context: ctx)
        #expect(perfectFifth.letter == "E")
        #expect(perfectFifth.scientificOctave == 5)

        let octaveUp = spellRatio(p: 2, q: 1, context: ctx)
        #expect(octaveUp.letter == "A")
        #expect(octaveUp.scientificOctave == 5)

        let fourth = spellRatio(p: 4, q: 3, context: ctx)
        #expect(fourth.letter == "D")
        #expect(fourth.scientificOctave == 5)

        let twelfth = spellRatio(p: 3, q: 1, context: ctx)
        #expect(twelfth.letter == "E")
        #expect(twelfth.scientificOctave == 6)
    }

    @Test func unsupportedPrimeDetection() {
        let spelling = spellRatio(p: 5, q: 4, context: context())
        #expect(spelling.unsupportedPrimes == [5])
    }
}
