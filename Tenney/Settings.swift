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
    private struct Option: Identifiable { let id: String; let label: String; let colors: [Color] }
    private let options: [Option] = [
        .init(id: "system", label: "System", colors: [.accentColor, .accentColor.opacity(0.6)]),
        .init(id: "amber",  label: "Amber",  colors: [.orange, .yellow]),
        .init(id: "red",    label: "Red",    colors: [.red, .pink])
    ]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(options) { opt in
                let on = (selected == opt.id)
                Button {
                    withAnimation(.snappy) { selected = opt.id }
                } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: opt.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(on ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.2), lineWidth: on ? 2 : 1)
                            )
                        Text(opt.label)
                            .font(.caption2.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? .primary : .secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            let on = invertVisual ? !isOn : isOn
            HStack(spacing: 8) {
                Image(systemName: on ? systemNameOn : systemNameOff)
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
}


struct StudioConsoleView: View {
    @AppStorage(SettingsKeys.defaultView) private var defaultView: String = "tuner" // "lattice" | "tuner"

    @EnvironmentObject private var model: AppModel   // ⬅️ bring AppModel into scope
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.colorScheme) private var systemScheme

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
    
        // Local scheme override for immediate visual update inside Settings
        private var settingsScheme: ColorScheme? {
            switch ThemeStyleChoice(rawValue: themeStyleRaw) ?? .system {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    // Sound
    @AppStorage(SettingsKeys.attackMs)   private var attackMs: Double = 10
    @AppStorage(SettingsKeys.releaseSec) private var releaseSec: Double = 0.5
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
        }
        // Apply the hidden flag to this stack so the chip has visible effect here
        .statusBar(hidden: stageHideStatus)
        .preferredColorScheme(settingsScheme)
        .toolbar { doneToolbar }
        .navigationBarTitleDisplayMode(.inline)
        // Move all listeners off the main expression tree
        .background(
            SettingsChangeSinks(
                defaultView: $defaultView,
                a4Staff: $a4Staff,
                labelDefault: $labelDefault,
                showRatioAlong: $showRatioAlong,
                nodeSize: $nodeSize,
                labelDensity: $labelDensity,
                guidesOn: $guidesOn,
                overlay7: $overlay7,
                overlay11: $overlay11,
                foldAudible: $foldAudible,
                attackMs: $attackMs,
                releaseSec: $releaseSec,
                safeAmp: $safeAmp,
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
                broadcastAll: broadcastAll
            )
        )
    }

    // MARK: - Split content
    private var contentStack: some View {
        ZStack {
            backgroundGlass
            VStack(spacing: 14) {
                headerView
                ScrollView { gridView }
            }
            inkOverlay
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: (hSizeClass == .compact ? 34 : 30), weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tuner & Lattice Algorithm Configs")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var gridView: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            latticeUISection
            themeSection
            tenneyDistanceSection
            stageSection
            defaultViewSection
            // labelingSection
            // overlaysSection
            soundSection
            ProAudioSettingsView()
            tuningSection
            quickSetupCard
            aboutSection
            // ⚠️ Avoid Spacer() inside grid – it confuses layout and adds type load
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

    @ViewBuilder
    private var quickSetupCard: some View {
        glassCard("Quick Setup Wizard") {
            HStack {
                Text("Run the first-time setup again.")
                    .foregroundStyle(.gray, .primary)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.showOnboardingWizard = true
                    dismiss()
                } label: {
                    Label("Rerun Setup", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.callout)
            .foregroundStyle(.white, .secondary)
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
        @Binding var defaultView: String
        @Binding var a4Staff: Double
        @Binding var labelDefault: String
        @Binding var showRatioAlong: Bool
        @Binding var nodeSize: String
        @Binding var labelDensity: Double
        @Binding var guidesOn: Bool
        @Binding var overlay7: Bool
        @Binding var overlay11: Bool
        @Binding var foldAudible: Bool
        @Binding var attackMs: Double
        @Binding var releaseSec: Double
        @Binding var safeAmp: Double
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

        @State private var lastEffectiveIsDark: Bool = false

        var body: some View {
            Color.clear
                .onAppear {
                    broadcastAll()
                    lastEffectiveIsDark = effectiveIsDark
                }
                .onChange(of: defaultView)   { postSetting(SettingsKeys.defaultView, $0) }
                .onChange(of: a4Staff)       { postSetting(SettingsKeys.staffA4Hz, $0) }
                .onChange(of: labelDefault)  { postSetting(SettingsKeys.labelDefault, $0) }
                .onChange(of: showRatioAlong){ postSetting(SettingsKeys.showRatioAlongHeji, $0) }
                .onChange(of: nodeSize)      { postSetting(SettingsKeys.nodeSize, $0) }
                .onChange(of: labelDensity)  { postSetting(SettingsKeys.labelDensity, $0) }
                .onChange(of: guidesOn)      { postSetting(SettingsKeys.guidesOn, $0) }
                .onChange(of: overlay7)      { postSetting(SettingsKeys.overlay7, $0) }
                .onChange(of: overlay11)     { postSetting(SettingsKeys.overlay11, $0) }
                .onChange(of: foldAudible)   { postSetting(SettingsKeys.foldAudible, $0) }
                .onChange(of: attackMs)      { postSetting(SettingsKeys.attackMs, $0) }
                .onChange(of: releaseSec)    { postSetting(SettingsKeys.releaseSec, $0) }
                .onChange(of: safeAmp)       { postSetting(SettingsKeys.safeAmp, $0) }
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
        if #available(iOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular,
                             in: RoundedRectangle(cornerRadius: 0, style: .continuous))
        } else {
            Color.clear.background(.ultraThinMaterial)
        }
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

    @ViewBuilder private var stageSection: some View {
        glassCard("Stage Mode") {
            VStack(alignment: .leading, spacing: 14) {

                // == Background dimming (now lockable in explicit Dark) ==
                let dimLocked = isExplicitDarkStyle

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Background dimming")
                        Spacer()
                        if dimLocked {
                            LockTag(text: "Dark Mode")
                        }
                        Text("\(Int(stageDimLevel * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    // Quick presets
                    HStack(spacing: 8) {
                        DimPresetChip(title: "Off",  value: 0.00, current: $stageDimLevel)
                        DimPresetChip(title: "25%", value: 0.25, current: $stageDimLevel)
                        DimPresetChip(title: "50%", value: 0.50, current: $stageDimLevel)
                        DimPresetChip(title: "75%", value: 0.75, current: $stageDimLevel)
                    }
                    .disabled(dimLocked)
                    .opacity(dimLocked ? 0.5 : 1)

                    // Fine-tune
                    Slider(value: $stageDimLevel, in: 0.0...0.75, step: 0.01)
                        .disabled(dimLocked)
                        .opacity(dimLocked ? 0.5 : 1)

                    // Visual mini-preview (shows a lock overlay when disabled)
                    StageDimMiniPreview(dim: stageDimLevel, locked: dimLocked)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )

                    // Clarifying captions
                    Group {
                        if dimLocked {
                            Text("Background dimming doesn’t apply in Dark Mode. Switch to Light or Auto to adjust.")
                        } else if isAutoAndCurrentlyDark {
                            Text("You’re in Auto (Dark right now). Dimming only affects the background when the app is in Light.")
                        } else {
                            EmptyView()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: stageDimLevel) { v in postSetting(SettingsKeys.stageDimLevel, v) }

                // == Accent for dark stages ==
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent for dark stages")
                    HStack(spacing: 12) {
                        StageAccentTile(
                            label: "System",
                            colors: [.accentColor, .accentColor.opacity(0.55)],
                            selected: stageAccent == "system"
                        ) { stageAccent = "system" }

                        StageAccentTile(
                            label: "Amber",
                            colors: [.orange, .yellow],
                            selected: stageAccent == "amber"
                        ) { stageAccent = "amber" }

                        StageAccentTile(
                            label: "Red",
                            colors: [.red, .pink],
                            selected: stageAccent == "red"
                        ) { stageAccent = "red" }
                    }
                    .onChange(of: stageAccent) { v in postSetting(SettingsKeys.stageAccent, v) }

                    Text("Amber/Red preserves night vision and reduces blue light; affects accent UI and halos, not pitch detection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // == Behavior (one line; scrolls if tight) ==
                VStack(alignment: .leading, spacing: 6) {
                    Text("Behavior")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // "Status Bar" — ON = visible, OFF = hidden (storage remains: stageHideStatus == hidden)
                            // "Status Bar" — ON = visible, OFF = hidden
                                                        StageToggleChip(
                                                            title: "Status Bar",
                                                            systemNameOn: "rectangle.topthird.inset",          // ON (visible)
                                                            systemNameOff: "rectangle.topthird.inset.filled",   // OFF (hidden)
                                                            isOn: Binding(
                                                                get: { !stageHideStatus },       // show = true
                                                                set: { stageHideStatus = !$0 }   // stored flag is 'hidden'
                                                            )
                                                        )
                            StageToggleChip(
                                title: "Keep Awake",
                                systemNameOn: "moon.zzz.fill",
                                systemNameOff: "moon.zzz",
                                isOn: $stageKeepAwake
                            )
                            StageToggleChip(
                                title: "Minimal UI",
                                systemNameOn: "star.slash.fill",
                                systemNameOff: "star.slash",
                                isOn: $stageMinimalUI
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onChange(of: stageHideStatus) { v in postSetting(SettingsKeys.stageHideStatus, v) }
                .onChange(of: stageKeepAwake)  { v in postSetting(SettingsKeys.stageKeepAwake, v) }
                .onChange(of: stageMinimalUI)  { v in postSetting(SettingsKeys.stageMinimalUI, v) }
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
                LinearGradient(colors: [.gray.opacity(0.25), .gray.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 30)

                Color.black.opacity(dim)

                if locked {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill").imageScale(.small)
                        Text("Disabled in Dark").font(.caption2)
                    }
                    .padding(8)
                    .foregroundStyle(.secondary)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .contentShape(Rectangle())
            .opacity(locked ? 0.6 : 1)
        }
    }


    @ViewBuilder private var tuningSection: some View {
            glassCard("Equal-Temperament Reference (A4)") {
                SettingsA4PickerView()
            }
        }

    @ViewBuilder private var labelingSection: some View {
        glassCard("Labeling") {
            Picker("Default", selection: $labelDefault) {
                Text("Ratio").tag("ratio")
                Text("HEJI").tag("heji")
            }
            .pickerStyle(.segmented)

            Toggle("Show ratio alongside HEJI", isOn: $showRatioAlong)

            Text("Affects Lattice info cards and Builder labels.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var defaultViewSection: some View {
        glassCard("Default Screen at Launch") {
            HStack(spacing: 12) {
                GlassSelectTile(title: "Lattice", isOn: defaultView == "lattice") {
                    withAnimation(.snappy) { defaultView = "lattice" }
                }
                GlassSelectTile(title: "Tuner", isOn: defaultView == "tuner") {
                    withAnimation(.snappy) { defaultView = "tuner" }
                }
            }
            Text("Matches the first-run setup. Reorders the Utility Bar so your default is on the left.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }


    @ViewBuilder private var latticeUISection: some View {
        glassCard("Lattice UI") {
            VStack(alignment: .leading, spacing: 12) {

                // ✅ Real lattice preview (uses your actual nodes + guides)
                Group {
                    if #available(iOS 26.0, *) {
                        GlassEffectContainer {
                            SettingsLatticePreview()
                                .environment(\.latticePreviewMode, true)
                                .environment(\.latticePreviewHideChips, true)
                                .allowsHitTesting(false)
                                .disabled(true)
                                .frame(height: 180)
                                .scaleEffect(0.92, anchor: .center)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
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
                            .scaleEffect(0.92, anchor: .center)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                    }
                }


                // One middle window control: left/right stepper + current size label
                NodeSizeStepperControl(
                    choice: Binding(
                        get: { NodeSizeChoice(rawValue: nodeSize) ?? .m },
                        set: { nodeSize = $0.rawValue }
                    )
                )

                // Live controls (update preview instantly)
                HStack(spacing: 12) {
                    Text("Label density")
                    Slider(value: $labelDensity, in: 0...1, step: 0.05)
                    Text("\(Int(labelDensity * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }

                Toggle("Guides on", isOn: $guidesOn)

              //  Toggle("Fold audition to 20–5k Hz", isOn: $foldAudible)

                Text("Node size affects pad size & hit-target; density controls label fade.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }


    @ViewBuilder private var themeSection: some View {
        glassCard("Appearance · Lattice Theme") {
            SettingsThemePickerView()
            Text("Themes change node colors (3- vs 5-limit) and high-prime overlays. Guides and selection halos remain unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }


    @ViewBuilder private var overlaysSection: some View {
        glassCard("Overlays") {
            Toggle("Show 7-limit overlay", isOn: $overlay7)
            Toggle("Show 11-limit overlay", isOn: $overlay11)
            Text("Toggles higher-prime ghost nodes.")
                .font(.footnote).foregroundStyle(.secondary)
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
        glassCard("Interval Distance (Tenney Height)") {
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

    @State private var cfg = ToneOutputEngine.shared.config

    @ViewBuilder private var soundSection: some View {
        glassCard("Sine Envelope & Headroom") {
            VStack(alignment: .leading, spacing: 14) {

                // Waveform tiles (same visual treatment as theme/default pickers)
                // Waveform tiles (glass + mini preview; label outside)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 12)], spacing: 10) {
                    ForEach(Array(waveOptions.enumerated()), id: \.offset) { _, opt in
                        WaveTile(option: opt, selected: cfg.wave == opt.wave) {
                            withAnimation(.snappy) { setWave(opt.wave) }
                        }
                    }
                }
                .animation(.snappy, value: cfg.wave)


                .pickerStyle(.segmented)

                // Fold
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

                // Drive
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

                // Attack
                HStack {
                    Text("Attack")
                    Slider(
                        value: Binding(
                            get: { cfg.attackMs },
                            set: { cfg.attackMs = $0; ToneOutputEngine.shared.config = cfg }
                        ),
                        in: 1...200
                    )
                    Text("\(Int(cfg.attackMs))ms").monospacedDigit()
                }

                // Release
                HStack {
                    Text("Release")
                    Slider(
                        value: Binding(
                            get: { cfg.releaseMs },
                            set: { cfg.releaseMs = $0; ToneOutputEngine.shared.config = cfg }
                        ),
                        in: 20...2000
                    )
                    Text("\(Int(cfg.releaseMs))ms").monospacedDigit()
                }

                // Limiter
                Toggle(
                    "Limiter",
                    isOn: Binding(
                        get: { cfg.limiterOn },
                        set: { cfg.limiterOn = $0; ToneOutputEngine.shared.config = cfg }
                    )
                )
            }
            .onChange(of: cfg) { ToneOutputEngine.shared.config = $0 }
        }
    }

    // MARK: Wave options + preview tile

    // Put these at file scope (outside any struct)

    fileprivate struct WaveOption { let wave: ToneOutputEngine.GlobalWave; let label: String }
    fileprivate let waveOptions: [WaveOption] = [
        .init(wave: .foldedSine, label: "Folded Sine"),
        .init(wave: .triangle,   label: "Triangle"),
        .init(wave: .saw,        label: "Saw")
    ]

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
                                    .stroke(selected ? Color.accentColor.opacity(0.35)
                                                     : Color.secondary.opacity(0.12), lineWidth: 1)
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
                                        .stroke(selected ? Color.accentColor.opacity(0.35)
                                                         : Color.secondary.opacity(0.12), lineWidth: 1)
                                )
                                .frame(minWidth: 120, minHeight: 64)
                        }

                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical)
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
            glassCard("About · Credits & Licenses") {
                // One clear entry that pushes the full AboutView
                NavigationLink {
                    AboutView()
                } label: {
                    HStack(spacing: 12) {
                        // App icon if available; otherwise a system symbol
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tenney").font(.subheadline.weight(.semibold))
                            Text(versionString)
                                .font(.caption).foregroundStyle(.secondary)
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
        postSetting(SettingsKeys.attackMs, attackMs)
        postSetting(SettingsKeys.releaseSec, releaseSec)
        postSetting(SettingsKeys.safeAmp, safeAmp)
        postSetting(SettingsKeys.staffA4Hz, a4Staff)
        postSetting(SettingsKeys.stageDimLevel, stageDimLevel)
        postSetting(SettingsKeys.stageAccent, stageAccent)
        postSetting(SettingsKeys.stageHideStatus, stageHideStatus)
        postSetting(SettingsKeys.stageKeepAwake, stageKeepAwake)
        postSetting(SettingsKeys.stageMinimalUI, stageMinimalUI)

    }

    // MARK: - Glass primitive
    @ViewBuilder private func glassCard(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(14)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular,
                                     in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                }
            }
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
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(choice.displayName).font(.headline)
                Text("Tap arrows to change size").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button { withAnimation(.snappy) { step(+1) } } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain)
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
              .environment(\.latticePreviewHideDistance, true) // ⬅️ hide distance overlay in preview
              .allowsHitTesting(false)
              .disabled(true)

                .frame(width: geo.size.width, height: geo.size.height)
                // A slight scale to keep a nice crop in the preview window;
                // adjust if your scene already fits tightly.
                .scaleEffect(0.92, anchor: .center)
                .clipped()
        }
        // Keep sound off while preview is visible
        .onAppear { app.latticeAuditionOn = false }
    }
}
