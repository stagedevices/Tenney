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
        case .classicBO: return "Classic"
        case .tealAmber: return "Teal/Amber"
        case .indigoGold: return "Indigo/Gold"
        case .sodium: return "Goldenrod"
        case .monochrome: return "Monochrome"
        case .nocturneBO: return "Nocturne"
        }
    }
}
struct ThemeRegistry {
    static func theme(_ id: LatticeThemeID, dark: Bool) -> LatticeTheme {
        switch id {
        case .classicBO:
            return LatticeTheme(
                e3: Color(hex: "#4EA1FF"),
                e5: Color(hex: "#FF9F47"),
                mix: .hardSplit,
                isDark: dark,
                axisE3: Color(hex: "#4EA1FF").opacity(0.18),
                axisE5: Color(hex: "#FF9F47").opacity(0.18),
                path: .white.opacity(dark ? 0.60 : 0.55),
                labelPrimary: dark ? Color(hex: "#E9F2FF") : Color.primary,
                labelSecondary: dark ? Color(hex: "#A8B4CC") : Color.secondary,
                overlayPrime: overlayClassic(dark: dark)
            )
            
        case .tealAmber:
            return LatticeTheme(
                e3: Color(hex: "#22B3AC"),
                e5: Color(hex: "#FFC247"),
                mix: .hardSplit,
                isDark: dark,
                axisE3: Color(hex: "#22B3AC").opacity(0.18),
                axisE5: Color(hex: "#FFC247").opacity(0.18),
                path: .white.opacity(0.55),
                labelPrimary: dark ? .white : .black,
                labelSecondary: .secondary,
                overlayPrime: overlayTealAmber(dark: dark)
            )
            
        case .indigoGold:
            return LatticeTheme(
                e3: Color(hex: "#5B66FF"),
                e5: Color(hex: "#E6B400"),
                mix: .blendByWeight,
                isDark: dark,
                axisE3: Color(hex: "#5B66FF").opacity(0.16),
                axisE5: Color(hex: "#E6B400").opacity(0.16),
                path: .white.opacity(0.66),
                labelPrimary: dark ? Color(hex: "#E8EAFF") : .black,
                labelSecondary: .secondary,
                overlayPrime: overlayIndigoGold(dark: dark)
            )
            
        case .sodium:
            return LatticeTheme(
                e3: Color(hex: "#FFD36A"),
                e5: Color(hex: "#FFEFBB"),
                mix: .hardSplit,
                isDark: dark,
                axisE3: Color(hex: "#7A5A2E").opacity(0.25),
                axisE5: Color(hex: "#7A5A2E").opacity(0.25),
                path: Color(hex: "#FFF7DA").opacity(0.60),
                labelPrimary: Color(hex: "#FFF3CC"),
                labelSecondary: Color(hex: "#E8D39A"),
                overlayPrime: overlaySodium(dark: dark)
            )
            
        case .monochrome:
            let primary = dark ? Color.white : Color.black
            let secondary = dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
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
                overlayPrime: overlayMonochrome(dark: dark)
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
    
    // Classic: bright candy hues
    private static func overlayClassic(dark: Bool) -> [Int:Color] {
        dark
        ? palette([ 7:"#C29AFF", 11:"#6FE0D6", 13:"#FFA1C4", 17:"#F0D46B",
                    19:"#B7F277", 23:"#8AD8FF", 29:"#E29CFF", 31:"#FFB084"])
        : palette([ 7:"#B07CFF", 11:"#59D0C6", 13:"#FF7DAE", 17:"#E7C652",
                    19:"#9EDB50", 23:"#70C9FF", 29:"#D16BF0", 31:"#FF9B6B"])
    }
    
    // Teal/Amber: sea + sand spectrum
    private static func overlayTealAmber(dark: Bool) -> [Int:Color] {
        dark
        ? palette([ 7:"#B694FF", 11:"#72E5DE", 13:"#FF99BC", 17:"#E8D468",
                    19:"#A7EF6F", 23:"#8ED7FF", 29:"#F39CFF", 31:"#FFC085"])
        : palette([ 7:"#9F6CFF", 11:"#3CD6CE", 13:"#FF6FA3", 17:"#E5C24B",
                    19:"#69CC4E", 23:"#4DBDFF", 29:"#E36FF2", 31:"#FF9853"])
    }
    
    // Indigo/Gold: royal violets & ambers
    private static func overlayIndigoGold(dark: Bool) -> [Int:Color] {
        dark
        ? palette([ 7:"#D4B6FF", 11:"#7EE7EF", 13:"#FFA6CC", 17:"#F6BA6E",
                    19:"#A5F07A", 23:"#9FD8FF", 29:"#E4A6FF", 31:"#FFC69A"])
        : palette([ 7:"#B58BFF", 11:"#43D0E1", 13:"#FF82BE", 17:"#F49A54",
                    19:"#76D85A", 23:"#64C3FF", 29:"#CC75F7", 31:"#FFA267"])
    }
    
    // Sodium: warm sodium-lamp / sepia accents
    private static func overlaySodium(dark: Bool) -> [Int:Color] {
        dark
        ? palette([ 7:"#C59CFF", 11:"#7DD8DE", 13:"#FFA3C4", 17:"#E6D067",
                    19:"#A6DE6B", 23:"#8ED0FF", 29:"#E2A1FF", 31:"#FFB37E"])
        : palette([ 7:"#9962FF", 11:"#3EAFBD", 13:"#DE5C93", 17:"#BFA23E",
                    19:"#6DAA42", 23:"#47AFFF", 29:"#B156E8", 31:"#F5814D"])
    }
    
    // Monochrome: strict grayscale ramp
    private static func overlayMonochrome(dark: Bool) -> [Int:Color] {
        dark
        ? palette([ 7:"#EDEDED", 11:"#D0D0D0", 13:"#B4B4B4", 17:"#999999",
                    19:"#7F7F7F", 23:"#666666", 29:"#4D4D4D", 31:"#343434"])
        : palette([ 7:"#111111", 11:"#2E2E2E", 13:"#444444", 17:"#5C5C5C",
                    19:"#767676", 23:"#909090", 29:"#AAAAAA", 31:"#C4C4C4"])
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

//
