//
//  ThemePreviewComponents.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  ThemePreviewComponents.swift
//  Tenney
//

import SwiftUI

struct ThemeDialPreview: View {
    
    @Environment(\.tenneyTheme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)

            // ticks (arc, gauge-style)
            ForEach(0..<17, id: \.self) { i in
                let t = Double(i) / 16.0
                let ang = -140.0 + (280.0 * t) // sweep an arc instead of full circle

                Capsule()
                    .fill(theme.tunerTicks.opacity(theme.tunerTickOpacity))
                    .frame(width: 2, height: i % 4 == 0 ? 13 : 7)
                    .offset(y: -30)
                    .rotationEffect(.degrees(ang))
            }


            // needle (gauge-style: pivots from center)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(theme.tunerNeedle)
                .frame(width: 4, height: 44)
                .rotationEffect(.degrees(-24), anchor: .bottom)
                .offset(y: -22) // places the pivot at the dial center

            // hub
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(theme.tunerNeedle.opacity(0.9), lineWidth: 1))
                .frame(width: 10, height: 10)
        }
        .frame(width: 86, height: 86)
    }
}

struct ThemeNodeTrioPreview: View {
    @Environment(\.tenneyTheme) private var theme
    private let sigs: [RatioSignature] = [
        .init(e3: 1, e5: 0),                              // “simple”
        .init(e3: 2, e5: 1),                              // “medium”
        .init(e3: 1, e5: 1, extra: [7: 1, 11: 1])         // “mixed primes”
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(sigs.enumerated()), id: \.offset) { _, sig in
                Circle()
                    .fill(theme.nodeColor(signature: sig, basis: theme.mixBasisDefault, mode: theme.mixModeDefault))
                    .frame(width: 18, height: 18)
            }
        }
    }
}

struct ThemeScopeMicroPreview: View {
    @Environment(\.tenneyTheme) private var theme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let midY = h * 0.5

            var p = Path()
            let n = 48
            for i in 0..<n {
                let t = Double(i) / Double(n - 1)
                let x = w * t
                let y = midY + CGFloat(sin(t * 6.0 * .pi) * 0.32) * h
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(p, with: .color(theme.scopeTraceDefault), lineWidth: 1.4)
        }
        .frame(height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ThemeTilePreviewStrip: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ThemeDialPreview()
            VStack(alignment: .leading, spacing: 8) {
                ThemeNodeTrioPreview()
                ThemeScopeMicroPreview()
            }
            Spacer(minLength: 0)
        }
    }
}
