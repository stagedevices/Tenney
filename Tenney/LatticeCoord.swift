//
//  LatticeCoord.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  LatticeCoord.swift
//  Tenney
//

import Foundation

/// Coordinate in the 3×5 lattice plane: exponents of 3 and 5.
struct LatticeCoord: Hashable, Codable, Sendable {
    var e3: Int
    var e5: Int

    init(e3: Int, e5: Int) {
        self.e3 = e3
        self.e5 = e5
    }

    static let zero = LatticeCoord(e3: 0, e5: 0)
}

extension LatticeCoord: CustomStringConvertible {
    var description: String { "⟨3^\(e3),5^\(e5)⟩" }
}

extension LatticeCoord {
    static let unison = LatticeCoord(e3: 0, e5: 0)
}
