//
//  DistanceDetailSheet.swift
//  Tenney
//
//  Created by Codex.
//

import SwiftUI

struct DistanceDetailSheet: View {
    struct Model: Identifiable {
        let id: UUID = UUID()
        let fromLabel: String
        let toLabel: String
        let metricText: String
        let tint: Color
    }

    let model: Model

    var body: some View {
        VStack(spacing: 16) {
            Text("From \(model.fromLabel) → \(model.toLabel)")
                .font(.headline)
                .multilineTextAlignment(.center)

            GlassChip(text: model.metricText, tint: model.tint)

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}
