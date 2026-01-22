//
//  HejiStaffSnippetView.swift
//  Tenney
//

import SwiftUI

struct HejiStaffSnippetView: View {
    let layout: HejiStaffLayout
    var staffHeight: CGFloat = 56

    @Environment(\.displayScale) private var displayScale

    private struct Metrics {
        let gap: CGFloat
        let thickness: CGFloat
        let width: CGFloat
        let height: CGFloat
        let noteX: CGFloat
        let accX: CGFloat
        let clefX: CGFloat
        let clefSize: CGFloat
        let headSize: CGFloat
        let accSize: CGFloat
        let topInset: CGFloat
    }

    private func metrics(for height: CGFloat) -> Metrics {
        let gap = height / 4
        let thickness = snap(1 / displayScale)
        return Metrics(
            gap: gap,
            thickness: thickness,
            width: height * 2.5,
            height: height + 12,
            noteX: height * 1.8,
            accX: height * 1.5,
            clefX: height * 0.35,
            clefSize: height * 0.6,
            headSize: height * 0.42,
            accSize: height * 0.38,
            topInset: snap(4 / displayScale)
        )
    }

    var body: some View {
        let m = metrics(for: staffHeight)
        Canvas { ctx, _ in
            let topY = m.topInset
            for i in 0..<5 {
                let y = snap(topY + CGFloat(i) * m.gap)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: m.width, y: y))
                ctx.stroke(line, with: .color(Color.primary.opacity(0.55)), lineWidth: m.thickness)
            }

            let bottomLineY = topY + 4 * m.gap
            let y = snap(bottomLineY - CGFloat(layout.staffStepFromMiddle) * (m.gap / 2))

            let clefGlyph = layout.clef == .treble ? HejiGlyphs.gClef : HejiGlyphs.fClef
            if HejiGlyphs.glyphAvailable(clefGlyph, fontName: "Bravura") {
                let clefText = Text(clefGlyph).font(.custom("Bravura", size: m.clefSize))
                let clefY = snap(layout.clef == .treble ? bottomLineY - 2 * m.gap : bottomLineY - 3 * m.gap)
                ctx.draw(clefText, at: CGPoint(x: m.clefX, y: clefY), anchor: .center)
            }

            for (index, run) in layout.accidentalGlyphs.enumerated() {
                guard HejiGlyphs.glyphAvailable(run.glyph, fontName: run.font.fontName) else { continue }
                let size = m.accSize
                let accText = Text(run.glyph).font(.custom(run.font.fontName, size: size))
                let x = m.accX + run.offset.x + CGFloat(index) * 0
                ctx.draw(accText, at: CGPoint(x: x, y: y + run.offset.y), anchor: .center)
            }

            let headText = Text(layout.noteheadGlyph).font(.custom("Bravura", size: m.headSize))
            ctx.draw(headText, at: CGPoint(x: m.noteX, y: y), anchor: .center)

            drawLedgerLines(step: layout.staffStepFromMiddle, metrics: m, y: y, topY: topY, bottomY: bottomLineY, ctx: &ctx)

            if let approx = layout.approxMarkerGlyph {
                let approxText = Text(approx).font(.system(size: m.accSize * 0.8, weight: .regular))
                ctx.draw(approxText, at: CGPoint(x: m.width - 8, y: topY - 4), anchor: .trailing)
            }
        }
        .frame(width: metrics(for: staffHeight).width, height: metrics(for: staffHeight).height)
    }

    private func drawLedgerLines(step: Int, metrics: Metrics, y: CGFloat, topY: CGFloat, bottomY: CGFloat, ctx: inout GraphicsContext) {
        let absStep = abs(step)
        guard absStep > 4 else { return }
        let count = (absStep - 4 + 1) / 2
        for i in 0..<count {
            let offset = CGFloat(i + 1) * metrics.gap
            let ly = step > 0 ? topY - offset : bottomY + offset
            var p = Path()
            p.move(to: CGPoint(x: metrics.noteX - 10, y: ly))
            p.addLine(to: CGPoint(x: metrics.noteX + 10, y: ly))
            ctx.stroke(p, with: .color(Color.primary.opacity(0.6)), lineWidth: metrics.thickness)
        }
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.toNearestOrEven) / scale
    }
}

