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
    @AppStorage(SettingsKeys.lissaSamples) private var samplesPerCurve: Int = 4096
    @AppStorage(SettingsKeys.lissaGridDivs) private var gridDivs: Int = 8
    @AppStorage(SettingsKeys.lissaShowGrid) private var showGrid: Bool = true
    @AppStorage(SettingsKeys.lissaShowAxes) private var showAxes: Bool = true
    @AppStorage(SettingsKeys.lissaStrokeWidth) private var ribbonWidth: Double = 1.5
    @AppStorage(SettingsKeys.lissaDotMode) private var dotMode: Bool = false
    @AppStorage(SettingsKeys.lissaDotSize) private var dotSize: Double = 2.0
    @AppStorage(SettingsKeys.lissaPersistence) private var persistenceEnabled: Bool = true
    @AppStorage(SettingsKeys.lissaHalfLife) private var halfLife: Double = 0.6
    @AppStorage(SettingsKeys.lissaSnap) private var snapSmall: Bool = true
    @AppStorage(SettingsKeys.lissaMaxDen) private var maxDen: Int = 24
    @AppStorage(SettingsKeys.lissaLiveSamples) private var liveSamples: Int = 768
    @AppStorage(SettingsKeys.lissaGlobalAlpha) private var globalAlpha: Double = 1.0

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

    private var previewConfig: LissajousRenderer.Config {
        LissajousPreviewConfigBuilder.makeConfig(
            liveSamples: liveSamples,
            samplesPerCurve: samplesPerCurve,
            gridDivs: gridDivs,
            showGrid: showGrid,
            showAxes: showAxes,
            ribbonWidth: ribbonWidth,
            dotMode: dotMode,
            dotSize: dotSize,
            globalAlpha: globalAlpha,
            persistenceEnabled: persistenceEnabled,
            halfLife: halfLife,
            snapSmall: snapSmall,
            maxDen: maxDen,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        ).config
    }

    var body: some View {
        LissajousPreviewFrame {
            ZStack(alignment: .bottomLeading) {
                LissajousMetalView(
                    theme: theme,
                    rootHz: rootHz,
                    config: previewConfig
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                axisChips
            }
        }
        .onChange(of: activeSignals) { newSignals in
            ToneOutputEngine.shared.setScopeMode(.liveActiveSignals(newSignals))
        }
        .onAppear { ToneOutputEngine.shared.setScopeMode(.liveActiveSignals(activeSignals))
        }
        .onDisappear { ToneOutputEngine.shared.setScopeMode(.liveActiveSignals([]))  }
        .accessibilityLabel("Lissajous Oscilloscope")
    }
}
