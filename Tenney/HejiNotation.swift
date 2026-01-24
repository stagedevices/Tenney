//
//  HejiNotation.swift
//  Tenney
//
//  Facade for HEJI spelling + layout.
//

import Foundation
import CoreGraphics
import SwiftUI

enum HejiNotationMode: String, CaseIterable, Identifiable {
    case staff
    case text
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .staff: return "Staff"
        case .text: return "Text"
        case .combined: return "Combined"
        }
    }
}

enum AccidentalPreference: String, CaseIterable, Identifiable {
    case auto
    case preferSharps
    case preferFlats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .preferSharps: return "Sharps"
        case .preferFlats: return "Flats"
        }
    }
}

struct HejiContext {
    /// Concert pitch reference (audio/test tone behavior).
    var concertA4Hz: Double
    /// Absolute note-name reference (ET mapping for octave/letter).
    var noteNameA4Hz: Double
    var rootHz: Double
    var rootRatio: RatioRef?
    var preferred: AccidentalPreference
    var maxPrime: Int
    var allowApproximation: Bool
    var scaleDegreeHint: RatioRef?
    var tonicE3: Int?

    static let `default` = HejiContext(
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
}

enum HejiFont {
    case bravura
    case systemText

    var fontName: String {
        switch self {
        case .bravura: return "Bravura"
        case .systemText: return ".SFUI"
        }
    }
}

struct GlyphRun: Hashable {
    var font: HejiFont
    var glyph: String
    var offset: CGPoint
}

struct HejiSpelling: Hashable {
    var baseLetter: String
    var helmholtzOctave: Int
    var accidental: HejiAccidental
    var isApproximate: Bool
    var centsError: Double?
    var ratio: Ratio?
    var unsupportedPrimes: [Int]
}

struct HejiStaffLayout: Hashable {
    enum Clef: Hashable { case treble, bass }
    var clef: Clef
    var staffStepFromMiddle: Int
    var noteheadGlyph: String
    var accidentalGlyphs: [GlyphRun]
    var ledgerLineCount: Int
    var approxMarkerGlyph: String?
}

struct HejiAccidental: Hashable {
    var diatonicAccidental: Int
    var microtonalComponents: [HejiMicrotonalComponent]
}

enum HejiMicrotonalComponent: Hashable {
    case syntonic(up: Bool)
    case septimal(up: Bool)
    case undecimal(up: Bool)
    case tridecimal(up: Bool)
}

enum HejiNotation {
    static func spelling(forRatio ratioRef: RatioRef, context: HejiContext) -> HejiSpelling {
        let ratio = Ratio(ratioRef.p, ratioRef.q)
        let spelling = spelling(forRatio: ratio, octave: ratioRef.octave, context: context)
        if shouldLogHejiLabel(for: ratioRef) {
            let e3Interval = pythagoreanBaseE3Interval(for: ratio, octave: ratioRef.octave, maxPrime: context.maxPrime)
            let e3Total = context.tonicE3.map { $0 + e3Interval } ?? e3Interval
            let base = letter(for: e3Total)
            let tonicDisplay = context.tonicE3.map { TonicSpelling(e3: $0).displayText } ?? "nil"
            let tonicE3Text = context.tonicE3.map(String.init) ?? "nil"
            let label = textLabelString(spelling, showCents: false)
            print("[HEJI] ratio=\(ratioRef.p)/\(ratioRef.q) oct=\(ratioRef.octave) tonicE3=\(tonicE3Text) tonic=\(tonicDisplay) e3Interval=\(e3Interval) e3Total=\(e3Total) base=\(base.letter) acc=\(base.accidentalCount) label=\"\(label)\"")
        }
        return spelling
    }

    static func spelling(forRatio ratio: Ratio, octave: Int = 0, context: HejiContext) -> HejiSpelling {
        let value = ratio.value * pow(2.0, Double(octave))
        let e3Interval = pythagoreanBaseE3Interval(for: ratio, octave: octave, maxPrime: context.maxPrime)
        let e3Total = context.tonicE3.map { $0 + e3Interval } ?? e3Interval
        let base = letter(for: e3Total)
        let accidental = HejiAccidental(
            diatonicAccidental: base.accidentalCount,
            microtonalComponents: microtonalComponents(for: ratio, maxPrime: context.maxPrime)
        )

        let hz = context.rootHz > 0 ? context.rootHz * value : value
        let staff = NotationFormatter.staffNoteName(freqHz: hz, a4Hz: context.noteNameA4Hz)
        let octaveOut = staff.octave

        let unsupported = unsupportedPrimes(in: ratio)

        return HejiSpelling(
            baseLetter: base.letter,
            helmholtzOctave: octaveOut,
            accidental: accidental,
            isApproximate: false,
            centsError: nil,
            ratio: ratio,
            unsupportedPrimes: unsupported
        )
    }

