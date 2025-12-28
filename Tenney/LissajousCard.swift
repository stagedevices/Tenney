//
//  LissajousCard.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/24/25.
//


import SwiftUI
import MetalKit

struct LissajousCard: View {
    let activeSignals: [ToneOutputEngine.ScopeSignal]   // ordered
    @Environment(\.tenneyTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let rootHz: Double

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
    private enum ScopeLabel {
        case idle
        case one(label: String)
        case two(x: String, y: String)
        case many(x: String, y: String)
    }

    private var scopeLabel: ScopeLabel {
        switch activeSignals.count {
        case 0:
            return .idle
        case 1:
            return .one(label: activeSignals[0].label)
        case 2:
            return .two(x: activeSignals[0].label, y: activeSignals[1].label)
        default:
            // round-robin
            let x = activeSignals.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element.label : nil }
            let y = activeSignals.enumerated().compactMap { $0.offset % 2 == 1 ? $0.element.label : nil }
            return .many(x: "Σ(" + x.joined(separator: ",") + ")", y: "Σ(" + y.joined(separator: ",") + ")")
        }
    }
    @State private var showScopeSettings = false
    @State private var scopeRenderMode: LissajousRenderer.Mode = .live   // NEW enum in renderer

    private var scopeControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scopeRenderMode = (scopeRenderMode == .live ? .synthetic : .live)
                }
            } label: {
                Label(scopeRenderMode == .live ? "Live" : "Math", systemImage: "slider.horizontal.3")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        }
        .padding(10)
    }

    private func axisChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private var axisChips: some View {
        HStack(spacing: 8) {
            switch scopeLabel {
            case .idle:
                axisChip("X —")
                axisChip("Y —")
            case .one(let label):
                axisChip("X  \(label)")
                axisChip("Y  \(label) (+90°)")
            case .two(let x, let y):
                axisChip("X  \(x)")
                axisChip("Y  \(y)")
            case .many(let x, let y):
                axisChip("X  \(x)")
                axisChip("Y  \(y)")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }


    var body: some View {
        ZStack {
            GlassCard(corner: 16) {
                ZStack(alignment: .topLeading) {
                    // plot “preview window” inside the card
                    LissajousMetalView(
                        theme: theme,
                        rootHz: rootHz,
                        config: LissajousRenderer.Config(
                            mode: scopeRenderMode,
                            sampleCount: 768,
                            persistenceEnabled: true,
                            halfLifeSeconds: 0.6
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(12) // match Settings preview padding
                    .overlay(alignment: .topTrailing) { scopeControls }
                    .overlay(alignment: .bottomLeading) { axisChips }
                }
            }
        }
        .onChange(of: activeSignals) { newSignals in
            ToneOutputEngine.shared.setScopeMode(.liveActiveSignals(newSignals))
        }
        .onAppear { ToneOutputEngine.shared.setScopeMode(.liveActiveSignals(activeSignals))
        }
        .onDisappear { ToneOutputEngine.shared.setScopeMode(.liveActiveSignals([]))  }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .accessibilityLabel("Lissajous Oscilloscope")
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
    let pair: (RatioResult, RatioResult) = (.init(num: 1, den: 1, octave: 0),
                                           .init(num: 1, den: 1, octave: 0))
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
