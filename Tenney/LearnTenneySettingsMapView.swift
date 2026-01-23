import SwiftUI

private struct SettingsHotspot: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let valuePills: [String]
    let expandedRows: [String]
    let openAction: () -> Void
    let openLabel: String
}

struct LearnTenneySettingsMapView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var audioController = AudioSessionController.shared

    @AppStorage(SettingsKeys.tonicNameMode) private var tonicNameModeRaw: String = TonicNameMode.auto.rawValue
    @AppStorage(SettingsKeys.tonicE3) private var tonicE3: Int = 0
    @AppStorage(SettingsKeys.accidentalPreference) private var accidentalPreferenceRaw: String = AccidentalPreference.auto.rawValue
    @AppStorage(SettingsKeys.noteNameA4Hz) private var noteNameA4Hz: Double = 440
    @AppStorage(SettingsKeys.staffA4Hz) private var concertA4Hz: Double = 440

    @AppStorage(SettingsKeys.guidesOn) private var guidesOn: Bool = true
    @AppStorage(SettingsKeys.latticeAlwaysRecenterOnQuit) private var latticeAlwaysRecenterOnQuit: Bool = false
    @AppStorage(SettingsKeys.latticeSoundEnabled) private var latticeSoundEnabled: Bool = true
    @AppStorage(SettingsKeys.latticeDefaultZoomPreset) private var latticeDefaultZoomPresetRaw: String = LatticeZoomPreset.close.rawValue
    @AppStorage(SettingsKeys.tenneyDistanceMode) private var tenneyDistanceModeRaw: String = TenneyDistanceMode.breakdown.rawValue
    @AppStorage(SettingsKeys.labelDensity) private var labelDensity: Double = 0.65

    @AppStorage(SettingsKeys.lissaSnap) private var lissaSnapSmall: Bool = true
    @AppStorage(SettingsKeys.lissaMaxDen) private var lissaMaxDen: Int = 24
    @AppStorage(SettingsKeys.lissaDotMode) private var lissaDotMode: Bool = false
    @AppStorage(SettingsKeys.lissaHalfLife) private var lissaHalfLife: Double = 0.6

    @AppStorage(SettingsKeys.stageKeepAwake) private var stageKeepAwake: Bool = true
    @AppStorage(SettingsKeys.stageMinimalUI) private var stageMinimalUI: Bool = false

    @State private var expandedIDs = Set<String>()
    @State private var showEverything = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LearnGlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Learning Settings")
                            .font(.title2.weight(.semibold))
                        Text("Most power lives in a few panels—tap to open.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                ForEach(hotspots) { hotspot in
                    SettingsHotspotCard(
                        hotspot: hotspot,
                        isExpanded: expandedIDs.contains(hotspot.id)
                    ) {
                        toggleExpanded(hotspot.id)
                    }
                }

                LearnGlassCard {
                    DisclosureGroup("Show everything", isExpanded: $showEverything) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Root Studio")
                            Text("Lattice UI · View · Grid · Distance")
                            Text("Oscilloscope · View · Trace · Persistence · Snapping")
                            Text("Audio & I/O · Device · Tone · Envelope · Headroom")
                            Text("Tuner · Stage Mode")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .onAppear { audioController.refreshAll() }
    }

    private func toggleExpanded(_ id: String) {
        let update = {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                update()
            }
        }
    }

    private var hotspots: [SettingsHotspot] {
        [
            SettingsHotspot(
                id: "root-naming",
                title: "Root & Naming",
                subtitle: "What note is 1/1?",
                systemImage: "tuningfork",
                valuePills: [
                    "Tonic: \(tonicDisplayName)",
                    "Root: \(formatHz(app.rootHz))"
                ],
                expandedRows: [
                    "Tonic naming",
                    "Current",
                    "Suggested",
                    "Manual",
                    "Letter",
                    "Accidental",
                    "Preview"
                ],
                openAction: { openRootStudioSection("nameAs") },
                openLabel: "Open Root & Naming settings"
            ),
            SettingsHotspot(
                id: "concert-a4",
                title: "Concert Pitch / A4",
                subtitle: nil,
                systemImage: "music.quarternote.3",
                valuePills: [
                    "A4: \(formatHz(concertA4Hz))"
                ],
                expandedRows: [
                    "440",
                    "442",
                    "Custom",
                    "A4"
                ],
                openAction: { openRootStudioTab("a4") },
                openLabel: "Open Concert Pitch settings"
            ),
            SettingsHotspot(
                id: "pro-audio",
                title: "Pro Audio (Mic / Device)",
                subtitle: "Mic device + tone shaping.",
                systemImage: "waveform.and.mic",
                valuePills: [
                    "Input: \(inputDeviceName)"
                ],
                expandedRows: [
                    "Routing",
                    "Output",
                    "Force Built-in Speaker",
                    "Engine",
                    "Diagnostics"
                ],
                openAction: { openSettings(.audio, audioPage: .device) },
                openLabel: "Open Pro Audio Device settings"
            ),
            SettingsHotspot(
                id: "lattice-view",
                title: "Lattice Grid / View",
                subtitle: nil,
                systemImage: "square.grid.2x2",
                valuePills: [
                    "Axes: \(onOff(guidesOn)) · Recenter: \(onOff(latticeAlwaysRecenterOnQuit))",
                    "Sound: \(onOff(latticeSoundEnabled)) · Zoom: \(zoomPresetTitle)"
                ],
                expandedRows: [
                    "Axis",
                    "Always Recenter",
                    "Sound",
                    "Zoom Preset",
                    "Node Size",
                    "Label Density",
                    "Connection Mode"
                ],
                openAction: { openSettings(.lattice, latticePage: .view) },
                openLabel: "Open Lattice View settings"
            ),
            SettingsHotspot(
                id: "snapping",
                title: "Snapping",
                subtitle: "How the lattice ‘chooses’ ratios.",
                systemImage: "number",
                valuePills: [
                    "Favor small closure: \(onOff(lissaSnapSmall))",
                    "Max den: \(lissaMaxDen)"
                ],
                expandedRows: [
                    "Favor small closure",
                    "Max den"
                ],
                openAction: { openSettings(.oscilloscope, oscilloscopePage: .snapping) },
                openLabel: "Open Snapping settings"
            ),
            SettingsHotspot(
                id: "distance",
                title: "Distance",
                subtitle: "How closeness is measured.",
                systemImage: "ruler",
                valuePills: [
                    "Distance: \(distanceModeTitle)",
                    "Cents ticks: \(onOff(centsTickLabelsOn))"
                ],
                expandedRows: [
                    "Off",
                    "Total",
                    "Total + Breakdown"
                ],
                openAction: { openSettings(.lattice, latticePage: .distance) },
                openLabel: "Open Distance settings"
            ),
            SettingsHotspot(
                id: "scope-trace",
                title: "Scope / Trace / Persistence",
                subtitle: nil,
                systemImage: "waveform.path.ecg",
                valuePills: [
                    "Trace: \(traceModeLabel)",
                    "Half-life: \(formatHalfLife(lissaHalfLife))"
                ],
                expandedRows: [
                    "Ribbon Width",
                    "Dots",
                    "Live Samples",
                    "Alpha",
                    "Persistence",
                    "Half-life"
                ],
                openAction: { openSettings(.oscilloscope, oscilloscopePage: .trace) },
                openLabel: "Open Scope settings"
            ),
            SettingsHotspot(
                id: "stage-display",
                title: "Stage / Display",
                subtitle: nil,
                systemImage: "rectangle.on.rectangle.angled",
                valuePills: [
                    "Keep awake: \(onOff(stageKeepAwake))",
                    "Minimal UI: \(onOff(stageMinimalUI))"
                ],
                expandedRows: [
                    "Stage dimmer",
                    "Dim level",
                    "Accent color",
                    "Hide status bar",
                    "Keep screen awake",
                    "Minimal UI"
                ],
                openAction: { openSettings(.tuner) },
                openLabel: "Open Stage display settings"
            )
        ]
    }

    private var tonicDisplayName: String {
        let mode = TonicNameMode(rawValue: tonicNameModeRaw) ?? .auto
        let preference = AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
        switch mode {
        case .manual:
            return TonicSpelling(e3: tonicE3).displayText
        case .auto:
            return TonicSpelling.from(
                rootHz: app.rootHz,
                noteNameA4Hz: noteNameA4Hz,
                preference: preference
            )?.displayText ?? TonicSpelling(e3: tonicE3).displayText
        }
    }

    private var inputDeviceName: String {
        if let selected = audioController.availableInputs.first(where: { $0.uid == audioController.selectedInputUID }) {
            return selected.portName
        }
        return audioController.availableInputs.first?.portName ?? "System"
    }

    private var zoomPresetTitle: String {
        LatticeZoomPreset(rawValue: latticeDefaultZoomPresetRaw)?.title ?? "Standard"
    }

    private var distanceModeTitle: String {
        TenneyDistanceMode(rawValue: tenneyDistanceModeRaw)?.title ?? "Total"
    }

    private var centsTickLabelsOn: Bool {
        labelDensity > 0.01
    }

    private var traceModeLabel: String {
        lissaDotMode ? "Dots" : "Ribbon"
    }

    private func openRootStudioTab(_ tabRaw: String) {
        NotificationCenter.default.post(name: .requestRootStudioTab, object: tabRaw)
    }

    private func openRootStudioSection(_ section: String) {
        NotificationCenter.default.post(name: .requestRootStudioSection, object: section)
    }

    private func openSettings(
        _ category: StudioConsoleView.SettingsCategory,
        latticePage: SettingsDeepLinkLatticePage? = nil,
        oscilloscopePage: SettingsDeepLinkOscilloscopePage? = nil,
        audioPage: SettingsDeepLinkAudioPage? = nil
    ) {
        SettingsDeepLinkCenter.shared.open(
            SettingsDeepLink(
                category: category,
                latticePage: latticePage,
                oscilloscopePage: oscilloscopePage,
                audioPage: audioPage
            )
        )
    }

    private func formatHz(_ value: Double) -> String {
        if value.rounded(.down) == value {
            return "\(Int(value)) Hz"
        }
        return String(format: "%.1f Hz", value)
    }

    private func formatHalfLife(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }

    private func onOff(_ v: Bool) -> String { v ? "On" : "Off" }
}

private struct SettingsHotspotCard: View {
    let hotspot: SettingsHotspot
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LearnGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hotspot.systemImage)
                        .font(.title3.weight(.semibold))
                        .frame(width: 28)
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(hotspot.title)
                            .font(.headline)
                        if let subtitle = hotspot.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if !hotspot.valuePills.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(hotspot.valuePills, id: \.self) { pill in
                                    Text(pill)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.thinMaterial, in: Capsule())
                                }
                            }
                        }
                    }

                    Spacer()

                    Button(action: hotspot.openAction) {
                        Text("Open")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .modifier(GlassRoundedRect(corner: 12))
                    }
                    .buttonStyle(GlassPressFeedback())
                    .accessibilityLabel(Text(hotspot.openLabel))
                }

                if !hotspot.expandedRows.isEmpty {
                    Button(action: toggleExpanded) {
                        HStack(spacing: 6) {
                            Text("What’s inside")
                                .font(.caption.weight(.semibold))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(isExpanded ? "Hide what's inside" : "Show what's inside"))

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(hotspot.expandedRows, id: \.self) { row in
                                Text(row)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
}
