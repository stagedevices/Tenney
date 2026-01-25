//
//  HejiRatioDisplayTests.swift
//  TenneyTests
//

import Foundation
import Testing
#if canImport(CoreText)
import CoreText
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
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
        #expect(pythagoreanBaseE3Interval(p: 13, q: 8, octave: 0) == 3)
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
        #expect(String(label.characters) == tonic.displayText)
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
        let spelling = HejiNotation.spelling(forRatio: ratio, context: context)
        let accidental = accidentalString(for: spelling.accidental)
        #expect(label.localizedCaseInsensitiveContains("d"))
        #expect(label.hasSuffix(accidental))
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
        #expect(labels[1].hasSuffix(accidentalString(for: HejiNotation.spelling(forRatio: ratios[1], context: context).accidental)))
        #expect(labels[4].localizedCaseInsensitiveContains("f"))
        #expect(labels[4].hasSuffix(accidentalString(for: HejiNotation.spelling(forRatio: ratios[4], context: context).accidental)))
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

    @Test func thirteenLimitDoesNotCollapseToTonic() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let ratio = RatioRef(p: 13, q: 8, octave: 0, monzo: [:])
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

    @Test func textAccidentalsAppearAfterNoteAndOctave() async throws {
        let tonic = TonicSpelling.from(letter: "G", accidental: 1)
        let ratios: [RatioRef] = [
            RatioRef(p: 3, q: 2, octave: 0, monzo: [:]),
            RatioRef(p: 5, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 7, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 11, q: 8, octave: 0, monzo: [:]),
            RatioRef(p: 13, q: 8, octave: 0, monzo: [:])
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
        for ratio in ratios {
            let spelling = HejiNotation.spelling(forRatio: ratio, context: context)
            let label = HejiNotation.textLabelString(spelling, showCents: false)
            let accidental = accidentalString(for: spelling.accidental)
            #expect(!accidental.isEmpty)
            #expect(label.hasSuffix(accidental))
        }
    }

    @Test func fiveLimitAccidentalsRenderInBaseThenModifierOrder() async throws {
        let tonic = TonicSpelling.from(letter: "C", accidental: 0)
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .auto,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: tonic.e3
        )
        let cases: [RatioRef] = [
            RatioRef(p: 32, q: 25, octave: 0, monzo: [:]),
            RatioRef(p: 5, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 8, q: 5, octave: 0, monzo: [:])
        ]
        for ratio in cases {
            let spelling = HejiNotation.spelling(forRatio: ratio, context: context)
            let accidental = accidentalString(for: spelling.accidental)
            let label = HejiNotation.textLabelString(spelling, showCents: false)
            #expect(label.hasSuffix(accidental))
            #expect(label.unicodeScalars.suffix(accidental.unicodeScalars.count).elementsEqual(accidental.unicodeScalars))
        }
    }

    @Test func fiveLimitAccidentalsAvoidForcedNaturals() async throws {
        let tonic = TonicSpelling.from(letter: "C", accidental: 0)
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .auto,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: tonic.e3
        )
        let naturalGlyph = "\u{E261}"
        let ratios: [RatioRef] = [
            RatioRef(p: 32, q: 25, octave: 0, monzo: [:]),
            RatioRef(p: 5, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 8, q: 5, octave: 0, monzo: [:])
        ]
        let spellings = ratios.map { HejiNotation.spelling(forRatio: $0, context: context) }
        let accidentals = spellings.map { accidentalString(for: $0.accidental) }
        #expect(!accidentals[0].hasPrefix(naturalGlyph))
        #expect(!accidentals[1].hasPrefix(naturalGlyph))
        #expect(accidentals[2].hasPrefix(naturalGlyph))
    }

    @Test func tridecimalAccidentalsUseHejiTextFontRun() async throws {
        let tonic = TonicSpelling.from(letter: "C", accidental: 0)
        let ratio = RatioRef(p: 13, q: 8, octave: 0, monzo: [:])
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .auto,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: ratio,
            tonicE3: tonic.e3
        )
        let spelling = HejiNotation.spelling(forRatio: ratio, context: context)
        let label = HejiNotation.textLabel(spelling, showCents: false)
        let labelString = String(label.characters)
        let accidental = accidentalString(for: spelling.accidental)
        #expect(!accidental.isEmpty)
        #expect(labelString.hasSuffix(accidental))

        let nsLabel = NSAttributedString(label)
        guard let range = labelString.range(of: accidental) else {
            #expect(false, "Expected accidental substring in label.")
            return
        }
        let location = labelString.distance(from: labelString.startIndex, to: range.lowerBound)
        let fontAttribute = nsLabel.attribute(.font, at: location, effectiveRange: nil)
        let expectedFontName = Heji2FontRegistry.hejiTextFontName

