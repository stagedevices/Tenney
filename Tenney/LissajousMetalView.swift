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
    let theme: LatticeTheme
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
        let r = context.coordinator.renderer!
        r.setTheme(theme)
        r.setRatios(
            x: .init(num: pair.0.num, den: pair.0.den, octave: pair.0.octave),
            y: .init(num: pair.1.num, den: pair.1.den, octave: pair.1.octave),
            rootHz: rootHz
        )
        r.setConfig { $0 = config } // apply full config atomically
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject {
        var renderer: LissajousRenderer?
        func attach(to view: MTKView) {
            renderer = LissajousRenderer(mtkView: view)
            view.delegate = renderer
        }
    }
}
