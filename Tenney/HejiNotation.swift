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
    case heji2Text
    case heji2Music

    var fontName: String {
        switch self {
        case .bravura: return "Bravura"
        case .systemText: return ".SFUI"
        case .heji2Text: return Heji2FontRegistry.hejiTextFontName
        case .heji2Music: return Heji2FontRegistry.hejiMusicFontName
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

struct HejiMicrotonalComponent: Hashable {
    let prime: Int
    let up: Bool
    /// “How many” of this prime-step the glyph represents (e.g. 1-arrow vs 2-arrows; 1-flag vs 2-flags).
    let steps: Int
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

        let unsupported = unsupportedPrimes(in: ratio, maxPrime: context.maxPrime)

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

    static func textLabel(
        _ spelling: HejiSpelling,
        showCents: Bool = false,
        textStyle: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        basePointSize: CGFloat? = nil
    ) -> AttributedString {
        Heji2FontRegistry.registerIfNeeded()
        let (core, marks) = helmholtzParts(letter: spelling.baseLetter, octave: spelling.helmholtzOctave)
        let baseSize = basePointSize ?? Heji2FontRegistry.preferredPointSize(for: textStyle)
        let baseFont = Font.system(size: baseSize, weight: weight, design: design)

        var out = AttributedString(core + marks)
        out.font = baseFont

        let accidentalText = accidentalGlyphString(for: spelling.accidental)
        if !accidentalText.isEmpty {
            var acc = AttributedString(accidentalText)
            acc.font = Heji2FontRegistry.hejiTextFont(size: baseSize, relativeTo: textStyle)
            out += acc
        }

        if showCents, let cents = spelling.centsError, cents.isFinite {
            let rounded = String(format: "%+.1f¢", cents)
            var centsText = AttributedString(" \(rounded)")
            centsText.font = .system(size: baseSize * 0.75, weight: .regular, design: .default)
            out += centsText
        }

        return out
    }

    static func textLabelString(_ spelling: HejiSpelling, showCents: Bool = false) -> String {
        String(textLabel(spelling, showCents: showCents).characters)
    }

    static func textLabel(
        for ratioRef: RatioRef,
        context: HejiContext,
        showCents: Bool = false,
        textStyle: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        basePointSize: CGFloat? = nil
    ) -> AttributedString {
        if ratioRef.p == 1, ratioRef.q == 1, ratioRef.octave == 0, let tonicE3 = context.tonicE3 {
            let tonic = TonicSpelling(e3: tonicE3)
            return tonic.attributedDisplayText(
                textStyle: textStyle,
                weight: weight,
                design: design,
                basePointSize: basePointSize
            )
        }
        let spelling = spelling(forRatio: ratioRef, context: context)
        return textLabel(
            spelling,
            showCents: showCents,
            textStyle: textStyle,
            weight: weight,
            design: design,
            basePointSize: basePointSize
        )
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
        return HejiStaffLayout(
            clef: clef,
            staffStepFromMiddle: step,
            noteheadGlyph: HejiGlyphs.noteheadBlack,
            accidentalGlyphs: accidentals,
            ledgerLineCount: ledger,
            approxMarkerGlyph: nil
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
        let exponents = primeExponents(for: ratio, maxPrime: maxPrime)
        let mapping = Heji2Mapping.shared
        var components: [HejiMicrotonalComponent] = []
        for (prime, exp) in exponents where prime >= 5 && prime <= maxPrime && exp != 0 && mapping.supportedPrimes.contains(prime) {
                    let up = hejiUpDirection(forPrime: prime, exponent: exp)
                    let count = abs(exp)
        
                    // Prefer “bigger” glyph-steps when the mapping provides them (e.g. 3 -> 2+1).
                    let available = mapping.availableSteps(forPrime: prime) // e.g. [2, 1]
                    let stepParts = decompose(count, using: available)
                    for s in stepParts {
                        components.append(HejiMicrotonalComponent(prime: prime, up: up, steps: s))
                    }
        }
        return components
    }

    /// HEJI polarity is not uniform across primes in practice; prime 11 is the one you called out as inverted.
        private static func hejiUpDirection(forPrime prime: Int, exponent exp: Int) -> Bool {
            switch prime {
            case 11:
                // Fix: 11/8 should read as “up/sharp”, 16/11 as “down/flat”.
                return exp > 0
            default:
                // Works for 5, 7, 13 as used elsewhere in the app currently.
                return exp < 0
            }
        }
    
        private static func decompose(_ count: Int, using availableSteps: [Int]) -> [Int] {
            guard count > 0 else { return [] }
            var steps = availableSteps.filter { $0 > 0 }.sorted(by: >)
            if steps.isEmpty { steps = [1] }
            if steps.last != 1 { steps.append(1) }
    
            var remaining = count
            var out: [Int] = []
            for s in steps {
                while remaining >= s {
                    out.append(s)
                    remaining -= s
                }
                if remaining == 0 { break }
            }
            return out
        }
    
    private static func unsupportedPrimes(in ratio: Ratio, maxPrime: Int) -> [Int] {
        let allPrimes = Set(factorPrimes(in: ratio.n) + factorPrimes(in: ratio.d))
        let supported = Heji2Mapping.shared.supportedPrimes
        let allowed = Set([2, 3]).union(supported.filter { $0 <= maxPrime })
        return allPrimes.filter { !allowed.contains($0) }.sorted()
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
        let mapping = Heji2Mapping.shared
        var baseGlyphs = mapping.glyphsForDiatonicAccidental(accidental.diatonicAccidental)
        if baseGlyphs.isEmpty, accidental.diatonicAccidental == 0, !accidental.microtonalComponents.isEmpty {
            baseGlyphs = [Heji2Glyph(glyph: "\u{E261}", staffOffset: nil, textOffset: nil, advance: nil, staffAdvance: nil, textAdvance: nil)]
        }
        for glyph in baseGlyphs {
            let offset = glyph.staffOffset.map { CGPoint(x: $0.x, y: $0.y) } ?? .zero
            runs.append(GlyphRun(font: .heji2Music, glyph: glyph.string, offset: offset))
        }
        let componentGlyphs = mapping.glyphsForPrimeComponents(accidental.microtonalComponents)
        var stackX: CGFloat = -10
        for glyph in componentGlyphs {
            let offset = glyph.staffOffset.map { CGPoint(x: $0.x, y: $0.y) } ?? .zero
            runs.append(GlyphRun(font: .heji2Music, glyph: glyph.string, offset: CGPoint(x: stackX + offset.x, y: offset.y)))
            let advance = glyph.staffAdvance ?? glyph.advance ?? -10
            stackX += CGFloat(advance)
        }
        return runs
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
        let p = helmholtzParts(letter: letter, octave: octave)
        return p.core + p.marks
    }
    private static func helmholtzParts(letter: String, octave: Int) -> (core: String, marks: String) {
        let lower = letter.lowercased()
        let upper = letter.uppercased()
        if octave >= 4 {
            let primes = String(repeating: "′", count: max(1, octave - 3))
            return (lower, primes)
        } else {
            let commas = String(repeating: ",", count: max(0, 3 - octave))
            return (upper, commas)
        }
    }

    private static func accidentalGlyphString(for accidental: HejiAccidental) -> String {
        let mapping = Heji2Mapping.shared
        let microtonal = mapping.glyphsForPrimeComponents(accidental.microtonalComponents)
        var base = mapping.glyphsForDiatonicAccidental(accidental.diatonicAccidental)
        if base.isEmpty, accidental.diatonicAccidental == 0, !microtonal.isEmpty {
            base = [Heji2Glyph(glyph: "\u{E261}", staffOffset: nil, textOffset: nil, advance: nil, staffAdvance: nil, textAdvance: nil)]
        }
        return (base + microtonal).map(\.string).joined()
    }

    private static func primeExponents(for ratio: Ratio, maxPrime: Int) -> [Int: Int] {
        let num = factorPrimeExponents(abs(ratio.n), maxPrime: maxPrime)
        let den = factorPrimeExponents(abs(ratio.d), maxPrime: maxPrime)
        var out: [Int: Int] = [:]
        for prime in Set(num.keys).union(den.keys) {
            let exp = (num[prime] ?? 0) - (den[prime] ?? 0)
            if exp != 0 { out[prime] = exp }
        }
        return out
    }

    private static func factorPrimeExponents(_ value: Int, maxPrime: Int) -> [Int: Int] {
        guard value > 1 else { return [:] }
        var n = value
        var out: [Int: Int] = [:]
        var p = 2
        while p * p <= n {
            while n % p == 0 {
                out[p, default: 0] += 1
                n /= p
            }
            p += (p == 2 ? 1 : 2)
        }
        if n > 1 { out[n, default: 0] += 1 }
        return out.filter { $0.key <= maxPrime }
    }

    private static func factorPrimes(in value: Int) -> [Int] {
        guard value >= 2 else { return [] }
        var n = value
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
            let prime = component.prime
            let direction = component.up ? "up" : "down"
            switch prime {
            case 5: pieces.append("syntonic comma \(direction)")
            case 7: pieces.append("septimal comma \(direction)")
            case 11: pieces.append("undecimal quartertone \(direction)")
            case 13: pieces.append("tridecimal quartertone \(direction)")
            default: pieces.append("\(prime)-prime comma \(direction)")
            }
        }
        return pieces.joined(separator: " ")
    }
}
