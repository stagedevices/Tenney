//
//  TenneyThemeRegistry.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  TenneyThemeRegistry.swift
//  Tenney
//

import SwiftUI
import UIKit

enum TenneyThemeRegistry {
    // Built-in IDs are your existing LatticeThemeIDs (string raw values).
    static var builtinIDs: [String] {
        LatticeThemeID.allCases.map { $0.rawValue }
    }

    static func resolvedCurrent(
        themeIDRaw: String,
        scheme: ColorScheme,
        mixBasis: TenneyMixBasis?,
        mixMode: TenneyMixMode?,
        scopeMode: TenneyScopeColorMode?
    ) -> ResolvedTenneyTheme {

        let mb = mixBasis ?? .complexityWeight
        let mm = mixMode  ?? .blend
        let sm = scopeMode ?? .constant
        
        // Monochrome is user-tinted (AppStorage). Its resolved theme must reflect live changes,
            // so we bypass the cache to avoid stale palettes.
            if themeIDRaw == LatticeThemeID.monochrome.rawValue {
                return resolvedBuiltin(idRaw: themeIDRaw, scheme: scheme, mixBasis: mb, mixMode: mm, scopeMode: sm)
            }

        let key = TenneyThemeCache.ResolvedKey(
            themeIDRaw: themeIDRaw,
            schemeIsDark: (scheme == .dark),
            mixBasis: mb.rawValue,
            mixMode: mm.rawValue,
            scopeMode: sm.rawValue
        )

        if let cached = TenneyThemeCache.shared.getResolved(key) {
            return cached
        }

        let resolved: ResolvedTenneyTheme

        if themeIDRaw.hasPrefix("custom:") {
            resolved = resolvedCustom(idRaw: themeIDRaw, scheme: scheme, mixBasis: mb, mixMode: mm, scopeMode: sm)
        } else {
            resolved = resolvedBuiltin(idRaw: themeIDRaw, scheme: scheme, mixBasis: mb, mixMode: mm, scopeMode: sm)
        }

        TenneyThemeCache.shared.setResolved(resolved, for: key)
        return resolved
    }

    static func resolvedBuiltin(
        idRaw: String,
        scheme: ColorScheme,
        mixBasis: TenneyMixBasis,
        mixMode: TenneyMixMode,
        scopeMode: TenneyScopeColorMode
    ) -> ResolvedTenneyTheme {

        let id = LatticeThemeID(rawValue: idRaw) ?? .classicBO
        let dark = (scheme == .dark)
        let base = ThemeRegistry.theme(id, dark: dark)

        // Extend overlayPrime to full limit set (3..31 themed primes only)
        var pal: [Int: Color] = [:]
        for p in TenneyPrime.themed {
            pal[p] = base.primeTint(p)
        }

        // Fixed neutral for primes outside themed set (stability rule)
        // NOTE: not inserted into palette; handled by fallbackPrime.

        // Museum glass tint: subtle, scheme-aware
        let surfaceTint: Color = {
             let mid = base.primeTint(3)._tenneyInterpolate(to: base.primeTint(5), t: 0.5)
             return dark ? mid.opacity(0.055) : mid.opacity(0.040)
         }()

        // Chroma shadow for exempt controls (shadow only)
        let chromaShadow: Color = {
            let mid = base.primeTint(3)._tenneyInterpolate(to: base.primeTint(5), t: 0.5)
            return dark ? mid.opacity(0.42) : mid.opacity(0.28)
        }()

        let resolved = ResolvedTenneyTheme(
            idRaw: idRaw,
            name: id.displayName,
            scheme: scheme,
            palette: pal,
            surfaceTint: surfaceTint,
            chromaShadow: chromaShadow,
            tunerNeedle: base.primeTint(5),
            tunerTicks: Color.primary.opacity(dark ? 0.78 : 0.70),
            tunerTickOpacity: dark ? 0.75 : 0.68,
            tunerInTuneNeutral: base.primeTint(3),
            tunerInTuneStrength: 0.85,
            scopeTraceDefault: base.primeTint(11).opacity(dark ? 0.92 : 0.88),
            scopeModeDefault: scopeMode,
            mixBasisDefault: mixBasis,
            mixModeDefault: mixMode
        )

        return resolved
    }

    private static func resolvedCustom(
        idRaw: String,
        scheme: ColorScheme,
        mixBasis: TenneyMixBasis,
        mixMode: TenneyMixMode,
        scopeMode: TenneyScopeColorMode
    ) -> ResolvedTenneyTheme {

        let all = TenneyThemePersistence.loadAll()
        let uuidString = idRaw.replacingOccurrences(of: "custom:", with: "")
        let id = UUID(uuidString: uuidString)
        let theme = all.first(where: { $0.id == id })

        // Fallback: if missing, bounce to classicBO
        guard let t = theme else {
            return resolvedBuiltin(idRaw: LatticeThemeID.classicBO.rawValue, scheme: scheme, mixBasis: mixBasis, mixMode: mixMode, scopeMode: scopeMode)
        }

        let dark = (scheme == .dark)

        var pal: [Int: Color] = [:]
        for p in TenneyPrime.themed {
            if let hex = t.paletteHex[p] {
                pal[p] = Color(hex: hex)
            }
        }

        let surfaceTint: Color = dark
            ? Color(hex: t.darkTintHex).opacity(max(0, min(0.18, t.darkStrength)))
            : Color(hex: t.lightTintHex).opacity(max(0, min(0.18, t.lightStrength)))

        let chromaShadow: Color = {
            let a = pal[3] ?? Color.secondary
            let b = pal[5] ?? Color.secondary
            let mid = a._tenneyInterpolate(to: b, t: 0.5)
            return dark ? mid.opacity(0.45) : mid.opacity(0.30)
        }()

        return ResolvedTenneyTheme(
            idRaw: idRaw,
            name: t.name,
            scheme: scheme,
            palette: pal,
            surfaceTint: surfaceTint,
            chromaShadow: chromaShadow,
            tunerNeedle: Color(hex: t.tunerNeedleHex),
            tunerTicks: Color(hex: t.tunerTicksHex),
            tunerTickOpacity: t.tunerTickOpacity,
            tunerInTuneNeutral: Color(hex: t.tunerInTuneNeutralHex),
            tunerInTuneStrength: t.tunerInTuneStrength,
            scopeTraceDefault: Color(hex: t.scopeTraceHex),
            scopeModeDefault: TenneyScopeColorMode(rawValue: t.scopeMode) ?? scopeMode,
            mixBasisDefault: TenneyMixBasis(rawValue: t.mixBasis) ?? mixBasis,
            mixModeDefault: TenneyMixMode(rawValue: t.mixMode) ?? mixMode
        )
    }
}

