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
        let vInset: CGFloat
    }

    private struct OctaveAssist {
        let writtenStep: Int
        let shiftOctaves: Int
        let mark: String?
    }

    private func metrics(for height: CGFloat) -> Metrics {
        let gap = height / 4
        let thickness = snap(1 / displayScale)

        let headScale: CGFloat = 1.2
        let headDrawSize = height * 0.42 * headScale
        let vInset = snap(max(6 / displayScale, headDrawSize * 0.75))

        return Metrics(
            gap: gap,
            thickness: thickness,
            width: height * 2.5,
            height: height + vInset * 2,
            noteX: height * 1.8,
            accX: height * 1.5,
            clefX: height * 0.35,
            clefSize: height * 0.6,
            headSize: height * 0.42,
            accSize: height * 0.38,
            vInset: vInset
        )
    }

    private func octaveAssist(clef: HejiStaffLayout.Clef, originalStep: Int) -> OctaveAssist {
        // Display-only octave assist for staff rendering (does not affect pitch identity).
        let trebleMaxStep = HejiNotation.staffStepFromMiddleForRendering(letter: "A", octave: 5, clef: .treble)
        let bassMinStep = HejiNotation.staffStepFromMiddleForRendering(letter: "G", octave: 2, clef: .bass)
        let octaveSteps = HejiNotation.staffStepSpanForOctave(clef: clef)

        switch clef {
        case .treble:
            var writtenStep = originalStep
            var shifts = 0
            while writtenStep > trebleMaxStep && shifts < 3 {
                writtenStep -= octaveSteps
                shifts += 1
            }
            let mark: String?
            switch shifts {
            case 1: mark = "8va"
            case 2: mark = "15ma"
            case 3: mark = "22ma"
            default: mark = nil
            }
            return OctaveAssist(writtenStep: writtenStep, shiftOctaves: shifts, mark: mark)
        case .bass:
            var writtenStep = originalStep
            var shifts = 0
            while writtenStep < bassMinStep && shifts < 3 {
                writtenStep += octaveSteps
                shifts += 1
            }
            let mark: String?
            switch shifts {
            case 1: mark = "8vb"
            case 2: mark = "15mb"
            case 3: mark = "22mb"
            default: mark = nil
            }
            return OctaveAssist(writtenStep: writtenStep, shiftOctaves: -shifts, mark: mark)
        }
    }

    var body: some View {
        let m = metrics(for: staffHeight)
        Canvas { ctx, _ in
            let topY = m.vInset
            for i in 0..<5 {
                let y = snap(topY + CGFloat(i) * m.gap)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: m.width, y: y))
                ctx.stroke(line, with: .color(Color.primary.opacity(0.55)), lineWidth: m.thickness)
            }

            let bottomLineY = topY + 4 * m.gap
            let middleLineY = bottomLineY - 2 * m.gap
            let assist = octaveAssist(clef: layout.clef, originalStep: layout.staffStepFromMiddle)
            let y = snap(middleLineY - CGFloat(assist.writtenStep) * (m.gap / 2))

            let clefGlyph = layout.clef == .treble ? HejiGlyphs.gClef : HejiGlyphs.fClef
            if HejiGlyphs.glyphAvailable(clefGlyph, fontName: "Bravura") {
                let clefText = Text(clefGlyph).font(.custom("Bravura", size: m.clefSize))
                var clefY = snap(layout.clef == .treble ? bottomLineY - 2 * m.gap : bottomLineY - 3 * m.gap)
                if layout.clef == .treble { clefY = snap(clefY + m.gap) }
                ctx.draw(clefText, at: CGPoint(x: m.clefX, y: clefY), anchor: .center)
            }

            for (index, run) in layout.accidentalGlyphs.enumerated() {
                guard HejiGlyphs.glyphAvailable(run.glyph, fontName: run.font.fontName) else { continue }
                let size = m.accSize
                let accText = Text(run.glyph).font(.custom(run.font.fontName, size: size))
                let x = m.accX + run.offset.x + CGFloat(index) * 0
                ctx.draw(accText, at: CGPoint(x: x, y: y + run.offset.y), anchor: .center)
            }
// notehead
            let headText = Text(layout.noteheadGlyph).font(.custom("Bravura", size: m.headSize * 2.1))
            ctx.draw(headText, at: CGPoint(x: m.noteX, y: y), anchor: .center)

            drawLedgerLines(step: assist.writtenStep, metrics: m, y: y, topY: topY, bottomY: bottomLineY, ctx: &ctx)

            if let mark = assist.mark {
                let markText = Text(mark).font(.caption2.weight(.semibold))
                let markY = layout.clef == .treble
                    ? snap(topY - m.gap * 0.75)
                    : snap(bottomLineY + m.gap * 0.75)
                let markX = m.noteX + m.gap * 0.9
                ctx.draw(markText, at: CGPoint(x: markX, y: markY), anchor: .leading)
            }

        }
        .frame(width: m.width, height: m.height)

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

#if DEBUG
struct HejiStaffSnippetView_Previews: PreviewProvider {
    static func previewLayout(letter: String, octave: Int, clef: HejiStaffLayout.Clef) -> HejiStaffLayout {
        let step = HejiNotation.staffStepFromMiddleForRendering(letter: letter, octave: octave, clef: clef)
        return HejiStaffLayout(
            clef: clef,
            staffStepFromMiddle: step,
            noteheadGlyph: HejiGlyphs.noteheadBlack,
            accidentalGlyphs: [],
            ledgerLineCount: 0,
            approxMarkerGlyph: nil
        )
    }

    static var previews: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Treble")
                .font(.caption.weight(.semibold))
            HStack(spacing: 12) {
                HejiStaffSnippetView(layout: previewLayout(letter: "A", octave: 5, clef: .treble))
                HejiStaffSnippetView(layout: previewLayout(letter: "C", octave: 6, clef: .treble))
                HejiStaffSnippetView(layout: previewLayout(letter: "E", octave: 7, clef: .treble))
                HejiStaffSnippetView(layout: previewLayout(letter: "G", octave: 8, clef: .treble))
            }
            Text("Bass")
                .font(.caption.weight(.semibold))
            HStack(spacing: 12) {
                HejiStaffSnippetView(layout: previewLayout(letter: "G", octave: 2, clef: .bass))
                HejiStaffSnippetView(layout: previewLayout(letter: "E", octave: 2, clef: .bass))
                HejiStaffSnippetView(layout: previewLayout(letter: "C", octave: 1, clef: .bass))
                HejiStaffSnippetView(layout: previewLayout(letter: "A", octave: 0, clef: .bass))
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