#if canImport(UIKit)
        let fontName = (fontAttribute as? UIFont)?.fontName
            ?? (fontAttribute as? CTFont).map { CTFontCopyPostScriptName($0) as String }
        #expect(fontName?.contains(expectedFontName) == true)
#elseif canImport(AppKit)
        let fontName = (fontAttribute as? NSFont)?.fontName
            ?? (fontAttribute as? CTFont).map { CTFontCopyPostScriptName($0) as String }
        #expect(fontName?.contains(expectedFontName) == true)
#else
        #expect(fontAttribute != nil)
#endif
    }

    @Test func tridecimalGlyphsExistInHejiFont() async throws {
#if canImport(CoreText)
        Heji2FontRegistry.registerIfNeeded()
        let component = HejiMicrotonalComponent(prime: 13, up: true, steps: 1)
        let glyphString = Heji2Mapping.shared
            .glyphsForPrimeComponents([component])
            .map(\.string)
            .joined()
        #expect(!glyphString.isEmpty)

        let fontName = Heji2FontRegistry.hejiTextFontName
        let font = CTFontCreateWithName(fontName as CFString, 16, nil)
        let characters = Array(glyphString.utf16)
        var glyphs = Array<CGGlyph>(repeating: 0, count: characters.count)
        let mapped = CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        #expect(mapped)
        #expect(glyphs.contains { $0 != 0 })
#else
        #expect(true)
#endif
    }

    @Test func textLabelsAvoidForbiddenSymbols() async throws {
        let context = HejiContext(
            concertA4Hz: 440,
            noteNameA4Hz: 440,
            rootHz: 440,
            rootRatio: nil,
            preferred: .auto,
            maxPrime: 13,
            allowApproximation: true,
            scaleDegreeHint: nil,
            tonicE3: nil
        )
        let ratios: [RatioRef] = [
            RatioRef(p: 1, q: 1, octave: 0, monzo: [:]),
            RatioRef(p: 3, q: 2, octave: 0, monzo: [:]),
            RatioRef(p: 5, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 7, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 11, q: 8, octave: 0, monzo: [:]),
            RatioRef(p: 13, q: 8, octave: 0, monzo: [:])
        ]
        let labels = ratios.map { HejiNotation.textLabelString(for: $0, context: context, showCents: true) }
        let forbidden: [Character] = ["↑", "↓", "⇑", "⇓", "⤒", "⤓", "♯", "♭", "♮", "≈"]
        for label in labels {
            for ch in forbidden {
                #expect(!label.contains(ch))
            }
        }
    }

    @Test func supportedPrimesIncludeHejiDefaults() async throws {
        let context = HejiContext(
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
        let ratio = RatioRef(p: 13, q: 8, octave: 0, monzo: [:])
        let spelling = HejiNotation.spelling(forRatio: ratio, context: context)
        #expect(spelling.unsupportedPrimes.isEmpty)
    }

    private func baseLetter(from label: String) -> String? {
        for ch in label.lowercased() {
            if "abcdefg".contains(ch) {
                return String(ch)
            }
        }
        return nil
    }

    private func accidentalString(for accidental: HejiAccidental) -> String {
        let mapping = Heji2Mapping.shared
        let microtonal = mapping.glyphsForPrimeComponents(accidental.microtonalComponents)
        let diatonic = mapping.glyphsForDiatonicAccidental(accidental.diatonicAccidental)
        return (diatonic + microtonal).map(\.string).joined()
    }
}
