//
//  Ratio.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Minimal ratio & cents utilities; normalized so d > 0 and gcd(n,d) == 1
struct Ratio: Equatable, Hashable, Codable {
    let n: Int
    let d: Int

    init(_ n: Int, _ d: Int) {
        // Defensive: never crash; coerce bad input to 1/1
        if d == 0 {
            self.n = 1
            self.d = 1
            return
        }
        var nn = n, dd = d
        if dd < 0 { nn = -nn; dd = -dd }
        let g = gcd(nn, dd)
        self.n = nn / g
        self.d = dd / g
    }

    var value: Double { Double(n) / Double(d) }
    var cents: Double { 1200.0 * log2(value) }

    func multiplied(by r: Ratio) -> Ratio { Ratio(n * r.n, d * r.d) }
    func divided(by r: Ratio) -> Ratio { Ratio(n * r.d, d * r.n) }
}

enum Cents {
    @inlinable static func fromRatio(_ r: Ratio) -> Double { r.cents }
    @inlinable static func between(_ a: Ratio, _ b: Ratio) -> Double { 1200.0 * log2(a.value / b.value) }
}

