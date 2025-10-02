//
//  Strictness.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

enum Strictness: String, CaseIterable, Identifiable {
    case loose, performance, strict
    var id: String { rawValue }

    /// Hysteresis band (cents) around the current target before we consider switching
    var hysteresisCents: Double {
        switch self {
        case .loose:       return 8.0
        case .performance: return 5.0
        case .strict:      return 3.0
        }
    }

    /// Minimum time (ms) a new candidate must remain dominant before we switch
    var minDwellMs: Int {
        switch self {
        case .loose:       return 140
        case .performance: return 180
        case .strict:      return 240
        }
    }

    /// Kalman process noise (larger = more responsive)
    var kalmanQ: Double {
        switch self {
        case .loose:       return 3.5
        case .performance: return 2.0
        case .strict:      return 1.0
        }
    }

    /// Kalman measurement noise (lower = trust measurements more)
    var kalmanR: Double {
        switch self {
        case .loose:       return 8.0
        case .performance: return 6.0
        case .strict:      return 4.0
        }
    }
}
