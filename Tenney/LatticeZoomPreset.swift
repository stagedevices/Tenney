//
//  LatticeZoomPreset.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/24/25.
//


import Foundation
import CoreGraphics

enum LatticeZoomPreset: String, CaseIterable, Identifiable {
    case overview
    case standard
    case close
    case ultraClose   // NEW: tighter-than-close

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:   return "Overview"
        case .standard:   return "Standard"
        case .close:      return "Close"
        case .ultraClose: return "Ultra Close"
        }
    }

    /// Bigger scale = more zoomed in.
    var scale: CGFloat {
        switch self {
        // Shift everything “one step tighter” + add a new tight end-stop.
        case .overview:   return 56    // was your old .standard-ish
        case .standard:   return 84    // was your old .close-ish
        case .close:      return 120   // NEW tighter close
        case .ultraClose: return 168   // NEW max zoom step (keep < 240 clamp)
        }
    }

    static let order: [LatticeZoomPreset] = [.overview, .standard, .close, .ultraClose]

    static func step(from current: LatticeZoomPreset, dir: Int) -> LatticeZoomPreset {
        guard let i = order.firstIndex(of: current) else { return .standard }
        let j = max(0, min(order.count - 1, i + dir))
        return order[j]
    }

    static func fromDefaults() -> LatticeZoomPreset {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: SettingsKeys.latticeDefaultZoomPreset),
           let p = LatticeZoomPreset(rawValue: raw) { return p }
        return .close
    }

    static func nearest(toScale s: CGFloat) -> LatticeZoomPreset {
        order.min(by: { abs($0.scale - s) < abs($1.scale - s) }) ?? .standard
    }
}

