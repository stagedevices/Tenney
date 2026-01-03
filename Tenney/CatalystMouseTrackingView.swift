//
//  CatalystMouseTrackingView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/1/26.
//


#if targetEnvironment(macCatalyst)

import SwiftUI
import UIKit

struct CatalystMouseTrackingView: UIViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onScroll: (CGSize, CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove, onScroll: onScroll)
    }

    func makeUIView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.backgroundColor = .clear
        v.isOpaque = false

        let hover = UIHoverGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleHover(_:)))
        hover.delegate = context.coordinator
        v.addGestureRecognizer(hover)

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleScrollPan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        if #available(iOS 13.4, *) {
            pan.allowedScrollTypesMask = [.continuous, .discrete]
        }
        v.addGestureRecognizer(pan)

        context.coordinator.hostView = v
        return v
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        // keep closures up to date
        context.coordinator.onMove = onMove
        context.coordinator.onScroll = onScroll
    }

    final class TrackingView: UIView {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var hostView: UIView?

        var onMove: (CGPoint) -> Void
        var onScroll: (CGSize, CGPoint) -> Void

        init(onMove: @escaping (CGPoint) -> Void,
             onScroll: @escaping (CGSize, CGPoint) -> Void) {
            self.onMove = onMove
            self.onScroll = onScroll
        }

        @objc func handleHover(_ gr: UIHoverGestureRecognizer) {
            guard let v = hostView else { return }
            let loc = gr.location(in: v)
            switch gr.state {
            case .began, .changed:
                onMove(loc)
            default:
                break
            }
        }

        @objc func handleScrollPan(_ gr: UIPanGestureRecognizer) {
            guard let v = hostView else { return }
            // translation is a good “delta” proxy for scroll wheel / trackpad scroll in Catalyst
            let delta = gr.translation(in: v)
            let loc = gr.location(in: v)
            if gr.state == .began || gr.state == .changed {
                onScroll(delta, loc)
                gr.setTranslation(.zero, in: v) // turn it into per-tick delta
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

#elseif os(macOS)

import SwiftUI
import AppKit

struct MacMouseTrackingView: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onScroll: (CGSize, CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        view.onScroll = onScroll
        view.configureTrackingArea()
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = onMove
        nsView.onScroll = onScroll
        nsView.configureTrackingArea()
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onScroll: ((CGSize, CGPoint) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }

        func configureTrackingArea() {
            if let area = trackingArea {
                removeTrackingArea(area)
            }
            let opts: NSTrackingArea.Options = [
                .mouseMoved,
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited
            ]
            trackingArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
            if let area = trackingArea {
                addTrackingArea(area)
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            configureTrackingArea()
        }

        override func mouseEntered(with event: NSEvent) {
            handleMouseMove(event)
        }

        override func mouseMoved(with event: NSEvent) {
            handleMouseMove(event)
        }

        override func scrollWheel(with event: NSEvent) {
            let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
            let loc = convert(event.locationInWindow, from: nil)
            onScroll?(delta, loc)
        }

        private func handleMouseMove(_ event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            onMove?(loc)
        }
    }
}

#endif
