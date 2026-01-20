//
//  LatticeMetalView.swift
//  Tenney
//
//  SwiftUI wrapper for MTKView lattice renderer.
//

import SwiftUI
import Metal
import MetalKit
#if targetEnvironment(macCatalyst)
import AppKit
#endif
import Combine

final class LatticeMetalBridge: ObservableObject {
    fileprivate weak var renderer: LatticeMetalRenderer?
    @Published var nodeLookup: [UInt32: LatticeMetalNodeInfo] = [:]

    func attach(renderer: LatticeMetalRenderer) {
        self.renderer = renderer
    }

    func requestPick(_ request: LatticeMetalPickRequest) {
        renderer?.enqueuePick(request)
    }
}

struct LatticeMetalView: UIViewRepresentable {
    typealias UIViewType = MTKView

    let snapshot: LatticeMetalSnapshot
    let pickRequest: LatticeMetalPickRequest?
    let onPick: (LatticeMetalPickResult) -> Void
    @ObservedObject var bridge: LatticeMetalBridge

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isOpaque = false
        view.preferredFramesPerSecond = 120
        view.colorPixelFormat = .bgra8Unorm
        view.isUserInteractionEnabled = false
        configure(view: view, useMetalFX: snapshot.useMetalFX)

        let renderer = LatticeMetalRenderer(view: view)
        renderer?.onPick = onPick
        context.coordinator.renderer = renderer
        if let renderer {
            bridge.attach(renderer: renderer)
            view.delegate = renderer
            renderer.update(snapshot: snapshot)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        configure(view: uiView, useMetalFX: snapshot.useMetalFX)
        renderer.onPick = onPick
        renderer.update(snapshot: snapshot)
        if let pickRequest {
            renderer.enqueuePick(pickRequest)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var renderer: LatticeMetalRenderer?
    }

    private func configure(view: MTKView, useMetalFX: Bool) {
        // MetalFX writes into the drawable; framebufferOnly must be false when enabled.
        view.framebufferOnly = !useMetalFX
        // MetalFX source textures are single-sampled; avoid MSAA resolve mismatches.
        view.sampleCount = 1
    }
}

#if targetEnvironment(macCatalyst)
struct LatticeMetalNSView: NSViewRepresentable {
    typealias NSViewType = MTKView

    let snapshot: LatticeMetalSnapshot
    let pickRequest: LatticeMetalPickRequest?
    let onPick: (LatticeMetalPickResult) -> Void
    @ObservedObject var bridge: LatticeMetalBridge

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isOpaque = false
        view.preferredFramesPerSecond = 120
        view.colorPixelFormat = .bgra8Unorm
        view.isUserInteractionEnabled = false
        configure(view: view, useMetalFX: snapshot.useMetalFX)

        let renderer = LatticeMetalRenderer(view: view)
        renderer?.onPick = onPick
        context.coordinator.renderer = renderer
        if let renderer {
            bridge.attach(renderer: renderer)
            view.delegate = renderer
            renderer.update(snapshot: snapshot)
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        configure(view: nsView, useMetalFX: snapshot.useMetalFX)
        renderer.onPick = onPick
        renderer.update(snapshot: snapshot)
        if let pickRequest {
            renderer.enqueuePick(pickRequest)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var renderer: LatticeMetalRenderer?
    }

    private func configure(view: MTKView, useMetalFX: Bool) {
        // MetalFX writes into the drawable; framebufferOnly must be false when enabled.
        view.framebufferOnly = !useMetalFX
        // MetalFX source textures are single-sampled; avoid MSAA resolve mismatches.
        view.sampleCount = 1
    }
}
#endif
