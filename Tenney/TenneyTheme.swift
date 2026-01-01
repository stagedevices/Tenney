//
//  TenneyPrime.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  TenneyTheme.swift
//  Tenney
//
//  Themes are “inking on museum glass”: strictly color + subtle tint tokens.
//

import SwiftUI
import UIKit

// MARK: - Prime set (themed)
public enum TenneyPrime {
    public static let themed: [Int] = [3,5,7,11,13,17,19,23,29,31]
    public static let themedSet: Set<Int> = Set(themed)
}

// MARK: - Settings-backed enums
public enum TenneyMixBasis: String, CaseIterable, Identifiable {
    case exponentMagnitude
    case complexityWeight
    public var id: String { rawValue }
}

public enum TenneyMixMode: String, CaseIterable, Identifiable {
    case hardSplit
    case blend
    public var id: String { rawValue }
}

public enum TenneyScopeColorMode: String, CaseIterable, Identifiable {
    case constant
    case followLimit
    case followNearestRatio
    public var id: String { rawValue }
}

// MARK: - Ratio signature (stable key)
public struct RatioSignature: Hashable, Sendable {
    public struct PrimeExp: Hashable, Sendable {
        public let p: Int
        public let e: Int
        public init(_ p: Int, _ e: Int) {
            self.p = p
            self.e = e
        }
    }

    /// Sorted, non-zero exponents for themed primes only.
    public let exps: [PrimeExp]

    public init(exps: [PrimeExp]) {
        self.exps = exps
            .filter { $0.e != 0 && TenneyPrime.themedSet.contains($0.p) }
            .sorted { $0.p < $1.p }
    }

    public init(e3: Int, e5: Int, extra: [Int:Int] = [:]) {
        var arr: [PrimeExp] = [
            .init(3, e3),
            .init(5, e5)
        ]
        for (p,e) in extra {
            guard TenneyPrime.themedSet.contains(p) else { continue }
            arr.append(.init(p,e))
        }
        self.init(exps: arr)
    }

    public var isZero: Bool { exps.isEmpty }

    public var isOnly3and5: Bool {
        for pe in exps {
            if pe.p != 3 && pe.p != 5 { return false }
        }
        return true
    }

    public func exponent(_ p: Int) -> Int {
        exps.first(where: { $0.p == p })?.e ?? 0
    }
}

// MARK: - Resolved theme tokens (runtime)
public struct ResolvedTenneyTheme: Equatable {
     public var isDark: Bool { scheme == .dark }
     public var e3: Color { primeTint(3) }
     public var e5: Color { primeTint(5) }
     init(
         idRaw: String,
         name: String,
         scheme: ColorScheme,
         palette: [Int: Color],
         surfaceTint: Color,
         chromaShadow: Color,
         tunerNeedle: Color,
         tunerTicks: Color,
         tunerTickOpacity: Double,
         tunerInTuneNeutral: Color,
         tunerInTuneStrength: Double,
         scopeTraceDefault: Color,
         scopeModeDefault: TenneyScopeColorMode,
     mixBasisDefault: TenneyMixBasis,
         mixModeDefault: TenneyMixMode
     ) {
         self.idRaw = idRaw
         self.name = name
         self.scheme = scheme
         self.palette = palette
         self.surfaceTint = surfaceTint
         self.chromaShadow = chromaShadow
         self.tunerNeedle = tunerNeedle
         self.tunerTicks = tunerTicks
         self.tunerTickOpacity = tunerTickOpacity
         self.tunerInTuneNeutral = tunerInTuneNeutral
         self.tunerInTuneStrength = tunerInTuneStrength
         self.scopeTraceDefault = scopeTraceDefault
         self.scopeModeDefault = scopeModeDefault
         self.mixBasisDefault = mixBasisDefault
         self.mixModeDefault = mixModeDefault
     }


    public let idRaw: String
    public let name: String
    public let scheme: ColorScheme

    // Prime palette (includes 3/5 + overlays)
    private let palette: [Int: Color]

    // Surface tint (“museum glass”, subtle, scheme-aware)
    public let surfaceTint: Color        // already contains strength via opacity
    public let chromaShadow: Color       // for “NOT themed” controls (shadow only)

    // Tuner tokens (color only; intensity via opacity/strength)
    public let tunerNeedle: Color
    public let tunerTicks: Color
    public let tunerTickOpacity: Double
    public let tunerInTuneNeutral: Color
    public let tunerInTuneStrength: Double

    // Scope tokens
    public let scopeTraceDefault: Color
    public let scopeModeDefault: TenneyScopeColorMode

    // Mixing defaults
    public let mixBasisDefault: TenneyMixBasis
    public let mixModeDefault: TenneyMixMode

    // --- Compatibility surface (minimize call-site churn) ---
    public func primeTint(_ p: Int) -> Color { palette[p] ?? ResolvedTenneyTheme.fallbackPrime }

    /// Preserve existing 3/5 spectral behavior EXACTLY (ported from your current `LatticeTheme.nodeColor`).
    public func nodeColor(e3 e3Exp: Int, e5 e5Exp: Int) -> Color {
        let e3 = primeTint(3)
        let e5 = primeTint(5)

        // Your existing mapping: stable “spectral” feel between 3 & 5.
        // This keeps the look unchanged for existing themes/nodes.
        let a = abs(e3Exp)
        let b = abs(e5Exp)
        let denom = max(1, (a + b))
        let t = Double(b) / Double(denom) // 0 => pure 3, 1 => pure 5
        return e3._tenneyInterpolate(to: e5, t: t)
    }

