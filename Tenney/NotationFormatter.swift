//
//  NotationFormatter.swift
//  Tenney
//
//  Rebuilt “latest” formatter surface to satisfy Ratio+Octave.swift and current lattice UI.
//  Key change: StaffName is a *tuple* so callers can destructure: `let (n, o) = ...`
//              AND access: `staff.name`, `staff.octave`.
//

import Foundation

public enum NotationFormatter {

    public enum AccidentalPreference: Int, Codable {
        case auto = 0
        case preferSharps = 1
        case preferFlats = 2
    }

    // MARK: - Staff name surface (tuple for destructuring + dot access)

    /// Tuple on purpose:
    /// - Supports `let (name, octave) = staffNoteName(...)`
    /// - Supports `staff.name`, `staff.octave`
    public typealias StaffName = (name: String, octave: Int)

    public typealias SpelledETNote = (letter: String, accidental: String, octave: Int)

    // MIDI 69 = A4
    private static let a4MIDINote: Double = 69.0

    // Chromatic spelling (letter + accidental count).
    private static let chromatic: [(letter: String, accidentalCount: Int)] = [
        ("C", 0), ("C", 1), ("D", 0), ("D", 1),
        ("E", 0), ("F", 0), ("F", 1), ("G", 0),
        ("G", 1), ("A", 0), ("A", 1), ("B", 0)
    ]
    private static let chromaticSharps: [(letter: String, accidentalCount: Int)] = [
        ("C", 0), ("C", 1), ("D", 0), ("D", 1),
        ("E", 0), ("F", 0), ("F", 1), ("G", 0),
        ("G", 1), ("A", 0), ("A", 1), ("B", 0)
    ]
    private static let chromaticFlats: [(letter: String, accidentalCount: Int)] = [
        ("C", 0), ("D", -1), ("D", 0), ("E", -1),
        ("E", 0), ("F", 0), ("G", -1), ("G", 0),
        ("A", -1), ("A", 0), ("B", -1), ("B", 0)
    ]

    // MARK: - Public API

    /// Returns the *letter only* + octave for staff placement (e.g. "C", 4).
    /// (Accidentals are handled elsewhere in your UI.)
    public static func staffNoteName(freqHz: Double, a4Hz: Double = 440.0) -> StaffName {
        guard freqHz.isFinite, freqHz > 0, a4Hz.isFinite, a4Hz > 0 else { return ("—", 0) }

        let midi = nearestMIDINoteNumber(freqHz: freqHz, a4Hz: a4Hz)
        let idx = mod12(midi)
        let octave = midi / 12 - 1
        let letter = chromatic[idx].letter
        return (letter, octave)
    }

    /// Returns letter + accidental + octave for display labels (e.g. "C♯4").
    public static func spelledETNote(freqHz: Double, a4Hz: Double = 440.0) -> SpelledETNote {
        guard freqHz.isFinite, freqHz > 0, a4Hz.isFinite, a4Hz > 0 else { return ("—", "", 0) }

        let midi = nearestMIDINoteNumber(freqHz: freqHz, a4Hz: a4Hz)
        let idx = mod12(midi)
        let octave = midi / 12 - 1
        let base = chromatic[idx]
        return (base.letter, accidentalGlyph(base.accidentalCount), octave)
    }

    /// Cent deviation from the nearest equal-tempered semitone (relative to A4 = a4Hz).
    /// Positive = sharp; negative = flat.
    public static func centsFromNearestET(freqHz: Double, a4Hz: Double = 440.0) -> Double {
        guard freqHz.isFinite, freqHz > 0, a4Hz.isFinite, a4Hz > 0 else { return 0 }
        let midiFloat = a4MIDINote + 12.0 * log2(freqHz / a4Hz)
        let nearest = midiFloat.rounded()
        return (midiFloat - nearest) * 100.0
    }

