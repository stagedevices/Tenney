//
//  LissajousMetalView.swift
//  Tenney
//
//  Shared MTKView bridge for Lissajous renderer previews.
//

import Foundation
import MetalKit
import SwiftUI

struct LissajousMetalView: UIViewRepresentable {
    let theme: ResolvedTenneyTheme
    let rootHz: Double
    var pair: (RatioResult, RatioResult) = (.init(num: 1, den: 1, octave: 0),
                                            .init(num: 1, den: 1, octave: 0))
    let config: LissajousRenderer.Config

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        v.preferredFramesPerSecond = config.preferredFPS
        context.coordinator.attach(to: v)
        return v
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.preferredFramesPerSecond = config.preferredFPS

        context.coordinator.theme = theme

        let r = context.coordinator.renderer!
        r.setTheme(theme)
        r.setRatios(
            x: .init(num: pair.0.num, den: pair.0.den, octave: pair.0.octave),
            y: .init(num: pair.1.num, den: pair.1.den, octave: pair.1.octave),
            rootHz: rootHz
        )
        r.setConfig { $0 = config }
    }

    func makeCoordinator() -> Coordinator { Coordinator(theme: theme) }
    final class Coordinator: NSObject {
        var renderer: LissajousRenderer?
        var theme: ResolvedTenneyTheme

        init(theme: ResolvedTenneyTheme) {
            self.theme = theme
        }

        func attach(to view: MTKView) {
            renderer = LissajousRenderer(mtkView: view, theme: theme)
            view.delegate = renderer
        }
    }
}
