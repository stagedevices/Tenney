//
//  HejiPrime29And31FixesTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiPrime29And31FixesTests {
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

    private let diatonicSet: Set<UInt32> = [
        0xE260, 0xE261, 0xE262, 0xE263, 0xE264, 0xE265, 0xE266
    ]

    private func firstScalar(from glyphs: [Heji2Glyph]) -> UInt32? {
        glyphs.first?.glyph.unicodeScalars.first?.value
    }

    private func totalSteps(
        _ components: [HejiMicrotonalComponent],
        prime: Int,
        up: Bool
    ) -> Int {
        components
            .filter { $0.prime == prime && $0.up == up }
            .map(\.steps)
            .reduce(0, +)
    }

    @Test func mappingUsesDistinctNonBracketGlyphsFor29And31() async throws {
        let mapping = Heji2Mapping.shared
        let prime29Up = mapping.glyphsForPrimeComponents([
            HejiMicrotonalComponent(prime: 29, up: true, steps: 1)
        ])
        let prime31Up = mapping.glyphsForPrimeComponents([
            HejiMicrotonalComponent(prime: 31, up: true, steps: 1)
        ])
        let prime31Down = mapping.glyphsForPrimeComponents([
            HejiMicrotonalComponent(prime: 31, up: false, steps: 1)
        ])

        let prime29Scalar = firstScalar(from: prime29Up)
        let prime31Scalar = firstScalar(from: prime31Up)
        #expect(prime29Scalar != nil)
        #expect(prime31Scalar != nil)
        #expect(prime29Scalar != prime31Scalar)

        let bracketScalars: Set<UInt32> = [0xE2EE, 0xE2EF]
        if let upScalar = prime31Scalar {
            #expect(!bracketScalars.contains(upScalar))
        }
        if let downScalar = firstScalar(from: prime31Down) {
            #expect(!bracketScalars.contains(downScalar))
        }
    }

    @Test func prime31NearTonicAnchoring() async throws {
        let up = HejiNotation.spelling(forRatio: Ratio(32, 31), context: context)
        #expect(up.baseLetter == "A")
        #expect(up.accidental.diatonicAccidental == 0)
        #expect(totalSteps(up.accidental.microtonalComponents, prime: 31, up: true) == 1)

        let down = HejiNotation.spelling(forRatio: Ratio(31, 16), context: context)
        #expect(down.baseLetter == "A")
        #expect(down.accidental.diatonicAccidental == 0)
        #expect(totalSteps(down.accidental.microtonalComponents, prime: 31, up: false) == 1)

        let downTwo = HejiNotation.spelling(forRatio: Ratio(961, 512), context: context)
        #expect(downTwo.baseLetter == "A")
        #expect(downTwo.accidental.diatonicAccidental == 0)
        #expect(totalSteps(downTwo.accidental.microtonalComponents, prime: 31, up: false) == 2)
    }

    @Test func prime11RenderingRemainsSuppressed() async throws {
        let ratio = RatioRef(p: 11, q: 8, octave: 0, monzo: [:])
        let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
        let scalars = label.unicodeScalars.map(\.value)
        let hasDiatonic = scalars.contains { diatonicSet.contains($0) }
        #expect(!hasDiatonic)
    }
}
