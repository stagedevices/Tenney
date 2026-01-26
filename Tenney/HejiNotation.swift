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
    private static let placeholderNatural = "\u{E261}"
        // HEJI2 / SMuFL-ish diatonic accidentals you’re already using.
        // (We only need “non-natural” to know when E261 is just a placeholder.)
        private static let diatonicAccidentals: Set<String> = [
            "\u{E260}", // flat
            "\u{E262}", // sharp
            "\u{E263}", // double-sharp
            "\u{E264}", // double-flat
            "\u{E265}", // triple-sharp (if present)
            "\u{E266}"  // triple-flat (if present)
        ]
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
        
        let hz = context.rootHz > 0 ? context.rootHz * value : value
                let staff = NotationFormatter.staffNoteName(freqHz: hz, a4Hz: context.noteNameA4Hz)
                let octaveOut = staff.octave
        let e3Interval = pythagoreanBaseE3Interval(for: ratio, octave: octave, maxPrime: context.maxPrime)
        let e3Total = context.tonicE3.map { $0 + e3Interval } ?? e3Interval
        let base = letter(for: e3Total)
        
        let diatonicAcc = bestDiatonicAccidentalCount(
                    for: base.letter,
                    nearOctave: octaveOut,
                    freqHz: hz,
                    a4Hz: context.noteNameA4Hz
                )
        var baseLetter = base.letter
        var diatonicAccidental = diatonicAcc
        var microComponents = microtonalComponents(for: ratio, maxPrime: context.maxPrime)

        // Prime-29: surgical fix for the specific F# edge case (e.g. 841/512 and (32/29)^5),
                // without affecting other prime-29 spellings (notably the A𝄪→B rewrite for 32/29).
                if microComponents.contains(where: { $0.prime == 29 }) {
                    let primes = Set(factorPrimes(in: abs(ratio.n)) + factorPrimes(in: abs(ratio.d)))
                    let pure29 = primes.contains(29) && primes.subtracting([2, 29]).isEmpty
                    if pure29 && baseLetter == "F" && diatonicAccidental == 1 {
                        diatonicAccidental = 0
                    }
                }
        
        if microComponents.contains(where: { $0.prime == 17 }),
           let tonicE3 = context.tonicE3 {
            let semitoneOffset = roundedSemitoneOffset(from: value)
            if abs(semitoneOffset) <= 2 {
                // Prime-17 schisma near-tonic anchoring: keep tonic letter and force 17 down.
                baseLetter = letter(for: tonicE3).letter
                diatonicAccidental = max(-2, min(2, semitoneOffset))
                microComponents = microComponents.map { component in
                    guard component.prime == 17 else { return component }
                    return HejiMicrotonalComponent(prime: 17, up: false, steps: component.steps)
                }
            }
        }

        if let prime19 = microComponents.first(where: { $0.prime == 19 }) {
            // Prime-19 schisma enharmonic preference is driven by its direction only.
            let rewritten = rewriteEnharmonic(
                letter: baseLetter,
                accidental: diatonicAccidental,
                preferSharps: !prime19.up
            )
            baseLetter = rewritten.letter
            diatonicAccidental = rewritten.accidental
        } else if let prime23 = microComponents.first(where: { $0.prime == 23 }) {
            let rewritten = applyEnharmonicSidePreferenceForPrime23(
                baseLetter: baseLetter,
                diatonicAccidental: diatonicAccidental,
                preferSharps: prime23.up
            )
            baseLetter = rewritten.baseLetter
            diatonicAccidental = rewritten.diatonicAccidental
        }
        
        // Prime-29 only: prefer adjacent naturals over double-accidentals when equivalent.
               // (Do NOT fight the prime-17 near-tonic “tonic-letter anchored” rule.)
               let has29 = microComponents.contains(where: { $0.prime == 29 })
               let has17 = microComponents.contains(where: { $0.prime == 17 })
               if has29 && !has17 && baseLetter == "A" && diatonicAccidental == 2 {
                   baseLetter = "B"
                   diatonicAccidental = 0
               }

        if shouldAnchorToTonicForPrime31(
            ratioValue: value,
            context: context,
            microComponents: microComponents
        ) {
            if let tonicE3 = context.tonicE3 {
                baseLetter = letter(for: tonicE3).letter
                diatonicAccidental = 0
            }
        }

        let accidental = HejiAccidental(
            diatonicAccidental: diatonicAccidental,
            microtonalComponents: microComponents
        )

        let unsupported = unsupportedPrimes(in: ratio, maxPrime: context.maxPrime)

        return HejiSpelling(
            baseLetter: baseLetter,
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
        logHejiRenderingIfNeeded(spelling)
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
        logHejiRenderingIfNeeded(spelling) // ← add
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

    private static func logHejiRenderingIfNeeded(_ spelling: HejiSpelling) {
#if DEBUG
        guard let ratio = spelling.ratio else { return }
        let reduced = Ratio(ratio.n, ratio.d)
        let key = "\(reduced.n)/\(reduced.d)"
        let targets: Set<String> = ["32/25", "5/4", "8/5"]
        guard targets.contains(key) else { return }
        let components = spelling.accidental.microtonalComponents
            .map { "(\($0.prime), \($0.steps), \($0.up))" }
            .joined(separator: ", ")
        print("[HEJI_RENDER] ratio=\(key) baseLetter=\(spelling.baseLetter) diatonicAccidental=\(spelling.accidental.diatonicAccidental) microtonalComponents=[\(components)]")
#endif
    }

    // MARK: - Microtonal components

    private static func microtonalComponents(for ratio: Ratio, maxPrime: Int) -> [HejiMicrotonalComponent] {
        let exponents = primeExponents(for: ratio, maxPrime: maxPrime)
        let mapping = Heji2Mapping.shared
#if DEBUG
        if maxPrime >= 5 {
            let missing = exponents
                .filter { $0.key >= 5 && $0.key <= maxPrime && $0.value != 0 && !mapping.supportsPrime($0.key) }
            if !missing.isEmpty {
                let ratioText = "\(ratio.n)/\(ratio.d)"
                for (prime, exp) in missing.sorted(by: { $0.key < $1.key }) {
                    print("[HEJI_MISSING_MAPPING] prime=\(prime) exp=\(exp) ratio=\(ratioText) maxPrime=\(maxPrime)")
                }
            }
        }
#endif
        var components: [HejiMicrotonalComponent] = []
        for prime in exponents.keys.sorted() {
            guard prime >= 5, prime <= maxPrime, mapping.supportsPrime(prime) else { continue }
            // Don’t let a stale supportedPrimes list block 13 (or higher) if the mapping actually has steps.
            guard !mapping.availableSteps(forPrime: prime).isEmpty || mapping.supportedPrimes.contains(prime) else { continue }
            let exp = exponents[prime] ?? 0
            guard exp != 0 else { continue }
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
        case 29:
                // Prime-29: numerator = utonal, denominator = otonal
                return exp < 0
        case 31:
            // Prime-31 inverts direction versus primes 19/23.
            return exp < 0
        case 19:
            // Prime-19 is numerator-up and denominator-down.
            return exp > 0
        case 23:
            // Prime-23 is numerator-up and denominator-down.
            return exp > 0
        default:
            // Works for 5, 7, 13 as used elsewhere in the app currently.
            return exp < 0
        }
    }

    private static func shouldAnchorToTonicForPrime31(
        ratioValue: Double,
        context: HejiContext,
        microComponents: [HejiMicrotonalComponent]
    ) -> Bool {
        guard context.tonicE3 != nil else { return false }
        guard microComponents.contains(where: { $0.prime == 31 }) else { return false }
        let semitoneOffset = roundedSemitoneOffset(from: ratioValue)
        let nearUnison = abs(semitoneOffset) <= 1
        let nearOctave = abs(abs(semitoneOffset) - 12) <= 1
        return nearUnison || nearOctave
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
        let mapping = Heji2Mapping.shared
        let allowedMicro: [Int]
        if maxPrime >= 5 {
        allowedMicro = (5...maxPrime).filter { !mapping.availableSteps(forPrime: $0).isEmpty || mapping.supportedPrimes.contains($0) }
            } else {
            allowedMicro = []
            }
        let allowed = Set([2, 3]).union(allowedMicro)
        return allPrimes.filter { !allowed.contains($0) }.sorted()
    }

    // MARK: - Staff layout helpers

    /// Shared staff-step mapping for renderer-only helpers.
    static func staffStepFromMiddleForRendering(letter: String, octave: Int, clef: HejiStaffLayout.Clef) -> Int {
        staffStepFromMiddle(letter: letter, octave: octave, clef: clef)
    }

    /// Staff-step span for one octave, based on the same diatonic mapping used by staff layout.
    static func staffStepSpanForOctave(clef: HejiStaffLayout.Clef, referenceLetter: String = "C", referenceOctave: Int = 4) -> Int {
        let base = staffStepFromMiddle(letter: referenceLetter, octave: referenceOctave, clef: clef)
        let upper = staffStepFromMiddle(letter: referenceLetter, octave: referenceOctave + 1, clef: clef)
        return upper - base
    }

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

    private static func normalizedForRendering(_ accidental: HejiAccidental) -> (
        diatonicToRender: Int,
        absorbDiatonicIntoPrime5: Int
    ) {
        let has11 = accidental.microtonalComponents.contains { $0.prime == 11 }
        let has5 = accidental.microtonalComponents.contains { $0.prime == 5 }
        let diatonic = has11 ? 0 : accidental.diatonicAccidental
        let absorb = (!has11 && has5 && diatonic != 0) ? diatonic : 0
        return (diatonicToRender: absorb != 0 ? 0 : diatonic, absorbDiatonicIntoPrime5: absorb)
    }

    private static func staffAccidentalGlyphs(_ accidental: HejiAccidental) -> [GlyphRun] {
        var runs: [GlyphRun] = []
        let mapping = Heji2Mapping.shared
        let norm = normalizedForRendering(accidental)
        let baseGlyphs = mapping.glyphsForDiatonicAccidental(norm.diatonicToRender)
        for glyph in baseGlyphs {
            let offset = glyph.staffOffset.map { CGPoint(x: $0.x, y: $0.y) } ?? .zero
            let fontKind = mapping.preferredFontForGlyph(glyph.string)
            let font: HejiFont = fontKind == .music ? .heji2Music : .heji2Text
            runs.append(GlyphRun(font: font, glyph: glyph.string, offset: offset))
        }
        var stackX: CGFloat = -10
                let componentGlyphs = mapping.glyphsForPrimeComponents(
                    accidental.microtonalComponents,
                    absorbDiatonicIntoPrime5: norm.absorbDiatonicIntoPrime5
                )

        // If we already have any real diatonic accidental glyph in the run, E261 is just a placeholder → strip ALL of them.
        let hasRealDiatonic = !baseGlyphs.isEmpty || componentGlyphs.contains { diatonicAccidentals.contains($0.string) }
        for glyph in componentGlyphs {
            let offset = glyph.staffOffset.map { CGPoint(x: $0.x, y: $0.y) } ?? .zero
            let fontKind = mapping.preferredFontForGlyph(glyph.string)
            let font: HejiFont = fontKind == .music ? .heji2Music : .heji2Text
            runs.append(GlyphRun(font: font, glyph: glyph.string, offset: CGPoint(x: stackX + offset.x, y: offset.y)))
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
        let norm = normalizedForRendering(accidental)
                let base = mapping.glyphsForDiatonicAccidental(norm.diatonicToRender)
                let micro = mapping.glyphsForPrimeComponents(
                    accidental.microtonalComponents,
                    absorbDiatonicIntoPrime5: norm.absorbDiatonicIntoPrime5
                )
                return (base + micro).map(\.string).joined()
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
// MARK: - ET helper for diatonic accidental count (keeps letter, chooses ♯/♭ count that best fits Hz)

    private static func bestDiatonicAccidentalCount(
        for letter: String,
        nearOctave: Int,
        freqHz: Double,
        a4Hz: Double
    ) -> Int {
        // Search small accidental range, and allow octave±1 so enharmonics like B#≈C can win.
        let accRange = -2...2
        let octRange = (nearOctave - 1)...(nearOctave + 1)

        var bestAcc = 0
        var bestAbsCents = Double.infinity

        for oct in octRange {
            for acc in accRange {
                let midi = midiNumber(letter: letter, accidental: acc, octave: oct)
                let target = etFrequency(midi: midi, a4Hz: a4Hz)
                let cents = 1200.0 * log2(freqHz / target)
                let absCents = abs(cents)
                if absCents < bestAbsCents {
                    bestAbsCents = absCents
                    bestAcc = acc
                }
            }
        }
        return bestAcc
    }

    private static func semitoneForLetterNatural(_ letter: String) -> Int {
        switch letter.uppercased() {
        case "C": return 0
        case "D": return 2
        case "E": return 4
        case "F": return 5
        case "G": return 7
        case "A": return 9
        case "B": return 11
        default:  return 0
        }
    }

    private static func midiNumber(letter: String, accidental: Int, octave: Int) -> Int {
        // MIDI: C-1 = 0, C4 = 60, A4 = 69.
        let base = semitoneForLetterNatural(letter)
        let semitone = base + accidental
        return (octave + 1) * 12 + semitone
    }

    private static func etFrequency(midi: Int, a4Hz: Double) -> Double {
        a4Hz * pow(2.0, Double(midi - 69) / 12.0)
    }

    private static func roundedSemitoneOffset(from ratioValue: Double) -> Int {
        Int(round(12.0 * log2(ratioValue)))
    }

    private static func rewriteEnharmonic(
        letter: String,
        accidental: Int,
        preferSharps: Bool
    ) -> (letter: String, accidental: Int) {
        guard (-2...2).contains(accidental) else { return (letter, accidental) }
        let normalized = letter.uppercased()
        if preferSharps {
            switch (normalized, accidental) {
            case ("C", -1): return ("B", 0)
            case ("F", -1): return ("E", 0)
            case ("D", -1): return ("C", 1)
            case ("E", -1): return ("D", 1)
            case ("G", -1): return ("F", 1)
            case ("A", -1): return ("G", 1)
            case ("B", -1): return ("A", 1)
            default: return (letter, accidental)
            }
        } else {
            switch (normalized, accidental) {
            case ("B", 1): return ("C", 0)
            case ("E", 1): return ("F", 0)
            case ("C", 1): return ("D", -1)
            case ("D", 1): return ("E", -1)
            case ("F", 1): return ("G", -1)
            case ("G", 1): return ("A", -1)
            case ("A", 1): return ("B", -1)
            default: return (letter, accidental)
            }
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
