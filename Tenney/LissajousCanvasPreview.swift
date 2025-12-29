//
//  LissajousCanvasPreview.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/28/25.
//


//
//  LissajousCanvasPreview.swift
//  Tenney
//
//  Shared Canvas-based Lissajous preview used by Settings + Builder
//

import SwiftUI
import UIKit

struct LissajousCanvasPreview: View {
    enum IdleMode { case cycle, empty }
    let idleMode: IdleMode

    
    let e3: Color
    let e5: Color

    let samples: Int
    let gridDivs: Int
    let showGrid: Bool
    let showAxes: Bool
    let strokeWidth: Double
    let dotMode: Bool
    let dotSize: Double
    let globalAlpha: Double
    
    init(
        e3: Color,
        e5: Color,
        samples: Int,
        gridDivs: Int,
        showGrid: Bool,
        showAxes: Bool,
        strokeWidth: Double,
        dotMode: Bool,
        dotSize: Double,
        globalAlpha: Double,
        idleMode: IdleMode = .cycle,
        xRatio: (n: Int, d: Int)? = nil,
        yRatio: (n: Int, d: Int)? = nil
    ) {
        self.e3 = e3
        self.e5 = e5
        self.samples = samples
        self.gridDivs = gridDivs
        self.showGrid = showGrid
        self.showAxes = showAxes
        self.strokeWidth = strokeWidth
        self.dotMode = dotMode
        self.dotSize = dotSize
        self.globalAlpha = globalAlpha
        self.idleMode = idleMode
        self.xRatio = xRatio
        self.yRatio = yRatio
    }


    // Optional override (Builder can pass its current X/Y ratio to avoid cycling)
    var xRatio: (n: Int, d: Int)? = nil
    var yRatio: (n: Int, d: Int)? = nil

    fileprivate struct Ratio: Hashable {
        let n: Int
        let d: Int
        var value: Double { Double(n) / Double(d) }
        var label: String { "\(n)/\(d)" }
    }

    // Small, musically-relevant closure set (stable + “readable” shapes)
    private static let pairs: [(Ratio, Ratio)] = [
        (.init(n: 1, d: 1),  .init(n: 1, d: 1)),
        (.init(n: 3, d: 2),  .init(n: 5, d: 4)),
        (.init(n: 4, d: 3),  .init(n: 5, d: 3)),
        (.init(n: 5, d: 4),  .init(n: 6, d: 5)),
        (.init(n: 7, d: 4),  .init(n: 9, d: 8)),
        (.init(n: 5, d: 3),  .init(n: 8, d: 5)),
        (.init(n: 9, d: 8),  .init(n: 15, d: 8)),
        (.init(n: 6, d: 5),  .init(n: 10, d: 9)),
        (.init(n: 8, d: 5),  .init(n: 7, d: 6)),
        (.init(n: 5, d: 4),  .init(n: 9, d: 7)),
        (.init(n: 3, d: 2),  .init(n: 7, d: 4)),
        (.init(n: 4, d: 3),  .init(n: 9, d: 8))
    ]

    private func pickPair(for step: Int) -> (Ratio, Ratio) {
        // Deterministic “random”: LCG over step index
        let x = (Int64(step) * 1103515245 + 12345) & 0x7fffffff
        return Self.pairs[Int(x) % Self.pairs.count]
    }

    var body: some View {
        // No ratios + idleMode.empty => draw only the frame (no curve, no label), no timeline ticks.
        if xRatio == nil, yRatio == nil, idleMode == .empty {
            Canvas { ctx, size in
                drawFrame(ctx: &ctx, size: size, rx: nil, ry: nil, tNow: 0)
            }
        } else {
            TimelineView(.animation) { tl in
                let tNow = tl.date.timeIntervalSinceReferenceDate

                let resolved: (Ratio, Ratio)? = {
                    // If Builder supplies explicit ratios, freeze the pair (no cycling).
                    if let xr = xRatio, let yr = yRatio {
                        return (
                            .init(n: max(1, xr.n), d: max(1, xr.d)),
                            .init(n: max(1, yr.n), d: max(1, yr.d))
                        )
                    } else if let xr = xRatio {
                        let r = Ratio(n: max(1, xr.n), d: max(1, xr.d))
                        return (r, r)
                    } else if let yr = yRatio {
                        let r = Ratio(n: max(1, yr.n), d: max(1, yr.d))
                        return (r, r)

                    } else {
                        guard idleMode == .cycle else { return nil }
                        let step = Int(tNow / 3.8) // swap intervals every ~4s
                        return pickPair(for: step)
                    }
                }()

                let rx = resolved?.0
                let ry = resolved?.1

                Canvas { ctx, size in
                    drawFrame(ctx: &ctx, size: size, rx: rx, ry: ry, tNow: tNow)
                }
            }
        }
    }
    private func drawFrame(ctx: inout GraphicsContext, size: CGSize, rx: Ratio?, ry: Ratio?, tNow: TimeInterval) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        let cx = rect.midX
        let cy = rect.midY
        let r  = min(rect.width, rect.height) * 0.42

