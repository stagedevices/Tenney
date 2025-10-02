//
//  PrimeChip.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import SwiftUI

struct PrimeChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(TenneyTokens.Font.body(15))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .modifier(PrimeChipGlass())
    }
}

private struct PrimeChipGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: Capsule(style: .continuous))     // Apple API
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(TenneyTokens.Color.glassBorder, lineWidth: 1)
                }
        }
    }
}
