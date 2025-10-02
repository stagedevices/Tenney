//
//  ScaleRuntime.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Runtime scale table produced from Scala + optional KBM mapping.
/// Provides per-degree cents and Ratio, relative to 1/1 root.
struct ScaleTable {
    struct Degree: Equatable {
        let ratio: Ratio
        let cents: Double
    }
    let description: String
    let degrees: [Degree] // does not include 2/1 unless in source

    static func from(scala: ScalaScale) -> ScaleTable {
        let degs: [Degree] = scala.entries.map {
            switch $0 {
            case .ratio(let r): return Degree(ratio: r, cents: r.cents)
            case .cents(let c):
                // approximate cents to nearest ratio under 11-limit within 5 cents for a clean runtime table
                let r = centsToNearestRatio(c, limit: .eleven, tolerance: 5.0)
                return Degree(ratio: r, cents: c)
            }
        }
        return ScaleTable(description: scala.description, degrees: degs)
    }

    /// Convert cents (relative to 1/1) to nearest ratio under a limit.
    private static func centsToNearestRatio(_ cents: Double, limit: PrimeLimit, tolerance: Double) -> Ratio {
        let x = pow(2.0, cents / 1200.0)
        let r = RatioApproximator.approximate(x, options: .init(primeLimit: limit, maxDenominator: 4096, maxCentsError: max(tolerance, 50)))
        return r
    }
}
