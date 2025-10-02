//
//  Monzo.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Monzo vector exponents for primes [2,3,5,7,11,13]
/// You can ignore higher components for lower prime-limits.
struct Monzo: Equatable, Hashable, Codable {
    var e2: Int
    var e3: Int
    var e5: Int
    var e7: Int
    var e11: Int
    var e13: Int

    init(e2: Int = 0, e3: Int = 0, e5: Int = 0, e7: Int = 0, e11: Int = 0, e13: Int = 0) {
        self.e2 = e2; self.e3 = e3; self.e5 = e5; self.e7 = e7; self.e11 = e11; self.e13 = e13
    }

    /// Convert to Ratio by computing ∏ p_i^{e_i}; negative exponents go to denominator.
    func toRatio() -> Ratio {
        let primes = [2,3,5,7,11,13]
        let exps   = [e2,e3,e5,e7,e11,e13]
        var num = 1
        var den = 1
        for (p,e) in zip(primes, exps) {
            if e > 0 {
                for _ in 0..<e { num = num &* p }
            } else if e < 0 {
                for _ in 0..<(-e) { den = den &* p }
            }
        }
        return Ratio(num, den)
    }

    /// Tenney "height" complexity: sum |e_i| * ln(p_i)
    var tenneyHeight: Double {
        let primes = [2.0,3.0,5.0,7.0,11.0,13.0]
        let exps = [e2,e3,e5,e7,e11,e13]
        return zip(primes, exps).reduce(0.0) { $0 + Double(abs($1.1)) * log($1.0) }
    }

    /// Add monzos (multiplying ratios)
    func adding(_ other: Monzo) -> Monzo {
        Monzo(
            e2: e2 + other.e2, e3: e3 + other.e3, e5: e5 + other.e5,
            e7: e7 + other.e7, e11: e11 + other.e11, e13: e13 + other.e13
        )
    }
}

extension Ratio {
    /// Factor numerator & denominator into monzo (only primes up to 13 considered).
    /// Returns nil if factors include primes > 13.
    func toMonzoIfWithin13() -> Monzo? {
        func factor(_ x: Int) -> [Int: Int]? {
            var n = abs(x)
            var result: [Int:Int] = [:]
            let small = [2,3,5,7,11,13]
            for p in small {
                if n == 1 { break }
                var c = 0
                while n % p == 0 { n /= p; c += 1 }
                if c > 0 { result[p] = c }
            }
            if n != 1 { return nil } // contains primes > 13
            return result
        }
        guard let fn = factor(n), let fd = factor(d) else { return nil }
        func exp(_ p: Int) -> Int { (fn[p] ?? 0) - (fd[p] ?? 0) }
        return Monzo(e2: exp(2), e3: exp(3), e5: exp(5), e7: exp(7), e11: exp(11), e13: exp(13))
    }
}
