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
    var accentColor: Color {
        switch self {
        case .auto:   return .cyan
        case .strict: return .gray
        case .live:   return .pink
        }
    }

}

enum TunerViewStyle: String, CaseIterable, Identifiable {
    case Gauge
    case chronoDial
    // add back in when ready to test phasescope

  //  case phaseScope   //  NEW
    var id: String { rawValue }

    var title: String {
        switch self {
        case .Gauge:  return "Gauge"
        case .chronoDial:return "Chrono"
            // add back in when ready to test phasescope

    //    case .phaseScope: return "Scope"   // ✅ NEW
        }
    }

    var symbol: String {
        switch self {
        case .Gauge:  return "gauge"
        case .chronoDial:return "circle.dotted"
            // add back in when ready to test phasescope

  //      case .phaseScope: return "scope"
        }
    }
}

enum NeedleHoldMode: String, CaseIterable, Identifiable {
    case snapHold   // “pro”: hold last stable value when confidence is low
    case float      // “soft”: keep moving, but de-emphasize when confidence is low
    var id: String { rawValue }

    var title: String {
        switch self {
        case .snapHold: return "Hold"
        case .float:    return "Float"
        }
    }
}

// MARK: - TunerStore (UI-only, walled off; keeps lock, stage, mode, local limit)
@MainActor
final class TunerStore: ObservableObject {
    @Published var scopePartial: Int = {
        let v = UserDefaults.standard.integer(forKey: SettingsKeys.tunerScopePartial)
        return (v == 0 ? 1 : max(1, min(16, v)))
    }() { didSet { UserDefaults.standard.set(scopePartial, forKey: SettingsKeys.tunerScopePartial) } }

    @Published var scopeReferenceOn: Bool = {
        UserDefaults.standard.object(forKey: SettingsKeys.tunerScopeReferenceOn) as? Bool ?? false
    }() { didSet { UserDefaults.standard.set(scopeReferenceOn, forKey: SettingsKeys.tunerScopeReferenceOn) } }

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

    @Published var viewStyleRaw: String = {
        UserDefaults.standard.string(forKey: SettingsKeys.tunerViewStyle)
        ?? TunerViewStyle.Gauge.rawValue
    }() { didSet { UserDefaults.standard.set(viewStyleRaw, forKey: SettingsKeys.tunerViewStyle) } }

    var viewStyle: TunerViewStyle {
        get { TunerViewStyle(rawValue: viewStyleRaw) ?? .Gauge }
        set { viewStyleRaw = newValue.rawValue }
    }

    @Published var needleHoldRaw: String = {
        UserDefaults.standard.string(forKey: SettingsKeys.tunerNeedleHoldMode)
        ?? NeedleHoldMode.snapHold.rawValue
    }() { didSet { UserDefaults.standard.set(needleHoldRaw, forKey: SettingsKeys.tunerNeedleHoldMode) } }

    var needleHoldMode: NeedleHoldMode {
        get { NeedleHoldMode(rawValue: needleHoldRaw) ?? .snapHold }
        set { needleHoldRaw = newValue.rawValue }
    }

    var mode: TunerUIMode {
        get { TunerUIMode(rawValue: modeRaw) ?? .auto }
        set { modeRaw = newValue.rawValue }
    }
    func toggleLock(currentNearest: RatioResult?) {
        if lockedTarget != nil {
            lockedTarget = nil
        } else {
            lockedTarget = currentNearest
        }
    }

}

// MARK: - Mode strip (glyphs + matched-geometry capsule)
struct TunerModeStrip: View {
    @Environment(\.tenneyTheme) private var theme

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


// MARK: - Chrono Dial # TUNER NO. 1
// Uses cents error + confidence to drive motion/saturation.
// Keep the card strictly rectangular; glass applied at the card, not here.
struct ChronoDial: View {
    @Environment(\.tenneyTheme) private var theme

