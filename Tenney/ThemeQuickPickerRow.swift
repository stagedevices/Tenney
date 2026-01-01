//
//  ThemeQuickPickerRow.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  ThemeQuickPickerRow.swift
//  Tenney
//

import SwiftUI

struct ThemeQuickPickerRow: View {
    @AppStorage(SettingsKeys.tenneyThemeID)
    private var selectedThemeIDRaw: String = LatticeThemeID.classicBO.rawValue

    var body: some View {
        let ids = TenneyThemeRegistry.builtinIDs
        let idx = ids.firstIndex(of: selectedThemeIDRaw) ?? 0

        // show current + neighbors (wrap)
        let windowCount = min(5, max(3, ids.count))
        let start = max(0, idx - (windowCount / 2))
        let end = min(ids.count, start + windowCount)
        let slice = Array(ids[start..<end])

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Theme").font(.headline)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(slice, id: \.self) { idRaw in
                        ThemeQuickChip(idRaw: idRaw, selectedIDRaw: $selectedThemeIDRaw)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ThemeQuickChip: View {
    @Environment(\.colorScheme) private var scheme

    let idRaw: String
    @Binding var selectedIDRaw: String

    var body: some View {
        let isOn = (selectedIDRaw == idRaw)
        let resolved = TenneyThemeRegistry.resolvedCurrent(
            themeIDRaw: idRaw,
            scheme: scheme,
            mixBasis: nil,
            mixMode: nil,
            scopeMode: nil
        )

        Button {
            withAnimation(.snappy) { selectedIDRaw = idRaw }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(resolved.primeTint(3))
                    .frame(width: 10, height: 10)
                Text(resolved.name)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
        }
        // NOT themed: allow chromatic shadow only
        .tenneyChromaShadow(true, radius: 14, y: 6)
    }
}
