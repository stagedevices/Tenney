//
//  TenneySceneBackground.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/25/25.
//

import SwiftUI

/// Shared “atmospheric” background for instrument surfaces (Lattice + Tuner).
/// No visible grain/noise; depth comes from subtle multi-layer gradients + vignette.
struct TenneySceneBackground: View {
    let isDark: Bool
    /// Optional theme identity (very subtle): typically prime 3 + prime 5 tints.
    var tintA: Color = .accentColor
    var tintB: Color = .accentColor

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let s = geo.size

            // Push light mode back toward “paper-white”; keep dark mode off-black.
            let base: Color = isDark ? Color(white: 0.045) : Color(white: 0.992)

            ZStack {
                base

                // If user requests reduced transparency, keep it simple + clean.
                if !reduceTransparency {
                    // Gentle vertical lift (light mode should NOT darken at the top)
                    LinearGradient(
                        stops: isDark
                        ? [
                            .init(color: Color.white.opacity(0.060), location: 0.00),
                            .init(color: Color.clear,               location: 0.55),
                            .init(color: Color.black.opacity(0.220), location: 1.00)
                          ]
                        : [
                            .init(color: Color.white.opacity(0.55),  location: 0.00),
                            .init(color: Color.clear,               location: 0.55),
                            .init(color: Color.black.opacity(0.030), location: 1.00)
                          ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.normal)

                    // Vignette (light mode: lighter + non-multiply so it doesn’t gray-out the whole field)
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.clear, location: 0.00),
                            .init(color: Color.clear, location: isDark ? 0.54 : 0.62),
                            .init(color: Color.black.opacity(isDark ? 0.72 : 0.10), location: 1.00)
                        ]),
                        center: .center,
                        startRadius: min(s.width, s.height) * (isDark ? 0.10 : 0.12),
                        endRadius: max(s.width, s.height) * (isDark ? 0.80 : 0.92)
                    )
                    .blendMode(isDark ? .multiply : .normal)
                    .opacity(isDark ? 1.0 : 0.85)

                    // Top-left “ambient” bloom (tinted identity)
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: tintA.opacity(isDark ? 0.095 : 0.070), location: 0.00),
                            .init(color: tintB.opacity(isDark ? 0.050 : 0.035), location: 0.36),
                            .init(color: Color.clear,                           location: 0.74)
                        ]),
                        center: UnitPoint(x: 0.18, y: 0.18),
                        startRadius: 0,
                        endRadius: max(s.width, s.height) * 0.62
                    )
                    .blendMode(isDark ? .screen : .plusLighter)
                    .opacity(isDark ? 0.78 : 0.55)

                    // Bottom-right “sink” (dark mode only; in light mode this is what was pushing you to mid-gray)
                    if isDark {
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear,                 location: 0.00),
                                .init(color: Color.black.opacity(0.55),   location: 0.78),
                                .init(color: Color.black.opacity(0.86),   location: 1.00)
                            ]),
                            center: UnitPoint(x: 0.86, y: 0.86),
                            startRadius: 0,
                            endRadius: max(s.width, s.height) * 0.70
                        )
                        .blendMode(.multiply)
                    }

                    // Optional micro “specular” wash (static; not noisy). Disable if reduce motion.
                    if !reduceMotion {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isDark ? 0.030 : 0.018), location: 0.00),
                                .init(color: Color.clear,                                   location: 0.42),
                                .init(color: Color.clear,                                   location: 1.00)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.screen)
                        .opacity(isDark ? 1.0 : 0.70)
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}