    let cents: Double  // signed cents (vs nearest, or vs locked target if provided)
    let confidence: Double  // 0–1
    let inTuneWindow: Double // e.g. 5¢
    let stageMode: Bool
    let accent: Color

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
                                        ctx.stroke(p, with: .color(theme.tunerTicks.opacity(op * theme.tunerTickOpacity)),
                                                   lineWidth: (stageMode ? 3.0 : 2.0))

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
                    ctx.fill(ticks, with: .color(theme.tunerTicks.opacity(0.06 + 0.10 * (stageMode ? 1 : 0))))

                }

                // In-tune glow
                if abs(err) <= inTuneWindow {
                    let glow = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2*r, height: 2*r))
                    ctx.stroke(glow, with: .color(accent.opacity(stageMode ? 0.45 : 0.28)),
                               lineWidth: (stageMode ? 10 : 8))

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
                .stroke(theme.tunerNeedle, style: StrokeStyle(lineWidth: stageMode ? 4 : 3, lineCap: .round))
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

// MARK: - GAUGE TUNER DIAL # TUNER NO. 2
struct TunerViewStyleStrip: View {
    @Binding var style: TunerViewStyle
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TunerViewStyle.allCases) { s in
                let on = (s == style)
                ZStack {
                    if on {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .matchedGeometryEffect(id: "hilite", in: ns)
                            .frame(height: 34)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: s.symbol)
                            .symbolRenderingMode(.hierarchical)
                        Text(s.title)
                            .font(.caption2.weight(on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { style = s } }
            }
        }
        .padding(6)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Tuner view")
    }
}

@MainActor
final class NeedleHoldState: ObservableObject {
    private(set) var lastStableCents: Double = 0
    private(set) var lastOutputCents: Double = 0

    func reset(to cents: Double) {
        lastStableCents = cents
        lastOutputCents = cents
    }

    /// Returns (outputCents, isHeld)
    func output(rawCents: Double, confidence: Double, mode: NeedleHoldMode, threshold: Double) -> (Double, Bool) {
        let conf = confidence.isFinite ? max(0, min(1, confidence)) : 0
        let c = rawCents.isFinite ? rawCents : lastOutputCents

        switch mode {
        case .snapHold:
            if conf >= threshold {
                lastStableCents = c
                lastOutputCents = c
                return (c, false)
            } else {
                lastOutputCents = lastStableCents
                return (lastStableCents, true)
            }

        case .float:
            // Still move, but soften when confidence is low (cheap 1-pole smoothing)
            let alpha = 0.12 + 0.68 * conf  // low conf => slow; high conf => fast
            let out = lastOutputCents + (c - lastOutputCents) * alpha
            if conf >= threshold { lastStableCents = out }
            lastOutputCents = out
            return (out, conf < threshold)
        }
    }
}

struct Gauge: View {
    @Environment(\.tenneyTheme) private var theme

    let cents: Double            // signed cents vs current target (locked or auto)
    let confidence: Double       // 0–1
    let inTuneWindow: Double     // 5¢
    let stageMode: Bool
    let mode: TunerUIMode
    let stageAccent: Color
    let showFarHint: Bool
    let heldByConfidence: Bool   // for de-emphasis
    let farLabel: String         // e.g. "Far"

    @State private var breathe = false
    private let dialSweepDeg: CGFloat = 140
    private let needleSweepDeg: CGFloat = 120 // ±60

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let w = size.width
            let h = size.height
            let pivot = CGPoint(x: w * 0.5, y: h * 0.66)
            let rOuter = min(w, h) * 0.46
            let rTickOuter = rOuter * 0.98
            let rTickInnerMajor = rOuter * 0.90
            let rTickInnerMinor = rOuter * 0.935
            let rNeedle = rOuter * 0.92