        ctx.opacity = max(0, min(1, globalAlpha))

        // Background
        ctx.fill(
            Path(roundedRect: rect, cornerRadius: 12),
            with: .color(Color.secondary.opacity(0.06))
        )

        // Grid
        if showGrid && gridDivs >= 2 {
            var grid = Path()
            for i in 0...gridDivs {
                let t = CGFloat(i) / CGFloat(gridDivs)
                let x = rect.minX + rect.width * t
                let y = rect.minY + rect.height * t
                grid.move(to: CGPoint(x: x, y: rect.minY))
                grid.addLine(to: CGPoint(x: x, y: rect.maxY))
                grid.move(to: CGPoint(x: rect.minX, y: y))
                grid.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            ctx.stroke(grid, with: .color(Color.secondary.opacity(0.14)), lineWidth: 1)
        }

        // Axes
        if showAxes {
            var axes = Path()
            axes.move(to: CGPoint(x: rect.minX, y: cy))
            axes.addLine(to: CGPoint(x: rect.maxX, y: cy))
            axes.move(to: CGPoint(x: cx, y: rect.minY))
            axes.addLine(to: CGPoint(x: cx, y: rect.maxY))
            ctx.stroke(axes, with: .color(Color.secondary.opacity(0.22)), lineWidth: 1)
        }

        // Nothing selected => blank (frame only)
        guard let rx, let ry else { return }

        // Slow phase drift
        let phaseX = tNow * 0.42
        let phaseY = tNow * 0.37 + 0.9

        let fx = rx.value
        let fy = ry.value
        let period = Double(Self.tenneyLCM(rx.d, ry.d))

        let n = max(64, min(8192, samples))
        var curve = Path()

        func point(_ i: Int) -> CGPoint {
            let u = Double(i) / Double(max(1, n - 1))
            let tt = u * period
            let x = sin((2.0 * .pi * fx * tt) + phaseX)
            let y = sin((2.0 * .pi * fy * tt) + phaseY)
            return CGPoint(x: cx + CGFloat(x) * r, y: cy - CGFloat(y) * r)
        }

        if dotMode {
            let d = max(0.8, dotSize)
            let stepDots = max(1, n / 600)
            for i in stride(from: 0, to: n, by: stepDots) {
                let p = point(i)
                let dotRect = CGRect(x: p.x - d/2, y: p.y - d/2, width: d, height: d)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(e5.opacity(0.9)))
            }
        } else {
            for i in 0..<n {
                let p = point(i)
                if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }

            let w = CGFloat(max(0.6, strokeWidth))
            ctx.stroke(
                curve,
                with: .linearGradient(
                    Gradient(colors: [e3.opacity(0.85), e5.opacity(0.95)]),
                    startPoint: rect.origin,
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                lineWidth: w
            )
        }

        // Tiny label
        let label = "\(rx.label) × \(ry.label)"
        var a = AttributedString(label)
        a.font = .system(size: 11, weight: .semibold)
        a.foregroundColor = .secondary
        ctx.draw(Text(a), at: CGPoint(x: rect.minX + 58, y: rect.minY + 14))
    }


    private static func tenneyGCD(_ a: Int, _ b: Int) -> Int {
        var x = abs(a), y = abs(b)
        while y != 0 { let t = x % y; x = y; y = t }
        return max(1, x)
    }

    private static func tenneyLCM(_ a: Int, _ b: Int) -> Int {
        (abs(a) / tenneyGCD(a, b)) * abs(b)
    }
}
