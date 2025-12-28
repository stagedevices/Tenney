//
//  Settings.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//
import SwiftUI
import Foundation
import UIKit
 import AVFAudio

// MARK: Wave options (file scope)

fileprivate struct WaveOption {
    let wave: ToneOutputEngine.GlobalWave
    let label: String
}

fileprivate let audioWaveOptions: [WaveOption] = [
    .init(wave: .foldedSine, label: "Folded Sine"),
    .init(wave: .triangle,   label: "Triangle"),
    .init(wave: .saw,        label: "Saw")
]


// Somewhere shared (e.g., near other enums)
enum TenneyDistanceMode: String, CaseIterable, Identifiable {
    case off, total, breakdown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off:        return "Off"
        case .total:      return "Total"
        case .breakdown:  return "Total + Breakdown"
        }
    }
}
// Environment flags (e.g., in a small file Env+LatticePreview.swift)
private struct LatticePreviewHideDistanceKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var latticePreviewHideDistance: Bool {
        get { self[LatticePreviewHideDistanceKey.self] }
        set { self[LatticePreviewHideDistanceKey.self] = newValue }
    }
}

private enum A4Choice: String, CaseIterable, Identifiable { case _440="440", _442="442", custom="custom"; var id: String { rawValue } }
private enum NodeSizeChoice: String, CaseIterable, Identifiable { case s, m, mplus, l; var id: String { rawValue } }
private struct StageOptionChip: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var invertVisual: Bool = false
    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            let on = invertVisual ? !isOn : isOn
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(on ? Color.accentColor : Color.secondary, .clear)
                    .frame(width: 18)
                Text(title)
                    .font(.footnote.weight(on ? .semibold : .regular))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(on ? .thinMaterial : .ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct StageAccentPicker: View {
    @Binding var selected: String   // "system" | "amber" | "red"

    private struct Option: Identifiable {
        let id: String
        let label: String
        let colors: [Color]
    }

    private let options: [Option] = [
        .init(id: "system", label: "System", colors: [.accentColor, .accentColor.opacity(0.6)]),
        .init(id: "amber",  label: "Amber",  colors: [.orange, .yellow]),
        .init(id: "red",    label: "Red",    colors: [.red, .pink])
    ]

    @Environment(\.tenneyTheme) private var theme

    private var strokeGrad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options) { opt in
                let on = (selected == opt.id)

                Button {
                    withAnimation(.snappy) { selected = opt.id }
                } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: opt.colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        on
                                        ? AnyShapeStyle(strokeGrad)
                                        : AnyShapeStyle(Color.secondary.opacity(0.2)),
                                        lineWidth: on ? 2 : 1
                                    )
                            )

                        Text(opt.label)
                            .font(.caption2.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? .primary : .secondary)
                    }
                    .padding(8)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: on)
            }
        }
    }
}


private struct StageToggleChip: View {
    let title: String
    let systemNameOn: String
    let systemNameOff: String
    @Binding var isOn: Bool
    var invertVisual: Bool = false

    @Environment(\.tenneyTheme) private var theme

    private var grad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            let on = invertVisual ? !isOn : isOn

            HStack(spacing: 8) {
                Image(systemName: on ? systemNameOn : systemNameOff)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(
                        on
                        ? AnyShapeStyle(grad)
                        : AnyShapeStyle(Color.secondary)
                    )
                    .blendMode(on ? (theme.isDark ? .screen : .darken) : .normal)
                    .frame(width: 18)

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .font(.footnote.weight(on ? .semibold : .regular))
                    .foregroundStyle(
                        on
                        ? (theme.isDark ? Color.white : Color.black)
                        : Color.secondary
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    on
                    ? AnyShapeStyle(grad)
                    : AnyShapeStyle(Color.secondary.opacity(0.12)),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }
}




// Utils somewhere shared in the lattice module
func tenneyHeightDelta(_ delta: [Int:Int]) -> Double {
    // H = Σ |Δe_p| * log2(p)
    delta.reduce(0.0) { acc, kv in
        let (p, e) = kv
        guard p >= 2, e != 0 else { return acc }
        return acc + Double(abs(e)) * log2(Double(p))
    }
}

// Pretty “+2×3” / “−1×5” label
func deltaLabel(_ p: Int, _ e: Int) -> String {
    let s = e >= 0 ? "+" : "−"
    return "\(s)\(abs(e))×\(p)"
}
// MARK: - Pro Audio keys
// Persist the selected input device (AVAudioSessionPortDescription.uid)
extension SettingsKeys {
    static let audioInputUID = "audio.input.uid"
    static let audioPreferSpeaker = "audio.prefer.speaker"
    static let toneConfigJSON = "tone.config.json"
    static let whatsNewLastSeenBuild = "whatsnew.lastSeen.build"
    static let whatsNewLastSeenMajorMinor = "whatsnew.lastSeen.majorMinor"
    static let latticeAlwaysRecenterOnQuit = "lattice.always.recenter.on.quit"
    static let latticeRecenterPending = "lattice.recenter.pending"
}

struct AudioRoutingSnapshot: Equatable {
    enum OutputKind {
        case speaker
        case headphones
        case bluetooth
        case other
    }

    let kind: OutputKind
    let displayName: String   // e.g. "iPhone Speaker", "AirPods Pro"

    static func fromCurrentRoute() -> AudioRoutingSnapshot {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        guard let first = outputs.first else {
            return AudioRoutingSnapshot(kind: .other, displayName: "System Output")
        }

        let portType = first.portType
        let name = first.portName

        switch portType {
        case .builtInSpeaker:
            return AudioRoutingSnapshot(kind: .speaker,    displayName: name)
        case .headphones, .headsetMic:
            return AudioRoutingSnapshot(kind: .headphones, displayName: name)
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return AudioRoutingSnapshot(kind: .bluetooth,  displayName: name)
        default:
            return AudioRoutingSnapshot(kind: .other,      displayName: name)
        }
    }

    /// Short code for small labels inside the console (OUT module).
    var shortCode: String {
        switch kind {
        case .speaker:    return "Spkr"
        case .headphones: return "HP"
        case .bluetooth:  return "BT"
        case .other:      return "Sys"
        }
    }

    /// SF Symbol for routing pill.
    var systemImage: String {
        switch kind {
        case .speaker:    return "speaker.wave.2.fill"
        case .headphones: return "headphones"
        case .bluetooth:  return "bonjour"
        case .other:      return "circle.grid.2x1"
        }
    }
}


struct StudioConsoleView: View {
    
    @State private var settingsHeaderBaselineMinY: CGFloat? = nil
    @AppStorage(SettingsKeys.latticeConnectionMode)
    private var latticeConnectionModeRaw: String = LatticeConnectionMode.chain.rawValue

    @AppStorage(SettingsKeys.whatsNewLastSeenBuild)
    private var whatsNewLastSeenBuild: String = ""

    @AppStorage(SettingsKeys.whatsNewLastSeenMajorMinor)
    private var whatsNewLastSeenMajorMinor: String = ""

    @State private var showWhatsNewSheet: Bool = false
    
    private var whatsNewIsUnread: Bool {
    // “new” if either changes
    (whatsNewLastSeenBuild != AppInfo.build) || (whatsNewLastSeenMajorMinor != AppInfo.majorMinor)
    }

    private func markWhatsNewSeen() {
        whatsNewLastSeenBuild = AppInfo.build
        whatsNewLastSeenMajorMinor = AppInfo.majorMinor
    }
    
    @AppStorage(SettingsKeys.latticeDefaultZoomPreset)
    private var latticeDefaultZoomPresetRaw: String = LatticeZoomPreset.close.rawValue

    @AppStorage(SettingsKeys.latticeAlwaysRecenterOnQuit)
    private var latticeAlwaysRecenterOnQuit: Bool = false

    
    @AppStorage(SettingsKeys.defaultView) private var defaultView: String = "tuner" // "lattice" | "tuner"

    @EnvironmentObject private var model: AppModel   // ⬅️ bring AppModel into scope
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var oscMode: LissajousRenderer.Mode = .synthetic

    private var effectiveIsDark: Bool {
        (themeStyleRaw == "dark") || (themeStyleRaw == "system" && systemScheme == .dark)
    }
    // NEW: local ink overlay for this sheet layer
        @State private var localInkVisible = false
        @State private var localInkIsDark  = false
        @State private var lastEffectiveIsDark = false
    // Tuning
    @AppStorage(SettingsKeys.a4Choice)   private var a4Choice = A4Choice._440.rawValue
    @AppStorage(SettingsKeys.a4CustomHz) private var a4Custom: Double = 440
    @AppStorage(SettingsKeys.staffA4Hz)  private var a4Staff: Double = 440

    // Labels
    @AppStorage(SettingsKeys.labelDefault)       private var labelDefault = "ratio" // "ratio" | "heji"
    @AppStorage(SettingsKeys.showRatioAlongHeji) private var showRatioAlong: Bool = true

    // Lattice UI
    @AppStorage(SettingsKeys.nodeSize)     private var nodeSize = NodeSizeChoice.m.rawValue
    @AppStorage(SettingsKeys.labelDensity) private var labelDensity: Double = 0.65
    @AppStorage(SettingsKeys.guidesOn)     private var guidesOn: Bool = true
    @AppStorage(SettingsKeys.overlay7)     private var overlay7: Bool = true
    @AppStorage(SettingsKeys.overlay11)    private var overlay11: Bool = true
    @AppStorage(SettingsKeys.foldAudible)  private var foldAudible: Bool = false
    @AppStorage(SettingsKeys.latticeThemeID) private var latticeThemeID: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.latticeThemeStyle) private var themeStyleRaw: String = ThemeStyleChoice.system.rawValue
    
    // Hex grid (Lattice) — single value (no light/dark split)
    @AppStorage(SettingsKeys.latticeHexGridMode)
    private var gridModeRaw: String = LatticeGridMode.outlines.rawValue

    @AppStorage(SettingsKeys.latticeHexGridStrength)
    private var gridStrength: Double = 0.16

    @AppStorage(SettingsKeys.latticeHexGridMajorEnabled)
    private var gridMajorEnabled: Bool = true

    @AppStorage(SettingsKeys.latticeHexGridMajorEvery)
    private var gridMajorEvery: Int = 2

    // Oscilloscope
    @AppStorage(SettingsKeys.lissaSamples) private var lissaSamplesPerCurve: Int = 4096
    @AppStorage(SettingsKeys.lissaGridDivs) private var lissaGridDivs: Int = 8
    @AppStorage(SettingsKeys.lissaShowGrid) private var lissaShowGrid: Bool = true
    @AppStorage(SettingsKeys.lissaShowAxes) private var lissaShowAxes: Bool = true
    @AppStorage(SettingsKeys.lissaStrokeWidth) private var lissaRibbonWidth: Double = 1.5
    @AppStorage(SettingsKeys.lissaDotMode) private var lissaDotMode: Bool = false
    @AppStorage(SettingsKeys.lissaDotSize) private var lissaDotSize: Double = 2.0
    @AppStorage(SettingsKeys.lissaPersistence) private var lissaPersistenceEnabled: Bool = true
    @AppStorage(SettingsKeys.lissaHalfLife) private var lissaHalfLife: Double = 0.6
    @AppStorage(SettingsKeys.lissaSnap) private var lissaSnapSmall: Bool = true
    @AppStorage(SettingsKeys.lissaMaxDen) private var lissaMaxDen: Int = 24
    @AppStorage(SettingsKeys.lissaLiveSamples) private var lissaLiveSamples: Int = 768
    @AppStorage(SettingsKeys.lissaGlobalAlpha) private var lissaGlobalAlpha: Double = 1.0