            ZStack {
                // subtle arc wash (restrained, “ink on glass”)
                Path { p in
                    p.addArc(
                        center: pivot,
                        radius: rOuter,
                        startAngle: .degrees(-90.0 - Double(dialSweepDeg) / 2.0),
                        endAngle:   .degrees(-90.0 + Double(dialSweepDeg) / 2.0),
                        clockwise: false
                    )
                }
                .stroke(theme.tunerTicks.opacity((stageMode ? 0.08 : 0.12) * theme.tunerTickOpacity), lineWidth: stageMode ? 5 : 7)
                .blur(radius: stageMode ? 0 : 0.5)
                .opacity(heldByConfidence ? 0.65 : 1.0)

                // ticks (crisp, instrument-grade)
                Canvas { ctx, _ in
                    let major = [ -50, -25, -10, -5, 0, 5, 10, 25, 50 ]
                    let minor = stageMode ? [] : [ -4, -3, -2, -1, 1, 2, 3, 4 ] // “±1 only inside in-tune region”: we draw inside ±5
                    func theta(_ c: Double) -> CGFloat {
                        // map [-50..50] -> [-70..70] degrees around “up”
                        let clamped = max(-50, min(50, c))
                        let t = CGFloat(clamped / 50.0)
                        return (-CGFloat.pi/2) + (t * (dialSweepDeg/2) * .pi/180)
                    }
                    
                    let majorTickOpacity = theme.tunerTickOpacity * (heldByConfidence ? 0.70 : 1.0)
                    let minorTickOpacity = theme.tunerTickOpacity * (heldByConfidence ? 0.70 : 1.0) * 0.45

                    // major ticks
                    for c in major {
                        let th = theta(Double(c))
                        let isZero = (c == 0)
                        let isEnd  = (abs(c) == 50)
                        let isFive = (abs(c) == 5)
                        let isTen  = (abs(c) == 10)

                        let inner = isEnd ? rOuter * 0.885
                                  : isZero ? rOuter * 0.875
                                  : (isFive || isTen) ? rOuter * 0.905
                                  : rTickInnerMajor

                        let p0 = CGPoint(x: pivot.x + inner * cos(th),     y: pivot.y + inner * sin(th))
                        let p1 = CGPoint(x: pivot.x + rTickOuter * cos(th),y: pivot.y + rTickOuter * sin(th))

                        var path = Path()
                        path.move(to: p0); path.addLine(to: p1)

                        let lw: CGFloat = isZero ? 2.3 : (isEnd ? 2.2 : 2.0)
                        ctx.stroke(path, with: .color(theme.tunerTicks.opacity(majorTickOpacity)),
                                   style: StrokeStyle(lineWidth: lw, lineCap: .butt))
                    }

                    // minor ticks inside ±5¢ (acute, subtle)
                    for c in minor {
                        let th = theta(Double(c))
                        let p0 = CGPoint(x: pivot.x + rTickInnerMinor * cos(th), y: pivot.y + rTickInnerMinor * sin(th))
                        let p1 = CGPoint(x: pivot.x + (rTickOuter * 0.995) * cos(th), y: pivot.y + (rTickOuter * 0.995) * sin(th))
                        var path = Path()
                        path.move(to: p0); path.addLine(to: p1)
                        ctx.stroke(path, with: .color(theme.tunerTicks.opacity(stageMode ? 0 : minorTickOpacity)),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .butt))
                    }
                }
                .opacity(heldByConfidence ? 0.70 : 1.0)

                // minimal labels: -50, 0, +50
                label(text: "−50", atCents: -50, pivot: pivot, r: rOuter * 0.80).opacity(stageMode ? 0.85 : 1.0)
                label(text: "0",   atCents:   0, pivot: pivot, r: rOuter * 0.78).opacity(0.95)
                label(text: "+50", atCents:  50, pivot: pivot, r: rOuter * 0.80).opacity(stageMode ? 0.85 : 1.0)

                // far hint
                if showFarHint {
                    Text(farLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                        .foregroundStyle(.primary)
                        .position(x: w * 0.5, y: h * 0.18)
                        .opacity(0.95)
                }

                // needle
                GaugeNeedle(
                    pivot: pivot,
                    rNeedle: rNeedle,
                    cents: cents,
                    heldByConfidence: heldByConfidence,
                    mode: mode
                )
                .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.90, blendDuration: 0.02),
                           value: cents)

                // lamp dot (in-tune jewel)
                LampDot(
                    pivot: pivot,
                    inTune: abs(cents) <= inTuneWindow,
                    confidence: confidence,
                    stageMode: stageMode,
                    tint: (abs(cents) <= inTuneWindow ? stageAccent : mode.accentColor.opacity(0.35)),
                    breathe: (!stageMode)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                guard !stageMode else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    breathe.toggle()
                }
            }
        }
        .frame(minHeight: 260)
        .accessibilityLabel(Text(String(format: "%+.1f cents", cents.isFinite ? cents : 0)))
    }

    private func label(text: String, atCents c: Double, pivot: CGPoint, r: CGFloat) -> some View {
        let th = thetaForLabel(c)
        let pt = CGPoint(x: pivot.x + r * cos(th), y: pivot.y + r * sin(th))
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .position(pt)
    }

    private func thetaForLabel(_ c: Double) -> CGFloat {
        let clamped = max(-50, min(50, c))
        let t = CGFloat(clamped / 50.0)
        return (-CGFloat.pi/2) + (t * (dialSweepDeg/2) * .pi/180)
    }
}

