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

    /// Mac builds render slightly closer without changing stored zoom values or slider ranges.
    private static let macZoomBoost: CGFloat = {
#if os(macOS) || targetEnvironment(macCatalyst)
        return 1.5
#else
        return 1.0
#endif
    }()

    /// Platform-adjusted scale used for all world/screen math.
    /// The raw `scale` remains the stored/user-facing value.
    var appliedScale: CGFloat {
        Self.appliedScale(for: scale)
    }

    private static func appliedScale(for raw: CGFloat) -> CGFloat {
        let boosted = raw * macZoomBoost
        let minS = minScale * macZoomBoost
        let maxS = maxScale * macZoomBoost
        return min(maxS, max(minS, boosted))
    }

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
        let oldRaw = scale
        let newRaw = min(Self.maxScale, max(Self.minScale, oldRaw * clampedFactor))

        let oldScale = appliedScale
        let newScale = Self.appliedScale(for: newRaw)
        if newScale == oldScale { return }

        // Anchor-preserving zoom:
        // Solve for translation' so that world point under `anchor` stays under `anchor` after scaling.
        // screen = world*scale + translation
        // worldUnderAnchor = (anchor - translation)/scale
        let worldX = (anchor.x - translation.x) / oldScale
        let worldY = (anchor.y - translation.y) / oldScale

        translation.x = anchor.x - worldX * newScale
        translation.y = anchor.y - worldY * newScale
        scale = newRaw
    }

    // MARK: - Transforms

    func worldToScreen(_ world: CGPoint) -> CGPoint {
        let s = appliedScale
        return CGPoint(x: world.x * s + translation.x,
                       y: world.y * s + translation.y)
    }

    func screenToWorld(_ screen: CGPoint) -> CGPoint {
        let s = appliedScale
        return CGPoint(x: (screen.x - translation.x) / max(0.0001, s),
                       y: (screen.y - translation.y) / max(0.0001, s))
    }
}
