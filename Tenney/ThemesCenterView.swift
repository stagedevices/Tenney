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

                    Picker("Basis", selection: $mixBasisRaw) {
                        ForEach(TenneyMixBasis.allCases) { b in
                            Text(b == .exponentMagnitude ? "Exponent" : "Complexity").tag(b.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Mode", selection: $mixModeRaw) {
                        ForEach(TenneyMixMode.allCases) { m in
                            Text(m == .blend ? "Blend" : "Hard").tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Scope", selection: $scopeModeRaw) {
                        ForEach(TenneyScopeColorMode.allCases) { m in
                            Text(title(m)).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
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
}