private struct GaugeNeedle: View {
    @Environment(\.tenneyTheme) private var theme
    let pivot: CGPoint
    let rNeedle: CGFloat
    let cents: Double
    let heldByConfidence: Bool
    let mode: TunerUIMode

    private let needleMaxDeg: CGFloat = 60
    private let overshootMaxDeg: CGFloat = 10 // allows to “push into bezel” up to ±70°

    var body: some View {
        let th = needleTheta(cents)
        let tip = CGPoint(x: pivot.x + rNeedle * cos(th), y: pivot.y + rNeedle * sin(th))

        return ZStack {
            // needle shaft
            Path { p in
                p.move(to: pivot)
                p.addLine(to: tip)
            }
            .stroke(theme.tunerNeedle.opacity(heldByConfidence ? 0.78 : 0.98),
            style: StrokeStyle(lineWidth: 3.0, lineCap: .round))

            // tiny tail (subtle)
            Path { p in
                let back = CGPoint(x: pivot.x - (rNeedle * 0.14) * cos(th),
                                   y: pivot.y - (rNeedle * 0.14) * sin(th))
                p.move(to: pivot)
                p.addLine(to: back)
            }
            .stroke(Color.secondary.opacity(0.35), lineWidth: 1.2)

            // pivot cap ring (ink)
            Circle()
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                .frame(width: 22, height: 22)
                .position(pivot)
        }
        .drawingGroup(opaque: false, colorMode: .linear)
    }

    private func needleTheta(_ c: Double) -> CGFloat {
        // centered at “up”
        let sign: CGFloat = (c < 0 ? -1 : 1)
        let absC = CGFloat(abs(c))

        // base: map ±50¢ -> ±60°
        let base = min(absC, 50) / 50 * needleMaxDeg

        // soft overshoot: for 50..200¢, add up to 10°
        let extra = max(0, min(150, absC - 50))
        let t = extra / 150
        let eased = sqrt(t) // quick initial push, then taper
        let over = overshootMaxDeg * eased

        let deg = sign * (base + over)
        return (-CGFloat.pi/2) + (deg * .pi/180)
    }
}

private struct LampDot: View {
    let pivot: CGPoint
    let inTune: Bool
    let confidence: Double
    let stageMode: Bool
    let tint: Color
    let breathe: Bool

    @State private var pulse = false

    var body: some View {
        let conf = max(0, min(1, confidence.isFinite ? confidence : 0))
        let on = inTune
        let baseOpacity = on ? (0.55 + 0.40 * conf) : (0.10 + 0.12 * conf)
        let glowOpacity = on ? (0.18 + 0.28 * conf) : 0.0

        return ZStack {
            if on {
                Circle()
                    .fill(tint.opacity(glowOpacity))
                    .frame(width: 34, height: 34)
                    .blur(radius: 8)
                    .opacity(stageMode ? 0.90 : 1.0)
            }

            Circle()
                .fill(tint.opacity(baseOpacity))
                .frame(width: on ? 10 : 8, height: on ? 10 : 8)
                .scaleEffect((!stageMode && breathe) ? (pulse ? 1.06 : 0.96) : 1.0)
                .animation((!stageMode && breathe) ? .easeInOut(duration: 2.8).repeatForever(autoreverses: true) : .none,
                           value: pulse)
        }
        .position(pivot)
        .onAppear { pulse.toggle() }
        .accessibilityHidden(true)
    }
}
