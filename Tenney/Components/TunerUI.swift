//  TunerUI.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Mode (UI) — distinct from detector.strictness
enum TunerUIMode: String, CaseIterable, Identifiable {
    case auto, strict, live
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .auto:   return "dial.low.fill"     // SFS7: swap to your exact pick at build
        case .strict: return "scope"                // precise/authoritative
        case .live:   return "metronome.fill"       // performance context
        }
    }
    var title: String {
            switch self {
            case .auto:   return "Auto"
            case .strict: return "Strict"
            case .live:   return "Live"
            }
        }
    var palette: some ShapeStyle {
        switch self {
        case .auto:   return AnyShapeStyle(Color.cyan.gradient)
            case .strict: return AnyShapeStyle(Color.gray.opacity(0.95))
            case .live:   return AnyShapeStyle(Color.pink.gradient)
        }
    }
}

// MARK: - TunerStore (UI-only, walled off; keeps lock, stage, mode, local limit)
@MainActor
final class TunerStore: ObservableObject {
    @Published var primeLimit: Int = {
        let v = UserDefaults.standard.integer(forKey: SettingsKeys.tunerPrimeLimit)
        return (v == 0 ? 11 : v)
    }() { didSet { UserDefaults.standard.set(primeLimit, forKey: SettingsKeys.tunerPrimeLimit) } }

    @Published var stageMode: Bool = {
        UserDefaults.standard.object(forKey: SettingsKeys.tunerStageMode) as? Bool ?? false
    }() { didSet { UserDefaults.standard.set(stageMode, forKey: SettingsKeys.tunerStageMode) } }

    @Published var modeRaw: String = {
        (UserDefaults.standard.string(forKey: SettingsKeys.tunerMode) ?? TunerUIMode.auto.rawValue)
    }() { didSet { UserDefaults.standard.set(modeRaw, forKey: SettingsKeys.tunerMode) } }

    @Published var lockedTarget: RatioResult? = nil  // exact JI target when locked

    var mode: TunerUIMode {
        get { TunerUIMode(rawValue: modeRaw) ?? .auto }
        set { modeRaw = newValue.rawValue }
    }
    func toggleLock(currentNearest: RatioResult?) {
        if let t = lockedTarget, currentNearest != nil {
            lockedTarget = nil
        } else {
            lockedTarget = currentNearest
        }
    }
}

// MARK: - Mode strip (glyphs + matched-geometry capsule)
struct TunerModeStrip: View {
    @Binding var mode: TunerUIMode
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 8) {
            ForEach(TunerUIMode.allCases) { m in
                let on = (m == mode)
                ZStack {
                    if on {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .matchedGeometryEffect(id: "hilite", in: ns)
                            .frame(width: 44, height: 34)
                    }
                    VStack(spacing: 2) {
                                            Image(systemName: m.symbol)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(m.palette)
                                                .frame(width: 44, height: 22)
                                                .contentTransition(.symbolEffect(.replace.downUp))
                                                .symbolEffect(.bounce, value: on)
                                            Text(m.title)
                                                .font(.caption2.weight(on ? .semibold : .regular))
                                                .foregroundStyle(on ? .primary : .secondary)
                                                .fixedSize()
                                        }
                                        .accessibilityElement(children: .combine)
                }
                .onTapGesture { withAnimation(.snappy) { mode = m } }
            }
        }
        .padding(6)
        .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - Chrono Dial (strobe bezel + needle w/ thin tail)
// Uses cents error + confidence to drive motion/saturation.
// Keep the card strictly rectangular; glass applied at the card, not here.
struct ChronoDial: View {
    let cents: Double        // signed cents (vs nearest, or vs locked target if provided)
    let confidence: Double   // 0–1
    let inTuneWindow: Double // e.g. 2¢
    let stageMode: Bool

    @State private var tail: [Double] = []
    private let tailLen = 30

