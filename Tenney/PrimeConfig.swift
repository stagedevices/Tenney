

//  PrimeConfig.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//



// ============================================================================
// 1) NEW: PrimeConfig.swift — prime axes (angles, colors) up to 31
// ============================================================================
import SwiftUI

struct PrimeAxis: Identifiable, Hashable {
    let id: Int
    let angleDeg: Double      // visual axis angle in degrees
    let color: Color          // base tint for nodes/overlays
}

/// Color/hue suggestions (distinct yet readable on glass). Adjust to taste.
private func hue(_ h: Double) -> Color { Color(hue: h, saturation: 0.65, brightness: 0.95) }

enum PrimeConfig {
    /// order matters for UI chips
    static let primes: [Int] = [3,5,7,11,13,17,19,23,29,31]

    /// angles adapted for readable separation; 3→0°, 5→60°, others spaced to avoid collisions
    static let axes: [Int: PrimeAxis] = [
        3:  PrimeAxis(id: 3,  angleDeg:   0, color: hue(0.62)), // blue-violet
        5:  PrimeAxis(id: 5,  angleDeg:  60, color: hue(0.10)), // orange
        7:  PrimeAxis(id: 7,  angleDeg: 110, color: hue(0.90)), // magenta
        11: PrimeAxis(id: 11, angleDeg: 150, color: hue(0.50)), // cyan
        13: PrimeAxis(id: 13, angleDeg: 200, color: hue(0.78)), // pink
        17: PrimeAxis(id: 17, angleDeg: 230, color: hue(0.30)), // lime
        19: PrimeAxis(id: 19, angleDeg: 265, color: hue(0.00)), // red
        23: PrimeAxis(id: 23, angleDeg: 305, color: hue(0.42)), // teal
        29: PrimeAxis(id: 29, angleDeg: 330, color: hue(0.15)), // amber
        31: PrimeAxis(id: 31, angleDeg: 345, color: hue(0.70))  // purple
    ]
}

//
