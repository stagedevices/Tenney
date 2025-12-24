//
//  HarmonicModel.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


import Foundation

public enum HarmonicModel {
    public struct Fit {
        public let f0: Double
        public let beta: Double
        public let r2: Double
    }

    public static func fitF0Beta(initialF0: Double,
                                 partials: [(k: Int, freq: Double, snrDB: Double)],
                                 maxIter: Int = 8) -> Fit? {
        guard initialF0 > 0, !partials.isEmpty else { return nil }
        var f0 = initialF0
        var beta = 0.0

        for _ in 0..<maxIter {
            var a11 = 0.0, a12 = 0.0, a22 = 0.0
            var b1  = 0.0, b2  = 0.0

            for p in partials {
                let k = Double(p.k)
                let w = pow(10.0, p.snrDB / 20.0)
                let g = sqrt(1.0 + beta * k * k)
                let pred = k * f0 * g
                let r = p.freq - pred
                let df0 = k * g
                let db  = 0.5 * k * f0 * (1.0 / g) * (k * k)

                a11 += w * df0 * df0
                a12 += w * df0 * db
                a22 += w * db  * db
                b1  += w * df0 * r
                b2  += w * db  * r
            }

            let det = a11 * a22 - a12 * a12
            guard abs(det) > 1e-12 else { break }
            let df0 = ( a22 * b1 - a12 * b2) / det
            let db  = (-a12 * b1 + a11 * b2) / det

            f0 += df0
            beta = max(0.0, beta + db)
            if abs(df0) < 1e-6 && abs(db) < 1e-9 { break }
        }

        var num = 0.0, den = 0.0
        for p in partials {
            let k = Double(p.k)
            let g = sqrt(1.0 + beta * k * k)
            let pred = k * f0 * g
            let w = pow(10.0, p.snrDB / 20.0)
            let r = p.freq - pred
            num += w * r * r
            den += w * (p.freq * p.freq)
        }
        let r2 = den > 0 ? max(0, 1.0 - num / den) : 0
        return Fit(f0: f0, beta: beta, r2: r2)
    }
}
