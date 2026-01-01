//
//  SettingsA4PickerView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  SettingsA4PickerView.swift
//  Tenney
//
//  Re-styled A4 reference picker using the same card language as SettingsThemePickerView.
//  - Presets: 425 / 440 / 442 / 444 + Custom
//  - Writes to @AppStorage(SettingsKeys.staffA4Hz)
//  - Calls onSelectionChanged(hz) when the value changes (used by the wizard for live preview)
//

import SwiftUI

struct SettingsA4PickerView: View {
    @AppStorage(SettingsKeys.staffA4Hz) private var staffA4Hz: Double = 440

    var onSelectionChanged: ((Double) -> Void)? = nil
    
    @Environment(\.tenneyTheme) private var theme

        private var headerGrad: LinearGradient {
            LinearGradient(
                colors: [theme.e3, theme.e5],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

    private enum Preset: String, CaseIterable, Identifiable {
        case _425 = "425", _440 = "440", _442 = "442", _444 = "444", custom = "custom"
        var id: String { rawValue }
        var hz: Double? {
            switch self {
            case ._425: return 425
            case ._440: return 440
            case ._442: return 442
            case ._444: return 444
            case .custom: return nil
            }
        }
        var label: String {
            switch self {
            case ._425: return "425 Hz"
            case ._440: return "440 Hz"
            case ._442: return "442 Hz"
            case ._444: return "444 Hz"
            case .custom: return "Custom"
            }
        }
    }

    @State private var selected: Preset = ._440
    @State private var customHz: Double = 440

    private let cols = [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12, alignment: .top)]

    init(onSelectionChanged: ((Double) -> Void)? = nil) {
        self.onSelectionChanged = onSelectionChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Style: match Theme cards / titles
            HStack(spacing: 10) {
                Image(systemName: "tuningfork")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(headerGrad)
                    .imageScale(.large)
                Text("Equal-Temperament Reference (A4)")
                    .font(.headline)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: cols, spacing: 12) {
                ForEach([Preset._425, ._440, ._442, ._444]) { p in
                    A4Card(label: p.label, isSelected: selected == p)
                        .onTapGesture {
                            withAnimation(.snappy) { select(p) }
                        }
                        .tenneyChromaShadow(true)
                        .accessibilityAddTraits(selected == p ? .isSelected : [])
                }

                // Custom card with inline numeric field
                VStack(alignment: .leading, spacing: 8) {
                    A4Card(label: "Custom", isSelected: selected == .custom)
                        .onTapGesture {
                            withAnimation(.snappy) { select(.custom) }
                        }
                        .tenneyChromaShadow(true)
                    if selected == .custom {
                        HStack {
                            Text("A4")
                            Spacer()
                            TextField("Hz", value: $customHz, format: .number.precision(.fractionLength(1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onChange(of: customHz) { _ in commitCustom() }
                    }
                }
            }

            Text("Used for staff note names and ET meters. Doesn’t affect your Just Intonation root. You can change this anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear { syncFromStored() }
    }

    // MARK: - Logic
    private func syncFromStored() {
        let current = staffA4Hz
        if let match = [425.0, 440.0, 442.0, 444.0].first(where: { abs($0 - current) < 0.01 }) {
            switch match {
            case 425: selected = ._425
            case 440: selected = ._440
            case 442: selected = ._442
            default:  selected = ._444
            }
        } else {
            selected = .custom
            customHz = current
        }
    }

    private func select(_ p: Preset) {
        selected = p
        if let hz = p.hz {
            commit(hz)
        } else {
            // keep customHz; selecting custom doesn’t change staffA4Hz until edited
            customHz = staffA4Hz
        }
    }

    private func commitCustom() {
        let clamped = max(200, min(1000, customHz))
        commit(clamped)
    }

    private func commit(_ hz: Double) {
        staffA4Hz = hz
        postSetting(SettingsKeys.staffA4Hz, hz)
        onSelectionChanged?(hz)
    }
}

private struct A4Card: View {
    let label: String
    let isSelected: Bool

    @Environment(\.tenneyTheme) private var theme

    private var grad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Label in center
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    isSelected
                    ? (theme.isDark ? Color.white : Color.black)
                    : Color.secondary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // Checkmark badge (theme gradient)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AnyShapeStyle(grad))
                    .blendMode(theme.isDark ? .screen : .darken)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                    .symbolEffect(.bounce, value: isSelected)
            }
        }
        .frame(height: 64)
        .padding(10)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                    ? AnyShapeStyle(grad)
                    : AnyShapeStyle(Color.secondary.opacity(0.15)),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
    }
}

