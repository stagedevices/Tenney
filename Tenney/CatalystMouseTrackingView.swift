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
    let onScroll: (CGFloat, CGPoint) -> Void

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
        var onScroll: (CGFloat, CGPoint) -> Void

        init(onMove: @escaping (CGPoint) -> Void,
             onScroll: @escaping (CGFloat, CGPoint) -> Void) {
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
            // translation.y is a good “delta” proxy for scroll wheel / trackpad scroll in Catalyst
            let dy = gr.translation(in: v).y
            let loc = gr.location(in: v)
            if gr.state == .began || gr.state == .changed {
                onScroll(dy, loc)
                gr.setTranslation(.zero, in: v) // turn it into per-tick delta
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

#endif
