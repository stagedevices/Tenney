//
//  Ratio+Octave.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/7/25.
//

//  Ratio+Octave.swift
import Foundation
import SwiftUI

extension RatioRef {
    func withOctaveOffset(_ d: Int) -> RatioRef {
        RatioRef(p: p, q: q, octave: octave + d, monzo: monzo)
    }
}

enum OctaveStepDirection { case up, down }

// Local helpers (file-scoped so we don't collide with other files)
public func gcd(_ a: Int, _ b: Int) -> Int {
    var x = abs(a), y = abs(b)
    while y != 0 { let t = x % y; x = y; y = t }
    return max(1, x)
}
/// Returns (num, den) with 1 ≤ num/den < 2 and reduced by GCD.
private func canonicalPQUnit(_ p: Int, _ q: Int) -> (Int, Int) {
    guard p > 0 && q > 0 else { return (p, q) }
    var num = p, den = q
    while Double(num) / Double(den) >= 2.0 { den &*= 2 }
    while Double(num) / Double(den) <  1.0 { num &*= 2 }
    let g = gcd(num, den)
    return (num / g, den / g)
}

/// Returns (num, den) reduced, representing (p/q)*2^octave, folded to 0.5 ≤ ratio < 2
private func canonicalPQAroundUnison(_ p: Int, _ q: Int, octave: Int) -> (Int, Int) {
    guard p > 0 && q > 0 else { return (p, q) }

    var num = p
    var den = q

    if octave > 0 {
        for _ in 0..<octave { num &*= 2 }
    } else if octave < 0 {
        for _ in 0..<(-octave) { den &*= 2 }
    }

    while Double(num) / Double(den) >= 2.0 { den &*= 2 }
    while Double(num) / Double(den) <  0.5 { num &*= 2 }

    let g = gcd(num, den)
    return (num / g, den / g)
}

/// Returns a reduced fraction that applies octave offset directly (no unit-octave folding).
func unfoldedRatioString(_ r: RatioRef) -> String {
    guard r.p > 0 && r.q > 0 else { return "\(r.p)/\(r.q)" }

    var num = r.p
    var den = r.q

    if r.octave > 0 {
        for _ in 0..<r.octave { num &*= 2 }
    } else if r.octave < 0 {
        for _ in 0..<(-r.octave) { den &*= 2 }
    }

    let g = gcd(num, den)
    return "\(num / g)/\(den / g)"
}

/// Tuner-only helper: formats RatioResult without folding into the unit octave.
func tunerDisplayRatioString(_ r: RatioResult) -> String {
    unfoldedRatioString(RatioRef(p: r.num, q: r.den, octave: r.octave))
}


/// Frequency from RatioRef with canonicalized p/q (1 ≤ p/q < 2), no fold unless asked.
func frequencyHz(rootHz: Double, ratio: RatioRef, foldToAudible: Bool = false,
                 minHz: Double = 20, maxHz: Double = 5000) -> Double {
    let base = rootHz * pow(2.0, Double(ratio.octave)) * (Double(ratio.p) / Double(ratio.q))
    guard foldToAudible else { return base }
    var x = base
    var lo = minHz, hi = maxHz
    if lo <= 0 || !lo.isFinite { lo = 20 }
    if hi <= 0 || !hi.isFinite { hi = 5000 }
    while x < lo { x *= 2 }
    while x > hi { x *= 0.5 }
    return x
}

/// Bounds check per spec: *disable* step if the **unfolded** next frequency would be <20 or >5k.
func canStepOctave(rootHz: Double, ratio: RatioRef, direction: OctaveStepDirection,
                   minHz: Double = 20, maxHz: Double = 5000) -> Bool {
    let next = ratio.withOctaveOffset(direction == .up ? 1 : -1)
    let f = frequencyHz(rootHz: rootHz, ratio: next, foldToAudible: false, minHz: minHz, maxHz: maxHz)
    return f >= minHz && f <= maxHz && f.isFinite
}

/// Display helpers
func ratioDisplayString(_ r: RatioRef) -> String {
    let (cn, cd) = canonicalPQAroundUnison(r.p, r.q, octave: r.octave)
    return "\(cn)/\(cd)"
}

/// If you need name/octave from an effective frequency (cents vs ET can be filled by your model later)
func hejiDisplay(freqHz: Double) -> (name: String, oct: Int, cents: Double) {
    let reference = TonicSpelling.resolvedNoteNameA4Hz()
    let (name, oct) = NotationFormatter.staffNoteName(freqHz: freqHz, a4Hz: reference)
    // If you want ET cents here, compute it using your own ET helper.
    return (name, oct, 0)
}
