//
//  ThemeSettingsTile.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  ThemeSettingsTile.swift
//  Tenney
//

import SwiftUI

struct ThemeSettingsTile: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SettingsKeys.tenneyThemeID) private var selectedThemeIDRaw: String = LatticeThemeID.classicBO.rawValue

    var body: some View {
        let resolved = TenneyThemeRegistry.resolvedCurrent(
            themeIDRaw: selectedThemeIDRaw,
            scheme: scheme,
            mixBasis: nil,
            mixMode: nil,
            scopeMode: nil
        )

        NavigationLink {
            ThemesCenterView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "paintpalette")
                    Spacer()
                }
                Text("Themes").font(.headline)
                Text(resolved.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)

                ThemeTilePreviewStrip()
                    .environment(\.tenneyTheme, resolved) // no lattice in preview
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        // NOT themed: allow chromatic shadow only
        .tenneyChromaShadow(true, radius: 18, y: 8)
    }
}
