//
//  TenneyDistanceMode.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  TenneyDistancePreviews.swift
//  Tenney
//

import SwiftUI


// MARK: - Environment values for previews / lattice UI

private struct LatticePreviewHideDistanceKey: EnvironmentKey {
    static let defaultValue: Bool = false
}


// MARK: - UI components used by StudioConsoleView

struct TenneyModeTile: View {
    let mode: TenneyDistanceMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode.title)
                    .font(.headline)
          

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TenneyMiniPreview: View {
    /// Simple visual “distance” hint; your lattice can override via environment.
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red.opacity(0.85)).frame(width: 10, height: 10)
            Circle().fill(Color.orange.opacity(0.85)).frame(width: 10, height: 10)
            Circle().fill(Color.yellow.opacity(0.85)).frame(width: 10, height: 10)
            Circle().fill(Color.green.opacity(0.85)).frame(width: 10, height: 10)
            Circle().fill(Color.blue.opacity(0.85)).frame(width: 10, height: 10)
            Circle().fill(Color.purple.opacity(0.85)).frame(width: 10, height: 10)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Tenney distance preview")
    }
}
