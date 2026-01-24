//
//  HejiRatioDisplayTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiRatioDisplayTests {

    @Test func manualTonicUnisonUsesTonicDisplay() async throws {
        let tonic = TonicSpelling.from(letter: "C", accidental: 0)
        let ratio = RatioRef(p: 1, q: 1, octave: 0, monzo: [:])
        let label = spellHejiRatioDisplay(
            ratio: ratio,
            tonic: tonic,
            rootHz: 440,
            noteNameA4Hz: 440,
            concertA4Hz: 440,
            accidentalPreference: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            showCents: false,
            applyAccidentalPreference: false
        )
        #expect(label == tonic.displayText)
    }

    @Test func manualTonicSpellsIntervalRelativeToTonic() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let ratio = RatioRef(p: 15, q: 8, octave: 0, monzo: [:])
        let label = spellHejiRatioDisplay(
            ratio: ratio,
            tonic: tonic,
            rootHz: 440,
            noteNameA4Hz: 440,
            concertA4Hz: 440,
            accidentalPreference: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            showCents: false,
            applyAccidentalPreference: false
        )
        #expect(label == "♯♯f′′")
    }
}
