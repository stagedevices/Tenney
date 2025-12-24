//  LatticeCamera.swift
//  Tenney
//
//  Edited: add world/screen transforms + anchor zoom + scale bounds.
//

import Foundation
import CoreGraphics

/// Minimal camera model used by the lattice for pan/zoom.
/// `scale` is treated as "screen pixels per world unit".
struct LatticeCamera: Equatable, Sendable {
    var translation: CGPoint = .zero
    var scale: CGFloat = 72.0

    // Tuned to match the rest of the lattice code (labels + node sizing).
    static let minScale: CGFloat = 12.0
    static let maxScale: CGFloat = 240.0

    mutating func reset() {
        translation = .zero
        scale = 72.0
    }

    mutating func pan(by delta: CGSize) {
        translation.x += delta.width
        translation.y += delta.height
    }

    /// Zoom by a factor around a screen-space anchor point (pinch center).
    mutating func zoom(by factor: CGFloat, anchor: CGPoint) {
        let clampedFactor = max(0.5, min(2.0, factor))
        let oldScale = scale
        let newScale = min(Self.maxScale, max(Self.minScale, oldScale * clampedFactor))
        if newScale == oldScale { return }

        // Anchor-preserving zoom:
        // Solve for translation' so that world point under `anchor` stays under `anchor` after scaling.
        // screen = world*scale + translation
        // worldUnderAnchor = (anchor - translation)/scale
        let worldX = (anchor.x - translation.x) / oldScale
        let worldY = (anchor.y - translation.y) / oldScale

        scale = newScale
        translation.x = anchor.x - worldX * newScale
        translation.y = anchor.y - worldY * newScale
    }

    // MARK: - Transforms

    func worldToScreen(_ world: CGPoint) -> CGPoint {
        CGPoint(x: world.x * scale + translation.x,
                y: world.y * scale + translation.y)
    }

    func screenToWorld(_ screen: CGPoint) -> CGPoint {
        CGPoint(x: (screen.x - translation.x) / max(0.0001, scale),
                y: (screen.y - translation.y) / max(0.0001, scale))
    }
}

