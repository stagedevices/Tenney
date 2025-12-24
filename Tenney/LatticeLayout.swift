
//
//  LatticeLayout.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation
import CoreGraphics


/// Layout + coordinate mapping for the lattice.
/// World space is an abstract 2D plane; `LatticeCamera` maps world <-> screen.
struct LatticeLayout: Sendable {
    /// World-unit size for one step of the 3-axis.
    /// (Tuned so camera.scale can be treated as "pixels per world unit".)
    private let step: CGFloat = 1.0

    /// 60° basis for (3,5) lattice drawing.
    /// e3 axis: +x
    /// e5 axis: +60° from +x
    private let e5Angle = CGFloat(Double.pi / 3.0)

    /// Convert a plane coord (e3,e5) to world position.
    func position(for c: LatticeCoord) -> CGPoint {
            let e3 = c.e3
            let e5 = c.e5
    
            // Base 3×5 plane (FLIPPED vertically)
            let x0 = CGFloat(e3) * step
            let x1 = CGFloat(e5) * step * cos(e5Angle)
            let y1 = CGFloat(e5) * step * sin(e5Angle)
            return CGPoint(x: x0 + x1, y: -(y1))
        }

    /// Convert an arbitrary monzo (at least including 3/5) into world position.
    /// We only use 3 and 5 for the 2D basis; higher primes project along additional axes
    /// by reusing the same 2D basis with a slight rotation per-prime so overlays don't collapse.
    ///
    /// This is intentionally simple and "visual", not mathematically canonical — it must remain stable
    /// so hit-testing and drawing agree.
    func position(monzo: [Int:Int]) -> CGPoint {
        let e3 = monzo[3] ?? 0
        let e5 = monzo[5] ?? 0

        // Base 3×5 plane
        let x0 = CGFloat(e3) * step
        let y0: CGFloat = 0
        let x1 = CGFloat(e5) * step * cos(e5Angle)
        let y1 = CGFloat(e5) * step * sin(e5Angle)

        var x = x0 + x1
        var y = y0 + y1
        

        // Higher primes: add a small orthogonal-ish projection so overlays are spatially distinct.
        // Deterministic rotation per prime for stable placement.
        for (p, eP) in monzo where p != 2 && p != 3 && p != 5 && eP != 0 {
            // Map prime -> angle offset in radians (stable, not random)
            let a = primeAngle(p)
            let vx = cos(a)
            let vy = sin(a)
            let k: CGFloat = 0.72 * step // overlay axis length per exponent step
            x += CGFloat(eP) * k * vx
            y += CGFloat(eP) * k * vy
        }

        return CGPoint(x: x, y: y)
    }

    /// Generate visible plane nodes around the camera center.
    /// `radius` is in lattice steps (exponent units).
    func planeNodes(
        in viewRect: CGRect,
        camera: LatticeCamera,
        primeLimit: Int,
        radius: Int,
        shift: [Int:Int]
    ) -> [LatticeRenderNode] {
        // Center around pivot in world; the view decides pivot separately (store.pivot).
        // Here we just build a symmetric set around (0,0) plane coords and let LatticeView apply pivot.
        // BUT LatticeView currently expects coords *without* pivot baked into node.coord — it later adds pivot.
        // So: return local coords in [-radius...radius].
        var out: [LatticeRenderNode] = []
        out.reserveCapacity((2*radius+1)*(2*radius+1))

        for e3 in (-radius...radius) {
            for e5 in (-radius...radius) {
                let c = LatticeCoord(e3: e3, e5: e5)

                // Complexity proxy:
                // Tenney height ~ max(num,den) for 3^e3 * 5^e5 (ignoring octaves and other primes).
                let e3s = e3 + (shift[3] ?? 0)
                let e5s = e5 + (shift[5] ?? 0)

                let num = (e3s >= 0 ? ipow(3, e3s) : 1) * (e5s >= 0 ? ipow(5, e5s) : 1)
                let den = (e3s <  0 ? ipow(3, -e3s) : 1) * (e5s <  0 ? ipow(5, -e5s) : 1)
                let th = max(1, max(num, den))

                let pos = position(for: c)
                // Cull nodes far outside view (cheap)
                let sp = camera.worldToScreen(pos)
                if sp.x < viewRect.minX - 120 || sp.x > viewRect.maxX + 120 || sp.y < viewRect.minY - 120 || sp.y > viewRect.maxY + 120 {
                    continue
                }

                out.append(LatticeRenderNode(coord: c, pos: pos, tenneyHeight: th))
            }
        }
        return out
    }

    // MARK: - Helpers

    private func ipow(_ base: Int, _ exp: Int) -> Int {
        guard exp > 0 else { return 1 }
        var result = 1
        var b = base
        var e = exp
        while e > 0 {
            if (e & 1) == 1 { result &*= b }
            e >>= 1
            if e > 0 { b &*= b }
        }
        return max(1, result)
    }

    /// Deterministic "spread" for overlay axes by prime.
    private func primeAngle(_ p: Int) -> CGFloat {
        // 7 -> ~110°, 11 -> ~150°, 13 -> ~-150°, 17 -> ~-110° etc.
        // This keeps overlays readable and avoids stacking.
        let base: CGFloat = CGFloat(Double.pi * 0.62)
        let stride: CGFloat = CGFloat(Double.pi / 11.0)
        let idx = CGFloat((p % 19)) // small cycle
        return base + idx * stride
    }
}
