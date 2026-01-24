//
//  HejiRatioSpeller.swift
//  Tenney
//
//  Ratio-first spelling for 3-limit labels with a stable root anchor.
//

import Foundation

struct RootAnchor: Codable, Hashable {
    var fifthsFromC: Int
    var diatonicNumber: Int

    var letterIndex: Int { mod(diatonicNumber, 7) }
    var octave: Int { floorDiv(diatonicNumber, 7) }
    var letter: String { ["C", "D", "E", "F", "G", "A", "B"][letterIndex] }
}

struct HejiRatioSpelling: Equatable {
    var letter: String
    var scientificOctave: Int
    var helmholtzText: String
    var accidentalText: String
    var unsupportedPrimes: [Int]
    var isApproximate: Bool

    var labelText: String {
        accidentalText + helmholtzText
    }
}

struct PitchContext {
    var a4Hz: Double
    var rootHz: Double
    var rootAnchor: RootAnchor
    var accidentalPreference: AccidentalPreference
    var maxPrime: Int
}

func best3LimitE3Interval(p: Int, q: Int, octave: Int) -> Int {
    guard p != 0, q != 0 else { return 0 }
    let value = (Double(p) / Double(q)) * pow(2.0, Double(octave))
    guard value.isFinite, value > 0 else { return 0 }

    var bestE3 = 0
    var bestE2 = 0
    var bestCents = Double.greatestFiniteMagnitude

    for e3 in -14...14 {
        let base = pow(3.0, Double(e3))
        let e2 = Int(round(log2(value / base)))
        let candidate = base * pow(2.0, Double(e2))
        let cents = abs(1200.0 * log2(value / candidate))

        if cents < bestCents - 1e-6 {
            bestCents = cents
            bestE3 = e3
            bestE2 = e2
        } else if abs(cents - bestCents) <= 1e-6 {
            if abs(e3) < abs(bestE3) {
                bestE3 = e3
                bestE2 = e2
            } else if abs(e3) == abs(bestE3), abs(e2) < abs(bestE2) {
                bestE3 = e3
                bestE2 = e2
            }
        }
    }

    return bestE3
}

func applyOctaveToPQ(p: Int, q: Int, octave: Int) -> (Int, Int) {
    guard octave != 0 else { return (p, q) }
    let shift = 1 << abs(octave)
    if octave > 0 {
        return reduce(p * shift, q)
    }
    return reduce(p, q * shift)
}

func resolveRootAnchor(rootHz: Double, a4Hz: Double, preference: AccidentalPreference, defaults: UserDefaults = .standard) -> RootAnchor {
    let frozen = defaults.bool(forKey: SettingsKeys.rootAnchorIsFrozen)
    if frozen,
       let stored = readRootAnchor(defaults: defaults) {
        return stored
    }

    let anchor = deriveRootAnchor(rootHz: rootHz, a4Hz: a4Hz, preference: preference)
    defaults.set(anchor.fifthsFromC, forKey: SettingsKeys.rootAnchorFifthsFromC)
    defaults.set(anchor.diatonicNumber, forKey: SettingsKeys.rootAnchorDiatonicNumber)
    defaults.set(true, forKey: SettingsKeys.rootAnchorIsFrozen)
    return anchor
}

#if DEBUG
func resetRootAnchor(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: SettingsKeys.rootAnchorFifthsFromC)
    defaults.removeObject(forKey: SettingsKeys.rootAnchorDiatonicNumber)
    defaults.removeObject(forKey: SettingsKeys.rootAnchorIsFrozen)
}
#endif

func spellRatio(p: Int, q: Int, context: PitchContext) -> HejiRatioSpelling {
    guard p != 0, q != 0 else {
        return HejiRatioSpelling(
            letter: "—",
            scientificOctave: 0,
            helmholtzText: "—",
            accidentalText: "",
            unsupportedPrimes: [],
            isApproximate: false
        )
    }

    let (rp, rq) = reduce(abs(p), abs(q))
    let a = vFactor(2, rp) - vFactor(2, rq)
    let b = vFactor(3, rp) - vFactor(3, rq)
    let m = b
    let o = a + b

    let anchorDiatonic = context.rootAnchor.diatonicNumber
    let newDiatonic = anchorDiatonic + (4 * m) + (7 * o)
    let letterIndex = mod(newDiatonic, 7)
    let scientificOctave = floorDiv(newDiatonic, 7)
    let letter = ["C", "D", "E", "F", "G", "A", "B"][letterIndex]

    let anchorFifths = context.rootAnchor.fifthsFromC
    let newFifths = anchorFifths + m
    let fifthLetterIndex = mod(4 * newFifths, 7)
    let letterFromFifths = ["C", "D", "E", "F", "G", "A", "B"][fifthLetterIndex]
    let natural = naturalFifths(letterFromFifths)
    let accidentalCount = (newFifths - natural) / 7

    #if DEBUG
    assert(letterFromFifths == letter, "HEJI ratio speller letter mismatch")
    #endif

    let accidentalText = renderAccidentalText(accidentalCount)
    let unsupported = unsupportedPrimes(p: rp, q: rq)
    let helmholtz = helmholtzLabel(letter: letter, octave: scientificOctave)

    return HejiRatioSpelling(
        letter: letter,
        scientificOctave: scientificOctave,
        helmholtzText: helmholtz,
        accidentalText: accidentalText,
        unsupportedPrimes: unsupported,
        isApproximate: false
    )
}

