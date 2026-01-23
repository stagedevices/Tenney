//
//  TenneyLimitEncoding.swift
//  Tenney
//
//  Shared helpers for limit buckets + accessibility-friendly labeling.
//

import Foundation

enum TenneyLimitBucket: Int, CaseIterable, Sendable {
    case limit5 = 5
    case limit7 = 7
    case limit11 = 11
    case limit13 = 13
    case limit17 = 17
    case limit19 = 19
    case limit23 = 23
    case limit29 = 29
    case limit31 = 31

    var shapeName: String {
        switch self {
        case .limit5: return "circle"
        case .limit7: return "triangle"
        case .limit11: return "square"
        case .limit13: return "diamond"
        case .limit17: return "pentagon"
        case .limit19: return "hexagon"
        case .limit23: return "heptagon"
        case .limit29: return "octagon"
        case .limit31: return "shield"
        }
    }
}

func limitBucket(for signature: RatioSignature) -> TenneyLimitBucket {
    guard let highest = signature.exps.map(\.p).max() else { return .limit5 }
    return bucket(forPrime: highest)
}

func bucket(forPrime p: Int) -> TenneyLimitBucket {
    switch p {
    case ..<7:
        return .limit5
    case 7:
        return .limit7
    case 11:
        return .limit11
    case 13:
        return .limit13
    case 17:
        return .limit17
    case 19:
        return .limit19
    case 23:
        return .limit23
    case 29:
        return .limit29
    default:
        return .limit31
    }
}

// MARK: - Manual QA checklist
// - Toggle OFF: visuals unchanged.
// - Toggle ON: lattice nodes, tuner chips, and overlay chips show shapes.
// - Patterns: only active when enabled, and disabled for Reduce Motion/Transparency.
// - Light/Dark: shapes + stroke remain readable.
// - Performance: lattice pan/zoom remains smooth.
