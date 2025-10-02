//
//  LatticeNode.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Placeholder for lattice data; Sprint-3 will flesh this out.
/// Using `Ratio` (not a tuple) so Hashable/Equatable synthesize cleanly.
struct LatticeNode: Identifiable, Hashable {
    var id: String { "\(ratio.n)/\(ratio.d)" }

    let ratio: Ratio            // e.g., Ratio(5,4)
    let monzo: [Int]            // [e2,e3,e5,e7,e11,(e13)]
    let tags: [String]          // e.g., ["triad","7-limit"]
}
