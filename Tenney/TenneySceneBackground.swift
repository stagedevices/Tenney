//
//  TenneySceneBackground.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/25/25.
//

import SwiftUI

#if targetEnvironment(macCatalyst)
private let USE_STOP_GRADIENTS = false
#else
private let USE_STOP_GRADIENTS = true
#endif

/// Shared “atmospheric” background for instrument surfaces (Lattice + Tuner).
/// No visible grain/noise; depth comes from subtle multi-layer gradients + vignette.
struct TenneySceneBackground: View {
    let isDark: Bool
    var preset: TenneySceneBackgroundPreset = .standardAtmospheric
    /// Optional theme identity (very subtle): typically prime 3 + prime 5 tints.
    var tintA: Color = .accentColor
    var tintB: Color = .accentColor

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let s = geo.size

            let base: Color = {
                switch preset {
                case .standardAtmospheric:
                    // Push light mode back toward “paper-white”; keep dark mode off-black.
                    return isDark ? Color(white: 0.045) : Color(white: 0.992)
                case .nocturneReadable:
                    return isDark ? Color(hex: "#0E1A33") : Color(hex: "#F6F0E6")
                }
            }()

            ZStack {
                base

                // If user requests reduced transparency, keep it simple + clean.
                if !reduceTransparency {
                    // Gentle vertical lift (light mode should NOT darken at the top)
                    LinearGradient(
                        stops: {
                            switch preset {
                            case .standardAtmospheric:
                                return isDark
                                ? [
                                    .init(color: Color.white.opacity(0.060), location: 0.00),
                                    .init(color: Color.clear,               location: 0.55),
                                    .init(color: Color.black.opacity(0.220), location: 1.00)
                                  ]
                                : [
                                    .init(color: Color.white.opacity(0.55),  location: 0.00),
                                    .init(color: Color.clear,               location: 0.55),
                                    .init(color: Color.black.opacity(0.030), location: 1.00)
                                  ]
                            case .nocturneReadable:
                                let topLift = isDark ? Color(hex: "#2B3C60") : Color(hex: "#FFF9F1")
                                let lowShade = isDark ? Color(hex: "#071027") : Color(hex: "#2A1F18")
                                return isDark
                                ? [
                                    .init(color: topLift.opacity(0.22),     location: 0.00),
                                    .init(color: Color.clear,               location: 0.58),
                                    .init(color: lowShade.opacity(0.14),    location: 1.00)
                                  ]
                                : [
                                    .init(color: topLift.opacity(0.70),     location: 0.00),
                                    .init(color: Color.clear,               location: 0.60),
                                    .init(color: lowShade.opacity(0.06),    location: 1.00)
                                  ]
                            }
                        }(),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.normal)

                    // Vignette (light mode: lighter + non-multiply so it doesn’t gray-out the whole field)
                    let vignetteGradient = USE_STOP_GRADIENTS
                    ? Gradient(stops: [
                        .init(color: Color.clear, location: 0.00),
                        .init(color: Color.clear, location: isDark ? 0.54 : 0.62),
                        .init(
                            color: {
                                switch preset {
                                case .standardAtmospheric:
                                    return Color.black.opacity(isDark ? 0.72 : 0.10)
                                case .nocturneReadable:
                                    let tint = isDark ? Color(hex: "#05070A") : Color(hex: "#2A1F18")
                                    return tint.opacity(isDark ? 0.68 : 0.14)
                                }
                            }(),
                            location: 1.00
                        )
                    ])
                    : Gradient(colors: [
                        Color.clear,
                        Color.clear,
                        {
                            switch preset {
                            case .standardAtmospheric:
                                return Color.black.opacity(isDark ? 0.72 : 0.10)
                            case .nocturneReadable:
                                let tint = isDark ? Color(hex: "#05070A") : Color(hex: "#2A1F18")
                                return tint.opacity(isDark ? 0.68 : 0.14)
                            }
                        }()
                    ])

                    RadialGradient(
                        gradient: vignetteGradient,
                        center: .center,
                        startRadius: min(s.width, s.height) * (isDark ? 0.10 : 0.12),
                        endRadius: max(s.width, s.height) * (isDark ? 0.80 : 0.92)
                    )
                    .blendMode(isDark ? .multiply : .normal)
                    .opacity(isDark ? 1.0 : 0.85)

                    // Top-left “ambient” bloom (tinted identity)
                    let ambientGradient = USE_STOP_GRADIENTS
                    ? Gradient(stops: [
                        .init(color: {
                            switch preset {
                            case .standardAtmospheric:
                                return tintA.opacity(isDark ? 0.095 : 0.070)
                            case .nocturneReadable:
                                let ambientA = isDark ? Color(hex: "#D07A44") : Color(hex: "#C96A3A")
                                return ambientA.opacity(isDark ? 0.035 : 0.085)
                            }
                        }(), location: 0.00),
                        .init(color: {
                            switch preset {
                            case .standardAtmospheric:
                                return tintB.opacity(isDark ? 0.050 : 0.035)
                            case .nocturneReadable:
                                let ambientB = isDark ? Color(hex: "#E2C06A") : Color(hex: "#D7B25A")
                                return ambientB.opacity(isDark ? 0.020 : 0.045)
                            }
                        }(), location: 0.36),
                        .init(color: Color.clear, location: 0.74)
                    ])
                    : Gradient(colors: [
                        {
                            switch preset {
                            case .standardAtmospheric:
                                return tintA.opacity(isDark ? 0.095 : 0.070)
                            case .nocturneReadable:
                                let ambientA = isDark ? Color(hex: "#D07A44") : Color(hex: "#C96A3A")
                                return ambientA.opacity(isDark ? 0.035 : 0.085)
                            }
                        }(),
                        {
                            switch preset {
                            case .standardAtmospheric:
                                return tintB.opacity(isDark ? 0.050 : 0.035)
                            case .nocturneReadable:
                                let ambientB = isDark ? Color(hex: "#E2C06A") : Color(hex: "#D7B25A")
                                return ambientB.opacity(isDark ? 0.020 : 0.045)
                            }
                        }(),
                        Color.clear
                    ])

                    RadialGradient(
                        gradient: ambientGradient,
                        center: UnitPoint(x: 0.18, y: 0.18),
                        startRadius: 0,
                        endRadius: max(s.width, s.height) * 0.62
                    )
                    .blendMode(isDark ? .screen : .plusLighter)
                    .opacity({
                        switch preset {
                        case .standardAtmospheric:
                            return isDark ? 0.78 : 0.55
                        case .nocturneReadable:
                            return isDark ? 0.50 : 0.60
                        }
                    }())

                    // Bottom-right “sink” (dark mode only; in light mode this is what was pushing you to mid-gray)
                    if isDark {
                        let sinkGradient = USE_STOP_GRADIENTS
                        ? Gradient(stops: [
                            .init(color: Color.clear,                 location: 0.00),
                            .init(color: {
                                switch preset {
                                case .standardAtmospheric:
                                    return Color.black.opacity(0.55)
                                case .nocturneReadable:
                                    return Color(hex: "#05070A").opacity(0.48)
                                }
                            }(), location: 0.78),
                            .init(color: {
                                switch preset {
                                case .standardAtmospheric:
                                    return Color.black.opacity(0.86)
                                case .nocturneReadable:
                                    return Color(hex: "#05070A").opacity(0.72)
                                }
                            }(), location: 1.00)
                        ])
                        : Gradient(colors: [
                            Color.clear,
                            {
                                switch preset {
                                case .standardAtmospheric:
                                    return Color.black.opacity(0.55)
                                case .nocturneReadable:
                                    return Color(hex: "#05070A").opacity(0.48)
                                }
                            }(),
                            {
                                switch preset {
                                case .standardAtmospheric:
                                    return Color.black.opacity(0.86)
                                case .nocturneReadable:
                                    return Color(hex: "#05070A").opacity(0.72)
                                }
                            }()
                        ])

                        RadialGradient(
                            gradient: sinkGradient,
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
                                .init(color: {
                                    switch preset {
                                    case .standardAtmospheric:
                                        return Color.white.opacity(isDark ? 0.030 : 0.018)
                                    case .nocturneReadable:
                                        let lift = isDark ? Color(hex: "#243244") : Color(hex: "#FFF9F1")
                                        return lift.opacity(isDark ? 0.08 : 0.05)
                                    }
                                }(), location: 0.00),
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