private func readRootAnchor(defaults: UserDefaults) -> RootAnchor? {
    guard defaults.object(forKey: SettingsKeys.rootAnchorFifthsFromC) != nil,
          defaults.object(forKey: SettingsKeys.rootAnchorDiatonicNumber) != nil else {
        return nil
    }
    let fifths = defaults.integer(forKey: SettingsKeys.rootAnchorFifthsFromC)
    let diatonic = defaults.integer(forKey: SettingsKeys.rootAnchorDiatonicNumber)
    return RootAnchor(fifthsFromC: fifths, diatonicNumber: diatonic)
}

private func deriveRootAnchor(rootHz: Double, a4Hz: Double, preference: AccidentalPreference) -> RootAnchor {
    let midi = nearestMIDINoteNumber(freqHz: rootHz, a4Hz: a4Hz)
    let octave = midi / 12 - 1
    let idx = mod(midi, 12)
    let spelling = spelledNote(forSemitone: idx, preference: preference)
    let letterIndex = letterIndex(for: spelling.letter)
    let diatonic = octave * 7 + letterIndex
    let fifths = naturalFifths(spelling.letter) + (7 * spelling.accidentalCount)
    return RootAnchor(fifthsFromC: fifths, diatonicNumber: diatonic)
}

private func spelledNote(forSemitone idx: Int, preference: AccidentalPreference) -> (letter: String, accidentalCount: Int) {
    let sharps: [(String, Int)] = [
        ("C", 0), ("C", 1), ("D", 0), ("D", 1),
        ("E", 0), ("F", 0), ("F", 1), ("G", 0),
        ("G", 1), ("A", 0), ("A", 1), ("B", 0)
    ]
    let flats: [(String, Int)] = [
        ("C", 0), ("D", -1), ("D", 0), ("E", -1),
        ("E", 0), ("F", 0), ("G", -1), ("G", 0),
        ("A", -1), ("A", 0), ("B", -1), ("B", 0)
    ]
    switch preference {
    case .preferFlats:
        return flats[idx]
    case .preferSharps, .auto:
        return sharps[idx]
    }
}

private func naturalFifths(_ letter: String) -> Int {
    switch letter.uppercased() {
    case "C": return 0
    case "G": return 1
    case "D": return 2
    case "A": return 3
    case "E": return 4
    case "B": return 5
    case "F": return -1
    default: return 0
    }
}

private func renderAccidentalText(_ count: Int) -> String {
    accidentalGlyph(count)
}

private func helmholtzLabel(letter: String, octave: Int) -> String {
    let lower = letter.lowercased()
    let upper = letter.uppercased()
    if octave >= 4 {
        let primes = String(repeating: "′", count: max(1, octave - 3))
        return "\(lower)\(primes)"
    }
    let commas = String(repeating: ",", count: max(0, 3 - octave))
    return "\(upper)\(commas)"
}

private func unsupportedPrimes(p: Int, q: Int) -> [Int] {
    let remainingP = stripFactors(stripFactors(abs(p), prime: 2), prime: 3)
    let remainingQ = stripFactors(stripFactors(abs(q), prime: 2), prime: 3)
    let primes = Set(factorPrimes(remainingP) + factorPrimes(remainingQ))
    return primes.filter { $0 >= 5 }.sorted()
}

private func stripFactors(_ value: Int, prime: Int) -> Int {
    guard value > 1 else { return value }
    var n = value
    while n % prime == 0 { n /= prime }
    return n
}

private func factorPrimes(_ value: Int) -> [Int] {
    guard value >= 2 else { return [] }
    var n = value
    var p = 2
    var out: [Int] = []
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

private func vFactor(_ prime: Int, _ value: Int) -> Int {
    guard value != 0 else { return 0 }
    var n = value
    var exp = 0
    while n % prime == 0 {
        n /= prime
        exp += 1
    }
    return exp
}

private func reduce(_ p: Int, _ q: Int) -> (Int, Int) {
    let g = hejiGCD(p, q)
    return (p / g, q / g)
}

private func hejiGCD(_ a: Int, _ b: Int) -> Int {
    var x = a
    var y = b
    while y != 0 {
        let t = x % y
        x = y
        y = t
    }
    return max(1, x)
}

private func mod(_ a: Int, _ b: Int) -> Int {
    let m = a % b
    return m >= 0 ? m : m + b
}

private func floorDiv(_ a: Int, _ b: Int) -> Int {
    var q = a / b
    let r = a % b
    if r != 0 && ((r > 0) != (b > 0)) { q -= 1 }
    return q
}

private func nearestMIDINoteNumber(freqHz: Double, a4Hz: Double) -> Int {
    guard freqHz.isFinite, freqHz > 0, a4Hz.isFinite, a4Hz > 0 else { return 69 }
    let midiFloat = 69.0 + 12.0 * log2(freqHz / a4Hz)
    return Int(midiFloat.rounded())
}

private func letterIndex(for letter: String) -> Int {
    switch letter.uppercased() {
    case "C": return 0
    case "D": return 1
    case "E": return 2
    case "F": return 3
    case "G": return 4
    case "A": return 5
    case "B": return 6
    default: return 0
    }
}
