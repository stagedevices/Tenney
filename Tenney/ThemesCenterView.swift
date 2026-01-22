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
    @State private var advancedExpanded: Bool = false
    @State private var advancedToggleLock: Bool = false
    @AppStorage(SettingsKeys.tenneyMonochromeTintHex) private var monoTintHex: String = "#000000"
    @Environment(\.colorScheme) private var scheme

    @AppStorage(SettingsKeys.tenneyThemeID) private var selectedThemeIDRaw: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixBasis) private var mixBasisRaw: String = TenneyMixBasis.complexityWeight.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixMode) private var mixModeRaw: String = TenneyMixMode.blend.rawValue
    @AppStorage(SettingsKeys.tenneyThemeScopeMode) private var scopeModeRaw: String = TenneyScopeColorMode.constant.rawValue

    private var mixBasis: TenneyMixBasis { TenneyMixBasis(rawValue: mixBasisRaw) ?? .complexityWeight }
    private var mixMode: TenneyMixMode { TenneyMixMode(rawValue: mixModeRaw) ?? .blend }
    private var scopeMode: TenneyScopeColorMode { TenneyScopeColorMode(rawValue: scopeModeRaw) ?? .constant }

    private func toggleAdvanced() {
        guard !advancedToggleLock else { return }
        advancedToggleLock = true

        // Important: avoid DisclosureGroup internal animation race; we control it.
        withAnimation(.snappy(duration: 0.22)) {
            advancedExpanded.toggle()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            advancedToggleLock = false
        }
    }

    var body: some View {
        let ids = TenneyThemeRegistry.builtinIDs

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                        themeTile(idRaw: idRaw, resolved: resolved)

                        // NOT themed: allow chromatic shadow only
                        .tenneyChromaShadow(true, radius: 18, y: 8)
                    }
                }
                advancedControlsDisclosure

                //               NavigationLink {
                    //                   ThemeStudioView()
                    //               } label: {
                    //                  HStack {
                        //                      VStack(alignment: .leading, spacing: 4) {
                            //                          Text("Pro Theme Studio").font(.headline)
                            //                          Text("Create and edit custom themes (local only).").font(.caption).foregroundStyle(.secondary)
                            //                      }
                        //                      Spacer()
                        //                       Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        //                   }
                    //                   .padding(14)
                    //                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    //                }
                //                .tenneyChromaShadow(true, radius: 18, y: 8)
                //

            }
            .padding()
        }
        .navigationTitle("Themes")
    }
    
    @ViewBuilder
    private func themeTile(idRaw: String, resolved: ResolvedTenneyTheme) -> some View {
        let isSelected = (selectedThemeIDRaw == idRaw)
        let isMono = (idRaw == LatticeThemeID.monochrome.rawValue)

        let tileBody = VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(resolved.name).font(.headline).lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(resolved.primeTint(5))
                }
            }

            ThemeTilePreviewStrip()
                .environment(\.tenneyTheme, resolved)
                .id(isMono ? monoTintHex : idRaw)

            if isMono {
                monochromeTintInline // chips live *inside* the monochrome tile
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        if isMono {
            tileBody
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    withAnimation(.snappy) { selectedThemeIDRaw = idRaw }
                }
        } else {
            Button {
                withAnimation(.snappy) { selectedThemeIDRaw = idRaw }
            } label: {
                tileBody
            }
            .buttonStyle(.plain)
        }
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
    
    private var monochromeTintPresets: [(name: String, hex: String)] {
        [
            ("Black",     "#000000"),
            ("Gray",       "#898989"),
            ("Teal",      "#009AFD"),
            ("Amber",     "#FF9400"),
            ("Crystal",   "#38D9FF"),
            ("Amethyst",  "#B06CFF"),
            ("Red",       "#E62E3D"),
            ("Blue",      "#1A4CFF")
        ]
    }

    private var monochromeTintInline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monochrome Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [.init(.adaptive(minimum: 30), spacing: 10)], spacing: 10) {
                ForEach(monochromeTintPresets, id: \.hex) { preset in
                    MonochromeTintChip(
                        name: preset.name,
                        hex: preset.hex,
                        selectedHex: monoTintHex,
                        size: 26
                    ) {
                        withAnimation(.snappy) { monoTintHex = preset.hex }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    
    private var advancedControlsDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {

            Button {
                toggleAdvanced()
            } label: {
                HStack {
                    Text("Advanced").font(.headline)
                    Spacer()
                    Text("Mixing • Mode • Scope")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(advancedExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .animation(.snappy(duration: 0.22), value: advancedExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(advancedToggleLock)

            if advancedExpanded {
                VStack(alignment: .leading, spacing: 14) {

                    // Basis
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

                    // Mode
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

                    // Scope
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
                .padding(.top, 10)
                .transition(.opacity) // simple + safe
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy(duration: 0.22), value: advancedExpanded)
    }


    private struct MonochromeTintChip: View {
        let name: String
        let hex: String
        let selectedHex: String
        var size: CGFloat = 30
        let action: () -> Void

        var body: some View {
            let isOn = (selectedHex.caseInsensitiveCompare(hex) == .orderedSame)

            Button(action: action) {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().strokeBorder(
                            isOn ? Color.primary.opacity(0.30) : Color.clear,
                            lineWidth: 2
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(
                            Color.black.opacity(0.10),
                            lineWidth: 1
                        )
                    )
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: max(10, size * 0.40), weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Monochrome color: \(name)")
            .accessibilityValue(hex)
            .accessibilityAddTraits(isOn ? .isSelected : [])
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
