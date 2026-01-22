//
//  PackPrimaryActionMode.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/20/26.
//


import SwiftUI

enum PackPrimaryActionMode: Equatable {
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
            case .install(let tint), .update(let tint):
                Button(action: action) {
                    label
                        .modifier(GlassTintedCapsule(tint: tint ?? .blue, isEnabled: !isDisabled))
                        .contentShape(Capsule())
                }
                .buttonStyle(GlassPressFeedback())
            case .preview:
                Button(action: action) {
                    label
                        .modifier(GlassRoundedRect(corner: corner))
                }
                .buttonStyle(GlassPressFeedback())
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

}

struct GlassTintedCapsule: ViewModifier {
    let tint: Color
    let isEnabled: Bool

    private var fillOpacity: Double {
        isEnabled ? 0.88 : 0.44
    }

    func body(content: Content) -> some View {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            content
                .background {
                    shape.fill(tint.opacity(fillOpacity))
                        .allowsHitTesting(false)
                }
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape.stroke(Color.white.opacity(0.25), lineWidth: 0.9)
                        .blendMode(.overlay)
                        .allowsHitTesting(false)
                )
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .allowsHitTesting(false)
                }
                .background {
                    shape.fill(tint.opacity(fillOpacity))
                        .allowsHitTesting(false)
                }
                .overlay(
                    shape.stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                        .allowsHitTesting(false)
                )
        }
    }
}
