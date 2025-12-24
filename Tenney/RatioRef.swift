//
//  RatioRef.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  RatioRef.swift
//  Tenney
//

import Foundation

/// Builder-friendly representation of a selected ratio (plus optional octave and monzo).
struct RatioRef: Identifiable, Hashable, Codable, Sendable {
    let p: Int
    let q: Int
    let octave: Int
    let monzo: [Int:Int]
    
    var id: String { "\(p)/\(q)@\(octave)" }
    
    init(p: Int, q: Int, octave: Int = 0, monzo: [Int:Int] = [:]) {
        self.p = max(1, p)
        self.q = max(1, q)
        self.octave = octave
        self.monzo = monzo
    }
    
    var ratio: Double { Double(p) / Double(q) }
    
    var ratioString: String { "\(p)/\(q)" }
    
    
    /// Canonicalize to the unit octave (1 ≤ P/Q < 2), reduced.
    func normalizedPQ() -> (Int, Int) {
        let (P, Q) = RatioMath.canonicalPQUnit(p, q)
        return (P, Q)
    }
    
}
/// Label display mode for lattice nodes / pills.
enum JILabelMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case ratio
    case heji

    var id: String { rawValue }
}
