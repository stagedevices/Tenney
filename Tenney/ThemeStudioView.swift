//
//  ThemeStudioView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  ThemeStudioView.swift
//  Tenney
//

import SwiftUI

struct ThemeStudioView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var customs: [TenneyThemePersistence.CustomTheme] = TenneyThemePersistence.loadAll()
    @State private var selectedCustomID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                HStack {
                    Text("Custom Themes").font(.headline)
                    Spacer()
                    Button {
                        createTheme()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }

                ForEach(customs) { t in
                    let idRaw = "custom:\(t.id.uuidString)"
                    let resolved = TenneyThemeRegistry.resolvedCurrent(
                        themeIDRaw: idRaw,
                        scheme: scheme,
                        mixBasis: TenneyMixBasis(rawValue: t.mixBasis) ?? .complexityWeight,
                        mixMode: TenneyMixMode(rawValue: t.mixMode) ?? .blend,
                        scopeMode: TenneyScopeColorMode(rawValue: t.scopeMode) ?? .constant
                    )

                    NavigationLink {
                        ThemeStudioEditor(theme: binding(for: t.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(t.name).font(.headline)
                            ThemeTilePreviewStrip().environment(\.tenneyTheme, resolved)
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .tenneyChromaShadow(true, radius: 18, y: 8)
                }

            }
            .padding()
        }
        .navigationTitle("Theme Studio")
        .onChange(of: customs) { _ in TenneyThemePersistence.saveAll(customs) }
    }

    private func binding(for id: UUID) -> Binding<TenneyThemePersistence.CustomTheme> {
        Binding(
            get: { customs.first(where: { $0.id == id }) ?? customs[0] },
            set: { newValue in
                if let i = customs.firstIndex(where: { $0.id == id }) { customs[i] = newValue }
            }
        )
    }

    private func createTheme() {
        var pal: [Int:String] = [:]
        for p in TenneyPrime.themed { pal[p] = (p == 3 ? "#5C7CFF" : p == 5 ? "#FF6FA3" : "#77E4DD") }

        let t = TenneyThemePersistence.CustomTheme(
            id: UUID(),
            name: "Custom",
            paletteHex: pal,
            mixBasis: TenneyMixBasis.complexityWeight.rawValue,
            mixMode: TenneyMixMode.blend.rawValue,
            lightTintHex: "#FFFFFF",
            lightStrength: 0.04,
            darkTintHex: "#000000",
            darkStrength: 0.06,
            tunerNeedleHex: "#FF6FA3",
            tunerTicksHex: "#FFFFFF",
            tunerTickOpacity: 0.70,
            tunerInTuneNeutralHex: "#5C7CFF",
            tunerInTuneStrength: 0.85,
            scopeTraceHex: "#77E4DD",
            scopeMode: TenneyScopeColorMode.constant.rawValue
        )
        customs.insert(t, at: 0)
    }
}

private struct ThemeStudioEditor: View {
    @Environment(\.colorScheme) private var scheme

    @Binding var theme: TenneyThemePersistence.CustomTheme

    var body: some View {
        let resolved = TenneyThemeRegistry.resolvedCurrent(
            themeIDRaw: "custom:\(theme.id.uuidString)",
            scheme: scheme,
            mixBasis: TenneyMixBasis(rawValue: theme.mixBasis),
            mixMode: TenneyMixMode(rawValue: theme.mixMode),
            scopeMode: TenneyScopeColorMode(rawValue: theme.scopeMode)
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Name", text: $theme.name)
                        .textFieldStyle(.roundedBorder)

                    ThemeTilePreviewStrip()
                        .environment(\.tenneyTheme, resolved)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Palette
                VStack(alignment: .leading, spacing: 10) {
                    Text("Palette (3–31 primes)").font(.headline)

                    ForEach(TenneyPrime.themed, id: \.self) { p in
                        HStack {
                            Text("\(p)").frame(width: 36, alignment: .leading)
                            TextField("#RRGGBB", text: Binding(
                                get: { theme.paletteHex[p] ?? "#777777" },
                                set: { theme.paletteHex[p] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Mixing
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mixing").font(.headline)

                    Picker("Basis", selection: $theme.mixBasis) {
                        Text("Exponent").tag(TenneyMixBasis.exponentMagnitude.rawValue)
                        Text("Complexity").tag(TenneyMixBasis.complexityWeight.rawValue)
                    }
                    .pickerStyle(.segmented)

                    Picker("Mode", selection: $theme.mixMode) {
                        Text("Blend").tag(TenneyMixMode.blend.rawValue)
                        Text("Hard").tag(TenneyMixMode.hardSplit.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Glass tint
                VStack(alignment: .leading, spacing: 10) {
                    Text("Glass Tint").font(.headline)

                    HStack {
                        Text("Light").frame(width: 60, alignment: .leading)
                        TextField("#RRGGBB", text: $theme.lightTintHex).textFieldStyle(.roundedBorder)
                        Slider(value: $theme.lightStrength, in: 0...0.18)
                    }
                    HStack {
                        Text("Dark").frame(width: 60, alignment: .leading)
                        TextField("#RRGGBB", text: $theme.darkTintHex).textFieldStyle(.roundedBorder)
                        Slider(value: $theme.darkStrength, in: 0...0.18)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Tuner
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tuner").font(.headline)

                    HStack {
                        Text("Needle").frame(width: 60, alignment: .leading)
                        TextField("#RRGGBB", text: $theme.tunerNeedleHex).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Ticks").frame(width: 60, alignment: .leading)
                        TextField("#RRGGBB", text: $theme.tunerTicksHex).textFieldStyle(.roundedBorder)
                        Slider(value: $theme.tunerTickOpacity, in: 0.2...1.0)
                    }
                    HStack {
                        Text("In-Tune").frame(width: 60, alignment: .leading)
                        TextField("#RRGGBB", text: $theme.tunerInTuneNeutralHex).textFieldStyle(.roundedBorder)
                        Slider(value: $theme.tunerInTuneStrength, in: 0.2...1.0)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Scope
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scope").font(.headline)

                    HStack {
                        Text("Trace").frame(width: 60, alignment: .leading)
                        TextField("#RRGGBB", text: $theme.scopeTraceHex).textFieldStyle(.roundedBorder)
                    }
                    Picker("Mode", selection: $theme.scopeMode) {
                        Text("Constant").tag(TenneyScopeColorMode.constant.rawValue)
                        Text("Limit").tag(TenneyScopeColorMode.followLimit.rawValue)
                        Text("Nearest").tag(TenneyScopeColorMode.followNearestRatio.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            }
            .padding()
        }
        .navigationTitle(theme.name)
    }
}
