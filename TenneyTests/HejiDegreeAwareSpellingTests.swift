//
//  HejiDegreeAwareSpellingTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiDegreeAwareSpellingTests {

    @Test func manualTonicTransposesIntervalLetter() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 415,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: tonic.e3
        )
        let spelling = HejiNotation.spelling(forRatio: RatioRef(p: 15, q: 8, octave: 0, monzo: [:]), context: context)
        #expect(spelling.baseLetter == "F")
        #expect(spelling.accidental.diatonicAccidental == 2)
    }

    @Test func concertPitchDoesNotAffectLetterChoice() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let context440 = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 415,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: tonic.e3
        )
        let context415 = HejiContext(
            concertA4Hz: 415,
            noteNameA4Hz: 440,
            rootHz: 415,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: tonic.e3
        )
        let spelling440 = HejiNotation.spelling(forRatio: RatioRef(p: 15, q: 8, octave: 0, monzo: [:]), context: context440)
        let spelling415 = HejiNotation.spelling(forRatio: RatioRef(p: 15, q: 8, octave: 0, monzo: [:]), context: context415)
        #expect(spelling440.baseLetter == spelling415.baseLetter)
        #expect(spelling440.accidental.diatonicAccidental == spelling415.accidental.diatonicAccidental)
    }

    @Test func autoTonicDerivationUsesNamingReference() async throws {
        let spelling = TonicSpelling.from(rootHz: 415, noteNameA4Hz: 440, preference: .preferSharps)
        #expect(spelling?.letter == "G")
        #expect(spelling?.accidentalCount == 1)
    }
}
