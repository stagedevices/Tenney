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
    private var isPreview: Bool {
        if case .preview = mode { return true }
        return false
    }

    var body: some View {
        Group {
            switch mode {
            case .preview:
                Button(action: action) { label }
                    .buttonStyle(GlassPressFeedback())
                    .modifier(GlassRoundedRect(corner: corner))

            case .install(let tint), .update(let tint):
                // Keep the existing path: borderedProminent + tint.
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(tint)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.58 : 1)
    }

    private var label: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                symbol
            }

            Text(isBusy ? "Installing…" : title)
                .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, isPreview ? 14 : 0)
        .foregroundStyle(.primary)
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
}
