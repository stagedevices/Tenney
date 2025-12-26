//
//  LatticeGridSettings.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/25/25.
//


import Foundation
import SwiftUI

// Shared by Settings + LatticeView

enum LatticeGridStyle: String, CaseIterable, Identifiable {
    case off
    case cells   // hex cells (existing)
    case mesh    // tri mesh (existing)
    case rails   // NEW: 2-direction skew “rail” lines (meaningfully distinct)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:   return "Off"
        case .cells: return "Cells"
        case .mesh:  return "Mesh"
        case .rails: return "Rails"
        }
    }

    var icon: String {
        switch self {
        case .off:   return "circle.slash"
        case .cells: return "hexagon"
        case .mesh:  return "triangle"
        case .rails: return "rhombus"
        }
    }
}

enum LatticeGridWeight: String, CaseIterable, Identifiable {
    case thin, light, medium, bold, heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thin:   return "Thin"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .bold:   return "Bold"
        case .heavy:  return "Heavy"
        }
    }

    var icon: String {
        switch self {
        case .thin:   return "lineweight"
        case .light:  return "lineweight"
        case .medium: return "lineweight"
        case .bold:   return "lineweight"
        case .heavy:  return "lineweight"
        }
    }

    // Keep renderer changes low-risk: map weights -> legacy-ish “strength” numbers (0...1).
    // Tune later if needed; preview validates.
    var legacyStrength: CGFloat {
        switch self {
        case .thin:   return 0.16
        case .light:  return 0.24
        case .medium: return 0.32
        case .bold:   return 0.40
        case .heavy:  return 0.48
        }
    }

    static func nearestForLegacyStrength(_ s: Double) -> LatticeGridWeight {
        let v = max(0.0, min(1.0, s))
        let all = LatticeGridWeight.allCases
        return all.min { abs(Double($0.legacyStrength) - v) < abs(Double($1.legacyStrength) - v) } ?? .medium
    }
}

// 5 fixed options for “Major every …” (chips)
let latticeGridMajorEveryOptions: [Int] = [2, 3, 4, 6, 8]

func nearestMajorEvery(_ v: Int) -> Int {
    latticeGridMajorEveryOptions.min(by: { abs($0 - v) < abs($1 - v) }) ?? 6
}
