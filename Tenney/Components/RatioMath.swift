import Foundation

public struct RatioKey: Hashable, Codable {
    public let num: Int
    public let den: Int
    public let octave: Int
}

public enum RatioMath {
    // Euclidean GCD (positive)
    public static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a), y = abs(b)
        while y != 0 { (x, y) = (y, x % y) }
        return max(1, x)
    }

    // Largest power-of-2 common divisor
    public static func gcdPow2(_ a: Int, _ b: Int) -> Int {
        let g = gcd(a, b)
        return g & -g // isolate lowest set bit (2-adic)
    }

    public static func oddize(_ p: Int, _ q: Int) -> (Int, Int) {
        let g2 = gcdPow2(p, q)
        return (p / g2, q / g2)
    }

    // Canonicalize so 1 ≤ P/Q < 2 and gcd-reduced.
    public static func canonicalPQUnit(_ p: Int, _ q: Int) -> (Int, Int) {
        var P = p, Q = q
        if P <= 0 || Q <= 0 { return (1, 1) }
        let g = gcd(P, Q)
        P /= g; Q /= g
        (P, Q) = oddize(P, Q)

        while Double(P) / Double(Q) >= 2.0 { Q *= 2 }
        while Double(P) / Double(Q) < 1.0 { P *= 2 }

        (P, Q) = oddize(P, Q)
        let g2 = gcd(P, Q)
        return (P / g2, Q / g2)
    }

    // Canonical key for hashing/lookup: unit octave + explicit octave exponent.
    public static func canonicalize(p: Int, q: Int, octave: Int) -> RatioKey {
        let (P, Q) = canonicalPQUnit(p, q)
        var oct = octave

        // The canonicalPQUnit folding may have changed octave implicitly; correct it:
        let unit = Double(P) / Double(Q)
        let target = (Double(p) / Double(q)) * pow(2.0, Double(octave))
        let unitOct = log2(target / unit)
        oct += Int(round(unitOct))

        return RatioKey(num: P, den: Q, octave: oct)
    }

    public static func ratioToHz(p: Int, q: Int, octave: Int, rootHz: Double) -> Double {
        rootHz * (Double(p) / Double(q)) * pow(2.0, Double(octave))
    }

    // Fold Hz to monitoring band (does not mutate the source ratio).
    public static func foldToAudible(_ hz: Double, lo: Double = 220.0, hi: Double = 880.0) -> Double {
        guard hz.isFinite, hz > 0 else { return 0 }
        var x = hz
        while x < lo { x *= 2 }
        while x >= hi { x /= 2 }
        return x
    }

    /// ET deviation (in cents) of `freqHz` relative to the nearest 12-TET step above `refHz`.
    /// Used in the lattice info card ("¢ vs ET").
    public static func centsFromET(freqHz: Double, refHz: Double) -> Double {
        guard freqHz.isFinite, refHz.isFinite, freqHz > 0, refHz > 0 else { return 0 }
        let steps = 12.0 * log2(freqHz / refHz)
        let nearest = round(steps)
        return (steps - nearest) * 100.0
    }
}