    private var gridMode: LatticeGridMode {
        LatticeGridMode(rawValue: gridModeRaw) ?? .outlines
    }

    private var oscEffectiveFPS: Int { reduceMotion ? 30 : 60 }
    private var oscEffectivePersistence: Bool { reduceTransparency ? false : lissaPersistenceEnabled }
    private var oscEffectiveHalfLife: Double { reduceTransparency ? 0.35 : lissaHalfLife }
    private var oscEffectiveAlpha: Double { reduceTransparency ? min(lissaGlobalAlpha, 0.6) : lissaGlobalAlpha }
    private var oscEffectiveLiveSamples: Int { reduceMotion ? max(64, Int(Double(lissaLiveSamples) * 0.6)) : lissaLiveSamples }
    private var oscPreviewConfig: LissajousRenderer.Config {
        LissajousRenderer.Config(
            mode: oscMode,
            sampleCount: oscEffectiveLiveSamples,
            preferredFPS: oscEffectiveFPS,
            samplesPerCurve: oscMode == .synthetic ? lissaSamplesPerCurve : oscEffectiveLiveSamples,
            ribbonWidth: Float(lissaRibbonWidth),
            gridDivs: lissaGridDivs,
            showGrid: lissaShowGrid,
            showAxes: lissaShowAxes,
            globalAlpha: Float(oscEffectiveAlpha),
            edgeAA: 1.0,
            favorSmallIntegerClosure: lissaSnapSmall,
            maxDenSnap: lissaMaxDen,
            dotMode: lissaDotMode,
            dotSize: Float(lissaDotSize),
            persistenceEnabled: oscEffectivePersistence,
            halfLifeSeconds: Float(oscEffectiveHalfLife)
        )
    }
    
    private static func migrateLegacyGridSettingsIfNeeded() {
        let ud = UserDefaults.standard

        // If the new single-value keys already exist, do nothing.
        if ud.object(forKey: SettingsKeys.latticeHexGridStrength) != nil ||
           ud.object(forKey: SettingsKeys.latticeHexGridMajorEvery) != nil ||
           ud.object(forKey: SettingsKeys.latticeHexGridMajorEnabled) != nil {
            return
        }

        // Pull "Light" as canonical legacy source; fall back to Dark if needed.
        let legacyEnabledLight = ud.object(forKey: SettingsKeys.latticeHexGridEnabledLight) as? Bool
        let legacyEnabledDark  = ud.object(forKey: SettingsKeys.latticeHexGridEnabledDark)  as? Bool
        let legacyEnabled = legacyEnabledLight ?? legacyEnabledDark ?? true

        // Old mode was hexOutlines/triMesh; map to outlines/triMesh.
        if let raw = ud.string(forKey: SettingsKeys.latticeHexGridMode) {
            // existing value; map if needed (only if it matches old names)
            if raw == "hexOutlines" { ud.set(LatticeGridMode.outlines.rawValue, forKey: SettingsKeys.latticeHexGridMode) }
            if raw == "triMesh"     { ud.set(LatticeGridMode.triMesh.rawValue,  forKey: SettingsKeys.latticeHexGridMode) }
        }

        // If legacy disabled, force Off.
        if !legacyEnabled {
            ud.set(LatticeGridMode.off.rawValue, forKey: SettingsKeys.latticeHexGridMode)
        }

        let strengthLight = ud.object(forKey: SettingsKeys.latticeHexGridStrengthLight) as? Double
        let strengthDark  = ud.object(forKey: SettingsKeys.latticeHexGridStrengthDark)  as? Double
        ud.set(strengthLight ?? strengthDark ?? 0.16, forKey: SettingsKeys.latticeHexGridStrength)

        let majorEnabledLight = ud.object(forKey: SettingsKeys.latticeHexGridMajorEnabledLight) as? Bool
        let majorEnabledDark  = ud.object(forKey: SettingsKeys.latticeHexGridMajorEnabledDark)  as? Bool
        ud.set(majorEnabledLight ?? majorEnabledDark ?? true, forKey: SettingsKeys.latticeHexGridMajorEnabled)

        let everyLight = ud.object(forKey: SettingsKeys.latticeHexGridMajorEveryLight) as? Int
        let everyDark  = ud.object(forKey: SettingsKeys.latticeHexGridMajorEveryDark)  as? Int
        ud.set(everyLight ?? everyDark ?? 2, forKey: SettingsKeys.latticeHexGridMajorEvery)
    }

    private static let labelDensityDetents: [Double] = [0.0, 0.35, 0.65, 0.85, 1.0]
    private static let gridStrengthDetents: [Double] = [0.10, 0.25, 0.40, 0.65, 0.85, 1.0]
    
    
    // NEW: Headroom detents (safeAmp)
    private static let safeAmpDetents: [Double] = [0.12, 0.18, 0.24, 0.30, 0.36]

    private static func nearestDetent(_ v: Double, in detents: [Double]) -> Double {
        guard let best = detents.min(by: { abs($0 - v) < abs($1 - v) }) else { return v }
        return best
    }

    private func snapLabelDensityIfNeeded() {
        let snapped = Self.nearestDetent(labelDensity, in: Self.labelDensityDetents)
        if snapped != labelDensity { labelDensity = snapped }
    }

    private func snapGridStrengthIfNeeded() {
        let snapped = Self.nearestDetent(gridStrength, in: Self.gridStrengthDetents)
        if snapped != gridStrength { gridStrength = snapped }
    }
    
    
    // MARK: - Scroll offset (reliable; UIKit KVO)
    


    // MARK: - Chip / Tile primitives (match Theme + Pro Audio visual language)
    private struct DetentChip: View {
        let title: String
        let systemImage: String
        let value: Double
        @Binding var current: Double

        @Environment(\.tenneyTheme) private var theme

        private var grad: LinearGradient {
            LinearGradient(
                colors: [theme.e3, theme.e5],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        private var selected: Bool { current == value }

        var body: some View {
            Button {
                guard current != value else { return }
                withAnimation(.snappy) { current = value }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(
                            selected
                            ? AnyShapeStyle(grad)
                            : AnyShapeStyle(Color.secondary)
                        )
                        .blendMode(selected ? (theme.isDark ? .screen : .darken) : .normal)
                        .frame(width: 18)
                        .contentTransition(.symbolEffect(.replace))

                    Text(title)
                        .font(.footnote.weight(selected ? .semibold : .regular))
                        .foregroundStyle(
                            selected
                            ? (theme.isDark ? Color.white : Color.black)
                            : Color.secondary
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        selected
                        ? AnyShapeStyle(grad)
                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .symbolEffect(.bounce, value: selected)
        }
    }



    private enum LatticeUIPage: String, CaseIterable, Identifiable {
        case view, grid, theme, distance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .view: return "View"
            case .grid: return "Grid"
            case .theme: return "Theme"
            case .distance: return "Distance"
            }
        }
    }

    private struct GridModeRadioChip: View {
        let title: String
        let systemNameOff: String
        let systemNameOn: String
        let selected: Bool
        let tap: () -> Void

        @Environment(\.tenneyTheme) private var theme

        private var grad: LinearGradient {
            LinearGradient(
                colors: [theme.e3, theme.e5],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        var body: some View {
            Button(action: tap) {
                HStack(spacing: 8) {
                    Image(systemName: selected ? systemNameOn : systemNameOff)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            selected
                            ? AnyShapeStyle(grad)
                            : AnyShapeStyle(Color.secondary)
                        )
                        .blendMode(selected ? (theme.isDark ? .screen : .darken) : .normal)
                        .frame(width: 18)
                        .contentTransition(.symbolEffect(.replace))

                    Text(title)
                        .font(.footnote.weight(selected ? .semibold : .regular))
                        .foregroundStyle(
                            selected
                            ? (theme.isDark ? Color.white : Color.black)
                            : Color.secondary
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    selected
                    ? AnyShapeStyle(.thinMaterial)
                    : AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        selected
                        ? AnyShapeStyle(grad)
                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .symbolEffect(.bounce, value: selected)
        }
    }


    
    private struct AudioEnginePager: View {
        @Binding var cfg: ToneOutputEngine.Config
        @Binding var safeAmp: Double
        
        @Environment(\.tenneyTheme) private var theme

                private var pageGrad: LinearGradient {
                    LinearGradient(
                        colors: [theme.e3, theme.e5],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }


        private func setWave(_ w: ToneOutputEngine.GlobalWave) {
            guard cfg.wave != w else { return }
            cfg.wave = w
            ToneOutputEngine.shared.config = cfg
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        private enum Page: String, CaseIterable, Identifiable {
            case device, tone, envelope, headroom
            var id: String { rawValue }
            var title: String {
                switch self {
                case .device:   return "Device"
                case .tone:     return "Tone"
                case .envelope: return "Envelope"
                case .headroom: return "Headroom"
                }
            }
        }

        @State private var page: Page = .tone
        private let pageAnim = Animation.easeInOut(duration: 0.22)

        

        


        // MARK: - Icons & summaries

        private func icon(for p: Page) -> String {
            switch p {
            case .device:   return "hifispeaker.2"
            case .tone:     return "waveform"
            case .envelope: return "waveform.path.ecg"
            case .headroom: return "level"
            }
        }

        private func waveLabel(_ wave: ToneOutputEngine.GlobalWave) -> String {
            audioWaveOptions.first(where: { $0.wave == wave })?.label ?? "Custom"
        }

        private func onOff(_ v: Bool) -> String { v ? "On" : "Off" }

        private var deviceSummary: String {
            // We don’t have routing details here yet; keep it simple but descriptive.
            "Devices & routing"
        }

        private var toneSummary: String {
            let fold = String(format: "%.1f", cfg.foldAmount)
            let drive = Int(cfg.drive_dB.rounded())
            return "Wave: \(waveLabel(cfg.wave)) · Fold: \(fold) · Drive: \(drive)dB"
        }

        private var envelopeSummary: String {
            "Attack: \(Int(cfg.attackMs))ms · Release: \(Int(cfg.releaseMs))ms"
        }

        private var headroomSummary: String {
            let snapped = StudioConsoleView.nearestDetent(
                safeAmp,
                in: StudioConsoleView.safeAmpDetents
            )
            let dB = ToneOutputEngine.outputGain(forSafeAmp: snapped)
            let dBInt = Int(dB.rounded())
            let dBText = "\(dBInt) dBFS"

            return "Limiter: \(onOff(cfg.limiterOn)) · Nominal: \(dBText)"
        }
        
        private func summary(for p: Page) -> String {
            switch p {
            case .device:   return deviceSummary
            case .tone:     return toneSummary
            case .envelope: return envelopeSummary
            case .headroom: return headroomSummary
            }
        }

        // MARK: - Pager chips

        @ViewBuilder private func pageChip(_ p: Page) -> some View {
            let active = (page == p)

            Button {
                switchTo(p)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon(for: p))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            active
                            ? AnyShapeStyle(pageGrad)
                            : AnyShapeStyle(Color.secondary)
                        )
                        .blendMode(active ? (theme.isDark ? .screen : .darken) : .normal)
                        .frame(width: 18)
                        .contentTransition(.symbolEffect(.replace))

                    Text(p.title)
                        .font(.footnote.weight(active ? .semibold : .regular))
                        .foregroundStyle(
                            active
                            ? (theme.isDark ? Color.white : Color.black)
                            : Color.secondary
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    active
                    ? AnyShapeStyle(.thinMaterial)
                    : AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        active
                        ? AnyShapeStyle(pageGrad)
                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .symbolEffect(.bounce, value: active)
        }


        private func switchTo(_ p: Page) {
            guard page != p else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(pageAnim) { page = p }
        }


        private var pageSwitcher: some View {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        pageChip(.device)
                        pageChip(.tone)
                        pageChip(.envelope)
                        pageChip(.headroom)
                    }
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            pageChip(.device)
                            pageChip(.tone)
                        }
                        HStack(spacing: 10) {
                            pageChip(.envelope)
                            pageChip(.headroom)
                        }
                    }
                }

                Text(summary(for: page))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.14), value: page)
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }

        // MARK: - Page headers

        private struct AudioPageHeader: View {
            let title: String
            let systemImage: String
            @Environment(\.tenneyTheme) private var theme

            private var headerGradient: LinearGradient {
                LinearGradient(
                    colors: [theme.e3, theme.e5],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            var body: some View {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerGradient)
                        .blendMode(theme.isDark ? .screen : .darken)
                        .frame(width: 22)

                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.isDark ? Color.white : Color.black)
                }
                .padding(.bottom, 2)
            }
        }



        private func panelContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        }

