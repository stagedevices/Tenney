//
//  PhaseScopeTunerView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import SwiftUI
import Combine

struct PhaseScopeTunerView: View {
    @EnvironmentObject private var app: AppModel

    @EnvironmentObject private var model: AppModel
    @ObservedObject var vm: AppModel
    @ObservedObject var store: TunerStore

    @StateObject private var scopeVM = PhaseScopeViewModel()

    // Shared thresholds (use your existing ones if you have them centralized)
    private let inTuneWindow: Double = 5.0

    private var refToggle: some View {
        Toggle(isOn: Binding(
            get: { store.scopeReferenceOn },
            set: { store.scopeReferenceOn = $0 }
        )) {
            Label("Ref", systemImage: "speaker.wave.2.fill")
        }
        .toggleStyle(.button)
        .onChange(of: store.scopeReferenceOn) { on in
            scopeVM.setReferenceEnabled(on)
        }
    }

    private var partialPicker: some View {
        PartialPicker(partial: Binding(
            get: { store.scopePartial },
            set: { store.scopePartial = $0 }
        ))
        .onChange(of: store.scopePartial) { p in
            scopeVM.setPartial(p)
        }
    }
    var body: some View {
        let target = store.lockedTarget ?? parseRatioText(model.display.ratioText)
        let rootHz = model.rootHz
        let conf = model.display.confidence
        let cents: Double = {
        let hz = model.display.hz
        guard hz.isFinite else { return model.display.cents }
        if let locked = store.lockedTarget {
        let tHz = locked.targetHz(rootHz: rootHz)

        return tHz > 0 ? (1200.0 * log2(hz / tHz)) : model.display.cents
        }
        return model.display.cents
        }()

        VStack(spacing: 12) {
            // Controls row (compact)
            ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                refToggle
                                Spacer()
                                partialPicker
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                refToggle
                                partialPicker
                            }
                        }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 2)

            // Scope pane (dominant)
            ZStack {
                ScopeReticle()
                    .opacity(0.55)

                ScopeTrace(
                    points: scopeVM.points,
                    confidence: conf,
                    referenceOn: store.scopeReferenceOn
                )
                .padding(10)

                if !store.scopeReferenceOn {
                    DisabledOverlay(text: "Reference Off")
                }

                // Beat pulse + direction (subtle, not stealing focus)
                BeatPulse(
                    beatRate: scopeVM.beatRateDisplay,
                    directionSign: scopeVM.centsSign,
                    confidence: conf,
                    cap: 12.0
                )
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // HUD readouts (small)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scopeVM.beatHUDText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(scopeVM.directionHUDText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // “In tune” cue uses your existing notion (same window)
                if abs(cents) <= inTuneWindow && conf > 0.25 {
                    InTuneJewel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 10)
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .frame(minHeight: 210, idealHeight: 230, maxHeight: 260) // give height back to controls + rest of card
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                scopeVM.attach(
                    app: vm,
                    store: store
                )
                scopeVM.setReferenceEnabled(store.scopeReferenceOn)
                scopeVM.setPartial(store.scopePartial)
            }
            .onAppear {
                scopeVM.attach(app: app, store: store)
            }
            .onDisappear {
                scopeVM.detach()
            }
            .onChange(of: store.lockedTarget) { _ in
                scopeVM.onLockChanged()
            }

        }
    }
}

// MARK: - Subviews

private struct PartialPicker: View {
    @Binding var partial: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .opacity(0.0) // keeps height stable vs other chips if you swap later

            Picker("Partial", selection: $partial) {
                Text("1×").tag(1)
                Text("2×").tag(2)
                Text("3×").tag(3)
                Text("4×").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
        }
        .accessibilityLabel("Partial")
    }
}


private struct ScopeReticle: View {
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            // border
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 16),
                       with: .color(Color.primary.opacity(0.10)),
                       lineWidth: 1)

            // center lines
            var p = Path()
            p.move(to: CGPoint(x: size.width/2, y: 0))
            p.addLine(to: CGPoint(x: size.width/2, y: size.height))
            p.move(to: CGPoint(x: 0, y: size.height/2))
            p.addLine(to: CGPoint(x: size.width, y: size.height/2))
            ctx.stroke(p, with: .color(Color.primary.opacity(0.08)), lineWidth: 1)

            // subtle grid
            let n = 8
            for i in 1..<n {
                let t = CGFloat(i) / CGFloat(n)
                let x = t * size.width
                let y = t * size.height
                var gp = Path()
                gp.move(to: CGPoint(x: x, y: 0)); gp.addLine(to: CGPoint(x: x, y: size.height))
                gp.move(to: CGPoint(x: 0, y: y)); gp.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(gp, with: .color(Color.primary.opacity(0.03)), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ScopeTrace: View {
    let points: [CGPoint]         // already normalized to [-1,1] mapped to view
    let confidence: Double
    let referenceOn: Bool

    var body: some View {
        GeometryReader { geo in
            let conf = max(0, min(1, confidence.isFinite ? confidence : 0))
            let alpha = referenceOn ? (0.10 + 0.85 * conf) : 0.0
            let blur  = (conf < 0.18 ? 1.6 : 0.0)

            Canvas { ctx, size in
                guard points.count >= 2 else { return }
                var path = Path()

                func map(_ p: CGPoint) -> CGPoint {
                    // points assumed in [-1,1]
                    let x = (p.x * 0.48 + 0.5) * size.width
                    let y = (0.5 - p.y * 0.48) * size.height
                    return CGPoint(x: x, y: y)
                }

                path.move(to: map(points[0]))
                for p in points.dropFirst() { path.addLine(to: map(p)) }

                ctx.stroke(path,
                           with: .color(Color.primary.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            .blur(radius: blur)
            .opacity(referenceOn ? 1.0 : 0.0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DisabledOverlay: View {
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "speaker.slash.fill")
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct BeatPulse: View {
    let beatRate: Double
    let directionSign: Double   // cents sign
    let confidence: Double
    let cap: Double

    @State private var t = false

    var body: some View {
        let conf = max(0, min(1, confidence.isFinite ? confidence : 0))
        let br = max(0, min(cap, beatRate.isFinite ? beatRate : 0))
        let period = (br <= 0.05 ? 2.0 : max(0.12, 1.0 / br)) // pulse speed from beat rate
        let opacity = 0.10 + 0.35 * conf

        HStack(spacing: 8) {
            Image(systemName: directionSign < 0 ? "arrow.down.right" : (directionSign > 0 ? "arrow.up.right" : "minus"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.85))

            Circle()
                .fill(Color.primary.opacity(opacity))
                .frame(width: 8, height: 8)
                .scaleEffect(t ? 1.35 : 0.88)
                .animation(.easeInOut(duration: period).repeatForever(autoreverses: true), value: t)
                .onAppear { t.toggle() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .opacity(conf < 0.10 ? 0.55 : 1.0)
    }
}

private struct InTuneJewel: View {
    var body: some View {
        Circle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().fill(Color.accentColor.opacity(0.45))
                    .blur(radius: 6)
                    .frame(width: 22, height: 22)
            )
            .accessibilityHidden(true)
    }
}
fileprivate func parseRatioText(_ s: String) -> RatioResult? {
    let parts = s.split(separator: "/")
    guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]) else { return nil }
    return RatioResult(num: n, den: d, octave: 0)
    }