    static func spelling(forFrequency hz: Double, context: HejiContext) -> HejiSpelling {
        if let hint = context.scaleDegreeHint {
            return spelling(forRatio: hint, context: context)
        }

        guard context.allowApproximation, context.rootHz > 0, hz.isFinite, hz > 0 else {
            let ratio = Ratio(1, 1)
            return spelling(forRatio: ratio, context: context)
        }

        let ratioValue = hz / context.rootHz
        let primeLimit = resolvePrimeLimit(context.maxPrime)
        let approx = RatioApproximator.approximate(ratioValue, options: .init(primeLimit: primeLimit, maxDenominator: 4096, maxCentsError: 120))
        let centsError = 1200.0 * log2(approx.value / ratioValue)
        var spelling = spelling(forRatio: approx, context: context)
        spelling.isApproximate = true
        spelling.centsError = centsError
        return spelling
    }

    static func textLabel(_ spelling: HejiSpelling, showCents: Bool = false) -> AttributedString {
        var out = AttributedString(helmholtzLabel(letter: spelling.baseLetter, octave: spelling.helmholtzOctave))
        let accidentalText = textAccidental(spelling.accidental)
        if !accidentalText.isEmpty {
            var acc = AttributedString(accidentalText)
            acc.font = .system(size: 16, weight: .regular)
            out = acc + out
        }

        if spelling.isApproximate {
            var approx = AttributedString(" ≈")
            approx.font = .system(size: 14, weight: .regular)
            out += approx
        }

        if showCents, let cents = spelling.centsError, cents.isFinite {
            let rounded = String(format: "%+.1f¢", cents)
            var centsText = AttributedString(" \(rounded)")
            centsText.font = .system(size: 12, weight: .regular)
            out += centsText
        }

        return out
    }

    static func textLabelString(_ spelling: HejiSpelling, showCents: Bool = false) -> String {
        String(textLabel(spelling, showCents: showCents).characters)
    }

    static func textLabelString(for ratioRef: RatioRef, context: HejiContext, showCents: Bool = false) -> String {
        if ratioRef.p == 1, ratioRef.q == 1, ratioRef.octave == 0, let tonicE3 = context.tonicE3 {
            return TonicSpelling(e3: tonicE3).displayText
        }
        let spelling = spelling(forRatio: ratioRef, context: context)
        return textLabelString(spelling, showCents: showCents)
    }

    static func accessibilityLabel(_ spelling: HejiSpelling) -> String {
        var parts: [String] = []
        parts.append(spelling.baseLetter)
        if !spelling.accidental.verbalization.isEmpty {
            parts.append(spelling.accidental.verbalization)
        }
        parts.append("Helmholtz \(helmholtzLabel(letter: spelling.baseLetter, octave: spelling.helmholtzOctave))")
        if let ratio = spelling.ratio {
            parts.append("ratio \(ratio.n)/\(ratio.d)")
        }
        if spelling.isApproximate, let cents = spelling.centsError, cents.isFinite {
            parts.append(String(format: "approximately, %.1f cents", cents))
        }
        return parts.joined(separator: " ")
    }

    static func staffLayout(_ spelling: HejiSpelling, context: HejiContext) -> HejiStaffLayout {
        let clef = autoClef(forOctave: spelling.helmholtzOctave)
        let step = staffStepFromMiddle(letter: spelling.baseLetter, octave: spelling.helmholtzOctave, clef: clef)
        let accidentals = staffAccidentalGlyphs(spelling.accidental)
        let ledger = ledgerLineCount(for: step)
        let approx = spelling.isApproximate ? "≈" : nil
        return HejiStaffLayout(
            clef: clef,
            staffStepFromMiddle: step,
            noteheadGlyph: HejiGlyphs.noteheadBlack,
            accidentalGlyphs: accidentals,
            ledgerLineCount: ledger,
            approxMarkerGlyph: approx
        )
    }

    // MARK: - 3-limit base

    private static func letter(for e3: Int) -> (letter: String, accidentalCount: Int) {
        let spelling = TonicSpelling(e3: e3)
        return (spelling.letter, spelling.accidentalCount)
    }

    private static func shouldLogHejiLabel(for ratioRef: RatioRef) -> Bool {
        guard ProcessInfo.processInfo.environment["HEJI_DEBUG_LABELS"] == "1" else { return false }
        guard ratioRef.octave == 0 else { return false }
        let reduced = Ratio(ratioRef.p, ratioRef.q)
        let key = "\(reduced.n)/\(reduced.d)"
        let whitelist: Set<String> = ["1/1", "3/2", "4/3", "5/4", "6/5", "9/8", "15/8"]
        return whitelist.contains(key)
    }

    // MARK: - Microtonal components

    private static func microtonalComponents(for ratio: Ratio, maxPrime: Int) -> [HejiMicrotonalComponent] {
        guard let monzo = ratio.toMonzoIfWithin13() else { return [] }
        var components: [HejiMicrotonalComponent] = []
        let primes: [(Int, Int)] = [(5, monzo.e5), (7, monzo.e7), (11, monzo.e11), (13, monzo.e13)]
        for (prime, exp) in primes where prime <= maxPrime && exp != 0 {
            let up = exp < 0
            let count = abs(exp)
            let component: HejiMicrotonalComponent
            switch prime {
            case 5: component = .syntonic(up: up)
            case 7: component = .septimal(up: up)
            case 11: component = .undecimal(up: up)
            case 13: component = .tridecimal(up: up)
            default: continue
            }
            components.append(contentsOf: Array(repeating: component, count: count))
        }
        return components
    }

