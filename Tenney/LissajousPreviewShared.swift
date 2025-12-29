//
//  LissajousPreviewShared.swift
//  Tenney
//
//  Shared helpers for Lissajous previews so Settings and Builder stay in sync.
//

import SwiftUI

struct LissajousPreviewFrame<Content: View>: View {
    private let height: CGFloat?
    private let contentPadding: CGFloat
    private let showsFill: Bool
    private let cornerRadius: CGFloat = 12
    private let content: Content

    init(height: CGFloat? = 180,
         contentPadding: CGFloat = 10,
         showsFill: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.height = height
        self.contentPadding = contentPadding
        self.showsFill = showsFill
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        let framed = ZStack {
            if showsFill {
                shape
                    .fill(Color.secondary.opacity(0.06))
            }

            content
                .padding(contentPadding)
        }
        .clipShape(shape)

        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    framed
                }
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                framed
                    .background(.ultraThinMaterial, in: shape)
            }
        }
        .overlay(
            shape.stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .frame(height: height)
    }
}

enum LissajousPreviewConfigBuilder {
    struct EffectiveValues {
        let fps: Int
        let persistenceEnabled: Bool
        let halfLife: Double
        let alpha: Double
        let liveSamples: Int
        let dotSize: Double
    }

    static func effectiveValues(liveSamples: Int,
                                globalAlpha: Double,
                                dotSize: Double,
                                persistenceEnabled: Bool,
                                halfLife: Double,
                                reduceMotion: Bool,
                                reduceTransparency: Bool) -> EffectiveValues {
        let fps = reduceMotion ? 30 : 60
        let persistence = reduceTransparency ? false : persistenceEnabled
        let halfLife = reduceTransparency ? 0.35 : halfLife
        let alpha = reduceTransparency ? min(globalAlpha, 0.6) : globalAlpha
        let liveSamples = reduceMotion ? max(64, Int(Double(liveSamples) * 0.6)) : liveSamples
        let dotSize = max(0.8, dotSize)

        return EffectiveValues(
            fps: fps,
            persistenceEnabled: persistence,
            halfLife: halfLife,
            alpha: alpha,
            liveSamples: liveSamples,
            dotSize: dotSize
        )
    }

    static func makeConfig(liveSamples: Int,
                           samplesPerCurve: Int,
                           gridDivs: Int,
                           showGrid: Bool,
                           showAxes: Bool,
                           ribbonWidth: Double,
                           dotMode: Bool,
                           dotSize: Double,
                           globalAlpha: Double,
                           persistenceEnabled: Bool,
                           halfLife: Double,
                           snapSmall: Bool,
                           maxDen: Int,
                           reduceMotion: Bool,
                           reduceTransparency: Bool) -> (config: LissajousRenderer.Config, effective: EffectiveValues) {
        let effective = effectiveValues(
            liveSamples: liveSamples,
            globalAlpha: globalAlpha,
            dotSize: dotSize,
            persistenceEnabled: persistenceEnabled,
            halfLife: halfLife,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
        let curveSamples = max(1, min(samplesPerCurve, effective.liveSamples))

        let config = LissajousRenderer.Config(
            mode: .live,
            sampleCount: effective.liveSamples,
            preferredFPS: effective.fps,
            samplesPerCurve: curveSamples,
            ribbonWidth: Float(ribbonWidth),
            gridDivs: gridDivs,
            showGrid: showGrid,
            showAxes: showAxes,
            globalAlpha: Float(effective.alpha),
            edgeAA: 1.0,
            favorSmallIntegerClosure: snapSmall,
            maxDenSnap: maxDen,
            dotMode: dotMode,
            dotSize: Float(effective.dotSize),
            persistenceEnabled: effective.persistenceEnabled,
            halfLifeSeconds: Float(effective.halfLife)
        )

        return (config, effective)
    }
}
