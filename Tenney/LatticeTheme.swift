//  LatticeTheme.swift
//  Tenney
//
//  Minimal node/guide/overlay theme tokens + Environment key/registry.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: Theme model
struct LatticeTheme: Equatable {
    enum Mix: String { case hardSplit, blendByWeight }

    // Node colors
    var e3: Color
    var e5: Color
    var mix: Mix = .hardSplit
    var isDark: Bool = false
    
    

    // Guides / selection path / labels
    var axisE3: Color
    var axisE5: Color
    var path: Color
    var labelPrimary: Color
    var labelSecondary: Color

    // High-prime overlay colors (chips/dots/planes)
    var overlayPrime: [Int: Color] = [:]

    // Node color resolver
    func nodeColor(e3 e3Exp: Int, e5 e5Exp: Int) -> Color {
        // Special-case the unshifted origin (1/1)
                if e3Exp == 0 && e5Exp == 0 {
                    // Dark gray in light mode, light gray in dark mode
                    return isDark ? Color(white: 0.82) : Color(white: 0.25)
                }
                switch mix {
                case .hardSplit:
                    return (e5Exp == 0) ? e3 : e5
                case .blendByWeight:
                    let a = abs(e3Exp), b = abs(e5Exp)
                    let t = (a + b == 0) ? 0.0 : Double(b) / Double(a + b)
                    return e3._interpolate(to: e5, t: t)
                }
    }
}
extension LatticeTheme {
    /// Theme-aware tint for any prime.
    func primeTint(_ p: Int) -> Color {
        switch p {
        case 3: return e3
        case 5: return e5
        default: return overlayPrime[p] ?? .gray
        }
    }
}

// MARK: Registry
enum LatticeThemeID: String, CaseIterable, Identifiable {
    case classicBO, tealAmber, indigoGold, sodium, monochrome, nocturneBO
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classicBO: return "Chromatic (Default)"
        case .tealAmber: return "Blue/Green"
        case .indigoGold: return "Crystal"
        case .sodium: return "Tricolor"
        case .monochrome: return "Monochrome"
        case .nocturneBO: return "Nocturne"
        }
    }
}
struct ThemeRegistry {
    static func theme(_ id: LatticeThemeID, dark: Bool) -> LatticeTheme {
        switch id {
            //system chromatic
        case .classicBO:
            return LatticeTheme(
                e3: Color(hex: "#2F7CF6"),
                e5: Color(hex: "#FF8A2A"),
                mix: .hardSplit,
                isDark: dark,
                axisE3: Color(hex: "#2F7CF6").opacity(0.18),
                axisE5: Color(hex: "#FF8A2A").opacity(0.18),
                path: .white.opacity(dark ? 0.60 : 0.55),
                labelPrimary: dark ? Color(hex: "#E9F2FF") : Color.primary,
                labelSecondary: dark ? Color(hex: "#A8B4CC") : Color.secondary,
                overlayPrime: overlayClassic(dark: dark)
            )
            
        case .tealAmber: // rename however you store this
            return LatticeTheme(
                e3: Color(hex: "#009AFD"),
                e5: Color(hex: "#FF9400"),
                mix: .blendByWeight,
                isDark: dark,
                axisE3: Color(hex: "#009AFD").opacity(0.16),
                axisE5: Color(hex: "#FF9400").opacity(0.16),
                path: Color(hex: dark ? "#FFFFFF" : "#0B1020").opacity(dark ? 0.56 : 0.26),
                labelPrimary: dark ? Color(hex: "#F5FAFF") : Color(hex: "#0B1020"),
                labelSecondary: dark ? Color(hex: "#B9C6DA") : .secondary,
                overlayPrime: overlayTealAmber(dark: dark)
            )
            
        case .indigoGold:
          return LatticeTheme(
            e3: Color(hex: "#38D9FF"),
            e5: Color(hex: "#B06CFF"),
            mix: .blendByWeight,
            isDark: dark,

            axisE3: Color(hex: "#38D9FF").opacity(dark ? 0.15 : 0.12),
            axisE5: Color(hex: "#B06CFF").opacity(dark ? 0.15 : 0.12),

            // crystal rail: bright in dark, ink-soft in light
            path: Color(hex: dark ? "#FFFFFF" : "#0A0F1F").opacity(dark ? 0.56 : 0.26),

            labelPrimary: dark ? Color(hex: "#F5F8FF") : Color(hex: "#0A0F1F"),
            labelSecondary: dark ? Color(hex: "#B8C2D9") : .secondary,
            overlayPrime: overlayIndigoGold(dark: dark)
          )
            
        case .sodium:
            return LatticeTheme(
                e3: Color(hex: "#F0442E"),        // 3-limit axis: red
                e5: Color(hex: "#1F6FE5"),        // 5-limit axis: the only blue

                mix: .hardSplit,
                isDark: dark,

                axisE3: Color(hex: "#F0442E").opacity(dark ? 0.20 : 0.14),
                axisE5: Color(hex: "#1F6FE5").opacity(dark ? 0.20 : 0.14),

                // warm/yellow field (less mustard, more primary)
                path: Color(hex: dark ? "#FFE7A6" : "#B97700").opacity(dark ? 0.58 : 0.30),

                labelPrimary: dark ? Color(hex: "#FFF4E6") : Color.primary,
                labelSecondary: dark ? Color(hex: "#E8D7C1") : Color.secondary,

                overlayPrime: overlaySodium(dark: dark)
            )
            
        case .monochrome:
            let inkHex = UserDefaults.standard.string(forKey: SettingsKeys.tenneyMonochromeTintHex) ?? "#000000"
            let ink = Color(hex: inkHex)

            let primary = dark
                ? ink.mixed(with: .white, amount: 0.85)   // “lab ink glow” on dark
                : ink                                     // true ink on light

            let secondary = dark ? primary.opacity(0.70) : primary.opacity(0.60)

            return LatticeTheme(
                e3: primary,
                e5: primary.opacity(0.7),
                mix: .blendByWeight,
                isDark: dark,
                axisE3: primary.opacity(0.35),
                axisE5: primary.opacity(0.35),
                path: primary.opacity(0.55),
                labelPrimary: primary,
                labelSecondary: secondary,
                overlayPrime: overlayMonochromeTinted(dark: dark, ink: ink) // see next section
            )
            
        case .nocturneBO:
            return LatticeTheme(
                e3: Color(hex: "#80B3FF"),
                e5: Color(hex: "#FFB47B"),
                mix: .blendByWeight,
                isDark: dark,
                axisE3: Color.white.opacity(0.14),
                axisE5: Color.white.opacity(0.14),
                path: Color.white.opacity(0.58),
                labelPrimary: Color(hex: "#D9E3F7"),
                labelSecondary: Color(hex: "#9AA9C1"),
                overlayPrime: overlayNocturne(dark: dark)
            )
        }
    }
    