    /// New: full-prime mixing. If only {3,5} are present, delegates to spectral baseline.
    public func nodeColor(signature sig: RatioSignature, basis: TenneyMixBasis, mode: TenneyMixMode) -> Color {
        if sig.isZero { return ResolvedTenneyTheme.fallbackNode }
        if sig.isOnly3and5 {
            return nodeColor(e3: sig.exponent(3), e5: sig.exponent(5))
        }

        let weights = ResolvedTenneyTheme.weights(for: sig, basis: basis)
        if weights.isEmpty { return ResolvedTenneyTheme.fallbackNode }

        switch mode {
        case .hardSplit:
            // dominant prime; stable tie-breaker: lowest prime wins
            let dom = weights.sorted {
                if $0.w == $1.w { return $0.p < $1.p }
                return $0.w > $1.w
            }.first!.p
            return primeTint(dom)

        case .blend:
            // sRGB blend via UIColor
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0

            for item in weights {
                let c = UIColor(primeTint(item.p))
                let comps = c._tenneyRGBA
                r += comps.r * item.w
                g += comps.g * item.w
                b += comps.b * item.w
                a += comps.a * item.w
            }
            return Color(uiColor: UIColor(red: r, green: g, blue: b, alpha: a))
        }
    }

    public func limitColor(_ p: Int) -> Color { primeTint(p) }

    public func inTuneHighlightColor(activeLimit: Int?) -> Color {
        if let p = activeLimit, TenneyPrime.themedSet.contains(p) { return primeTint(p) }
        return tunerInTuneNeutral.opacity(tunerInTuneStrength)
    }

    // MARK: - Internals
    private struct WeightItem { let p: Int; let w: CGFloat }

    private static func weights(for sig: RatioSignature, basis: TenneyMixBasis) -> [WeightItem] {
        var raw: [(p: Int, w: Double)] = []
        for pe in sig.exps {
            let mag = Double(abs(pe.e))
            if mag == 0 { continue }

            switch basis {
            case .exponentMagnitude:
                raw.append((pe.p, mag))

            case .complexityWeight:
                raw.append((pe.p, mag * log2(Double(pe.p))))
            }
        }

        let sum = raw.reduce(0.0) { $0 + $1.w }
        if sum <= 0 { return [] }

        // L1 normalize, clamp to avoid denorm weirdness
        return raw.map { (p, w) in
            let wn = max(0.0, min(1.0, w / sum))
            return WeightItem(p: p, w: CGFloat(wn))
        }
    }

    fileprivate static let fallbackPrime: Color = Color.secondary.opacity(0.55) // fixed, not theme-dependent
    fileprivate static let fallbackNode:  Color = Color.secondary.opacity(0.18)
}

// MARK: - Environment
private struct TenneyThemeKey: EnvironmentKey {
    static let defaultValue: ResolvedTenneyTheme =
        TenneyThemeRegistry.resolvedBuiltin(
            idRaw: TenneyThemeRegistry.builtinIDs.first ?? LatticeThemeID.classicBO.rawValue,
            scheme: .light,
            mixBasis: .complexityWeight,
            mixMode: .blend,
            scopeMode: .constant
        )
}

public extension EnvironmentValues {
    var tenneyTheme: ResolvedTenneyTheme {
        get { self[TenneyThemeKey.self] }
        set { self[TenneyThemeKey.self] = newValue }
    }
}

// MARK: - View helpers (strictly color/material)
public extension View {
    /// Applies the subtle, scheme-aware museum-glass tint to large surfaces.
    func tenneySurfaceTint() -> some View {
        self.modifier(_TenneySurfaceTint())
    }

    /// For explicitly NOT-themed controls: shadow only (no fill/stroke).
    func tenneyChromaShadow(_ enabled: Bool = true, radius: CGFloat = 18, y: CGFloat = 8) -> some View {
        self.modifier(_TenneyChromaShadow(enabled: enabled, radius: radius, y: y))
    }
}
private struct _TenneySurfaceTint: ViewModifier {
     @Environment(\.tenneyTheme) private var theme
     func body(content: Content) -> some View {
         content.overlay {
             theme.surfaceTint
                 .blendMode(.overlay)
                 .allowsHitTesting(false)
         }
     }
 }

private struct _TenneyChromaShadow: ViewModifier {
    @Environment(\.tenneyTheme) private var theme
    let enabled: Bool
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.shadow(color: theme.chromaShadow, radius: radius, x: 0, y: y)
        } else {
            content
        }
    }
}

// MARK: - Color mixing utilities
fileprivate extension UIColor {
    var _tenneyRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r,g,b,a)
    }
}

 extension Color {
    func _tenneyInterpolate(to other: Color, t: Double) -> Color {
        let a = UIColor(self)
        let b = UIColor(other)

        let ca = a._tenneyRGBA
        let cb = b._tenneyRGBA

        let tt = CGFloat(max(0.0, min(1.0, t)))
        let r = ca.r + (cb.r - ca.r) * tt
        let g = ca.g + (cb.g - ca.g) * tt
        let bl = ca.b + (cb.b - ca.b) * tt
        let al = ca.a + (cb.a - ca.a) * tt

        return Color(uiColor: UIColor(red: r, green: g, blue: bl, alpha: al))
    }
}
