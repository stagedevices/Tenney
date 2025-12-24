//
//  LissajousCard.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/24/25.
//


import SwiftUI
import MetalKit

struct LissajousCard: View {
    @Environment(\.tenneyTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let rootHz: Double
    let chosenRatios: [RatioRef]

    // persisted prefs
    @AppStorage("Lissa.samples") private var samplesPerCurve: Int = 4096
    @AppStorage("Lissa.gridDivs") private var gridDivs: Int = 8
    @AppStorage("Lissa.showGrid") private var showGrid: Bool = true
    @AppStorage("Lissa.showAxes") private var showAxes: Bool = true
    @AppStorage("Lissa.strokeWidth") private var strokeWidth: Double = 1.5
    @AppStorage("Lissa.dotMode") private var dotMode: Bool = false
    @AppStorage("Lissa.dotSize") private var dotSize: Double = 2.0
    @AppStorage("Lissa.persistence") private var persistenceEnabled: Bool = true
    @AppStorage("Lissa.halfLife") private var halfLife: Double = 0.6
    @AppStorage("Lissa.snap") private var snapSmall: Bool = true
    @AppStorage("Lissa.maxDen") private var maxDen: Int = 24

    @State private var assignXY: (RatioRef, RatioRef)?
    @State private var showSettings = false

    // helpers
    private func asResult(_ r: RatioRef) -> RatioResult { .init(num: r.p, den: r.q, octave: r.octave) }
    private func ratioString(_ r: RatioRef) -> String {
        func gcd(_ a: Int,_ b: Int)->Int{ var x=abs(a),y=abs(b); while y != 0 { let t=x%y; x=y; y=t }; return max(1,x) }
        var num = r.p, den = r.q
        while Double(num)/Double(den) >= 2.0 { den &*= 2 }
        while Double(num)/Double(den) < 1.0 { num &*= 2 }
        let g = gcd(num, den); return "\(num/g)/\(den/g)"
    }
    private func autoAssignXY(from items: [RatioRef]) -> (RatioRef, RatioRef) {
        if items.count <= 1 { let a = items.first ?? .init(p: 1, q: 1, octave: 0, monzo: [:]); return (a,a) }
        var best:(Double,Int,Int)?=nil
        func freq(_ r: RatioRef)->Double{
            var n=r.p,d=r.q; while Double(n)/Double(d) >= 2 { d&*=2 }; while Double(n)/Double(d)<1 { n&*=2 }
            let base = Double(n)/Double(d); return rootHz * pow(2.0, Double(r.octave)) * base
        }
        for i in 0..<(items.count-1) {
            for j in (i+1)..<items.count {
                let r = freq(items[i])/freq(items[j])
                let score = 1.0 / abs(log2(r) + 1e-6) // prefer near-integer-ish
                if best == nil || score > best!.0 { best = (score,i,j) }
            }
        }
        let i = best!.1, j = best!.2
        return (items[i], items[j])
    }

    var body: some View {
        ZStack {
            // Card chrome (HIG "liquid glass")
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reduceTransparency ? Color(.secondarySystemBackground)
                                         : .gray)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.08), radius: 12, y: 6)

            LissajousMetalView(
                theme: theme,
                rootHz: rootHz,
                pair: {
                    if let p = assignXY { return (asResult(p.0), asResult(p.1)) }
                    if chosenRatios.isEmpty {
                        let a = RatioRef(p: 1, q: 1, octave: 0, monzo: [:]); return (asResult(a), asResult(a))
                    }
                    let a = autoAssignXY(from: chosenRatios); return (asResult(a.0), asResult(a.1))
                }(),
                config: LissajousRenderer.Config(
                    samplesPerCurve: samplesPerCurve,
                    strokeWidth: Float(strokeWidth),
                    gridDivs: gridDivs,
                    showGrid: showGrid,
                    showAxes: showAxes,
                    globalAlpha: 1.0,
                    favorSmallIntegerClosure: snapSmall,
                    maxDenSnap: maxDen,
                    dotMode: dotMode,
                    dotSize: Float(dotSize),
                    persistenceEnabled: reduceMotion ? false : persistenceEnabled,
                    halfLifeSeconds: Float(halfLife)
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(axesOverlay)
            .overlay(gearButton, alignment: .topTrailing)
        }
        .onChange(of: chosenRatios) { _ in assignXY = autoAssignXY(from: chosenRatios) }
        .onAppear { assignXY = autoAssignXY(from: chosenRatios) }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .accessibilityLabel("Lissajous Oscilloscope")
    }

    // Axis labels
    private var axesOverlay: some View {
        VStack {
            HStack {
                Text(assignXY.map { "X  \(ratioString($0.0))" } ?? "X —")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.labelSecondary)
                Spacer()
            }.padding([.leading, .top], 10)
            Spacer()
            HStack {
                Text(assignXY.map { "Y  \(ratioString($0.1))" } ?? "Y —")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.labelSecondary)
                Spacer()
            }.padding([.leading, .bottom], 10)
        }.allowsHitTesting(false)
    }

    // Settings
    private var gearButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(10)
        .accessibilityLabel("Lissajous settings")
    }

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Display")) {
                    Toggle("Grid", isOn: $showGrid)
                    Toggle("Axes", isOn: $showAxes)
                    Stepper("Grid divisions: \(gridDivs)", value: $gridDivs, in: 2...16)
                    HStack {
                        Text("Stroke")
                        Slider(value: $strokeWidth, in: 0.5...3.0)
                        Text("\(strokeWidth, specifier: "%.1f")")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Toggle("Dot-only mode", isOn: $dotMode)
                    if dotMode {
                        HStack {
                            Text("Dot size")
                            Slider(value: $dotSize, in: 1...6)
                            Text("\(dotSize, specifier: "%.0f")").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Section(header: Text("Phosphor")) {
                    Toggle("Persistence", isOn: $persistenceEnabled)
                    HStack {
                        Text("Half-life")
                        Slider(value: $halfLife, in: 0.2...2.0)
                        Text("\(halfLife, specifier: "%.2f")s")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Section(header: Text("Closure")) {
                    Toggle("Favor small-integer closure", isOn: $snapSmall)
                    Stepper("Max denominator: \(maxDen)", value: $maxDen, in: 6...64)
                }
            }
            .navigationTitle("XY Lissajous")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - MTKView bridge
private struct LissajousMetalView: UIViewRepresentable {
    let theme: LatticeTheme
    let rootHz: Double
    let pair: (RatioResult, RatioResult)
    let config: LissajousRenderer.Config

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        v.preferredFramesPerSecond = 60
        context.coordinator.attach(to: v)
        return v
    }
    func updateUIView(_ uiView: MTKView, context: Context) {
        let r = context.coordinator.renderer!
        r.setTheme(theme)
        r.setRatios(
            x: .init(num: pair.0.num, den: pair.0.den, octave: pair.0.octave),
            y: .init(num: pair.1.num, den: pair.1.den, octave: pair.1.octave),
            rootHz: rootHz
        )
        r.setConfig { $0 = config } // apply full config atomically
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject {
        var renderer: LissajousRenderer?
        func attach(to view: MTKView) {
            renderer = LissajousRenderer(mtkView: view)
            view.delegate = renderer
        }
    }
}