    // Helper
    private static func palette(_ hexes: [Int:String]) -> [Int:Color] {
        var out: [Int:Color] = [:]
        for (k,v) in hexes { out[k] = Color(hex: v) }
        return out
    }
    
    // System Chromatic
    private static func overlayClassic(dark: Bool) -> [Int:Color] {
        dark
        ? palette([ 7:"#A9A7FF", 11:"#64D7D2", 13:"#FF86B6", 17:"#FFD166",
                    19:"#86E36E", 23:"#5FB3FF", 29:"#D59CFF", 31:"#FFB071"])
        : palette([ 7:"#6F73FF", 11:"#00BDB8", 13:"#FF4F93", 17:"#E7A700",
                    19:"#2CCB4A", 23:"#167DFF", 29:"#B45CFF", 31:"#FF7A2F"])
    }

    private static func overlayMonochromeTinted(dark: Bool, ink: Color) -> [Int:Color] {
        let primes = [7, 11, 13, 17, 19, 23, 29, 31]

        let weightsDark: [CGFloat]  = [0.92, 0.84, 0.76, 0.68, 0.60, 0.52, 0.44, 0.36] // toward white
        let weightsLight: [CGFloat] = [0.18, 0.28, 0.36, 0.44, 0.52, 0.60, 0.68, 0.76] // toward black

        let weights = dark ? weightsDark : weightsLight
        let target: Color = dark ? .white : .black

        var out: [Int:Color] = [:]
        out.reserveCapacity(primes.count)

        for (p, w) in zip(primes, weights) {
            out[p] = ink.mixed(with: target, amount: w)
        }
        return out
    }

    
    // Teal/Amber: sea + sand spectrum
    private static func overlayTealAmber(dark: Bool) -> [Int:Color] {
        dark
            ? palette([
                7 :"#FF2FD6",  // laser magenta (rhodamine)
                11:"#A6FF00",  // fluorescein lime (lab green)

                13:"#7B5CFF",  // UV-ish violet (no cyan)
                17:"#FFF36A",  // citrine-ice (clean yellow)
                19:"#3DFF9B",  // neon mint (clinical, not “leafy”)
                23:"#D6C7FF",  // sterile lilac (bright but soft)
                29:"#FF3B6A",  // red dye (warm but not orange)
                31:"#FFF1B8"   // champagne highlight (specular white-gold)
            ])
            : palette([
                7 :"#C600A9",  // deep magenta
                11:"#5FB800",  // fluorescein green (print-safe)

                13:"#4E3DFF",  // UV violet
                17:"#D6B800",  // citrine
                19:"#00B87A",  // mint-teal (still not cyan-blue)
                23:"#B69CFF",  // lilac
                29:"#E1004F",  // dye red
                31:"#B88900"   // champagne
            ])
        }
    