    private static func unsupportedPrimes(in ratio: Ratio) -> [Int] {
        let primes = [2, 3, 5, 7, 11, 13]
        func factor(_ x: Int) -> [Int] {
            var n = abs(x)
            var out: [Int] = []
            var p = 2
            while p * p <= n {
                if n % p == 0 {
                    out.append(p)
                    while n % p == 0 { n /= p }
                }
                p += (p == 2 ? 1 : 2)
            }
            if n > 1 { out.append(n) }
            return out
        }
        let all = Set(factor(ratio.n) + factor(ratio.d))
        return all.filter { !primes.contains($0) }.sorted()
    }

    // MARK: - Staff layout helpers

    private static func autoClef(forOctave octave: Int) -> HejiStaffLayout.Clef {
        // Heuristic: treble at middle C (C4) and above; bass below.
        return octave >= 4 ? .treble : .bass
    }

    private static func staffStepFromMiddle(letter: String, octave: Int, clef: HejiStaffLayout.Clef) -> Int {
        let baseLetter: String
        let baseOctave: Int
        switch clef {
        case .treble:
            baseLetter = "B" // middle line (B4)
            baseOctave = 4
        case .bass:
            baseLetter = "D" // middle line (D3)
            baseOctave = 3
        }
        let noteIndex = diatonicIndex(letter: letter, octave: octave)
        let baseIndex = diatonicIndex(letter: baseLetter, octave: baseOctave)
        return noteIndex - baseIndex
    }

    private static func diatonicIndex(letter: String, octave: Int) -> Int {
        let order = ["C", "D", "E", "F", "G", "A", "B"]
        let idx = order.firstIndex(of: letter.uppercased()) ?? 0
        return octave * 7 + idx
    }

    private static func ledgerLineCount(for staffStep: Int) -> Int {
        let absStep = abs(staffStep)
        if absStep <= 4 { return 0 }
        return (absStep - 4 + 1) / 2
    }

    private static func staffAccidentalGlyphs(_ accidental: HejiAccidental) -> [GlyphRun] {
        var runs: [GlyphRun] = []
        if accidental.diatonicAccidental != 0 {
            let glyph = HejiGlyphs.standardAccidental(for: accidental.diatonicAccidental)
            runs.append(GlyphRun(font: .bravura, glyph: glyph, offset: .zero))
        }
        for (index, component) in accidental.microtonalComponents.enumerated() {
            let glyph = HejiGlyphs.microtonalGlyph(for: component)
            let offset = CGPoint(x: CGFloat(index + 1) * -10, y: 0)
            runs.append(GlyphRun(font: .bravura, glyph: glyph, offset: offset))
        }
        return runs
    }

    private static func textAccidental(_ accidental: HejiAccidental) -> String {
        var text = ""
        text += accidentalGlyph(accidental.diatonicAccidental)
        for component in accidental.microtonalComponents {
            switch component {
            case .syntonic(let up): text += up ? "↑" : "↓"
            case .septimal(let up): text += up ? "⇑" : "⇓"
            case .undecimal(let up): text += up ? "⤒" : "⤓"
            case .tridecimal(let up): text += up ? "⤒" : "⤓"
            }
        }
        return text
    }

    private static func resolvePrimeLimit(_ maxPrime: Int) -> PrimeLimit {
        switch maxPrime {
        case ..<5: return .three
        case 5: return .five
        case 6...7: return .seven
        case 8...11: return .eleven
        default: return .thirteen
        }
    }

    private static func helmholtzLabel(letter: String, octave: Int) -> String {
        let lower = letter.lowercased()
        let upper = letter.uppercased()
        if octave >= 4 {
            let primes = String(repeating: "′", count: max(1, octave - 3))
            return "\(lower)\(primes)"
        } else {
            let commas = String(repeating: ",", count: max(0, 3 - octave))
            return "\(upper)\(commas)"
        }
    }
}

private extension HejiAccidental {
    var verbalization: String {
        var pieces: [String] = []
        if diatonicAccidental > 0 {
            pieces.append(String(repeating: "sharp ", count: diatonicAccidental).trimmingCharacters(in: .whitespaces))
        } else if diatonicAccidental < 0 {
            pieces.append(String(repeating: "flat ", count: abs(diatonicAccidental)).trimmingCharacters(in: .whitespaces))
        }
        for component in microtonalComponents {
            switch component {
            case .syntonic(let up): pieces.append(up ? "syntonic comma up" : "syntonic comma down")
            case .septimal(let up): pieces.append(up ? "septimal comma up" : "septimal comma down")
            case .undecimal(let up): pieces.append(up ? "undecimal quartertone up" : "undecimal quartertone down")
            case .tridecimal(let up): pieces.append(up ? "tridecimal quartertone up" : "tridecimal quartertone down")
            }
        }
        return pieces.joined(separator: " ")
    }
}