        // MARK: - Individual pages

        private var devicePage: some View {
            VStack(alignment: .leading, spacing: 12) {
                AudioPageHeader(title: "Device", systemImage: icon(for: .device))

                // Reuse existing Pro Audio controls as the Device page, without its own card.
                ProAudioSettingsView(showsOuterCard: false)

                Text("Input and output routing are shared across the tuner and lattice. “Prefer speaker” keeps sound on the main speaker when possible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        private var tonePage: some View {
            VStack(alignment: .leading, spacing: 14) {
                AudioPageHeader(title: "Tone", systemImage: icon(for: .tone))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 12)], spacing: 10) {
                    ForEach(Array(audioWaveOptions.enumerated()), id: \.offset) { _, opt in
                        WaveTile(option: opt, selected: cfg.wave == opt.wave) {
                            withAnimation(.snappy) { setWave(opt.wave) }
                        }
                    }
                }
                .animation(.snappy, value: cfg.wave)

                HStack {
                    Text("Fold")
                    Slider(
                        value: Binding(
                            get: { Double(cfg.foldAmount) },
                            set: { cfg.foldAmount = Float($0); ToneOutputEngine.shared.config = cfg }
                        ),
                        in: 0...5
                    )
                }

                HStack {
                    Text("Drive")
                    Slider(
                        value: Binding(
                            get: { Double(cfg.drive_dB) },
                            set: { cfg.drive_dB = Float($0); ToneOutputEngine.shared.config = cfg }
                        ),
                        in: -6...24
                    )
                }

                Text("Fold adds harmonics; Drive increases saturation before the limiter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        private var envelopePage: some View {
            VStack(alignment: .leading, spacing: 14) {
                AudioPageHeader(title: "Envelope", systemImage: icon(for: .envelope))

                HStack {
                    Text("Attack")
                    Slider(
                        value: Binding(
                            get: { cfg.attackMs },
                            set: { cfg.attackMs = $0; ToneOutputEngine.shared.config = cfg }
                        ),
                        in: 1...200
                    )
                    Text("\(Int(cfg.attackMs))ms")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Release")
                    Slider(
                        value: Binding(
                            get: { cfg.releaseMs },
                            set: { cfg.releaseMs = $0; ToneOutputEngine.shared.config = cfg }
                        ),
                        in: 20...2000
                    )
                    Text("\(Int(cfg.releaseMs))ms")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text("Envelope applies to both short beeps and sustained tones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        private var headroomPage: some View {
            VStack(alignment: .leading, spacing: 14) {
                AudioPageHeader(title: "Headroom", systemImage: icon(for: .headroom))

                HStack(spacing: 10) {
                    StageToggleChip(
                        title: "Limiter",
                        systemNameOn: "shield.lefthalf.fill",
                        systemNameOff: "shield",
                        isOn: Binding(
                            get: { cfg.limiterOn },
                            set: { cfg.limiterOn = $0; ToneOutputEngine.shared.config = cfg }
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Safe level")
                        Spacer()
                        let snapped = StudioConsoleView.nearestDetent(
                            safeAmp,
                            in: StudioConsoleView.safeAmpDetents
                        )
                        Text("\(Int((snapped * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            DetentChip(
                                title: "Safe",
                                systemImage: "speaker.wave.1",
                                value: 0.12,
                                current: $safeAmp
                            )
                            DetentChip(
                                title: "Normal",
                                systemImage: "speaker.wave.2",
                                value: 0.18,
                                current: $safeAmp
                            )
                            DetentChip(
                                title: "Loud",
                                systemImage: "speaker.wave.3",
                                value: 0.24,
                                current: $safeAmp
                            )
                            DetentChip(
                                title: "Hot",
                                systemImage: "speaker.badge.exclamationmark",
                                value: 0.30,
                                current: $safeAmp
                            )
                            DetentChip(
                                title: "Max",
                                systemImage: "exclamationmark.triangle",
                                value: 0.36,
                                current: $safeAmp
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Safe level sets Tenney’s nominal output in dB below the limiter ceiling (0 dBFS). Use Safe/Normal for headphones; use Loud/Hot/Max for speakers or stage systems.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    let dangerous = (!cfg.limiterOn && safeAmp >= 0.24)

                    if cfg.limiterOn {
                        Text("Limiter clamps peaks near 0 dBFS to prevent clipping across all output.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if dangerous {
                        Text("Limiter is off. At this level, keep your hardware gain conservative and avoid headphones.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Limiter is off. Outputs follow the Safe level target without a safety brickwall.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    GlassCTAButton(title: "Pro Audio Settings", systemName: "slider.horizontal.3") {
                        withAnimation(pageAnim) { page = .device }
                    }
                    .font(.footnote)
                }
            }
        }

        // MARK: - Preview + paged panel


        private var pagedPanel: some View {
            ZStack(alignment: .topLeading) {
                switch page {
                case .device:
                    // Place Device content directly in the tray body, no extra
                    // rounded-rect container.
                    devicePage
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("audio.engine.panel.device")
                        .transition(.opacity)

                case .tone:
                    panelContainer {
                        tonePage
                    }
                    .id("audio.engine.panel.tone")
                    .transition(.opacity)

                case .envelope:
                    panelContainer {
                        envelopePage
                    }
                    .id("audio.engine.panel.envelope")
                    .transition(.opacity)

                case .headroom:
                    panelContainer {
                        headroomPage
                    }
                    .id("audio.engine.panel.headroom")
                    .transition(.opacity)
                }
            }
            .animation(pageAnim, value: page)
        }


        // MARK: - Body

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                pageSwitcher
                pagedPanel
            }
            .onChange(of: cfg) { ToneOutputEngine.shared.config = $0 }
        }

        // existing helper lives in outer scope:
        // private func setWave(_ w: ToneOutputEngine.GlobalWave) { ... }
    }

    @State private var settingsHeaderPinned: CGFloat = 0
    @State private var settingsHeaderProgress: CGFloat = 0

    private struct SettingsHeaderMinYKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    private struct LatticeUIControlsPager: View {
        @Binding var latticeConnectionModeRaw: String

        @Environment(\.tenneyTheme) private var theme

        private var pageGrad: LinearGradient {
            LinearGradient(
                colors: [theme.e3, theme.e5],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        
        private var latticeConnectionMode: LatticeConnectionMode {
            LatticeConnectionMode(rawValue: latticeConnectionModeRaw) ?? .chain
        }

        @Binding var nodeSizeRaw: String
        @Binding var labelDensity: Double
        @Binding var guidesOn: Bool
        @Binding var alwaysRecenter: Bool
        @Binding var zoomPresetRaw: String

        @Binding var gridModeRaw: String
        @Binding var gridStrength: Double
        @Binding var gridMajorEnabled: Bool
        @Binding var gridMajorEvery: Int
        
        //  moved in from standalone cards
        @Binding var latticeThemeID: String
        @Binding var tenneyDistanceModeRaw: String

        @State private var page: LatticeUIPage = .view
                private let pageAnim = Animation.easeInOut(duration: 0.22)

                // Smooth height animation so the surrounding LazyVGrid doesn't "jump" on page swaps.
                @State private var panelHeights: [LatticeUIPage: CGFloat] = [:]
                @State private var panelHeight: CGFloat = 0

                private struct PanelHeightKey: PreferenceKey {
                    static var defaultValue: CGFloat = 0
                    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
                }

        private struct MeasuredPage<Content: View>: View {
           let id: LatticeUIPage
           @Binding var active: LatticeUIPage
           @Binding var heights: [LatticeUIPage: CGFloat]
           @Binding var currentHeight: CGFloat
           let pageAnim: Animation
           @ViewBuilder var content: () -> Content

            var body: some View {
                content()
                    // Let the page report its intrinsic vertical height,
                    // instead of the constrained/clipped height.
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
                        }
                    )
                    .onPreferenceChange(PanelHeightKey.self) { h in
                        guard h > 0 else { return }
                        heights[id] = h
                        guard active == id else { return }
                        if abs(currentHeight - h) > 0.5 {
                            withAnimation(pageAnim) { currentHeight = h }
                        } else {
                            currentHeight = h
                        }
                    }
            }
        }
        
        private func icon(for p: LatticeUIPage) -> String {
                    switch p {
                    case .view:     return "viewfinder.circle"
                    case .grid:     return "square.grid.2x2"
                    case .theme:    return "paintpalette"
                    case .distance: return "ruler"
                    }
                }

        private struct PageHeader: View {
            let title: String
            let systemImage: String
            @Environment(\.tenneyTheme) private var theme

            private var headerGradient: LinearGradient {
                LinearGradient(
                    colors: [theme.e3, theme.e5],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            var body: some View {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerGradient)
                        .blendMode(theme.isDark ? .screen : .darken)
                        .frame(width: 22)

                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.isDark ? Color.white : Color.black)
                }
                .padding(.bottom, 2)
            }
        }



        private var nodeChoice: NodeSizeChoice {
            NodeSizeChoice(rawValue: nodeSizeRaw) ?? .m
        }

        private var zoomPreset: LatticeZoomPreset {
            LatticeZoomPreset(rawValue: zoomPresetRaw) ?? .standard
        }

        private var gridMode: LatticeGridMode {
            LatticeGridMode(rawValue: gridModeRaw) ?? .outlines
        }

        private func onOff(_ v: Bool) -> String { v ? "On" : "Off" }

        private func labelDensityName(_ v: Double) -> String {
            let snapped = StudioConsoleView.nearestDetent(v, in: StudioConsoleView.labelDensityDetents)
            switch snapped {
            case 0.0:  return "Off"
            case 0.35: return "Low"
            case 0.65: return "Med"
            case 0.85: return "High"
            case 1.0:  return "Max"
            default:   return "Med"
            }
        }

        private func gridModeName(_ m: LatticeGridMode) -> String {
            switch m {
            case .off:      return "Off"
            case .outlines: return "Hex"
            case .triMesh:  return "Triangle"
            @unknown default:
                return "Hex"
            }
        }

        private var viewSummary: String {
                    "Axis: \(onOff(guidesOn)) · Recenter: \(onOff(alwaysRecenter)) · Zoom: \(zoomPreset.title) · Size: \(nodeChoice.summaryCode) · Labels: \(labelDensityName(labelDensity))"
                }
        
        private var themeSummary: String {
                    "Theme: \(latticeThemeID)"
                }
        
                private var tenneyMode: TenneyDistanceMode {
                    TenneyDistanceMode(rawValue: tenneyDistanceModeRaw) ?? .breakdown
                }
        
                private var distanceSummary: String {
                    "Distance: \(tenneyMode.title)"
                }

        private var gridSummary: String {
            if gridMode == .off { return "Grid: Off" }
            let pct = Int(StudioConsoleView.nearestDetent(gridStrength, in: StudioConsoleView.gridStrengthDetents) * 100)
            return "Grid: \(gridModeName(gridMode)) · \(pct)% · Major: \(onOff(gridMajorEnabled)) · Every \(gridMajorEvery)"
        }

        private func summary(for p: LatticeUIPage) -> String {
            switch p {
            case .view: return viewSummary
            case .grid: return gridSummary
            case .theme: return themeSummary
            case .distance: return distanceSummary
            }
        }

        private func snapLabelDensityIfNeeded() {
            let snapped = StudioConsoleView.nearestDetent(labelDensity, in: StudioConsoleView.labelDensityDetents)
            if snapped != labelDensity { labelDensity = snapped }
        }

        private func snapGridStrengthIfNeeded() {
            let snapped = StudioConsoleView.nearestDetent(gridStrength, in: StudioConsoleView.gridStrengthDetents)
            if snapped != gridStrength { gridStrength = snapped }
        }

        private func switchTo(_ p: LatticeUIPage) {
                    guard page != p else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let h = panelHeights[p], h > 0 { panelHeight = h } // preload target height
                    withAnimation(pageAnim) { page = p }
                }

        @ViewBuilder private func pageChip(_ p: LatticeUIPage) -> some View {
            let active = (page == p)

            Button { switchTo(p) } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon(for: p))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            active
                            ? AnyShapeStyle(pageGrad)
                            : AnyShapeStyle(Color.secondary)
                        )
                        .blendMode(active ? (theme.isDark ? .screen : .darken) : .normal)
                        .frame(width: 18)
                        .contentTransition(.symbolEffect(.replace))

                    Text(p.title)
                        .font(.footnote.weight(active ? .semibold : .regular))
                        .foregroundStyle(
                            active
                            ? (theme.isDark ? Color.white : Color.black)
                            : Color.secondary
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    active
                    ? AnyShapeStyle(.thinMaterial)
                    : AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        active
                        ? AnyShapeStyle(pageGrad)
                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .symbolEffect(.bounce, value: active)
        }


        private var pageSwitcher: some View {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 10) {
                                        pageChip(.view)
                                        pageChip(.grid)
                                        pageChip(.theme)
                                        pageChip(.distance)
                                    }
                                    VStack(spacing: 10) {
                                        HStack(spacing: 10) { pageChip(.view); pageChip(.grid) }
                                        HStack(spacing: 10) { pageChip(.theme); pageChip(.distance) }
                                    }
                                }

                Text(summary(for: page))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.14), value: page)
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }

        private var viewPage: some View {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Grid", systemImage: icon(for: .grid))
                HStack(spacing: 10) {
                    StageToggleChip(
                        title: "Axis",
                        systemNameOn: "ruler.fill",
                        systemNameOff: "ruler",
                        isOn: $guidesOn
                    )
                    StageToggleChip(
                        title: "Always Recenter",
                        systemNameOn: "viewfinder.circle.fill",
                        systemNameOff: "viewfinder.circle",
                        isOn: $alwaysRecenter
                    )
                }

                ZoomPresetStepperControl(
                    preset: Binding(
                        get: { LatticeZoomPreset(rawValue: zoomPresetRaw) ?? .standard },
                        set: { zoomPresetRaw = $0.rawValue }
                    )
                )

                NodeSizeStepperControl(
                    choice: Binding(
                        get: { NodeSizeChoice(rawValue: nodeSizeRaw) ?? .m },
                        set: { nodeSizeRaw = $0.rawValue }
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Label Density")
                        Spacer()
                        Text("\(Int(labelDensity * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            DetentChip(title: "Off",  systemImage: "textformat.alt",        value: 0.0,  current: $labelDensity)
                            DetentChip(title: "Low",  systemImage: "textformat.size.smaller", value: 0.35, current: $labelDensity)
                            DetentChip(title: "Med",  systemImage: "textformat",              value: 0.65, current: $labelDensity)
                            DetentChip(title: "High", systemImage: "textformat.size.larger",  value: 0.85, current: $labelDensity)
                            DetentChip(title: "Max",  systemImage: "textformat.size",         value: 1.0,  current: $labelDensity)
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear { snapLabelDensityIfNeeded() }
                    .onChange(of: labelDensity) { _ in snapLabelDensityIfNeeded() }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Mode")
                        .font(.subheadline.weight(.semibold))

                    Picker("Connection Mode", selection: $latticeConnectionModeRaw) {
                        ForEach(LatticeConnectionMode.allCases) { m in
                            Text(m.title).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text("Default Zoom affects Reset View; Labels control fade.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        
    private var themePage: some View {
                VStack(alignment: .leading, spacing: 12) {
                    PageHeader(title: "Theme", systemImage: icon(for: .theme))
                    SettingsThemePickerView()
                    Text("Themes change node colors (3- vs 5-limit) and high-prime overlays. Selection rims and the selection path inherit per-node tints.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            private var distancePage: some View {
                VStack(alignment: .leading, spacing: 12) {
                    PageHeader(title: "Distance", systemImage: icon(for: .distance))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                        spacing: 12
                    ) {
                        TenneyModeTile(mode: .off, selected: tenneyMode == .off) {
                            withAnimation(.snappy) { tenneyDistanceModeRaw = TenneyDistanceMode.off.rawValue }
                        }
                        TenneyModeTile(mode: .total, selected: tenneyMode == .total) {
                            withAnimation(.snappy) { tenneyDistanceModeRaw = TenneyDistanceMode.total.rawValue }
                        }
                        TenneyModeTile(mode: .breakdown, selected: tenneyMode == .breakdown) {
                            withAnimation(.snappy) { tenneyDistanceModeRaw = TenneyDistanceMode.breakdown.rawValue }
                        }
                    }
                    .animation(.snappy, value: tenneyMode)

                    Text("Shows Tenney height between two selected ratios. “Total + Breakdown” places ±prime counts on each guide and the total at the midpoint. Hidden in the Settings preview.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            @ViewBuilder private var activePage: some View {
                switch page {
                case .view:     viewPage
                case .grid:     gridPage
                case .theme:    themePage
                case .distance: distancePage
                }
            }

            private func panelContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
                content()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
            }

        @ViewBuilder private var gridModePicker: some View {
            let setMode: (LatticeGridMode) -> Void = { m in
                withAnimation(.snappy) { gridModeRaw = m.rawValue }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    GridModeRadioChip(
                        title: "Off",
                        systemNameOff: "slash.circle",
                        systemNameOn: "slash.circle.fill",
                        selected: gridMode == .off
                    ) { setMode(.off) }

                    GridModeRadioChip(
                        title: "Hex",
                        systemNameOff: "hexagon",
                        systemNameOn: "hexagon.fill",
                        selected: gridMode == .outlines
                    ) { setMode(.outlines) }

                    GridModeRadioChip(
                        title: "Triangle",
                        systemNameOff: "triangle",
                        systemNameOn: "triangle.fill",
                        selected: gridMode == .triMesh
                    ) { setMode(.triMesh) }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    GridModeRadioChip(
                        title: "Off",
                        systemNameOff: "slash.circle",
                        systemNameOn: "slash.circle.fill",
                        selected: gridMode == .off
                    ) { setMode(.off) }

                    GridModeRadioChip(
                        title: "Hex",
                        systemNameOff: "hexagon",
                        systemNameOn: "hexagon.fill",
                        selected: gridMode == .outlines
                    ) { setMode(.outlines) }

                    GridModeRadioChip(
                        title: "Triangle",
                        systemNameOff: "triangle",
                        systemNameOn: "triangle.fill",
                        selected: gridMode == .triMesh
                    ) { setMode(.triMesh) }
                }
            }
        }

        private var gridPage: some View {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "View", systemImage: icon(for: .view))

                gridModePicker

                if gridMode != .off {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Strength")
                                .font(.subheadline.weight(.semibold))

                            GridStrengthStepperChip(strength: $gridStrength)
                        }
                        .onAppear { snapGridStrengthIfNeeded() }
                        .onChange(of: gridStrength) { _ in snapGridStrengthIfNeeded() }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Major Lines")
                                .font(.subheadline.weight(.semibold))

                            StageToggleChip(
                                title: "Enabled",
                                systemNameOn: "grid.circle.fill",
                                systemNameOff: "grid.circle",
                                isOn: $gridMajorEnabled
                            )

                            MajorEveryStepperChip(value: $gridMajorEvery, enabled: gridMajorEnabled)
                        }


                        Text("Strength + Major Lines are shared across Light/Dark.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var pagedPanel: some View {
                    ZStack(alignment: .topLeading) {
                        switch page {
                        case .view:
                            panelContainer {
                                MeasuredPage(id: .view, active: $page, heights: $panelHeights, currentHeight: $panelHeight, pageAnim: pageAnim) {
                                    viewPage
                                }
                            }
                            .id("lattice.ui.panel.view")
                            .transition(.opacity)
                        case .grid:
                            panelContainer {
                                MeasuredPage(id: .grid, active: $page, heights: $panelHeights, currentHeight: $panelHeight, pageAnim: pageAnim) {
                                    gridPage
                                }
                            }
                            .id("lattice.ui.panel.grid")
                            .transition(.opacity)
                        case .theme:
                            panelContainer {
                                MeasuredPage(id: .theme, active: $page, heights: $panelHeights, currentHeight: $panelHeight, pageAnim: pageAnim) {
                                    themePage
                                }
                            }
                            .id("lattice.ui.panel.theme")
                            .transition(.opacity)
                        case .distance:
                            panelContainer {
                                MeasuredPage(id: .distance, active: $page, heights: $panelHeights, currentHeight: $panelHeight, pageAnim: pageAnim) {
                                    distancePage
                                }
                            }
                            .id("lattice.ui.panel.distance")
                            .transition(.opacity)
                        }
                    }
                    // Keep the panel's outer height stable + animated, so the rest of Settings doesn't jump around.
                    .frame(height: panelHeight > 0 ? panelHeight : nil, alignment: .topLeading)
                    .clipped()
                    .animation(pageAnim, value: page)
                    .animation(pageAnim, value: panelHeight)
                }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {

                // ✅ Preview window (unchanged; static; never animates)
                Group {
                    if #available(iOS 26.0, *) {
                        GlassEffectContainer {
                            SettingsLatticePreview()
                                .environment(\.latticePreviewMode, true)
                                .environment(\.latticePreviewHideChips, true)
                                .allowsHitTesting(false)
                                .disabled(true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                    } else {
                        SettingsLatticePreview()
                            .environment(\.latticePreviewMode, true)
                            .environment(\.latticePreviewHideChips, true)
                            .allowsHitTesting(false)
                            .disabled(true)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                    }
                }
                .transaction { $0.animation = nil }

                // 2) Page switcher (hierarchical, non-native)
                pageSwitcher

                // 3) Paged content panel (animated in/out)
                pagedPanel
            }
        }
    }
    private struct GridStrengthStepperChip: View {
        private let semanticNames = ["Thin", "Light", "Medium", "Bold", "Heavy"]

        private var semanticName: String {
            let n = detents.count
            guard n > 1 else { return semanticNames.last! }

            let idx = detents.firstIndex(of: snapped) ?? 0
            let t = Double(idx) / Double(n - 1)               // 0…1 across detents
            let j = Int((t * Double(semanticNames.count - 1)).rounded())
            return semanticNames[max(0, min(semanticNames.count - 1, j))]
        }

        @Binding var strength: Double

        private var detents: [Double] { StudioConsoleView.gridStrengthDetents.sorted() }
        private var snapped: Double { StudioConsoleView.nearestDetent(strength, in: detents) }
        private var pct: Int { Int((snapped * 100).rounded()) }

        private func step(_ dir: Int) {
            let cur = snapped
            guard let idx = detents.firstIndex(of: cur) else { return }
            let nextIdx = max(0, min(detents.count - 1, idx + dir))
            let next = detents[nextIdx]
            guard next != strength else { return }
            strength = next
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        var body: some View {
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { step(-1) } } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 2) {
                        ViewThatFits(in: .horizontal) {
                            Text(semanticName)
                            Text(String(semanticName.prefix(4)))
                        }
                        Text("\(pct)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))

                Button { withAnimation(.snappy) { step(+1) } } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct MajorEveryStepperChip: View {
        @Binding var value: Int
        let enabled: Bool

        private func step(_ dir: Int) {
            guard enabled else { return }
            value = max(2, min(24, value + dir))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        var body: some View {
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { step(-1) } } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)

                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .symbolRenderingMode(.hierarchical)

                    ViewThatFits(in: .horizontal) {
                        Text("Every \(value)")
                        Text("Every \(value)x") // tiny fallback; basically never used, but prevents ellipsis
                    }
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)          // ✅ pill gets the available width
                .layoutPriority(1)                   // ✅ resists compression
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                .opacity(enabled ? 1 : 0.5)

                Button { withAnimation(.snappy) { step(+1) } } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
            }
        }
    }
    
        // Local scheme override for immediate visual update inside Settings
        private var settingsScheme: ColorScheme? {
            switch ThemeStyleChoice(rawValue: themeStyleRaw) ?? .system {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    // Sound
    
    @AppStorage(SettingsKeys.safeAmp)    private var safeAmp: Double = 0.18
    @State private var showSetupWizard: Bool = false

    // Grid: 1 column on phones, 2 on iPad
    private var columns: [GridItem] {
        if hSizeClass == .compact {
            return [GridItem(.flexible(), spacing: 14)]
        } else {
            return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        }
    }

    // Pull the version once for display in About card
        private var versionString: String {
            let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
            let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            return b.isEmpty ? "Version \(v)" : "Version \(v) (\(b))"
        }
    
    // MARK: - Body (split to keep type-checker happy)
    var body: some View {
                NavigationStack {
                    contentStack
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .environment(
                    \.tenneyTheme,
                ThemeRegistry.theme(
                    LatticeThemeID(rawValue: latticeThemeID) ?? .classicBO,
                    dark: effectiveIsDark
                )
            )
            .statusBar(hidden: stageHideStatus)
            .preferredColorScheme(settingsScheme)
            .sheet(isPresented: $showWhatsNewSheet, onDismiss: {
                markWhatsNewSeen()
            }) {
            WhatsNewSheet(
                items: WhatsNewContent.v0_3Items,
                primaryAction: {
                    showWhatsNewSheet = false
                    markWhatsNewSeen()
                }
            )
        }
        .background(
            SettingsChangeSinks(
                defaultView: $defaultView,
                a4Staff: $a4Staff,
                labelDefault: $labelDefault,
                showRatioAlong: $showRatioAlong,
                nodeSize: $nodeSize,
                labelDensity: $labelDensity,
                gridModeRaw: $gridModeRaw,
                gridMajorEnabled: $gridMajorEnabled,
                gridMajorEvery: $gridMajorEvery,
                gridStrength: $gridStrength,
                guidesOn: $guidesOn,
                overlay7: $overlay7,
                overlay11: $overlay11,
                foldAudible: $foldAudible,
                safeAmp: $safeAmp,
                latticeConnectionModeRaw: $latticeConnectionModeRaw,
                latticeThemeID: $latticeThemeID,
                themeStyleRaw: $themeStyleRaw,
                stageDimLevel: $stageDimLevel,
                stageAccent: $stageAccent,
                stageHideStatus: $stageHideStatus,
                stageKeepAwake: $stageKeepAwake,
                stageMinimalUI: $stageMinimalUI,
                effectiveIsDark: effectiveIsDark,
                localInkVisible: $localInkVisible,
                localInkIsDark: $localInkIsDark,
                broadcastAll: broadcastAll,
                latticeDefaultZoomPresetRaw: $latticeDefaultZoomPresetRaw,
                latticeAlwaysRecenterOnQuit: $latticeAlwaysRecenterOnQuit
            )
        )
    }
    
    @ViewBuilder private var whatsNewSection: some View {
        glassCard(
            icon: "sparkles",
            title: "What’s New",
            subtitle: "Latest features and changes"
        ) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Tenney \(AppInfo.majorMinor)")
                            .font(.subheadline.weight(.semibold))

                        if whatsNewIsUnread {
                            Text("NEW")
                                .font(.caption2.weight(.black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Release highlights, new features, and fixes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                GlassCTAButton(title: "Check it out", systemName: "sparkles") {
                    showWhatsNewSheet = true
                }
            }
        }
    }


    // MARK: - Sticky Settings header (shared)
    private struct SettingsHeaderBar: View {
        let progress: CGFloat          // 0 expanded → 1 collapsed
        let hSizeClass: UserInterfaceSizeClass?
        let isDark: Bool

        private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

        var body: some View {
            let p = progress

            let titleBig: CGFloat   = (hSizeClass == .compact ? 34 : 30)
            let titleSmall: CGFloat = 24
            let titleSize = lerp(titleBig, titleSmall, p)

            let subBig: CGFloat   = 16
            let subSmall: CGFloat = 13
            let subSize = lerp(subBig, subSmall, p)

            VStack(alignment: .leading, spacing: lerp(6, 3, p)) {
                Text("Settings")
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(isDark ? Color.white : Color.black)
                    .lineLimit(1)

                Text("Tuner & Lattice Algorithm Configs")
                    .font(.system(size: subSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Divider()
                    .opacity(p * 0.9)
            }
            .padding(.horizontal, 20)
            .padding(.top, lerp(16, 10, p))
            .padding(.bottom, lerp(8, 4, p))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .transaction { $0.animation = nil }
        }
    }

    
    // MARK: - Split content
    private var contentStack: some View {
        ZStack {
            backgroundGlass

            let theme = ThemeRegistry.theme(
                LatticeThemeID(rawValue: latticeThemeID) ?? .classicBO,
                dark: effectiveIsDark
            )

            ScrollView {
                // ✅ header participates in scroll geometry, then pins itself
                SettingsHeaderBar(progress: settingsHeaderProgress, hSizeClass: hSizeClass, isDark: effectiveIsDark)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: SettingsHeaderMinYKey.self,
                                value: geo.frame(in: .named("settings.scroll")).minY
                            )
                        }
                    )
                    .offset(y: settingsHeaderPinned)
                    .zIndex(50)
                gridView
            }
            .coordinateSpace(name: "settings.scroll")
            .onPreferenceChange(SettingsHeaderMinYKey.self) { measuredMinY in
                // Remove our own offset from the measurement to avoid feedback loops
                let effectiveMinY = measuredMinY - settingsHeaderPinned
                if settingsHeaderBaselineMinY == nil { settingsHeaderBaselineMinY = effectiveMinY }
                let base = settingsHeaderBaselineMinY ?? effectiveMinY
                let raw = effectiveMinY - base // 0 at rest, negative as you scroll down
                let pin = max(0, -raw)
                settingsHeaderPinned = pin
                settingsHeaderProgress = min(1, pin / headerCollapseRange)

            }

            inkOverlay
        }
    }


    private var headerView: some View {
        let p = settingsHeaderProgress

        let titleBig: CGFloat   = (hSizeClass == .compact ? 34 : 30)
        let titleSmall: CGFloat = 24
        let titleSize = lerp(titleBig, titleSmall, p)

        let subBig: CGFloat   = 16
        let subSmall: CGFloat = 13
        let subSize = lerp(subBig, subSmall, p)

        let theme = ThemeRegistry.theme(
            LatticeThemeID(rawValue: latticeThemeID) ?? .classicBO,
            dark: effectiveIsDark
        )

        return VStack(alignment: .leading, spacing: lerp(6, 3, p)) {
            Text("Settings")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(theme.isDark ? Color.white : Color.black)
                .lineLimit(1)

            Text("Tuner & Lattice Algorithm Configs")
                .font(.system(size: subSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Divider()
                .opacity(p * 0.9)
        }
        .padding(.horizontal, 20)
        .padding(.top, lerp(16, 10, p))
        .padding(.bottom, lerp(8, 4, p))
        .frame(maxWidth: .infinity, alignment: .leading)
        .transaction { $0.animation = nil }
    }




    private var gridView: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            whatsNewSection
            latticeUISection
            oscilloscopeSection
            stageSection
            defaultViewSection
            // labelingSection
            // overlaysSection
            soundSection          // now the Type A Audio Engine section
            tuningSection
            quickSetupCard
            aboutSection
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }

    @ToolbarContentBuilder
    private var doneToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
        }
    }

    @ViewBuilder
    private var inkOverlay: some View {
        if localInkVisible {
            Rectangle()
                .fill(localInkIsDark ? Color.black : Color.white)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(10)
        }
    }

    @ViewBuilder private var quickSetupCard: some View {
        glassCard(
            icon: "wand.and.stars",
            title: "Quick Setup",
            subtitle: "Guided configuration"
        ) {
            HStack {
                Text("Run the first-time setup again.")
                    .foregroundStyle(.gray, .primary)
                Spacer()
                GlassCTAButton(title: "Rerun Setup", systemName: "sparkles") {
                    model.showOnboardingWizard = true
                    dismiss()
                }
            }
            .font(.callout)
        }
    }

    
    private static func forceStatusBarUpdate() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            for window in scene.windows {
                window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    // MARK: - Lightweight sink view holds all listeners
    private struct SettingsChangeSinks: View {
        private func pushSafeAmpToEngine(_ v: Double) {
            let mapped = ToneOutputEngine.outputGain(forSafeAmp: v)
            var cfg = ToneOutputEngine.shared.config
            if cfg.outputGain_dB != mapped {
                cfg.outputGain_dB = mapped
                ToneOutputEngine.shared.config = cfg
            }
        }

        @Binding var defaultView: String
        @Binding var a4Staff: Double
        @Binding var labelDefault: String
        @Binding var showRatioAlong: Bool
        @Binding var nodeSize: String
        @Binding var labelDensity: Double
        @Binding var gridModeRaw: String
        @Binding var gridMajorEnabled: Bool
        @Binding var gridMajorEvery: Int
        @Binding var gridStrength: Double
        @Binding var guidesOn: Bool
        @Binding var overlay7: Bool
        @Binding var overlay11: Bool
        @Binding var foldAudible: Bool
        @Binding var safeAmp: Double
        @Binding var latticeConnectionModeRaw: String
        @Binding var latticeThemeID: String
        @Binding var themeStyleRaw: String
        @Binding var stageDimLevel: Double
        @Binding var stageAccent: String
        @Binding var stageHideStatus: Bool
        @Binding var stageKeepAwake: Bool
        @Binding var stageMinimalUI: Bool
        let effectiveIsDark: Bool
        @Binding var localInkVisible: Bool
        @Binding var localInkIsDark: Bool
        let broadcastAll: () -> Void
        @Binding var latticeDefaultZoomPresetRaw: String
        @Binding var latticeAlwaysRecenterOnQuit: Bool


        @State private var lastEffectiveIsDark: Bool = false
        

        var body: some View {
            Color.clear
                .onAppear {
                    broadcastAll()
                    lastEffectiveIsDark = effectiveIsDark
                    StudioConsoleView.migrateLegacyGridSettingsIfNeeded()
                    let snappedLabel = StudioConsoleView.nearestDetent(labelDensity, in: StudioConsoleView.labelDensityDetents)
                    if snappedLabel != labelDensity { labelDensity = snappedLabel }

                    let snappedGrid = StudioConsoleView.nearestDetent(gridStrength, in: StudioConsoleView.gridStrengthDetents)
                    if snappedGrid != gridStrength { gridStrength = snappedGrid }
                    
                    let snappedSafe = StudioConsoleView.nearestDetent(
                        safeAmp,
                        in: StudioConsoleView.safeAmpDetents
                    )
                    if snappedSafe != safeAmp {
                        safeAmp = snappedSafe
                    }
                    pushSafeAmpToEngine(snappedSafe)

                    
                    // Always remember lattice view (remove user-facing toggle; enforce ON)
                                        UserDefaults.standard.set(true, forKey: SettingsKeys.latticeRememberLastView)
                                        postSetting(SettingsKeys.latticeRememberLastView, true)
                }
                .onChange(of: defaultView)   { postSetting(SettingsKeys.defaultView, $0) }
                .onChange(of: a4Staff)       { postSetting(SettingsKeys.staffA4Hz, $0) }
                .onChange(of: labelDefault)  { postSetting(SettingsKeys.labelDefault, $0) }
                .onChange(of: showRatioAlong){ postSetting(SettingsKeys.showRatioAlongHeji, $0) }
                .onChange(of: nodeSize)      { postSetting(SettingsKeys.nodeSize, $0) }
                .onChange(of: labelDensity)  { postSetting(SettingsKeys.labelDensity, $0) }
                .onChange(of: gridModeRaw)       { postSetting(SettingsKeys.latticeHexGridMode, $0) }
                .onChange(of: gridStrength)      { postSetting(SettingsKeys.latticeHexGridStrength, $0) }
                .onChange(of: gridMajorEnabled)  { postSetting(SettingsKeys.latticeHexGridMajorEnabled, $0) }
                .onChange(of: gridMajorEvery)    { postSetting(SettingsKeys.latticeHexGridMajorEvery, $0) }
                .onChange(of: guidesOn)      { postSetting(SettingsKeys.guidesOn, $0) }
                .onChange(of: overlay7)      { postSetting(SettingsKeys.overlay7, $0) }
                .onChange(of: overlay11)     { postSetting(SettingsKeys.overlay11, $0) }
                .onChange(of: foldAudible)   { postSetting(SettingsKeys.foldAudible, $0) }
                .onChange(of: safeAmp) { newValue in
                    let snapped = StudioConsoleView.nearestDetent(
                        newValue,
                        in: StudioConsoleView.safeAmpDetents
                    )

                    if snapped != newValue {
                        // Re-snap and early-out to avoid double-mapping.
                        safeAmp = snapped
                        return
                    }

                    postSetting(SettingsKeys.safeAmp, snapped)
                    pushSafeAmpToEngine(snapped)
                }

                .onChange(of: latticeConnectionModeRaw) { postSetting(SettingsKeys.latticeConnectionMode, $0) }
                .onChange(of: latticeThemeID){ postSetting(SettingsKeys.latticeThemeID, $0) }
                .onChange(of: themeStyleRaw) { postSetting(SettingsKeys.latticeThemeStyle, $0) }
                .onChange(of: stageDimLevel) { postSetting(SettingsKeys.stageDimLevel, $0) }
                .onChange(of: stageAccent)   { postSetting(SettingsKeys.stageAccent, $0) }

                .onChange(of: stageHideStatus){ v in
                    postSetting(SettingsKeys.stageHideStatus, v)
                    StudioConsoleView.forceStatusBarUpdate()
                }

                .onChange(of: stageKeepAwake){ postSetting(SettingsKeys.stageKeepAwake, $0) }
                .onChange(of: stageMinimalUI){ postSetting(SettingsKeys.stageMinimalUI, $0) }
                .onChange(of: latticeDefaultZoomPresetRaw) { postSetting(SettingsKeys.latticeDefaultZoomPreset, $0) }
                .onChange(of: latticeAlwaysRecenterOnQuit) { postSetting(SettingsKeys.latticeAlwaysRecenterOnQuit, $0) }
                                .onChange(of: effectiveIsDark) { newVal in
                                    guard newVal != lastEffectiveIsDark else { return }
                                    lastEffectiveIsDark = newVal
                                    localInkIsDark = newVal
                                    withAnimation(.easeInOut(duration: 0.25)) { localInkVisible = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                        withAnimation(.easeOut(duration: 0.15)) { localInkVisible = false }
                                    }
                                }
        }
    }


    // MARK: - Background
    @ViewBuilder private var backgroundGlass: some View {
        // Neutral, legible base – no more full-screen glassEffect
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }


    // MARK: - Sections
    @AppStorage(SettingsKeys.stageDimLevel) private var stageDimLevel: Double = 0.85
    @AppStorage(SettingsKeys.stageAccent)   private var stageAccent: String = "system" // "system"|"amber"|"red"
    @AppStorage(SettingsKeys.stageHideStatus) private var stageHideStatus: Bool = true
    @AppStorage(SettingsKeys.stageKeepAwake)  private var stageKeepAwake: Bool = true
    @AppStorage(SettingsKeys.stageMinimalUI)  private var stageMinimalUI: Bool = false
    // Convenience about the current appearance mode
    private var styleChoice: ThemeStyleChoice { ThemeStyleChoice(rawValue: themeStyleRaw) ?? .system }
    private var isExplicitDarkStyle: Bool { styleChoice == .dark }
    private var isAutoAndCurrentlyDark: Bool { styleChoice == .system && systemScheme == .dark }

    @ViewBuilder private var oscilloscopeSection: some View {
        glassCard(
            icon: "waveform.path.ecg",
            title: "Oscilloscope",
            subtitle: "Lissajous preview + pro controls"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                let theme = ThemeRegistry.theme(
                    LatticeThemeID(rawValue: latticeThemeID) ?? .classicBO,
                    dark: effectiveIsDark
                )
                Group {
                    if #available(iOS 26.0, *) {
                        GlassEffectContainer {
                            LissajousMetalView(
                                theme: theme,
                                rootHz: model.rootHz,
                                config: oscPreviewConfig
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    } else {
                        LissajousMetalView(
                            theme: theme,
                            rootHz: model.rootHz,
                            config: oscPreviewConfig
                        )
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(height: 180)

                HStack(spacing: 8) {
                    Picker("Mode", selection: $oscMode) {
                        Text("Live").tag(LissajousRenderer.Mode.live)
                        Text("Math").tag(LissajousRenderer.Mode.synthetic)
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show grid", isOn: $lissaShowGrid)
                    Toggle("Show axes", isOn: $lissaShowAxes)

                    HStack {
                        Text("Grid divisions")
                        Spacer()
                        Stepper("\(lissaGridDivs)", value: $lissaGridDivs, in: 2...16)
                    }

                    HStack {
                        Text("Ribbon width")
                        Slider(value: $lissaRibbonWidth, in: 0.5...4.0)
                        Text("\(lissaRibbonWidth, specifier: \"%.1f\")")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Dot-only mode", isOn: $lissaDotMode)
                    if lissaDotMode {
                        HStack {
                            Text("Dot size")
                            Slider(value: $lissaDotSize, in: 1...6)
                            Text("\(lissaDotSize, specifier: \"%.0f\")")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Live density")
                        Slider(value: Binding(
                            get: { Double(lissaLiveSamples) },
                            set: { lissaLiveSamples = Int($0) }
                        ), in: 128...2048)
                        Text("\(lissaLiveSamples)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Curve samples")
                        Slider(value: Binding(
                            get: { Double(lissaSamplesPerCurve) },
                            set: { lissaSamplesPerCurve = Int($0) }
                        ), in: 512...8192)
                        Text("\(lissaSamplesPerCurve)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Persistence", isOn: $lissaPersistenceEnabled)
                    if lissaPersistenceEnabled {
                        HStack {
                            Text("Half-life")
                            Slider(value: $lissaHalfLife, in: 0.2...2.0)
                            Text("\(lissaHalfLife, specifier: \"%.2f\")s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Global alpha")
                        Slider(value: $lissaGlobalAlpha, in: 0.2...1.0)
                        Text("\(lissaGlobalAlpha, specifier: \"%.2f\")")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Favor small-integer closure", isOn: $lissaSnapSmall)
                    HStack {
                        Text("Max denominator")
                        Stepper("\(lissaMaxDen)", value: $lissaMaxDen, in: 6...64)
                    }
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder private var stageSection: some View {
        glassCard(
            icon: "rectangle.on.rectangle.angled",
            title: "Stage Mode",
            subtitle: "Dim, accent, performance behavior"
        ) {
            let dimLocked = isExplicitDarkStyle || isAutoAndCurrentlyDark

            VStack(alignment: .leading, spacing: 14) {

                // Dimmer preview + lock state
                HStack(alignment: .center, spacing: 12) {
                    Group {
                        if #available(iOS 26.0, *) {
                            GlassEffectContainer {
                                StageDimMiniPreview(
                                    dim: dimLocked ? 0.9 : stageDimLevel,
                                    locked: dimLocked
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .frame(width: 140, height: 70)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        } else {
                            StageDimMiniPreview(
                                dim: dimLocked ? 0.9 : stageDimLevel,
                                locked: dimLocked
                            )
                            .frame(width: 140, height: 70)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stage dimmer")
                            .font(.subheadline.weight(.semibold))

                        if dimLocked {
                            Text("Locked while using Dark appearance.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Dims the background while Stage Mode is active.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if dimLocked {
                        LockTag(text: "Locked in Dark")
                    }
                }

                // Dim controls (only when not locked)
                if !dimLocked {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dim level")
                            Spacer()
                            Text("\(Int(stageDimLevel * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $stageDimLevel, in: 0.3...0.95)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                DimPresetChip(title: "Soft",    value: 0.55, current: $stageDimLevel)
                                DimPresetChip(title: "Classic", value: 0.75, current: $stageDimLevel)
                                DimPresetChip(title: "Deep",    value: 0.85, current: $stageDimLevel)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Divider()

                // Accent color
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent color")
                        .font(.subheadline.weight(.semibold))

                    StageAccentPicker(selected: $stageAccent)

                    Text("Controls the highlight color used while Stage Mode is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Behavior toggles
                VStack(alignment: .leading, spacing: 8) {
                    Text("Performance behavior")
                        .font(.subheadline.weight(.semibold))

                    StageToggleChip(
                        title: "Hide status bar",
                        systemNameOn: "rectangle.topthird.inset.filled",
                        systemNameOff: "rectangle",
                        isOn: $stageHideStatus
                    )

                    StageToggleChip(
                        title: "Keep screen awake",
                        systemNameOn: "moon.zzz.fill",
                        systemNameOff: "moon",
                        isOn: $stageKeepAwake
                    )

                    StageToggleChip(
                        title: "Minimal UI",
                        systemNameOn: "wand.and.stars.inverse",
                        systemNameOff: "wand.and.stars",
                        isOn: $stageMinimalUI
                    )

                    Text("Stage Mode is available from the Utility Bar. It remembers these dimmer and behavior settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }


    private struct LockTag: View {
        let text: String
        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").imageScale(.small)
                Text(text).font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(.secondary)
            .background(.thinMaterial, in: Capsule())
        }
    }

    // Updated preview supports a locked overlay
    private struct StageDimMiniPreview: View {
        let dim: Double
        let locked: Bool

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.secondarySystemBackground),
                                Color(.secondarySystemBackground).opacity(locked ? 0.95 : 0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Color.black.opacity(dim)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if locked {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill").imageScale(.small)
                        Text("Disabled in Dark").font(.caption2)
                    }
                    .padding(8)
                    .foregroundStyle(.secondary)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
            }
            .contentShape(Rectangle())
            .opacity(locked ? 0.7 : 1)
        }
    }




    @ViewBuilder private var tuningSection: some View {
        glassCard(
            icon: "tuningfork",
            title: "Reference Pitch (A4)",
            subtitle: "Staff & equal temperament base"
        ) {
            SettingsA4PickerView()
        }
    }


    

    
    @ViewBuilder private var defaultViewSection: some View {
        glassCard(
            icon: "rectangle.2.swap",
            title: "Default Screen",
            subtitle: "Which screen opens on launch"
        ) {
            HStack(spacing: 12) {
                GlassSelectTile(title: "Lattice", isOn: defaultView == "lattice") {
                    withAnimation(.snappy) { defaultView = "lattice" }
                }
                GlassSelectTile(title: "Tuner", isOn: defaultView == "tuner") {
                    withAnimation(.snappy) { defaultView = "tuner" }
                }
            }
            Text("Matches the first-run setup. Reorders the Utility Bar so your default is on the left.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }



    @ViewBuilder private var latticeUISection: some View {
        glassCard(
            icon: "hexagon",
            title: "Lattice UI",
            subtitle: "View, grid, theme, distance"
        ) {
            LatticeUIControlsPager(
                latticeConnectionModeRaw: $latticeConnectionModeRaw,
                nodeSizeRaw: $nodeSize,
                labelDensity: $labelDensity,
                guidesOn: $guidesOn,
                alwaysRecenter: $latticeAlwaysRecenterOnQuit,
                zoomPresetRaw: $latticeDefaultZoomPresetRaw,
                gridModeRaw: $gridModeRaw,
                gridStrength: $gridStrength,
                gridMajorEnabled: $gridMajorEnabled,
                gridMajorEvery: $gridMajorEvery,
                latticeThemeID: $latticeThemeID,
                tenneyDistanceModeRaw: $tenneyDistanceModeRaw
            )
        }
    }


    @ViewBuilder private var labelingSection: some View {
        glassCard(
            icon: "tag",
            title: "Labeling",
            subtitle: "Lattice labels and info cards"
        ) {
            Picker("Default", selection: $labelDefault) {
                Text("Ratio").tag("ratio")
                Text("HEJI").tag("heji")
            }
            .pickerStyle(.segmented)

            Toggle("Show ratio alongside HEJI", isOn: $showRatioAlong)

            Text("Affects Lattice info cards and Builder labels.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var overlaysSection: some View {
        glassCard(
            icon: "circle.grid.cross.down.fill",
            title: "Overlays",
            subtitle: "Higher-prime ghost nodes"
        ) {
            Toggle("Show 7-limit overlay", isOn: $overlay7)
            Toggle("Show 11-limit overlay", isOn: $overlay11)
            Text("Toggles higher-prime ghost nodes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var themeSection: some View {
        glassCard(
            icon: "paintpalette",
            title: "Appearance · Lattice Theme",
            subtitle: "Node colors and overlays"
        ) {
            SettingsThemePickerView()
            Text("Themes change node colors (3- vs 5-limit) and high-prime overlays. Selection rims and the selection path inherit per-node tints.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    
    @AppStorage(SettingsKeys.tenneyDistanceMode)
    private var tenneyDistanceModeRaw: String = TenneyDistanceMode.breakdown.rawValue

    private var tenneyMode: TenneyDistanceMode {
        get { TenneyDistanceMode(rawValue: tenneyDistanceModeRaw) ?? .breakdown }
        set { tenneyDistanceModeRaw = newValue.rawValue }
    }
    private struct TenneyModeTile: View {
        let mode: TenneyDistanceMode
        let selected: Bool
        let tap: () -> Void

        var body: some View {
            VStack(spacing: 6) {
                Button(action: tap) {
                    GlassEffectContainer {      // iOS 18; gracefully ignored pre-18
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.clear) // glass background drawn by container
                            TenneyMiniPreview(mode: mode)
                                .padding(10)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.hierarchical)
                                    .padding(6)
                                    .transition(.opacity)
                            }
                        }
                        .frame(minWidth: 160, minHeight: 84)
                    }
                }
                .buttonStyle(.plain)

                Text(mode.title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private struct TenneyMiniPreview: View {
        let mode: TenneyDistanceMode
        // a tiny fake lattice: two points and guide arrows
        var body: some View {
            Canvas { ctx, size in
                let a = CGPoint(x: size.width * 0.28, y: size.height * 0.62)
                let b = CGPoint(x: size.width * 0.74, y: size.height * 0.36)
                // draw nodes
                for p in [a,b] {
                    let r: CGFloat = 8
                    ctx.fill(Path(ellipseIn: .init(x: p.x-r, y: p.y-r, width: r*2, height: r*2)), with: .color(.primary))
                }
                // mid line
                var line = Path()
                line.move(to: a); line.addLine(to: b)
                ctx.stroke(line, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

                guard mode != .off else { return }
                // total chip at midpoint
                let mid = CGPoint(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
                let total = "H 3.84"
                let attr = AttributedString(total, attributes: .init([.font: UIFont.systemFont(ofSize: 10, weight: .semibold)]))
                let ts = Text(attr)
                let r = CGRect(x: mid.x-24, y: mid.y-10, width: 48, height: 20)
                ctx.fill(RoundedRectangle(cornerRadius: 6).path(in: r), with: .color(.secondary.opacity(0.15)))
                ctx.draw(ts, at: mid)

                guard mode == .breakdown else { return }
                // per-axis chips (fake example: +2×3, −1×5, +1×7)
                let chips = [("+2×3", Color.orange), ("−1×5", .pink), ("+1×7", .blue)]
                let offs: [CGPoint] = [ .init(x: -28, y: -18), .init(x: 0, y: 18), .init(x: 28, y: -14) ]
                for i in 0..<chips.count {
                    let text = chips[i].0
                    let col  = chips[i].1
                    let pos  = CGPoint(x: mid.x + offs[i].x, y: mid.y + offs[i].y)
                    let tAttr = AttributedString(text, attributes: .init([.font: UIFont.systemFont(ofSize: 9, weight: .semibold)]))
                    let t = Text(tAttr)
                    let rr = CGRect(x: pos.x-16, y: pos.y-8, width: 32, height: 16)
                    ctx.fill(RoundedRectangle(cornerRadius: 5).path(in: rr), with: .color(col.opacity(0.18)))
                    ctx.draw(t, at: pos)
                }
            }
        }
    }

    @ViewBuilder private var tenneyDistanceSection: some View {
        glassCard(
            icon: "ruler",
            title: "Interval Distance (Tenney Height)"
        ) {
            // Glass tiles like your theme/default pickers
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)], spacing: 12) {
                TenneyModeTile(mode: .off,       selected: tenneyMode == .off) {
                    withAnimation(.snappy) { tenneyDistanceModeRaw = TenneyDistanceMode.off.rawValue }
                }
                TenneyModeTile(mode: .total,     selected: tenneyMode == .total) {
                    withAnimation(.snappy) { tenneyDistanceModeRaw = TenneyDistanceMode.total.rawValue }
                }
                TenneyModeTile(mode: .breakdown,  selected: tenneyMode == .breakdown) {
                    withAnimation(.snappy) { tenneyDistanceModeRaw = TenneyDistanceMode.breakdown.rawValue }
                }
            }
            .animation(.snappy, value: tenneyMode)

            Text("Shows Tenney height between two selected ratios. “Total + Breakdown” places ±prime counts on each guide and the total at the midpoint. Hidden in the Settings preview.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    
    private let headerCollapseRange: CGFloat = 72
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    @State private var cfg = ToneOutputEngine.shared.config


    @ViewBuilder private var soundSection: some View {
        glassCard(
            icon: "waveform.and.mic",
            title: "Audio Engine & Headroom",
            subtitle: "Devices, tone, envelope, limiter"
        ) {
            AudioEnginePager(cfg: $cfg, safeAmp: $safeAmp)
        }

    }


    // MARK: Wave options + preview tile
    // Inside StudioConsoleView
    private static func previewWaveY(_ kind: ToneOutputEngine.GlobalWave, x: CGFloat) -> CGFloat {
        let t = x - floor(x)
        switch kind {
        case .foldedSine: return (abs(sin(2 * .pi * t)) * 2) - 1
        case .triangle:   return 1 - abs((t * 4).truncatingRemainder(dividingBy: 4) - 2)
        case .saw:        return (t * 2) - 1
        default:          return sin(2 * .pi * t)
        }
    }


    fileprivate struct WavePreview: View {
        let kind: ToneOutputEngine.GlobalWave
        var body: some View {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let mid = h / 2
                let amp = h * 0.36
                Canvas { ctx, size in
                    var p = Path()
                    let samples = max(24, Int(size.width))
                    for i in 0...samples {
                        let x01 = CGFloat(i) / CGFloat(samples)
                        let y01 = previewWaveY(kind, x: x01)   // ✅ now visible here
                        let px  = x01 * w
                        let py  = mid - (y01 * amp)
                        if i == 0 { p.move(to: .init(x: px, y: py)) }
                        else      { p.addLine(to: .init(x: px, y: py)) }
                    }
                    ctx.stroke(p, with: .color(.primary.opacity(0.85)), lineWidth: 6)
                }
            }
        }
    }

    fileprivate struct WaveTile: View {
        @Environment(\.tenneyTheme) private var theme

            private var grad: LinearGradient {
                LinearGradient(
                    colors: [theme.e3, theme.e5],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        let option: WaveOption
        let selected: Bool
        let tap: () -> Void
        var body: some View {
            VStack(spacing: 6) {
                Button(action: tap) {
                    ZStack(alignment: .topTrailing) {
                        if #available(iOS 26.0, *) {
                            GlassEffectContainer {
                                WavePreview(kind: option.wave)
                                    .padding(10)
                                    .frame(minWidth: 120, minHeight: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        selected
                                        ? AnyShapeStyle(grad)
                                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                        lineWidth: 1
                                    )
                            )

                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    WavePreview(kind: option.wave)
                                        .padding(10)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            selected
                                            ? AnyShapeStyle(grad)
                                            : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                            lineWidth: 1
                                        )
                                )

                                .frame(minWidth: 120, minHeight: 64)
                        }

                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(AnyShapeStyle(grad))
                                .blendMode(theme.isDark ? .screen : .darken)
                                .padding(6)
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(.plain)


                // Label OUTSIDE the button, secondary
                Text(option.label)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentTransition(.opacity)
        }
    }
    private func setWave(_ w: ToneOutputEngine.GlobalWave) {
        guard cfg.wave != w else { return }
        cfg.wave = w
        ToneOutputEngine.shared.config = cfg
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }


    // MARK: - About
    @ViewBuilder private var aboutSection: some View {
        glassCard(
            icon: "info.circle",
            title: "About Tenney",
            subtitle: "Version, acknowledgments, licenses"
        ) {
            NavigationLink {
                AboutView()
                    .toolbar(.visible, for: .navigationBar)
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tenney")
                            .font(.subheadline.weight(.semibold))
                        Text(versionString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About Tenney, Credits, and Licenses")
        }
    }


    // MARK: - Helpers
    

        private func updateA4() { /* legacy no-op; A4 now managed by SettingsA4PickerView */ }

    private func broadcastAll() {
        postSetting(SettingsKeys.labelDefault, labelDefault)
        postSetting(SettingsKeys.showRatioAlongHeji, showRatioAlong)
        postSetting(SettingsKeys.latticeThemeID, latticeThemeID)
        postSetting(SettingsKeys.nodeSize, nodeSize)
        postSetting(SettingsKeys.labelDensity, labelDensity)
        postSetting(SettingsKeys.guidesOn, guidesOn)
        postSetting(SettingsKeys.overlay7, overlay7)
        postSetting(SettingsKeys.overlay11, overlay11)
        postSetting(SettingsKeys.foldAudible, foldAudible)
        postSetting(SettingsKeys.safeAmp, safeAmp)
        postSetting(SettingsKeys.staffA4Hz, a4Staff)
        postSetting(SettingsKeys.stageDimLevel, stageDimLevel)
        postSetting(SettingsKeys.stageAccent, stageAccent)
        postSetting(SettingsKeys.stageHideStatus, stageHideStatus)
        postSetting(SettingsKeys.stageKeepAwake, stageKeepAwake)
        postSetting(SettingsKeys.stageMinimalUI, stageMinimalUI)
        postSetting(SettingsKeys.latticeDefaultZoomPreset, latticeDefaultZoomPresetRaw)
        postSetting(SettingsKeys.latticeHexGridMode, gridModeRaw)
        postSetting(SettingsKeys.latticeHexGridStrength, gridStrength)
        postSetting(SettingsKeys.latticeHexGridMajorEnabled, gridMajorEnabled)
        postSetting(SettingsKeys.latticeHexGridMajorEvery, gridMajorEvery)
        postSetting(SettingsKeys.latticeAlwaysRecenterOnQuit, latticeAlwaysRecenterOnQuit)
        
                // Always remember lattice view (remove user-facing toggle; enforce ON)
                UserDefaults.standard.set(true, forKey: SettingsKeys.latticeRememberLastView)
                postSetting(SettingsKeys.latticeRememberLastView, true)
    }

    // MARK: - Section Header + Glass Card

    private struct SectionHeader: View {
        let systemName: String
        let title: String
        var subtitle: String?
        @Environment(\.tenneyTheme) private var theme

        private var headerGradient: LinearGradient {
            LinearGradient(
                colors: [theme.e3, theme.e5],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Image(systemName: systemName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerGradient)
                        .blendMode(theme.isDark ? .screen : .darken)
                        .frame(width: 22)

                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.isDark ? Color.white : Color.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 4)
        }
    }


    
    private struct GlassCTAButton: View {
        let title: String
        let systemName: String
        let action: () -> Void

        var body: some View {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                Label(title, systemImage: systemName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)   // ⬅️ add this line
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if #available(iOS 26.0, *) {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(.clear)
                                    .glassEffect(
                                        .regular,
                                        in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }



    @ViewBuilder
    private func glassCard(
        icon systemName: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(systemName: systemName, title: title, subtitle: subtitle)
            content()
        }
        .padding(14)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    // Light, still a bit “liquid”, but not stacked on other glass
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)
                } else {
                    // Just a solid card on older OS; far more legible
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 10,
            x: 0,
            y: 4
        )
    }


    // Quick preset chip for dimming
    private struct DimPresetChip: View {
        let title: String
        let value: Double
        @Binding var current: Double
        var body: some View {
            Button {
                withAnimation(.snappy) { current = value }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text(title)
                    .font(.footnote.weight(current == value ? .semibold : .regular))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(current == value ? .thinMaterial : .ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(current == value ? Color.accentColor.opacity(0.35)
                                                          : Color.secondary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    
    // Accent tile matching your theme tiles (label outside, wave-style visuals)
    private struct StageAccentTile: View {
        let label: String
        let colors: [Color]
        let selected: Bool
        let tap: () -> Void

        var body: some View {
            VStack(spacing: 6) {
                Button(action: tap) {
                    ZStack(alignment: .topTrailing) {
                        if #available(iOS 26.0, *) {
                            GlassEffectContainer {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(minWidth: 100, minHeight: 44)
                            }
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                )
                                .frame(minWidth: 100, minHeight: 44)
                        }

                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical)
                                .padding(6)
                                .transition(.opacity)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? Color.accentColor.opacity(0.35)
                                             : Color.secondary.opacity(0.12), lineWidth: 1)
                    
                    )
                }
                .buttonStyle(.plain)

                Text(label)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

}

// MARK: - Lattice UI Live Preview + Stepper

 extension NodeSizeChoice {
    var displayName: String {
        switch self {
        case .s:     return "Small"
        case .m:     return "Medium"
        case .mplus: return "Medium+"
        case .l:     return "Large"
        }
    }
     
     // Used in Lattice UI inactive-page summaries.
         var summaryCode: String {
             switch self {
             case .s:     return "S"
             case .m:     return "M"
             case .mplus: return "M+"
             case .l:     return "L"
             }
         }
     
    var nodeDiameter: CGFloat {
        switch self {
        case .s:     return 22
        case .m:     return 32
        case .mplus: return 40
        case .l:     return 54
        }
    }
}

fileprivate let _nodeOrder: [NodeSizeChoice] = [.s, .m, .mplus, .l]

private struct NodeSizeStepperControl: View {
    @Binding var choice: NodeSizeChoice

    private func step(_ dir: Int) {
        guard let idx = _nodeOrder.firstIndex(of: choice) else { return }
        let next = max(0, min(_nodeOrder.count - 1, idx + dir))
        guard next != idx else { return }
        choice = _nodeOrder[next]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        HStack(spacing: 10) {
                    Button { withAnimation(.snappy) { step(-1) } } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
        
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted")
                            .symbolRenderingMode(.hierarchical)
        
                        VStack(spacing: 2) {
                            ViewThatFits(in: .horizontal) {
                                Text(choice.displayName)
                                Text(choice.summaryCode)
                            }
                            Text("Ø \(Int(choice.nodeDiameter))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        
                    Button { withAnimation(.snappy) { step(+1) } } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
    }
}

private struct ZoomPresetStepperControl: View {
    @Binding var preset: LatticeZoomPreset

    private func step(_ dir: Int) {
        let next = LatticeZoomPreset.step(from: preset, dir: dir)
        guard next != preset else { return }
        preset = next
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        HStack(spacing: 10) {
                    Button { withAnimation(.snappy) { step(-1) } } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .symbolRenderingMode(.hierarchical)

                        VStack(spacing: 2) {
                            ViewThatFits(in: .horizontal) {
                                Text(preset.title)
                                Text(String(preset.title.prefix(6)))
                            }
                            Text("Default zoom")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))

                    Button { withAnimation(.snappy) { step(+1) } } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
    }
}




private struct SettingsLatticePreview: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        GeometryReader { geo in
            // Use the real lattice screen; no gestures/taps in settings
            LatticeScreen()
              .environment(\.latticePreviewMode, true)
              .environment(\.latticePreviewHideChips, true)
              .allowsHitTesting(false)
              .disabled(true)

              .frame(width: geo.size.width, height: geo.size.height)
              .clipped()

        }
        // Keep sound off while preview is visible
        .onAppear { app.latticeAuditionOn = false }
    }
}

private extension CGPoint {
    static let topLeading     = CGPoint(x: 0, y: 0)
    static let bottomTrailing = CGPoint(x: 1, y: 1)
}
