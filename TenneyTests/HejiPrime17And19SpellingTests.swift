//
//  HejiPrime17And19SpellingTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiPrime17And19SpellingTests {
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

    @Test func prime17NearTonicAnchoring() async throws {
        let first = HejiNotation.spelling(forRatio: Ratio(17, 16), context: context)
        #expect(first.baseLetter == "A")
        #expect(first.accidental.diatonicAccidental == 1)
        #expect(first.accidental.microtonalComponents.contains { $0.prime == 17 && $0.steps == 1 && !$0.up })

        let second = HejiNotation.spelling(forRatio: Ratio(289, 256), context: context)
        #expect(second.baseLetter == "A")
        #expect(second.accidental.diatonicAccidental == 2)
        #expect(second.accidental.microtonalComponents.contains { $0.prime == 17 && $0.steps == 2 && !$0.up })

        let third = HejiNotation.spelling(forRatio: Ratio(512, 289), context: context)
        #expect(third.baseLetter == "A")
        #expect(third.accidental.diatonicAccidental == -2)
        #expect(third.accidental.microtonalComponents.contains { $0.prime == 17 && $0.steps == 2 && !$0.up })
    }

    @Test func prime19DirectionAndEnharmonicPreference() async throws {
        let up = HejiNotation.spelling(forRatio: Ratio(19, 16), context: context)
        #expect(up.baseLetter == "C")
        #expect(up.accidental.diatonicAccidental == 0)
        #expect(up.accidental.microtonalComponents.contains { $0.prime == 19 && $0.steps == 1 && $0.up })

        let down = HejiNotation.spelling(forRatio: Ratio(32, 19), context: context)
        #expect(down.baseLetter == "F")
        #expect(down.accidental.diatonicAccidental == 1)
        #expect(down.accidental.microtonalComponents.contains { $0.prime == 19 && $0.steps == 1 && !$0.up })

        let downTwo = HejiNotation.spelling(forRatio: Ratio(512, 361), context: context)
        #expect(downTwo.baseLetter == "D")
        #expect(downTwo.accidental.diatonicAccidental == 1)
        #expect(downTwo.accidental.microtonalComponents.contains { $0.prime == 19 && $0.steps == 2 && !$0.up })

        let upTwo = HejiNotation.spelling(forRatio: Ratio(361, 256), context: context)
        #expect(upTwo.baseLetter == "E")
        #expect(upTwo.accidental.diatonicAccidental == -1)
        #expect(upTwo.accidental.microtonalComponents.contains { $0.prime == 19 && $0.steps == 2 && $0.up })
    }

    @Test func prime11SpellingRemainsStable() async throws {
        let undecimal = HejiNotation.spelling(forRatio: Ratio(11, 8), context: context)
        #expect(undecimal.baseLetter == "F")
        #expect(undecimal.accidental.diatonicAccidental == -2)
        #expect(undecimal.accidental.microtonalComponents.contains { $0.prime == 11 })
    }
}
