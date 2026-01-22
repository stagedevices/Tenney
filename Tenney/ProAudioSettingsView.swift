//
//  ProAudioSettingsView.swift
//  Tenney
//
//  Pro Audio Settings View vNext
//
import AVFoundation
import AVKit
import SwiftUI

public struct ProAudioSettingsView: View {

    // Whether to draw its own rounded-rect card background and title.
    // When false, we render "flat" so the parent can supply the material layer.
    private let showsOuterCard: Bool

    @StateObject private var controller = AudioSessionController.shared
    @State private var preferredChannelMode: ChannelMode = .stereo
    @State private var monitorInput: Bool = false
    @State private var micPermission: MicrophonePermission.Status = .undetermined
    @State private var advancedExpanded: Bool = false
    @State private var diagnosticsExpanded: Bool = false
    @Environment(\.tenneyTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let deviceCols = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12, alignment: .top)]
    private let optCols = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12, alignment: .top)]

    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }

    public init(showsOuterCard: Bool = true) {
        self.showsOuterCard = showsOuterCard
    }

    public var body: some View {
        Group {
            if showsOuterCard {
                outerCard("Pro Audio") {
                    coreContent
                }
            } else {
                coreContent
            }
        }
        .onAppear {
            controller.refreshAll()
            micPermission = MicrophonePermission.status()
        }
    }

    @ViewBuilder
    private var coreContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            routingCard
            engineCard
            if controller.supportsInput || micPermission != .granted {
                inputMonitoringCard
            }
            diagnosticsCard
        }
    }

    // MARK: - Routing

    private var routingCard: some View {
        card(prominent: true) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow(title: "Routing", icon: "hifispeaker.2")

                if let banner = controller.routeChangeBanner {
                    Text(banner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                        .transition(.opacity)
                }

                OutputPickerRow(
                    icon: outputIcon(for: controller.routeOutputs.first?.portType),
                    summary: controller.currentRouteSummary
                )

                RouteInspectorChips(chips: routeInspectorChips)

                if shouldShowReinitializeButton {
                    ReinitializeRouteButton {
                        controller.reinitializeOutputRoute()
                    }
                }

                Toggle("Force Built-in Speaker (when allowed)", isOn: Binding(
                    get: { controller.preferSpeaker },
                    set: { controller.setPreferSpeaker($0) }
                ))
                .toggleStyle(.switch)

                Text("Only applies in Play & Record; ignored for USB/AirPlay.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 0.18), value: controller.routeChangeBanner)
        }
    }

    private var routeInspectorChips: [RouteChip] {
        let outputs = controller.routeOutputs
        let portType = outputs.first?.portType
        let deviceName = outputs.first?.name ?? "System Output"
        let portLabel = portTypeLabel(portType)
        let latency = latencyLabel(for: portType)
        let channels = controller.negotiatedOutputChannels
        let rate = Int(controller.negotiatedSampleRate.rounded())
        let buffer = controller.negotiatedBufferFrames
        let rateBufferLabel = rate > 0 && buffer > 0 ? "\(rate / 1000)k · \(buffer)f" : "--"

        return [
            RouteChip(label: deviceName, systemImage: "headphones"),
            RouteChip(label: portLabel, systemImage: "cable.connector"),
            RouteChip(label: latency, systemImage: "speedometer"),
            RouteChip(label: "\(channels)ch", systemImage: "circle.grid.3x3"),
            RouteChip(label: rateBufferLabel, systemImage: "waveform.path.ecg")
        ]
    }

    private var shouldShowReinitializeButton: Bool {
        let outputs = controller.routeOutputs
        let isWireless = outputs.contains {
            $0.portType == .airPlay || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE || $0.portType == .bluetoothHFP
        }
        return (isWireless && controller.isEngineActive) || controller.lastRouteChangeFailed
    }

    // MARK: - Engine

    private var engineCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                headerRow(title: "Engine", icon: "waveform.path.ecg")

                EngineStatusCapsule(
                    state: controller.engineState,
                    rate: controller.negotiatedSampleRate,
                    bufferFrames: controller.negotiatedBufferFrames,
                    channels: controller.negotiatedOutputChannels,
                    onResume: controller.engineState == .interrupted ? {
                        controller.resumeEngineIfNeeded()
                    } : nil
                )

                performancePresets

                DisclosureGroup(isExpanded: $advancedExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        sampleRateOverrides
                        bufferOverrides
                        channelModeOverrides
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Advanced")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var performancePresets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Presets")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)], spacing: 12) {
                PresetTile(
                    title: "Low Latency",
                    subtitle: "48k · 128–256f",
                    selected: isPresetSelected(sampleRate: 48_000, buffer: 128)
                ) {
                    applyPreset(sampleRate: 48_000, bufferFrames: 128)
                }

                PresetTile(
                    title: "Stable",
                    subtitle: "48k · 256–512f",
                    selected: isPresetSelected(sampleRate: 48_000, buffer: 256)
                ) {
                    applyPreset(sampleRate: 48_000, bufferFrames: 256)
                }

                PresetTile(
                    title: "High Quality",
                    subtitle: "96k · 512f+",
                    selected: isPresetSelected(sampleRate: 96_000, buffer: 512)
                ) {
                    applyPreset(sampleRate: 96_000, bufferFrames: 512)
                }
            }
        }
    }

    private var sampleRateOverrides: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sample Rate")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: optCols, spacing: 12) {
                RateTile(label: "44.1 kHz", rate: 44_100, current: controller.preferredSampleRate) {
                    controller.applyPreferences(sampleRate: 44_100)
                }
                RateTile(label: "48 kHz", rate: 48_000, current: controller.preferredSampleRate) {
                    controller.applyPreferences(sampleRate: 48_000)
                }
                RateTile(label: "96 kHz", rate: 96_000, current: controller.preferredSampleRate) {
                    controller.applyPreferences(sampleRate: 96_000)
                }
            }

            if let badge = sampleRateBadgeText {
                BadgeText(text: badge)
            }
        }
    }

    private var bufferOverrides: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buffer Size (frames)")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: optCols, spacing: 12) {
                BufferTile(size: 128, current: controller.preferredBufferFrames) { controller.applyPreferences(bufferFrames: 128) }
                BufferTile(size: 256, current: controller.preferredBufferFrames) { controller.applyPreferences(bufferFrames: 256) }
                BufferTile(size: 512, current: controller.preferredBufferFrames) { controller.applyPreferences(bufferFrames: 512) }
                BufferTile(size: 1024, current: controller.preferredBufferFrames) { controller.applyPreferences(bufferFrames: 1024) }
            }

            if let badge = bufferBadgeText {
                BadgeText(text: badge)
            }
        }
    }

    private var channelModeOverrides: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channel Mode")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: optCols, spacing: 12) {
                ChannelModeTile(label: "Mono", selected: preferredChannelMode == .mono) {
                    preferredChannelMode = .mono
                }
                ChannelModeTile(label: "Stereo", selected: preferredChannelMode == .stereo) {
                    preferredChannelMode = .stereo
                }
                ChannelModeTile(
                    label: "Multi",
                    selected: preferredChannelMode == .multi,
                    disabled: !supportsMultiChannel
                ) {
                    preferredChannelMode = .multi
                }
            }

            if !supportsMultiChannel {
                BadgeText(text: "Route supports up to 2 channels")
            }
        }
    }

    // MARK: - Input + Monitoring

    private var inputMonitoringCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                headerRow(title: "Input + Monitoring", icon: "waveform.badge.mic")

                if micPermission != .granted {
                    MicrophonePermissionCTA(status: micPermission) {
                        handleMicPermissionRequest()
                    }
                }

                if micPermission == .granted {
                    LazyVGrid(columns: deviceCols, spacing: 12) {
                        ForEach(controller.availableInputs, id: \.uid) { input in
                            DeviceTile(
                                title: displayName(for: input),
                                subtitle: subtitle(for: input),
                                symbol: symbolName(for: input),
                                selected: controller.selectedInputUID == input.uid
                            ) {
                                controller.selectInput(input)
                            }
                        }
                    }
                    if controller.availableInputs.isEmpty {
                        EmptyDevicesFallback()
                    }
                }

                Toggle("Input Monitoring", isOn: $monitorInput)
                if monitorInput {
                    Text("Make sure outputs are isolated to avoid feedback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        DiagnosticsSection(outputs: controller.routeOutputs)
                        diagnosticsSessionDetails

                        Button {
                            controller.copyDiagnostics()
                        } label: {
                            Label("Copy Diagnostics", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Diagnostics")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var diagnosticsSessionDetails: some View {
        let session = AVAudioSession.sharedInstance()
        let lastRouteTime = controller.lastRouteChangeTimestamp?.formatted(date: .numeric, time: .standard) ?? "n/a"

        return VStack(alignment: .leading, spacing: 6) {
            DiagnosticsRow(label: "Category", value: session.category.rawValue)
            DiagnosticsRow(label: "Mode", value: session.mode.rawValue)
            DiagnosticsRow(label: "Options", value: session.categoryOptions.prettyList)
            DiagnosticsRow(label: "IO Buffer Duration", value: String(format: "%.4fs", session.ioBufferDuration))
            DiagnosticsRow(label: "Preferred SR", value: "\(Int(controller.preferredSampleRate)) Hz")
            DiagnosticsRow(label: "Actual SR", value: "\(Int(controller.negotiatedSampleRate)) Hz")
            DiagnosticsRow(label: "Preferred Buffer", value: "\(controller.preferredBufferFrames) f")
            DiagnosticsRow(label: "Actual Buffer", value: "\(controller.negotiatedBufferFrames) f")
            DiagnosticsRow(label: "Last Route Change", value: "\(controller.lastRouteChangeReason) · \(lastRouteTime)")
        }
    }

    // MARK: - Helpers

    private var supportsMultiChannel: Bool {
        controller.negotiatedOutputChannels > 2
    }

    private func applyPreset(sampleRate: Double, bufferFrames: Int) {
        controller.applyPreferences(sampleRate: sampleRate, bufferFrames: bufferFrames)
    }

    private func isPresetSelected(sampleRate: Double, buffer: Int) -> Bool {
        controller.preferredSampleRate == sampleRate && controller.preferredBufferFrames == buffer
    }

    private var sampleRateBadgeText: String? {
        let actual = Int(controller.negotiatedSampleRate.rounded())
        let preferred = Int(controller.preferredSampleRate.rounded())
        guard actual > 0, preferred > 0, actual != preferred else { return nil }

        if controller.routeOutputs.first?.portType == .usbAudio {
            return "USB device locked at \(actual / 1000)k"
        }
        return "System locked at \(actual / 1000)k"
    }

    private var bufferBadgeText: String? {
        let actual = controller.negotiatedBufferFrames
        let preferred = controller.preferredBufferFrames
        guard actual > 0, actual != preferred else { return nil }

        if let port = controller.routeOutputs.first?.portType,
           port == .airPlay || port == .bluetoothA2DP || port == .bluetoothLE || port == .bluetoothHFP {
            return "AirPlay/Bluetooth forces high latency"
        }
        return "System forced buffer to \(actual)f"
    }

    private func handleMicPermissionRequest() {
        switch micPermission {
        case .undetermined:
            MicrophonePermission.ensure { granted in
                micPermission = granted ? .granted : .denied
                if granted {
                    controller.refreshInputs()
                }
            }
        case .denied:
            MicrophonePermission.openAppSettings()
        case .granted:
            break
        }
    }

    private func outputIcon(for portType: AVAudioSession.Port?) -> String {
        switch portType {
        case .builtInSpeaker: return "speaker.wave.2.fill"
        case .headphones, .headsetMic: return "headphones"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "wave.3.right.circle.fill"
        case .airPlay: return "airplayaudio"
        case .usbAudio: return "memorychip"
        default: return "speaker.wave.2"
        }
    }

    private func portTypeLabel(_ portType: AVAudioSession.Port?) -> String {
        switch portType {
        case .usbAudio: return "USB"
        case .airPlay: return "AirPlay"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "Bluetooth"
        case .headphones, .headsetMic: return "Headphones"
        case .builtInSpeaker: return "Speaker"
        default: return "System"
        }
    }

    private func latencyLabel(for portType: AVAudioSession.Port?) -> String {
        switch portType {
        case .airPlay, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return "High Latency"
        case .usbAudio, .headphones, .headsetMic, .builtInSpeaker:
            return "Low Latency"
        default:
            return "Medium Latency"
        }
    }

    private func displayName(for input: AVAudioSessionPortDescription) -> String {
        if input.portType == .builtInMic { return "Built-in Microphone" }
        return input.portName
    }

    private func subtitle(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic: return "On-device"
        case .headsetMic: return "Headset"
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: return "Bluetooth"
        case .lineIn: return "Line-In"
        case .usbAudio: return "USB Audio"
        default: return input.portType.rawValue
        }
    }

    private func symbolName(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic: return "mic.fill"
        case .headsetMic: return "headphones"
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: return "wave.3.right.circle.fill"
        case .lineIn: return "cable.connector"
        case .usbAudio: return "memorychip"
        default: return "mic"
        }
    }

    @ViewBuilder
    private func card<Content: View>(prominent: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(prominent ? 16 : 14)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(prominent ? .regularMaterial : .ultraThinMaterial)
                }
            }
        )
    }

    @ViewBuilder
    private func outerCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
    }

    private func headerRow(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentStyle)
                .imageScale(.large)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 2)
    }
}

