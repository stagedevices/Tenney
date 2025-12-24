//
//  SettingsThemePickerView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//

import Foundation
import SwiftUI
//  SettingsThemePickerView.swift
//  Tenney
//
//  Theme picker with Style (System/Light/Dark) override.
//  - Persists via AppStorage(SettingsKeys.latticeThemeID / latticeThemeStyle)
//  - Broadcasts .settingsChanged so Lattice updates live
//  - Uses SF Symbols motion + palette gradients; safe on iOS 17+

import SwiftUI

 enum ThemeStyleChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var icon: String {
        switch self {
        case .system: return "switch.2"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.zzz.fill"
        }
    }
}

struct SettingsThemePickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKeys.latticeThemeID) private var selectedIDRaw: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.latticeThemeStyle) private var styleRaw: String = ThemeStyleChoice.system.rawValue

    // Adaptive grid (1–2 per row depending on size)
    private let cols = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14, alignment: .top)]

    private var effectiveDark: Bool {
        switch ThemeStyleChoice(rawValue: styleRaw) ?? .system {
        case .system: return colorScheme == .dark
        case .light:  return false
        case .dark:   return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                AnimatedPaletteIcon()
                    .frame(width: 26, height: 26)
                Text("Lattice Theme")
                    .font(.headline)
                Spacer()
                CurrentThemeBadge(idRaw: selectedIDRaw)
            }
            .padding(.horizontal, 4)

            // Style override (System / Light / Dark) — card buttons matching ThemeCard
                    StyleCardRow(styleRaw: $styleRaw)

            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(LatticeThemeID.allCases) { id in
                    let isSelected = (id.rawValue == selectedIDRaw)
                    ThemeCard(
                        id: id,
                        // Build preview theme with the *effective* dark flag
                        theme: ThemeRegistry.theme(id, dark: effectiveDark),
                        isSelected: isSelected
                    )
                    .onTapGesture {
                        withAnimation(.snappy) { selectedIDRaw = id.rawValue }
                        NotificationCenter.default.post(
                            name: .settingsChanged,
                            object: nil,
                            userInfo: [SettingsKeys.latticeThemeID: id.rawValue]
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(id.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Animated palette symbol (SF Symbols motion + palette gradient)
private struct AnimatedPaletteIcon: View {
    @State private var pulse = false
    var body: some View {
        let gradient = LinearGradient(
            colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        Image(systemName: "paintpalette.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                    .linearGradient(
                        colors: [.red, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            .font(.system(size: 22, weight: .semibold))
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .regular))
                    .offset(x: 10, y: -10)
                    .opacity(pulse ? 0.0 : 1.0)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever()) { pulse.toggle() }
            }
          //  .symbolEffect(.pulse, options: [.repeating, .speed(0.9)])
    }
}

// MARK: - Current selection badge
private struct CurrentThemeBadge: View {
    let idRaw: String
    var body: some View {
        let id = LatticeThemeID(rawValue: idRaw) ?? .classicBO
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.green, .white)
                .imageScale(.medium)
                .symbolEffect(.bounce, value: idRaw)
            Text(id.displayName)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Theme card
private struct ThemeCard: View {
    let id: LatticeThemeID
    let theme: LatticeTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeSwatch(theme: theme)
                .frame(height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.8)
                                           : Color.secondary.opacity(0.15),
                                lineWidth: isSelected ? 2 : 1)
                        .animation(.snappy, value: isSelected)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.accentColor, .white)
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                            .symbolEffect(.bounce, value: isSelected)
                    }
                }
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.e3, theme.e5)
                    .imageScale(.medium)
                    .frame(width: 18)
                Text(id.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Style row using the same “card” visual language as ThemeCard
private struct StyleCardRow: View {
    @Binding var styleRaw: String
    private let cols = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(ThemeStyleChoice.allCases) { choice in
                StyleCard(choice: choice, isSelected: styleRaw == choice.rawValue)
                    .onTapGesture {
                        withAnimation(.snappy) { styleRaw = choice.rawValue }
                        NotificationCenter.default.post(
                            name: .settingsChanged,
                            object: nil,
                            userInfo: [SettingsKeys.latticeThemeStyle: choice.rawValue]
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(choice.label)
                    .accessibilityAddTraits(styleRaw == choice.rawValue ? .isSelected : [])
            }
        }
    }
}

private struct StyleCard: View {
    let choice: ThemeStyleChoice
    let isSelected: Bool

    private var symbol: some View {
        // palette/gradient + subtle motion; safe on iOS 17+
        let gradient = LinearGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        return Image(systemName: choice.icon)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.gray, .secondary)

            .font(.system(size: 26, weight: .semibold))
            .symbolEffect(.bounce, value: isSelected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.85)
                                               : Color.secondary.opacity(0.15),
                                    lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(
                        symbol
                            .padding(16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    )
                    .frame(height: 64)
                    .animation(.snappy, value: isSelected)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.accentColor, .white)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                        .symbolEffect(.bounce, value: isSelected)
                }
            }

            Text(choice.label)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


// MARK: - Mini swatch: tiny 3×5 sample with theme mapping
private struct ThemeSwatch: View {
    let theme: LatticeTheme

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width/2, y: size.height/2)
            let step: CGFloat = min(size.width, size.height) / 8
            let points: [(Int,Int)] = [
                (-2,0), (-1,0), (0,0), (1,0), (2,0),
                (-2,1), (-1,1), (0,1), (1,1), (2,1),
                (-1,2), (0,2), (1,2)
            ]
            for (e3,e5) in points {
                let x = center.x + CGFloat(e3) * step + CGFloat(e5) * step * 0.5
                let y = center.y + CGFloat(e5) * step * 0.866
                let color = theme.nodeColor(e3: e3, e5: e5)
                let tenney = max(1, abs(e3) + abs(e5) + 1)
                let r = CGFloat(max(6.0, 12.0 / sqrt(Double(tenney))))
                let rect = CGRect(x: x - r, y: y - r, width: 2*r, height: 2*r)
                ctx.fill(Circle().path(in: rect), with: .color(color.opacity(0.9)))
            }
            var axis = Path()
            axis.move(to: CGPoint(x: center.x - 3*step, y: center.y))
            axis.addLine(to: CGPoint(x: center.x + 3*step, y: center.y))
            ctx.stroke(axis, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            axis = Path()
            axis.move(to: center)
            axis.addLine(to: CGPoint(x: center.x + 2.5*step, y: center.y + 2.5*step*0.866))
            ctx.stroke(axis, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
        }
        .drawingGroup()
    }
}
