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

    // Renderer-facing mapping: stored strength is 0...1, but visual output can be much stronger.
    var index: Int {
        switch self {
        case .thin:   return 0
        case .light:  return 1
        case .medium: return 2
        case .bold:   return 3
        case .heavy:  return 4
        }
    }

    static func fromStrength01(_ s: Double) -> LatticeGridWeight {
        let v = max(0.0, min(1.0, s))
        let i = Int((v * 4.0).rounded()) // 0...4
        return LatticeGridWeight.allCases[max(0, min(4, i))]
    }

    // These are intentionally aggressive so 1.0 actually reads as "Heavy".
    var strokeAlpha: CGFloat {
        [0.14, 0.24, 0.40, 0.72, 0.88][index]
    }

    var strokeWidth: CGFloat {
        [0.65, 1.10, 1.35, 1.60, 2.10][index]
    }

    var majorStrokeAlpha: CGFloat {
        min(0.12, strokeAlpha * 0.8)
    }

    var majorStrokeWidth: CGFloat {
        strokeWidth * 1.1
    }

}

// 5 fixed options for “Major every …” (chips)
let latticeGridMajorEveryOptions: [Int] = [2, 3, 4, 6, 8]

func nearestMajorEvery(_ v: Int) -> Int {
    latticeGridMajorEveryOptions.min(by: { abs($0 - v) < abs($1 - v) }) ?? 6
}