private enum ChannelMode: Int {
    case mono = 0
    case stereo = 1
    case multi = 2
}

// MARK: - Subviews

private struct OutputPickerRow: View {
    let icon: String
    let summary: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.primary, .secondary)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Output")
                    .font(.headline.weight(.semibold))
                Text("Now routing to: \(summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            RoutePickerButton()
                .frame(width: 52, height: 52)
                .accessibilityLabel("Output route picker")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct RoutePickerButton: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            RoutePickerRepresentable()
                .frame(width: 44, height: 44)
        }
    }
}

private struct RoutePickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor.label
        view.activeTintColor = UIColor.systemBlue
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct RouteInspectorChips: View {
    let chips: [RouteChip]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    HStack(spacing: 6) {
                        Image(systemName: chip.systemImage)
                            .imageScale(.small)
                        Text(chip.label)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                    .accessibilityLabel(chip.label)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct RouteChip: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
}

private struct ReinitializeRouteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reinitialize Output")
                    .font(.subheadline.weight(.semibold))
                Text("Fixes flaky AirPlay/Bluetooth routes without restarting the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EngineStatusCapsule: View {
    let state: AudioSessionController.EngineState
    let rate: Double
    let bufferFrames: Int
    let channels: Int
    let onResume: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Engine: \(state.label)")
                    .font(.subheadline.weight(.semibold))

                if state == .active {
                    Text("\(Int(rate)) Hz · \(bufferFrames)f · \(channels)ch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if state == .interrupted {
                    Text("Interrupted by system")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onResume, state == .interrupted {
                Button("Resume", action: onResume)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

private struct PresetTile: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.12), lineWidth: selected ? 2 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(selected ? 0.08 : 0))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RateTile: View {
    let label: String
    let rate: Double
    let current: Double
    let tap: () -> Void

    var body: some View {
        SelectableTile(label: label, selected: current == rate, tap: tap)
    }
}

private struct BufferTile: View {
    let size: Int
    let current: Int
    let tap: () -> Void

    var body: some View {
        SelectableTile(label: "\(size)", selected: current == size, tap: tap)
    }
}

private struct ChannelModeTile: View {
    let label: String
    let selected: Bool
    var disabled: Bool = false
    let tap: () -> Void

    var body: some View {
        SelectableTile(label: label, selected: selected, disabled: disabled, tap: tap)
    }
}

private struct SelectableTile: View {
    let label: String
    let selected: Bool
    var disabled: Bool = false
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.12), lineWidth: selected ? 2 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(selected ? 0.08 : 0))
        )
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
    }
}

