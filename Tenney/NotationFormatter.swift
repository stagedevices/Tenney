//
//  NotationFormatter.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  NotationFormatter.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation

struct NotationFormatter {

    struct StaffName: Hashable, Sendable {
        let name: String   // "A"..."G"
        let octave: Int
    }

    /// Return a coarse staff spelling for a frequency (A4=440).
    /// This is intentionally minimal; it's used for the info card staff rendering.
    static func staffNoteName(freqHz: Double, a4: Double = 440.0) -> StaffName {
        guard freqHz.isFinite, freqHz > 0 else { return .init(name: "A", octave: 4) }
        let midi = 69.0 + 12.0 * log2(freqHz / a4)
        let n = Int(round(midi))
        let pc = ((n % 12) + 12) % 12
        let octave = (n / 12) - 1

        // Prefer naturals only (you render accidentals separately for HEJI anyway).
        // Map pitch class to nearest natural letter.
        // C=0, D=2, E=4, F=5, G=7, A=9, B=11
        let naturals: [(pc: Int, name: String)] = [
            (0,"C"), (2,"D"), (4,"E"), (5,"F"), (7,"G"), (9,"A"), (11,"B")
        ]
        let best = naturals.min(by: { abs($0.pc - pc) < abs($1.pc - pc) }) ?? (9,"A")
        return .init(name: best.name, octave: octave)
    }

    /// Simple prime badges for p/q.
    /// (Your UI colors these via activeTheme.primeTint.)
    static func primeBadges(p: Int, q: Int) -> [Int] {
        let fP = factorMap(abs(p))
        let fQ = factorMap(abs(q))
        let primes = Set(fP.keys).union(fQ.keys).subtracting([1, 2])
        return primes.sorted()
    }

    /// Basic HEJI label string.
    /// For now: show ratio and cents deviation vs ET (you render glyph separately).
    /// If you later want full HEJI text, replace internals but keep signature.
    static func hejiLabel(p: Int, q: Int, freqHz: Double, rootHz: Double) -> String {
        let (P, Q) = RatioMath.canonicalPQUnit(p, q)
        let cents = RatioMath.centsFromET(freqHz: freqHz, refHz: rootHz)
        // Keep it compact; staff row handles glyph rendering.
        return "\(P)/\(Q) \(String(format: "%+.1f¢", cents))"
    }

    /// Returns a Bravura/SMuFL glyph string for a HEJI accidental near the given ET deviation (in cents).
    /// Uses Extended Helmholtz–Ellis codepoints U+E2C0–U+E2FF

    // MARK: - helpers

    private static func factorMap(_ n: Int) -> [Int:Int] {
        var n = n
        var out: [Int:Int] = [:]
        var p = 2
        while p*p <= n {
            while n % p == 0 {
                out[p, default: 0] += 1
                n /= p
            }
            p += (p == 2 ? 1 : 2)
        }
        if n > 1 { out[n, default: 0] += 1 }
        return out
    }
}
