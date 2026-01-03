//
//  LatticeTrackpadBridge.swift
//  Tenney
//
//  Cross-platform bridge that delivers pointer, scroll-pan, and zoom events
//  from Mac trackpads (macOS + Mac Catalyst) into SwiftUI.
//

import SwiftUI

#if os(macOS)
import AppKit

struct LatticeTrackpadBridge: NSViewRepresentable {
    let onPointer: (CGPoint) -> Void
    let onScrollPan: (CGSize) -> Void
    let onZoom: (CGFloat) -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.onPointer = onPointer
        view.onScrollPan = onScrollPan
        view.onZoom = onZoom
        view.onHover = onHover
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.configureTrackingArea()
        return view
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.onPointer = onPointer
        nsView.onScrollPan = onScrollPan
        nsView.onZoom = onZoom
        nsView.onHover = onHover
        nsView.configureTrackingArea()
    }

    final class BridgeView: NSView {
        var onPointer: ((CGPoint) -> Void)?
        var onScrollPan: ((CGSize) -> Void)?
        var onZoom: ((CGFloat) -> Void)?
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }

        func configureTrackingArea() {
            if let area = trackingArea { removeTrackingArea(area) }
            let opts: NSTrackingArea.Options = [
                .mouseMoved,
                .mouseEnteredAndExited,
                .inVisibleRect,
                .activeInKeyWindow
            ]
            let area = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            configureTrackingArea()
        }

        override func mouseEntered(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        override func mouseMoved(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let loc = convert(event.locationInWindow, from: nil)
            onPointer?(loc)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func scrollWheel(with event: NSEvent) {
            let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
            onScrollPan?(delta)
        }

        override func magnify(with event: NSEvent) {
            let factor = 1.0 + event.magnification
            onZoom?(factor)
        }
    }
}

#elseif targetEnvironment(macCatalyst)
import UIKit

struct LatticeTrackpadBridge: UIViewRepresentable {
    let onPointer: (CGPoint) -> Void
    let onScrollPan: (CGSize) -> Void
    let onZoom: (CGFloat) -> Void
    let onHover: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPointer: onPointer, onScrollPan: onScrollPan, onZoom: onZoom, onHover: onHover)
    }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.backgroundColor = .clear
        view.isOpaque = false

        let hover = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHover(_:)))
        hover.delegate = context.coordinator
        view.addGestureRecognizer(hover)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScrollPan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        if #available(iOS 13.4, *) {
            pan.allowedScrollTypesMask = [.continuous, .discrete]
        }
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        context.coordinator.hostView = view
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        context.coordinator.onPointer = onPointer
        context.coordinator.onScrollPan = onScrollPan
        context.coordinator.onZoom = onZoom
        context.coordinator.onHover = onHover
    }

    final class BridgeView: UIView {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var hostView: UIView?

        var onPointer: (CGPoint) -> Void
        var onScrollPan: (CGSize) -> Void
        var onZoom: (CGFloat) -> Void
        var onHover: (Bool) -> Void

        private var lastScale: CGFloat = 1

        init(onPointer: @escaping (CGPoint) -> Void,
             onScrollPan: @escaping (CGSize) -> Void,
             onZoom: @escaping (CGFloat) -> Void,
             onHover: @escaping (Bool) -> Void) {
            self.onPointer = onPointer
            self.onScrollPan = onScrollPan
            self.onZoom = onZoom
            self.onHover = onHover
        }

        @objc func handleHover(_ gr: UIHoverGestureRecognizer) {
            guard let v = hostView else { return }
            let loc = gr.location(in: v)
            switch gr.state {
            case .began, .changed:
                onHover(true)
                onPointer(loc)
            default:
                onHover(false)
            }
        }

        @objc func handleScrollPan(_ gr: UIPanGestureRecognizer) {
            guard let v = hostView else { return }
            let translation = gr.translation(in: v)
            let delta = CGSize(width: translation.x, height: translation.y)
            if gr.state == .began || gr.state == .changed {
                onScrollPan(delta)
                gr.setTranslation(.zero, in: v)
            }
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            let scale = gr.scale
            let factor = scale / max(0.0001, lastScale)
            if gr.state == .began || gr.state == .changed {
                onZoom(factor)
                lastScale = scale
            } else {
                lastScale = 1
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#else
// No-op fallback for platforms that do not use the bridge.
struct LatticeTrackpadBridge: View {
    var onPointer: (CGPoint) -> Void = { _ in }
    var onScrollPan: (CGSize) -> Void = { _ in }
    var onZoom: (CGFloat) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }

    var body: some View { Color.clear }
}
#endif
