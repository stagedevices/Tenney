//
//  Approximate.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

struct RatioApproximator {

    struct Options {
        var primeLimit: PrimeLimit = .eleven
        var maxDenominator: Int = 4096
        var maxCentsError: Double = 30.0
    }

    static func approximate(_ x: Double, options: Options = Options()) -> Ratio {
        // Be defensive: if input is non-positive or non-finite, return identity ratio.
        guard x.isFinite, x > 0 else { return Ratio(1,1) }
        precondition(x > 0)
        // 1) Continued fraction convergents
        let convergents = cfConvergents(of: x, maxDen: options.maxDenominator)

        // 2) Filter by prime-limit
        var best: (r: Ratio, cents: Double, height: Double)?
        func consider(_ r: Ratio) {
            if let m = r.toMonzoIfWithin13() {
                let allowed = options.primeLimit.primes.contains(13) ? [2,3,5,7,11,13] : options.primeLimit.primes
                // if any exponent corresponds to prime not allowed -> reject
                let involvedPrimes: [Int: Int] = [
                    2: m.e2, 3: m.e3, 5: m.e5, 7: m.e7, 11: m.e11, 13: m.e13
                ]
                for (p, e) in involvedPrimes where e != 0 {
                    if !allowed.contains(p) { return }
                }
                let c = abs(1200.0 * log2(r.value / x))
                if c <= options.maxCentsError {
                    let height = m.tenneyHeight
                    if best == nil || c < best!.cents - 1e-9 || (abs(c - best!.cents) < 1e-9 && height < best!.height) {
                        best = (r, c, height)
                    }
                }
            }
        }
        convergents.forEach(consider)

        // 3) If nothing found, probe mediants near the best equal-tempered approx
        if best == nil, let near = convergents.last {
            let neighbors = mediantProbe(near, x: x, span: 16)
            neighbors.forEach(consider)
        }

        // 4) Fallback to closest convergent if still nil
        if let b = best { return b.r }
        return convergents.min { a, b in
            abs(log(a.value/x)) < abs(log(b.value/x))
        } ?? Ratio(1,1)
    }

    // MARK: helpers

    /// Continued fraction convergents up to denominator cap.
    private static func cfConvergents(of x: Double, maxDen: Int) -> [Ratio] {
        var a = floor(x)
        var h1 = 1, k1 = 0
        var h = Int(a), k = 1
        var res: [Ratio] = [Ratio(h,k)]
        var frac = x - a
        var p0 = h1, q0 = k1, p1 = h, q1 = k

        // Generate convergents
        for _ in 0..<64 {
            if frac == 0 { break }
            let inv = 1.0 / frac
            a = floor(inv)
            let p = Int(a) * p1 + p0
            let q = Int(a) * q1 + q0
            if q > maxDen { break }
            res.append(Ratio(p, q))
            p0 = p1; q0 = q1; p1 = p; q1 = q
            frac = inv - a
        }

        // Include some semiconvergents (mediants between last two)
        if res.count >= 2 {
            let last = res[res.count-1]; let prev = res[res.count-2]
            var t = 1
            while true {
                let p = last.n + t * prev.n
                let q = last.d + t * prev.d
                if q > maxDen { break }
                res.append(Ratio(p, q)); t += 1
            }
        }
        return Array(Set(res)).sorted { $0.value < $1.value }
    }

    /// Probe mediants near a ratio; small neighborhood exploration.
    private static func mediantProbe(_ r: Ratio, x: Double, span: Int) -> [Ratio] {
        var out: [Ratio] = []
        for i in -span...span where i != 0 {
            let p = r.n + i
            let q = r.d
            if q > 0 && p > 0 {
                out.append(Ratio(p, q))
            }
        }
        for j in -span...span where j != 0 {
            let p = r.n
            let q = r.d + j
            if q > 0 && p > 0 {
                out.append(Ratio(p, q))
            }
        }
        return Array(Set(out))
    }
}
