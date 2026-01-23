//
//  HejiDegreeAwareSpellingTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiDegreeAwareSpellingTests {

    @Test func majorSeventhDegreeUsesDiatonicLetterWithSharps() async throws {
        let context = HejiContext(
            referenceA4Hz: 440,
            rootHz: 415,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil
        )
        let spelling = HejiNotation.spelling(forRatio: RatioRef(p: 15, q: 8, octave: 0, monzo: [:]), context: context)
        #expect(spelling.baseLetter == "F")
        #expect(spelling.accidental.diatonicAccidental == 2)
    }

    @Test func majorSeventhDegreeUsesDiatonicLetterWithFlats() async throws {
        let context = HejiContext(
            referenceA4Hz: 440,
            rootHz: 415,
            rootRatio: nil,
            preferred: .preferFlats,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil
        )
        let spelling = HejiNotation.spelling(forRatio: RatioRef(p: 15, q: 8, octave: 0, monzo: [:]), context: context)
        #expect(spelling.baseLetter == "G")
        #expect(spelling.accidental.diatonicAccidental == 0)
    }

    @Test func nonLandmarkRatioFallsBackToDefaultSpelling() async throws {
        let context = HejiContext(
            referenceA4Hz: 440,
            rootHz: 415,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil
        )
        let spelling = HejiNotation.spelling(forRatio: RatioRef(p: 11, q: 8, octave: 0, monzo: [:]), context: context)
        #expect(!spelling.baseLetter.isEmpty)
    }
}