    var body: some View {
        ZStack {
            // Bezel strobe (outer)
            Canvas { ctx, size in
                let r = min(size.width, size.height) * 0.48
                let center = CGPoint(x: size.width/2, y: size.height/2)

                // Map cents to angular velocity (rings at slightly different multipliers)
                let err = max(-50, min(50, cents))
                let speed = err / 50.0    // -1...1
                let lockT = max(0, 1 - abs(err)/inTuneWindow) // > 0 inside window

                for ring in 0..<3 {
                    let rr = r - CGFloat(ring) * 10
                    var p = Path()
                    p.addArc(center: center, radius: rr, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                    let alpha = stageMode ? 0.9 : 0.75
                    let sat   = CGFloat(0.25 + 0.75 * confidence)
                    let op    = Double(0.18 + 0.62 * confidence) * (abs(err) <= inTuneWindow ? 0.25 : 1.0)
                    ctx.stroke(p, with: .color(Color.cyan.opacity(op)), lineWidth: (stageMode ? 3.0 : 2.0))
                    // Add subtle “phase dash” effect by overlaying short ticks
                    var ticks = Path()
                    let dashCount = 48 + ring * 8
                    for i in 0..<dashCount {
                        let a = Double(i) / Double(dashCount) * 2 * Double.pi
                        let phase = a + Double(speed) * 0.12 * Double(ring + 1)
                        let x = center.x + rr * CGFloat(cos(phase))
                        let y = center.y + rr * CGFloat(sin(phase))
                        ticks.addEllipse(in: CGRect(x: x-0.8, y: y-0.8, width: 1.6, height: 1.6))
                    }
                    ctx.fill(ticks, with: .color(Color.primary.opacity(0.06 + 0.10 * (stageMode ? 1 : 0))))
                }

                // In-tune glow
                if abs(err) <= inTuneWindow {
                    let glow = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2*r, height: 2*r))
                    let stageAccent = UserDefaults.standard.string(forKey: SettingsKeys.stageAccent) ?? "system"
                     let accent: Color = (stageAccent == "amber" ? .orange : stageAccent == "red" ? .red : .accentColor)
                     ctx.stroke(glow, with: .color(accent.opacity(stageMode ? 0.45 : 0.28)), lineWidth: (stageMode ? 10 : 8))
                }
            }

            // Needle (±50¢ sweep), with thin tail
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let center = CGPoint(x: w/2, y: h/2)
                let radius = min(w,h)*0.42
                let clamped = max(-50, min(50, cents))
                let angle = Angle.degrees( (clamped/50.0) * 60.0 ) // ±60° sweep (lower semicircle)

                // Tail buffer
                Color.clear.onChange(of: cents) {
                    var t = tail
                    t.append(clamped); if t.count > tailLen { t.removeFirst(t.count - tailLen) }
                    tail = t
                }

                // Tail path (thin)
                Path { p in
                    for (i,v) in tail.enumerated() {
                        let a = Angle.degrees( (v/50.0) * 60.0 )
                        let rp = CGPoint(x: center.x + radius * CGFloat(sin(a.radians)),
                                         y: center.y + radius * CGFloat(1 - cos(a.radians)))
                        if i == 0 { p.move(to: rp) } else { p.addLine(to: rp) }
                    }
                }
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)

                // Needle
                Path { p in
                    let tip = CGPoint(x: center.x + radius * CGFloat(sin(angle.radians)),
                                      y: center.y + radius * CGFloat(1 - cos(angle.radians)))
                    p.move(to: center); p.addLine(to: tip)
                }
                .stroke(Color.primary, style: StrokeStyle(lineWidth: stageMode ? 4 : 3, lineCap: .round))
                .animation(.spring(response: 0.22, dampingFraction: 0.82), value: clamped)
            }
        }
        .frame(minHeight: 260)
        .drawingGroup()
        .accessibilityLabel(Text(String(format: "%+.1f cents", cents.isFinite ? cents : 0)))
    }
}

// MARK: - Small helpers
struct BadgeCapsule: View {
    let text: String
    var style: AnyShapeStyle = AnyShapeStyle(Color.secondary.opacity(0.2))
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style, in: Capsule())
    }
}
