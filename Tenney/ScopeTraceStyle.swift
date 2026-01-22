//
//  ScopeTraceStyle.swift
//  Tenney
//
//  Created by OpenAI on 2025-02-14.
//

import SwiftUI

enum ScopeTraceStyle {
    static func strokeMonochrome(
        path: Path,
        in context: inout GraphicsContext,
        theme: ResolvedTenneyTheme,
        coreWidth: CGFloat,
        sheenWidth: CGFloat,
        alpha: Double = 1.0,
        bloom: Bool = true
    ) {
        let inks = theme.scopeInkPair()
        let ink = inks.ink.opacity(alpha)
        let deepInk = inks.deepInk.opacity(alpha)

        let coreGradient = Gradient(colors: [ink, deepInk])
        let sheenGradient = Gradient(colors: [ink.opacity(0.55), .clear])

        let coreStyle = StrokeStyle(lineWidth: coreWidth, lineCap: .round, lineJoin: .round)
        let sheenStyle = StrokeStyle(lineWidth: sheenWidth, lineCap: .round, lineJoin: .round)

        if bloom {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2))
                layer.stroke(
                    path,
                    with: .linearGradient(
                        LinearGradient(gradient: coreGradient, startPoint: .leading, endPoint: .trailing)
                    ),
                    style: StrokeStyle(lineWidth: coreWidth + 2, lineCap: .round, lineJoin: .round)
                )
            }
        }

        context.stroke(
            path,
            with: .linearGradient(
                LinearGradient(gradient: coreGradient, startPoint: .leading, endPoint: .trailing)
            ),
            style: coreStyle
        )

        context.stroke(
            path,
            with: .linearGradient(
                LinearGradient(gradient: sheenGradient, startPoint: .leading, endPoint: .trailing)
            ),
            style: sheenStyle
        )
    }
}
