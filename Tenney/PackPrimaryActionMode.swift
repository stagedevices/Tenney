//
//  PackPrimaryActionMode.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/20/26.
//


import SwiftUI

enum PackPrimaryActionMode {
    case install(tint: Color?)
    case update(tint: Color?)
    case preview
}

struct PackPrimaryActionButton: View {
    let mode: PackPrimaryActionMode
    let title: String
    let systemImage: String
    let isBusy: Bool
    let isEnabled: Bool
    let animateSymbol: Bool
    let action: () -> Void
    var corner: CGFloat = 12

    private var isDisabled: Bool { (!isEnabled) || isBusy }
    var body: some View {
        Group {
            switch mode {
            case .preview, .install, .update:
                Button(action: action) { label }
                    .buttonStyle(GlassPressFeedback())
                    .modifier(buttonBackground)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.58 : 1)
    }

    private var label: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(labelForeground)
            } else {
                symbol
            }

            if #available(iOS 17.0, *) {
                Text(isBusy ? "Installing…" : title)
                    .font(.callout.weight(.semibold))
                    .contentTransition(.opacity)
            } else {
                Text(isBusy ? "Installing…" : title)
                    .font(.callout.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 14)
        .foregroundStyle(labelForeground)
    }

    @ViewBuilder
    private var symbol: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: systemImage)
                .symbolEffect(.bounce, value: animateSymbol)
        } else {
            Image(systemName: systemImage)
        }
    }

    private var labelForeground: Color {
        switch mode {
        case .install, .update:
            return .white.opacity(0.98)
        case .preview:
            return .primary
        }
    }

    private var buttonBackground: some ViewModifier {
        switch mode {
        case .install(let tint), .update(let tint):
            return GlassTintedCapsule(tint: tint ?? .blue, isEnabled: !isDisabled)
        case .preview:
            return GlassRoundedRect(corner: corner)
        }
    }
}

private struct GlassTintedCapsule: ViewModifier {
    let tint: Color
    let isEnabled: Bool

    private var fillOpacity: Double {
        isEnabled ? 0.32 : 0.18
    }

    func body(content: Content) -> some View {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            content
                .background {
                    shape.fill(tint.opacity(fillOpacity))
                }
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape.stroke(Color.white.opacity(0.25), lineWidth: 0.9)
                        .blendMode(.overlay)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(tint.opacity(fillOpacity)))
                .overlay(
                    shape.stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                )
        }
    }
}