    // Indigo/Gold: royal violets & ambers
    private static func overlayIndigoGold(dark: Bool) -> [Int:Color] {
        dark
            ? palette([
                7:"#FF8EEA",   // fuchsia flash
                11:"#7CFFE6",  // aqua flash
                13:"#FF6FB3",  // opal-rose (cooler, less “reused ruby”)
                17:"#E9FF7A",  // citrine-ice (yellow with a green prism edge)
                19:"#7DFFB6",  // aurora-mint (icy green, not grassy)
                23:"#A9C0FF",  // glacier-periwinkle (ice facet highlight)
                29:"#D9B8FF",  // lavender-frost (soft amethyst sheen)
                31:"#FFF0B5"   // champagne flash (specular “white-gold”, not orange)
            ])
            : palette([
                7:"#C400A6",
                11:"#00C6A8",
                13:"#D30062",  // cool raspberry (less hot-pink, still crisp)
                17:"#B8C400",  // citrine (primary-leaning yellow, not mustard)
                19:"#00B87A",  // mint-teal (opal green)
                23:"#5B66FF",  // periwinkle-ice (kept in the “crystal” lane, not deep blue)
                29:"#6B2CFF",  // violet prism (more spectral, less “standard purple”)
                31:"#B88E00"   // champagne (reads like warm specular on white materials)
            ])
        }
    
    // Sodium: warm sodium-lamp / sepia accents
    private static func overlaySodium(dark: Bool) -> [Int:Color] {
        dark
            ? palette([
                7:"#FFCC00",   // primary yellow
                11:"#7FE36B",  // green
                13:"#FF4D6D",  // red-pink (warm)
                17:"#FF6A4A",  // red → orange (warm)
                19:"#A6F25A",  // yellow-green
                23:"#3DCC7A",  // green (deeper)
                29:"#D94DFF",  // magenta (no blue cast)
                31:"#FF9A3D"   // orange
            ])
            : palette([
                7:"#FFC400",
                11:"#2FB24A",
                13:"#D81B4E",
                17:"#E63B2A",
                19:"#63C52D",
                23:"#139D55",
                29:"#A12BE2",
                31:"#FF7A1A"
            ])
        }

    
    // Nocturne: cool night tones with neon warmth
    private static func overlayNocturne(dark: Bool) -> [Int:Color] {
        dark
        ? palette([ 7:"#C7A1FF", 11:"#77E4DD", 13:"#FFA7C6", 17:"#F4D37B",
                    19:"#ADEF77", 23:"#9EDCFF", 29:"#E3A9FF", 31:"#FFBE94"])
        : palette([ 7:"#AD88FF", 11:"#55D6D1", 13:"#FF94B4", 17:"#F2C259",
                    19:"#86DF63", 23:"#7FD2FF", 29:"#D389FF", 31:"#FFAC7A"])
    }
    
}

// MARK: Environment
private struct LatticeThemeKey: EnvironmentKey {
    static let defaultValue: LatticeTheme = ThemeRegistry.theme(.classicBO, dark: false)
}
extension EnvironmentValues {
    var latticeTheme: LatticeTheme {
        get { self[LatticeThemeKey.self] }
        set { self[LatticeThemeKey.self] = newValue }
    }
}


// MARK: Utilities
extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0; Scanner(string: s).scanHexInt64(&n)
        let a, r, g, b: UInt64
        switch s.count {
        case 3: (a, r, g, b) = (255, (n >> 8) * 17, (n >> 4 & 0xF) * 17, (n & 0xF) * 17)
        case 6: (a, r, g, b) = (255, n >> 16, n >> 8 & 0xFF, n & 0xFF)
        case 8: (a, r, g, b) = (n >> 24, n >> 16 & 0xFF, n >> 8 & 0xFF, n & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self = Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    /// sRGB interpolation (UI-safe; not perceptually uniform).
    fileprivate func _interpolate(to other: Color, t: Double) -> Color {
        #if canImport(UIKit)
        let ui1 = UIColor(self), ui2 = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ui1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ui2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tt = max(0.0, min(1.0, t))
        return Color(red: Double(r1 + (r2 - r1) * tt),
                     green: Double(g1 + (g2 - g1) * tt),
                     blue: Double(b1 + (b2 - b1) * tt),
                     opacity: Double(a1 + (a2 - a1) * tt))
        #else
        return self
        #endif
    }
}

extension Color {
    func mixed(with other: Color, amount: CGFloat) -> Color {
        let t = max(0, min(1, amount))
        let a = self.rgba
        let b = other.rgba
        return Color(
            red:   a.r * (1 - t) + b.r * t,
            green: a.g * (1 - t) + b.g * t,
            blue:  a.b * (1 - t) + b.b * t,
            opacity: a.a * (1 - t) + b.a * t
        )
    }

    private var rgba: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(AppKit)
        let ns = NSColor(self)
        let c = (ns.usingColorSpace(.sRGB) ?? ns)
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}

//
