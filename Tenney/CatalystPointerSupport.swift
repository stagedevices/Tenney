#if targetEnvironment(macCatalyst)
import SwiftUI
import AppKit

struct CatalystMouseTrackingView: NSViewRepresentable {
    var onMove: (CGPoint) -> Void
    var onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = onMove
        nsView.onScroll = onScroll
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onScroll: ((CGFloat, CGPoint) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            let opts: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
            addTrackingArea(NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let loc = convert(event.locationInWindow, from: nil)
            onMove?(loc)
        }

        override func scrollWheel(with event: NSEvent) {
            super.scrollWheel(with: event)
            let loc = convert(event.locationInWindow, from: nil)
            onScroll?(event.scrollingDeltaY, loc)
        }
    }
}

struct CatalystCursor: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering { cursor.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    func catalystCursor(_ cursor: NSCursor) -> some View {
        modifier(CatalystCursor(cursor: cursor))
    }
}
#endif
