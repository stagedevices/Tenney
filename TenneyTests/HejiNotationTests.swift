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
    private let extendedContext = HejiContext(
        concertA4Hz: 440,
        noteNameA4Hz: 440,
        rootHz: 440,
        rootRatio: nil,
        preferred: .auto,
        maxPrime: 31,
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

    @Test func extendedPrimeGlyphsRender() async throws {
        let ratios: [(prime: Int, ratio: RatioRef)] = [
            (17, RatioRef(p: 17, q: 16, octave: 0, monzo: [:])),
            (19, RatioRef(p: 19, q: 16, octave: 0, monzo: [:])),
            (23, RatioRef(p: 23, q: 16, octave: 0, monzo: [:])),
            (29, RatioRef(p: 29, q: 16, octave: 0, monzo: [:])),
            (31, RatioRef(p: 31, q: 16, octave: 0, monzo: [:]))
        ]
        let diatonicSet: Set<UInt32> = [0xE260, 0xE261, 0xE262, 0xE263, 0xE264, 0xE265, 0xE266]

        for (prime, ratioRef) in ratios {
            let spelling = HejiNotation.spelling(forRatio: ratioRef, context: extendedContext)
            #expect(spelling.accidental.microtonalComponents.contains { $0.prime == prime })

            let glyphs = Heji2Mapping.shared
                .glyphsForPrimeComponents(spelling.accidental.microtonalComponents)
                .map(\.string)
                .joined()
            #expect(!glyphs.isEmpty)

            let scalars = glyphs.unicodeScalars.map(\.value)
            let hasMicrotonal = scalars.contains { 0xE000...0xF8FF ~= $0 && !diatonicSet.contains($0) }
            #expect(hasMicrotonal)
        }
    }
}