    /// Closest ET semitone rendered as a Helmholtz label (letter + accidental + octave marks).
    public static func closestHelmholtzLabel(
        freqHz: Double,
        a4Hz: Double,
        preference: AccidentalPreference
    ) -> String {
        guard freqHz.isFinite, freqHz > 0, a4Hz.isFinite, a4Hz > 0 else { return "—" }

        let midi = nearestMIDINoteNumber(freqHz: freqHz, a4Hz: a4Hz)
        let idx = mod12(midi)
        let octave = midi / 12 - 1
        let spelling = spelledChromatic(for: idx, preference: preference)
        let helmholtz = helmholtzOctaveMarks(scientificOctave: octave, letter: spelling.letter)
        return "\(helmholtz.caseAdjustedLetter)\(helmholtz.marks)\(spelling.accidental)"
    }

    /// HEJI-ish text label for ratio tiles / info cards.
    /// Keeps this robust/legible: `C♯4 +14¢` (or no cents if near ET).
    public static func hejiLabel(p: Int, q: Int, freqHz: Double, rootHz: Double) -> String {
        let reference = TonicSpelling.resolvedNoteNameA4Hz()
        let anchor = resolveRootAnchor(rootHz: rootHz, a4Hz: reference, preference: .auto)
        let context = PitchContext(
            a4Hz: reference,
            rootHz: rootHz,
            rootAnchor: anchor,
            accidentalPreference: .auto,
            maxPrime: 13
        )
        let spelling = spellRatio(p: p, q: q, context: context)
        return spelling.labelText
    }

    /// Prime badges for p/q (unique primes dividing numerator or denominator), ascending.
    public static func primeBadges(p: Int, q: Int) -> [Int] {
        let a = abs(p)
        let b = abs(q)
        var set = Set<Int>()
        primeFactors(of: a).forEach { set.insert($0) }
        primeFactors(of: b).forEach { set.insert($0) }
        return set.sorted()
    }

    /// Convenience: reduced ratio string like "3/2" (always positive components).
    public static func ratioString(p: Int, q: Int) -> String {
        guard q != 0 else { return "—" }
        let g = gcd(abs(p), abs(q))
        let rp = abs(p) / max(1, g)
        let rq = abs(q) / max(1, g)
        return "\(rp)/\(rq)"
    }

    // MARK: - Internals

    private static func nearestMIDINoteNumber(freqHz: Double, a4Hz: Double) -> Int {
        let midiFloat = a4MIDINote + 12.0 * log2(freqHz / a4Hz)
        return Int(midiFloat.rounded())
    }

    private static func spelledChromatic(for idx: Int, preference: AccidentalPreference) -> (letter: String, accidental: String) {
        switch preference {
        case .preferFlats:
            let note = chromaticFlats[idx]
            return (note.letter, accidentalGlyph(note.accidentalCount))
        case .preferSharps, .auto:
            let note = chromaticSharps[idx]
            return (note.letter, accidentalGlyph(note.accidentalCount))
        }
    }

    /// Helmholtz conversion for scientific octave numbers.
    /// Examples: C4 → c′, A4 → a′, C5 → c″, B3 → B, B2 → B,
    private static func helmholtzOctaveMarks(
        scientificOctave: Int,
        letter: String
    ) -> (caseAdjustedLetter: String, marks: String) {
        let lower = letter.lowercased()
        let upper = letter.uppercased()
        if scientificOctave >= 4 {
            let primes = String(repeating: "′", count: max(1, scientificOctave - 3))
            return (lower, primes)
        }
        let commas = String(repeating: ",", count: max(0, 3 - scientificOctave))
        return (upper, commas)
    }

    private static func mod12(_ n: Int) -> Int {
        let m = n % 12
        return m >= 0 ? m : (m + 12)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let t = x % y
            x = y
            y = t
        }
        return x
    }

    private static func primeFactors(of n: Int) -> [Int] {
        guard n >= 2 else { return [] }
        var x = n
        var f: Int = 2
        var out: [Int] = []
        while f * f <= x {
            if x % f == 0 {
                out.append(f)
                while x % f == 0 { x /= f }
            }
            f += (f == 2 ? 1 : 2) // 2 then odd only
        }
        if x > 1 { out.append(x) }
        return out
    }
}
