#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Lightweight hover tracking for Catalyst (no AppKit).
/// Use this to capture pointer location for cursor-centered zoom logic.
struct CatalystHoverTrackingView: UIViewRepresentable {
    var onMove: (CGPoint) -> Void

    func makeUIView(context: Context) -> HoverView {
        let v = HoverView()
        v.onMove = onMove
        return v
    }

    func updateUIView(_ uiView: HoverView, context: Context) {
        uiView.onMove = onMove
    }

    final class HoverView: UIView {
        var onMove: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = true

            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            addGestureRecognizer(hover)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
            let p = g.location(in: self)
            onMove?(p)
        }
    }
}

/// Temporary no-op cursor API for Catalyst so call-sites compile.
/// (Catalyst does not support NSCursor.)
enum CatalystCursorIntent {
    case openHand
    case closedHand
    case pointingHand
}

extension View {
    func catalystCursor(_ intent: CatalystCursorIntent) -> some View { self }
}
#endif
