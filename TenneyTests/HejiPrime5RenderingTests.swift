//
//  HejiPrime5RenderingTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiPrime5RenderingTests {

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

    @Test func prime5DownOneUsesSharpVariant() async throws {
        let ratio = RatioRef(p: 5, q: 3, octave: 0, monzo: [:])
        let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
        let sharpDownOne = "\u{E2C3}"
        let naturalDownOne = "\u{E2C2}"
        #expect(label.contains(sharpDownOne))
        #expect(!label.contains(naturalDownOne))
    }

    @Test func prime5DownThreeUsesSingleSharpVariant() async throws {
        let ratio = RatioRef(p: 125, q: 108, octave: 0, monzo: [:])
        let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
        let sharpDownThree = "\u{E2D7}"
        let naturalDownThree = "\u{E2D6}"
        #expect(label.contains(sharpDownThree))
        #expect(!label.contains(naturalDownThree))
        #expect(!label.contains("\u{E2C2}"))
        #expect(!label.contains("\u{E2C3}"))
        #expect(!label.contains("\u{E2CC}"))
        #expect(!label.contains("\u{E2CD}"))
    }
}
