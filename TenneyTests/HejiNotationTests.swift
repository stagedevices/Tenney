//
//  HejiNotationTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiNotationTests {

    private let context = HejiContext(
        concertA4Hz: 440,
        noteNameA4Hz: 440,
        rootHz: 440,
        rootRatio: nil,
        preferred: .auto,
        maxPrime: 13,
        allowApproximation: false,
        scaleDegreeHint: nil,
        tonicE3: nil
    )

    @Test func threeLimitLetters() async throws {
        let fifth = HejiNotation.spelling(forRatio: Ratio(3, 2), context: context)
        #expect(fifth.baseLetter == "G")
        #expect(fifth.accidental.diatonicAccidental == 0)

        let fourth = HejiNotation.spelling(forRatio: Ratio(4, 3), context: context)
        #expect(fourth.baseLetter == "F")
        #expect(fourth.accidental.diatonicAccidental == 0)

        let second = HejiNotation.spelling(forRatio: Ratio(9, 8), context: context)
        #expect(second.baseLetter == "D")
        #expect(second.accidental.diatonicAccidental == 0)
    }

    @Test func higherPrimeComponents() async throws {
        let majorThird = HejiNotation.spelling(forRatio: Ratio(5, 4), context: context)
        #expect(majorThird.accidental.microtonalComponents.contains(.syntonic(up: false)))

        let septimal = HejiNotation.spelling(forRatio: Ratio(7, 4), context: context)
        #expect(septimal.accidental.microtonalComponents.contains(.septimal(up: false)))

        let undecimal = HejiNotation.spelling(forRatio: Ratio(11, 8), context: context)
        #expect(undecimal.accidental.microtonalComponents.contains(.undecimal(up: false)))

        let tridecimal = HejiNotation.spelling(forRatio: Ratio(13, 8), context: context)
        #expect(tridecimal.accidental.microtonalComponents.contains(.tridecimal(up: false)))
    }
}
