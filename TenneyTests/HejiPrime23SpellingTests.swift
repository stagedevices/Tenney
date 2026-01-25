//
//  HejiPrime23SpellingTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiPrime23SpellingTests {
    private let context: HejiContext = {
        let tonicA = TonicSpelling.from(letter: "A", accidental: 0).e3
        return HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .auto,
            maxPrime: 31,
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: tonicA
        )
    }()

    @Test func prime23SpellingPreferences() async throws {
        let ratioDown = RatioRef(p: 32, q: 23)
        let downSpelling = HejiNotation.spelling(forRatio: ratioDown, context: context)
        #expect(downSpelling.baseLetter == "E")
        #expect(downSpelling.accidental.diatonicAccidental == -1)
        #expect(downSpelling.accidental.microtonalComponents.contains { component in
            component.prime == 23 && component.steps == 1 && !component.up
        })

        let ratioUp = RatioRef(p: 23, q: 16)
        let upSpelling = HejiNotation.spelling(forRatio: ratioUp, context: context)
        #expect(upSpelling.baseLetter == "D")
        #expect(upSpelling.accidental.diatonicAccidental == 1)
        #expect(upSpelling.accidental.microtonalComponents.contains { component in
            component.prime == 23 && component.steps == 1 && component.up
        })

        let ratioDownTwo = RatioRef(p: 1024, q: 529)
        let downTwoSpelling = HejiNotation.spelling(forRatio: ratioDownTwo, context: context)
        #expect(downTwoSpelling.baseLetter == "B")
        #expect(downTwoSpelling.accidental.diatonicAccidental == -2)
        #expect(downTwoSpelling.accidental.microtonalComponents.contains { component in
            component.prime == 23 && component.steps == 2 && !component.up
        })

        let ratioUpTwo = RatioRef(p: 529, q: 512)
        let upTwoSpelling = HejiNotation.spelling(forRatio: ratioUpTwo, context: context)
        #expect(upTwoSpelling.baseLetter == "G")
        #expect(upTwoSpelling.accidental.diatonicAccidental == 2)
        #expect(upTwoSpelling.accidental.microtonalComponents.contains { component in
            component.prime == 23 && component.steps == 2 && component.up
        })
    }

    @Test func prime11ComponentStillPresent() async throws {
        let undecimal = HejiNotation.spelling(forRatio: Ratio(11, 8), context: context)
        #expect(undecimal.accidental.microtonalComponents.contains { component in
            component.prime == 11 && component.up
        })
    }
}
