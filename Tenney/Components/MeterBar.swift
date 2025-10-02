//
//  MeterBar.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import SwiftUI

struct MeterBar: View {
    /// RMS in [0, ~1]
    let level: Float

    private var normalized: CGFloat {
        // Map roughly -60 dBFS .. 0 dBFS → 0..1
        let l = max(1e-6, Double(level))
        let db = 20.0 * log10(l)
        let t = (db + 60.0) / 60.0
        return CGFloat(min(max(t, 0.0), 1.0))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(.green).frame(width: geo.size.width * normalized)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Input level")
    }
}