private struct DeviceTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selected ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.15), lineWidth: selected ? 2 : 1)
                    )
                    .frame(height: 64)
                    .overlay(
                        Image(systemName: symbol)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .secondary)
                            .font(.system(size: 22, weight: .semibold))
                    )
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
    }
}

private struct BadgeText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }
}

private struct MicrophonePermissionCTA: View {
    let status: MicrophonePermission.Status
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "mic.slash.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Microphone Access")
                        .font(.subheadline.weight(.semibold))
                    Text(status == .denied
                         ? "Microphone access is off. Open Settings to re-enable."
                         : "Allow access to list inputs and monitor audio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DiagnosticsSection: View {
    let outputs: [AudioSessionController.RouteOutputInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current Route Outputs")
                .font(.subheadline.weight(.semibold))

            if outputs.isEmpty {
                Text("No active outputs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(outputs) { output in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(output.name)
                            .font(.caption.weight(.semibold))
                        Text("\(output.portType.rawValue) · uid \(output.uid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DiagnosticsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct EmptyDevicesFallback: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow, .white)
                .imageScale(.medium)
            Text("No input devices reported. Grant microphone access or start the engine to refresh inputs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private extension AVAudioSession.CategoryOptions {
    var prettyList: String {
        var items: [String] = []
        if contains(.mixWithOthers) { items.append("mixWithOthers") }
        if contains(.allowBluetooth) { items.append("allowBluetooth") }
        if contains(.allowBluetoothA2DP) { items.append("allowBluetoothA2DP") }
        if contains(.allowAirPlay) { items.append("allowAirPlay") }
        if contains(.defaultToSpeaker) { items.append("defaultToSpeaker") }
        return items.isEmpty ? "none" : items.joined(separator: ", ")
    }
}
