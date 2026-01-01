//
//  ThemesCenterView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  ThemesCenterView.swift
//  Tenney
//

import SwiftUI

struct ThemesCenterView: View {
    @Environment(\.colorScheme) private var scheme

    @AppStorage(SettingsKeys.tenneyThemeID) private var selectedThemeIDRaw: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixBasis) private var mixBasisRaw: String = TenneyMixBasis.complexityWeight.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixMode) private var mixModeRaw: String = TenneyMixMode.blend.rawValue
    @AppStorage(SettingsKeys.tenneyThemeScopeMode) private var scopeModeRaw: String = TenneyScopeColorMode.constant.rawValue

    private var mixBasis: TenneyMixBasis { TenneyMixBasis(rawValue: mixBasisRaw) ?? .complexityWeight }
    private var mixMode: TenneyMixMode { TenneyMixMode(rawValue: mixModeRaw) ?? .blend }
    private var scopeMode: TenneyScopeColorMode { TenneyScopeColorMode(rawValue: scopeModeRaw) ?? .constant }

    var body: some View {
        let ids = TenneyThemeRegistry.builtinIDs

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Controls
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mixing").font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Basis").font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: [.init(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                            ForEach(TenneyMixBasis.allCases) { b in
                                let on = (mixBasisRaw == b.rawValue)

                                Button {
                                    withAnimation(.snappy) { mixBasisRaw = b.rawValue }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(basisTitle(b)).font(.headline)
                                            Spacer()
                                            if on { Image(systemName: "checkmark.circle.fill") }
                                        }
                                        Text(basisCopy(b))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(14)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Basis decides *what the mixer measures* when turning a ratio into a color weight.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mode").font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: [.init(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                            ForEach(TenneyMixMode.allCases) { m in
                                let on = (mixModeRaw == m.rawValue)

                                Button {
                                    withAnimation(.snappy) { mixModeRaw = m.rawValue }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(modeTitle(m)).font(.headline)
                                            Spacer()
                                            if on { Image(systemName: "checkmark.circle.fill") }
                                        }
                                        Text(modeCopy(m))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(14)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Mode decides *how* weights are applied: smooth interpolation vs discrete selection.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scope").font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: [.init(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                            ForEach(TenneyScopeColorMode.allCases) { m in
                                let on = (scopeModeRaw == m.rawValue)

                                Button {
                                    withAnimation(.snappy) { scopeModeRaw = m.rawValue }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(title(m)).font(.headline)
                                            Spacer()
                                            if on { Image(systemName: "checkmark.circle.fill") }
                                        }
                                        Text(scopeCopy(m))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(14)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Scope decides what the oscilloscope accent color should follow.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Grid
                LazyVGrid(columns: [.init(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(ids, id: \.self) { idRaw in
                        let resolved = TenneyThemeRegistry.resolvedCurrent(
                            themeIDRaw: idRaw,
                            scheme: scheme,
                            mixBasis: mixBasis,
                            mixMode: mixMode,
                            scopeMode: scopeMode
                        )

                        Button {
                            withAnimation(.snappy) { selectedThemeIDRaw = idRaw }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(resolved.name).font(.headline).lineLimit(1)
                                    Spacer()
                                    if selectedThemeIDRaw == idRaw {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(resolved.primeTint(5))
                                    }
                                }

                                ThemeTilePreviewStrip()
                                    .environment(\.tenneyTheme, resolved) // no lattice in preview
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        // NOT themed: allow chromatic shadow only
                        .tenneyChromaShadow(true, radius: 18, y: 8)
                    }
                }

                NavigationLink {
                    ThemeStudioView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pro Theme Studio").font(.headline)
                            Text("Create and edit custom themes (local only).").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .tenneyChromaShadow(true, radius: 18, y: 8)

            }
            .padding()
        }
        .navigationTitle("Themes")
    }

    private func title(_ m: TenneyScopeColorMode) -> String {
        switch m {
        case .constant: return "Constant"
        case .followLimit: return "Limit"
        case .followNearestRatio: return "Nearest"
        }
    }
    
    private func basisTitle(_ b: TenneyMixBasis) -> String {
        switch b {
        case .exponentMagnitude: return "Exponent"
        case .complexityWeight:  return "Complexity"
        @unknown default:        return "Basis"
        }
    }

    private func basisCopy(_ b: TenneyMixBasis) -> String {
        switch b {
        case .exponentMagnitude:
            return "Weights track the *size of prime exponents* (how far you move in p/q space)."
        case .complexityWeight:
            return "Weights track *ratio complexity* (penalize high-complexity prime structure)."
        @unknown default:
            return "Sets the weighting basis for theme mixing."
        }
    }

    private func modeTitle(_ m: TenneyMixMode) -> String {
        switch m {
        case .blend: return "Blend"
        case .hardSplit:  return "Hard"
        @unknown default: return "Mode"
        }
    }

    private func modeCopy(_ m: TenneyMixMode) -> String {
        switch m {
        case .blend:
            return "Smooth interpolation across weights (continuous, softer transitions)."
        case .hardSplit:
            return "Winner-take-most selection (crisper, more categorical transitions)."
        @unknown default:
            return "Sets the mixing behavior."
        }
    }

    private func scopeCopy(_ m: TenneyScopeColorMode) -> String {
        switch m {
        case .constant:
            return "Always use the theme’s scope color (stable UI)."
        case .followLimit:
            return "Scope follows the *limit* ratio’s color (ties to harmonic target)."
        case .followNearestRatio:
            return "Scope follows the *nearest* ratio’s color (ties to what you’re nearest to)."
        @unknown default:
            return "Controls scope color behavior."
        }
    }

}
