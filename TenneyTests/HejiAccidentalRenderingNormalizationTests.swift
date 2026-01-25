//
//  HejiAccidentalRenderingNormalizationTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiAccidentalRenderingNormalizationTests {

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

    private let diatonicSet: Set<UInt32> = [
        0xE260, 0xE261, 0xE262, 0xE263, 0xE264, 0xE265, 0xE266
    ]

    private func assertNoDiatonicAndHasMicrotonal(_ label: String) {
        let scalars = label.unicodeScalars.map(\.value)
        let hasDiatonic = scalars.contains { diatonicSet.contains($0) }
        let hasMicrotonal = scalars.contains { (0xE000...0xF8FF).contains($0) && !diatonicSet.contains($0) }
        #expect(!hasDiatonic, "Expected no diatonic accidental scalars in \\(label).")
        #expect(hasMicrotonal, "Expected microtonal PUA scalar in \\(label).")
    }

    @Test func prime11SuppressesDiatonicAccidentals() async throws {
        let ratios: [RatioRef] = [
            RatioRef(p: 11, q: 8, octave: 0, monzo: [:]),
            RatioRef(p: 16, q: 11, octave: 0, monzo: [:]),
            RatioRef(p: 128, q: 121, octave: 0, monzo: [:]),
            RatioRef(p: 1331, q: 1024, octave: 0, monzo: [:])
        ]

        for ratio in ratios {
            let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
            assertNoDiatonicAndHasMicrotonal(label)
        }
    }

    @Test func prime5AbsorbsDiatonicAccidentals() async throws {
        let ratio = RatioRef(p: 125, q: 64, octave: 0, monzo: [:])
        let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
        assertNoDiatonicAndHasMicrotonal(label)
    }
}
