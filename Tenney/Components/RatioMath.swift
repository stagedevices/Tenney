
//
//  RatioMath.swift
//  Tenney
//
//  Centralized helpers for ratio arithmetic, canonicalization, and ET comparisons.
//  Use these everywhere to keep labeling and audio paths consistent.
//
//  Created by Tenney Team on 12/24/25.
//

import Foundation

public enum RatioMath {
    
    
    @inlinable
    public static func ratioToHz(
        p: Int,
        q: Int,
        octave: Int,
        rootHz: Double,
        centsError: Int
    ) -> Double {
        guard rootHz.isFinite, rootHz > 0 else { return .nan }
        guard p > 0, q > 0 else { return .nan }

        let (cn, cd) = canonicalPQUnit(p, q)
        var hz = rootHz * (Double(cn) / Double(cd)) * pow(2.0, Double(octave))

        // Apply cents error (micro-offset) if present.
        if centsError != 0 {
            hz *= pow(2.0, Double(centsError) / 1200.0)
        }

        return hz
    }

    // MARK: - Canonicalization + helpers

    @inlinable
    public static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a), y = abs(b)
        while y != 0 { let t = x % y; x = y; y = t }
        return max(1, x)
    }

    /// Reduce and force positive denominator.
    @inlinable
    public static func reduced(_ p: Int, _ q: Int) -> (p: Int, q: Int) {
        guard q != 0 else { return (p, q) }
        let g = gcd(p, q)
        var P = p / g
        var Q = q / g
        if Q < 0 { P = -P; Q = -Q }
        return (P, Q)
    }

    /// Returns (P,Q) such that 1 ≤ P/Q < 2 (unit octave), reduced by gcd.
    /// Powers of 2 are shifted between numerator/denominator.
    @inlinable
    public static func canonicalPQUnit(_ p: Int, _ q: Int) -> (p: Int, q: Int) {
        guard p > 0, q > 0 else { return reduced(p, q) }
        var num = p
        var den = q
        while Double(num) / Double(den) >= 2.0 { den &*= 2 }
        while Double(num) / Double(den) <  1.0 { num &*= 2 }
        return reduced(num, den)
    }

/// Cents distance of a raw rational p/q (not folded) relative to 1/1.
@inlinable
public static func centsForRatio(_ p: Int, _ q: Int) -> Double {
    guard p > 0, q > 0 else { return .nan }
    return 1200.0 * log2(Double(p) / Double(q))
}

// MARK: - Frequency mapping

/// Computes frequency for a ratio relative to root, optionally folding into an audible band.
/// - Parameters:
///   - rootHz: Reference frequency for 1/1.
///   - p, q:   Ratio (any octave); will be canonicalized to 1 ≤ P/Q < 2 for musical display and pad audio.
///   - octave: Additional power-of-two offset (e.g., 0 for unit octave).
///   - fold:   If true, fold the result to [minHz, maxHz] for monitoring.
@inlinable
public static func hz(rootHz: Double,
                      p: Int,
                      q: Int,
                      octave: Int = 0,
                      fold: Bool = false,
                      minHz: Double = 20,
                      maxHz: Double = 5000) -> Double
{
    guard rootHz > 0, p > 0, q > 0 else { return .nan }
    let (P, Q) = canonicalPQUnit(p, q)
    let base = rootHz * (Double(P) / Double(Q)) * pow(2.0, Double(octave))
    return fold ? foldToAudible(base, minHz: minHz, maxHz: maxHz) : base
}

/// Fold any Hz into a safe audible band for monitoring-only playback.
@inlinable
public static func foldToAudible(_ f: Double, minHz: Double = 20, maxHz: Double = 5000) -> Double {
    guard f.isFinite, f > 0, minHz > 0, maxHz > minHz else { return f }
    var x = f
    while x < minHz { x *= 2 }
    while x > maxHz { x *= 0.5 }
    return x
}

// MARK: - 12TET comparisons

/// Returns the deviation in cents from the nearest 12TET pitch *anchored at refHz as 1/1*.
/// Example: if `refHz` is the current root (A = 415, or any root), then a perfect 3/2 will be ~+2 cents vs ET depending on temperament.
/// The result is wrapped into (-50, +50] cents.
@inlinable
public static func centsFromET(freqHz: Double, refHz: Double) -> Double {
    guard freqHz > 0, refHz > 0 else { return .nan }
    let cents = 1200.0 * log2(freqHz / refHz)         // cents above the local unison
    let nearest = round(cents / 100.0) * 100.0        // quantize to nearest semitone
    var delta = cents - nearest                        // deviation from ET (in cents)
    if delta <= -50.0 { delta += 100.0 }               // wrap into (-50, +50]
    if delta >   50.0 { delta -= 100.0 }
    return delta
}

/// Nearest ET semitone index relative to `refHz` (1/1). 0 means unison, +12 is one ET octave up, etc.
@inlinable
public static func nearestETSemiIndex(freqHz: Double, refHz: Double) -> Int {
    guard freqHz > 0, refHz > 0 else { return .min }
    return Int(lround(12.0 * log2(freqHz / refHz)))
}

// MARK: - Complexity & helpers

/// Simple Tenney-height proxy used for sizing/opacity (cheap and monotonic with complexity).
@inlinable
public static func tenneyHeight(p: Int, q: Int) -> Int {
    let (P, Q) = reduced(p, q)
    return max(abs(P), abs(Q))
}

/// Canonical display label "P/Q" with 1 ≤ P/Q < 2.
@inlinable
public static func unitLabel(_ p: Int, _ q: Int) -> String {
    let (P, Q) = canonicalPQUnit(p, q)
    return "\(P)/\(Q)"
}

// MARK: - Monzo (optional lightweight helpers)
// Monzo exponents keyed by prime (e.g., [3:e3, 5:e5, 7:e7, ...]); 2 is allowed but usually treated as the period.

/// Convert a sparse monzo into a reduced rational (p/q).
/// Note: This is intended for small exponents; very large exponents can overflow Int.
@inlinable
public static func pq(fromMonzo monzo: [Int: Int]) -> (p: Int, q: Int) {
    var num: Int = 1
    var den: Int = 1
    for (prime, exp) in monzo {
        guard prime >= 2 else { continue }
        if exp >= 0 {
            if exp > 0 {
                num = powMul(num, base: prime, exp: exp)
            }
        } else {
            den = powMul(den, base: prime, exp: -exp)
        }
    }
    return reduced(num, den)
}

/// Multiply `lhs` by `base^exp` using wrapping semantics on overflow (fast and predictable for UI use).
@inlinable
 static func powMul(_ lhs: Int, base: Int, exp: Int) -> Int {
    guard exp > 0 else { return lhs }
    var result = lhs
    var k = exp
    var b = base
    var acc = 1
    // Fast exponentiation (wrap on overflow via &*)
    while k > 0 {
        if (k & 1) == 1 { acc &*= b }
        b &*= b
        k >>= 1
    }
    result &*= acc
    return result
}

}

// MARK: - Convenience extensions

@inlinable public func log2(_ x: Double) -> Double { Darwin.log2(x) }

