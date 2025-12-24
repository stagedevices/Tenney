//
//  StudioConsoleView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//

//
//  StudioConsoleView.swift
//  Tenney
//

import SwiftUI
import Foundation

private enum A4Choice: String, CaseIterable, Identifiable {
    case _440 = "440"
    case _442 = "442"
    case custom = "custom"
    var id: String { rawValue }
}

private enum NodeSizeChoice: String, CaseIterable, Identifiable {
    case s, m, mplus, l
    var id: String { rawValue }
}

private struct StageToggleChip: View {
    let title: String
    let systemNameOn: String
    let systemNameOff: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? systemNameOn : systemNameOff)
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isOn ? .thinMaterial : .ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

