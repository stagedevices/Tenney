//
//  LatticeConnectionMode.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/26/25.
//


import Foundation

enum LatticeConnectionMode: String, CaseIterable, Identifiable, Codable {
    case chain      // current behavior
    case loop       // closes for 3+
    case gridPath   // routed along grid edges (ordinal; not closed)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chain:    return "Chain"
        case .loop:     return "Loop (3+ closes)"
        case .gridPath: return "Grid Path"
        }
    }
}
