
//
//  GlassUI.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import SwiftUI

// MARK: - GlassCard
struct GlassCard<Content: View>: View {
    private let content: Content
    private let corner: CGFloat

    init(corner: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var background: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            Color.clear
                .background(.ultraThinMaterial)
        }
    }
}

// MARK: - GlassChip (supports BOTH the old call sites and the newer action-based style)
struct GlassChip: View {
    private let title: String
    private let system: String?
    private let active: Bool
    private let color: Color
    private let action: (() -> Void)?

    // ✅ Old style (passive view; meant to be wrapped in an outer Button)
    init(text: String,
         system: String? = nil,
         isOn: Bool = true,
         tint: Color = .accentColor) {
        self.title = text
        self.system = system
        self.active = isOn
        self.color = tint
        self.action = nil
    }

    // ✅ New style (chip is the Button)
    init(title: String,
         active: Bool,
         color: Color = .accentColor,
         action: @escaping () -> Void) {
        self.title = title
        self.system = nil
        self.active = active
        self.color = color
        self.action = action
    }

    var body: some View {
        let label = HStack(spacing: 6) {
            if let system {
                Image(systemName: system)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(active ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
        .background(bg)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(active ? 0.70 : 0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var bg: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(color.opacity(active ? 0.35 : 0.18)), in: Capsule())
        } else {
#if os(macOS) || targetEnvironment(macCatalyst)
            Color.clear
                .background(.thinMaterial)
                .overlay(
                    Capsule()
                        .fill(color.opacity(active ? 0.22 : 0.14))
                )
#else
            Color.clear.background(.thinMaterial)
#endif
        }
    }
}


// MARK: - GlassChevronButton
struct GlassChevronButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: 36, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(isEnabled ? 0.14 : 0.08), lineWidth: 1)
        )
        .opacity(isEnabled ? 1.0 : 0.65)
        .accessibilityLabel(systemName.contains("down") ? "Octave down" : "Octave up")
        .accessibilityHint(isEnabled ? "" : "Unavailable")
    }

    @ViewBuilder
    private var bg: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 10))
        } else {
            Color.clear.background(.ultraThinMaterial)
        }
    }
}
