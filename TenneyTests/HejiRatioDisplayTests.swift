//
//  HejiRatioDisplayTests.swift
//  TenneyTests
//

import Testing
@testable import Tenney

struct HejiRatioDisplayTests {

    @Test func pythagoreanBaseE3IntervalForFifteenEight() async throws {
        #expect(pythagoreanBaseE3Interval(p: 15, q: 8, octave: 0) == 5)
    }

    @Test func pythagoreanBaseE3IntervalWhitelist() async throws {
        #expect(pythagoreanBaseE3Interval(p: 3, q: 2, octave: 0) == 1)
        #expect(pythagoreanBaseE3Interval(p: 4, q: 3, octave: 0) == -1)
        #expect(pythagoreanBaseE3Interval(p: 5, q: 4, octave: 0) == 4)
        #expect(pythagoreanBaseE3Interval(p: 6, q: 5, octave: 0) == -3)
        #expect(pythagoreanBaseE3Interval(p: 9, q: 8, octave: 0) == 2)
    }

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
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: ratio,
            tonicE3: tonic.e3
        )
        let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
        #expect(label.localizedCaseInsensitiveContains("f"))
        #expect(label.contains("\u{1D12A}"))
        #expect(!label.localizedCaseInsensitiveContains("g"))
    }

    @Test func manualTonicPerfectFifthUsesDSharp() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let ratio = RatioRef(p: 3, q: 2, octave: 0, monzo: [:])
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: ratio,
            tonicE3: tonic.e3
        )
        let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
        #expect(label.localizedCaseInsensitiveContains("d"))
        #expect(label.contains("♯"))
    }

    @Test func tonicGSharpLabelsStayDistinct() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let ratios: [RatioRef] = [
            RatioRef(p: 1, q: 1, octave: 0, monzo: [:]),
            RatioRef(p: 3, q: 2, octave: 0, monzo: [:]),
            RatioRef(p: 5, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 9, q: 8, octave: 0, monzo: [:]),
            RatioRef(p: 15, q: 8, octave: 0, monzo: [:])
        ]
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: tonic.e3
        )
        let labels = ratios.map { HejiNotation.textLabelString(for: $0, context: context, showCents: false) }
        let baseLetters = labels.compactMap { baseLetter(from: $0) }
        #expect(baseLetters.count == ratios.count)
        #expect(Set(baseLetters).count >= 3)
        #expect(!baseLetters.allSatisfy { $0 == "g" })
        #expect(baseLetters[2] != "g")
        #expect(baseLetters[3] != "g")
        #expect(labels[0] == tonic.displayText)
        #expect(labels[1].localizedCaseInsensitiveContains("d"))
        #expect(labels[1].contains("♯"))
        #expect(labels[4].localizedCaseInsensitiveContains("f"))
        #expect(labels[4].contains("\u{1D12A}"))
    }

    @Test func unsupportedPrimeDoesNotCollapseToTonic() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let ratio = RatioRef(p: 17, q: 16, octave: 0, monzo: [:])
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .preferSharps,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: ratio,
            tonicE3: tonic.e3
        )
        let label = HejiNotation.textLabelString(for: ratio, context: context, showCents: false)
        let base = baseLetter(from: label)
        #expect(base != "g")
        #expect(label != tonic.displayText)
    }

    private func baseLetter(from label: String) -> String? {
        for ch in label.lowercased() {
            if "abcdefg".contains(ch) {
                return String(ch)
            }
        }
        return nil
    }
}
