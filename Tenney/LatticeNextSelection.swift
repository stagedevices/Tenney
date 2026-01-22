//
//  LatticeNextSelection.swift
//  Tenney
//
//  Created by OpenAI Codex on 2025-02-15.
//

import CoreGraphics

struct NextNodeSelection {
    struct Candidate<ID: Equatable> {
        let id: ID
        let stableID: String
        let position: CGPoint
        let isVisible: Bool
        let isGhost: Bool
        let opacityOrPriority: Double?
        let complexity: Double
    }

    static func pickNext<ID: Equatable>(
        from candidates: [Candidate<ID>],
        excluding excludedID: ID,
        referencePoint: CGPoint,
        preferVisibleSubset: Bool,
        priorDirection: CGVector?,
        displayScale: CGFloat
    ) -> ID? {
        var filtered = candidates.filter { $0.id != excludedID }
        guard !filtered.isEmpty else { return nil }

        if preferVisibleSubset {
            let visible = filtered.filter { $0.isVisible }
            if !visible.isEmpty { filtered = visible }
        }

        let scale = max(displayScale, 0.0001)
        let eps = pow(1.0 / Double(scale), 2.0) * 1.5

        func dist2(_ c: Candidate<ID>) -> Double {
            let dx = Double(c.position.x - referencePoint.x)
            let dy = Double(c.position.y - referencePoint.y)
            return dx * dx + dy * dy
        }

        func angleDelta(_ c: Candidate<ID>, _ dir: CGVector) -> Double {
            let vx = Double(c.position.x - referencePoint.x)
            let vy = Double(c.position.y - referencePoint.y)
            let wx = Double(dir.dx)
            let wy = Double(dir.dy)
            let vMag = hypot(vx, vy)
            let wMag = hypot(wx, wy)
            guard vMag > 0.0001, wMag > 0.0001 else { return 0.0 }
            let dot = (vx * wx + vy * wy) / (vMag * wMag)
            let clamped = max(-1.0, min(1.0, dot))
            return acos(clamped)
        }

        func opacityScore(_ c: Candidate<ID>) -> Double {
            c.opacityOrPriority ?? 0.0
        }

        func better(_ a: Candidate<ID>, _ b: Candidate<ID>) -> Bool {
            let d2a = dist2(a)
            let d2b = dist2(b)
            if abs(d2a - d2b) > eps {
                return d2a < d2b
            }

            if a.isVisible != b.isVisible {
                return a.isVisible
            }

            if a.isGhost != b.isGhost {
                return !a.isGhost
            }

            let opA = opacityScore(a)
            let opB = opacityScore(b)
            if abs(opA - opB) > 0.0001 {
                return opA > opB
            }

            if abs(a.complexity - b.complexity) > 0.0001 {
                return a.complexity < b.complexity
            }

            if let dir = priorDirection {
                let angleA = angleDelta(a, dir)
                let angleB = angleDelta(b, dir)
                if abs(angleA - angleB) > 0.0001 {
                    return angleA < angleB
                }
            }

            return a.stableID < b.stableID
        }

        var best = filtered[0]
        for cand in filtered.dropFirst() {
            if better(cand, best) {
                best = cand
            }
        }
        return best.id
    }
}
