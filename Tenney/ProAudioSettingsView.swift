//
//  ProAudioSettingsView.swift
//  Tenney
//
//  Revamped to match Settings cards (iOS 26 glass), show real input devices,
//  and use the same tile language as Theme/A4 pickers.
//
import Foundation
import SwiftUI
import AVFAudio
import AVKit
import UIKit

public struct ProAudioSettingsView: View {
    // MARK: - Persisted prefs (use existing keys where present)
    @AppStorage(SettingsKeys.audioPreferredSampleRate) private var preferredSampleRate: Double = 48_000
    @AppStorage(SettingsKeys.audioPreferredBufferFrames) private var preferredBufferFrames: Int = 256

    // Not introducing a new SettingsKeys key for channel mode to avoid compile churn
    @State private var preferredChannelMode: Int = 1  // 0-Mono, 1-Stereo, 2-Multi
    @State private var monitorInput: Bool = false
    @AppStorage(SettingsKeys.audioPreferSpeaker) private var preferSpeaker: Bool = false

    // Input devices
    @State private var availableInputs: [AVAudioSessionPortDescription] = []
    @State private var selectedInputUID: String = ""
    @State private var selectedInputName: String = ""
    @Namespace private var inputNS
    @State private var currentOutputs: [AVAudioSessionPortDescription] = []
    @State private var routeObserver: NSObjectProtocol?

    // Grids aligned with Theme/A4 cards
    private let deviceCols = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12, alignment: .top)]
    private let optCols    = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12, alignment: .top)]

    public init() {}

    public var body: some View {
        card("Pro Audio · Input & Engine") {
            VStack(alignment: .leading, spacing: 14) {
                // == Input devices ==
                headerRow(title: "Input Device", icon: "waveform.badge.mic")
                LazyVGrid(columns: deviceCols, spacing: 12) {
                    ForEach(availableInputs, id: \.uid) { input in
                        let sel = (selectedInputUID == input.uid)
                        DeviceCard(
                            title: displayName(for: input),
                            subtitle: subtitle(for: input),
                            symbol: symbolName(for: input),
                            selected: sel
                        ) { select(input) }
                        .matchedGeometryEffect(id: sel ? "selectedDevice" : "\(input.uid)-idle", in: inputNS, isSource: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(displayName(for: input))
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
                if availableInputs.isEmpty {
                    EmptyDevicesFallback()
                }

                // == Channel mode ==
                headerRow(title: "Channel Mode", icon: "square.3.layers.3d.down.right")
                LazyVGrid(columns: optCols, spacing: 12) {
                    OptionTile(label: "Mono", selected: preferredChannelMode == 0) {
                        withAnimation(.snappy) { preferredChannelMode = 0 }
                    }
                    OptionTile(label: "Stereo", selected: preferredChannelMode == 1) {
                        withAnimation(.snappy) { preferredChannelMode = 1 }
                    }
                    OptionTile(label: "Multi-Channel", selected: preferredChannelMode == 2) {
                        withAnimation(.snappy) { preferredChannelMode = 2 }
                    }
                }

                // == Sample rate ==
                headerRow(title: "Sample Rate", icon: "metronome.fill")
                LazyVGrid(columns: optCols, spacing: 12) {
                    RateTile(label: "44.1 kHz", rate: 44_100, current: preferredSampleRate) { commitSampleRate(44_100) }
                    RateTile(label: "48 kHz",   rate: 48_000, current: preferredSampleRate) { commitSampleRate(48_000) }
                    RateTile(label: "96 kHz",   rate: 96_000, current: preferredSampleRate) { commitSampleRate(96_000) }
                }

                // == Buffer size ==
                headerRow(title: "Buffer Size (frames)", icon: "memorychip.fill")
                LazyVGrid(columns: optCols, spacing: 12) {
                    BufferTile(size: 128,  current: preferredBufferFrames) { commitBuffer(128) }
                    BufferTile(size: 256,  current: preferredBufferFrames) { commitBuffer(256) }
                    BufferTile(size: 512,  current: preferredBufferFrames) { commitBuffer(512) }
                    BufferTile(size: 1024, current: preferredBufferFrames) { commitBuffer(1024) }
                }

                // == Monitor ==
                Toggle("Monitor Input", isOn: $monitorInput)
                    .onChange(of: monitorInput) { _ in manageInputMonitoring() }
                if monitorInput {
                    Text("Make sure outputs are isolated to avoid feedback.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                
                // == Output & routing ==
                                Divider().padding(.vertical, 2)
                                headerRow(title: "Output & Routing", icon: "speaker.wave.2.fill")
                
                                // System route picker (this is how iOS exposes the device list)
                                RoutePickerRow()
                
                                // Current route badges (update on change)
                                CurrentRouteRow(outputs: currentOutputs.map { (outputDisplayName(for: $0), outputSymbolName(for: $0)) })
                
                                // Optional: Prefer Speaker (the only programmatic override iOS allows)
                                Toggle("Prefer Speaker (when possible)", isOn: $preferSpeaker)
                                    .onChange(of: preferSpeaker) { _ in applySpeakerOverride() }
                                Text("Use the button above to choose Bluetooth, AirPlay, USB, etc. “Prefer Speaker” only works in certain categories (e.g., Play & Record).")
                                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        
        .onAppear {
                    refreshInputs()
                    refreshOutputs()
                    applySpeakerOverride()
                    // Listen for system route changes so our chips reflect user selection
                    routeObserver = NotificationCenter.default.addObserver(
                        forName: AVAudioSession.routeChangeNotification,
                        object: AVAudioSession.sharedInstance(),
                        queue: .main
                    ) { _ in
                        refreshOutputs()
                    }
                }
                .onDisappear {
                    if let obs = routeObserver {
                        NotificationCenter.default.removeObserver(obs)
                        routeObserver = nil
                    }
                }
    }
    
    private func refreshOutputs() {
            let session = AVAudioSession.sharedInstance()
            currentOutputs = session.currentRoute.outputs
        }

    // MARK: - Cards (match StudioConsoleView glass language; no extra horizontal padding)
    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
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
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
    }

    // MARK: - Header row
    private func headerRow(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                        .linearGradient(
                            colors: [.red, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                .imageScale(.large)
                .symbolEffect(.bounce, value: title)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Device selection
    private func refreshInputs() {
        let session = AVAudioSession.sharedInstance()
        var inputs = session.availableInputs ?? []
        // Fallback: current route’s inputs (e.g., when microphones are restricted)
        if inputs.isEmpty {
            inputs = session.currentRoute.inputs
        }
        availableInputs = inputs

        // Choose a sensible default
        if !availableInputs.contains(where: { $0.uid == selectedInputUID }) {
            if let builtIn = availableInputs.first(where: { $0.portType == .builtInMic }) {
                select(builtIn)
            } else if let first = availableInputs.first {
                select(first)
            } else {
                selectedInputUID = ""
                selectedInputName = ""
            }
        }
    }

    private func select(_ input: AVAudioSessionPortDescription) {
        withAnimation(.snappy) {
            selectedInputUID = input.uid
            selectedInputName = displayName(for: input)
        }
        // Persist lightweight identity; engine may apply this later.
        UserDefaults.standard.set(selectedInputUID, forKey: SettingsKeys.audioInputUID)
    }

    private func displayName(for input: AVAudioSessionPortDescription) -> String {
        if input.portType == .builtInMic { return "Built-in Microphone" }
        return input.portName
    }
    private func subtitle(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic:        return "On-device"
        case .headsetMic:        return "Headset"
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: return "Bluetooth"
        case .lineIn:            return "Line-In"
        case .usbAudio:          return "USB Audio"
        default:                 return input.portType.rawValue
        }
    }
    private func symbolName(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic:        return "mic.fill"
        case .headsetMic:        return "headphones"
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: return "wave.3.right.circle.fill"
        case .lineIn:            return "cable.connector"
        case .usbAudio:          return "memorychip"
        default:                 return "mic"
        }
    }

    // MARK: - Commit prefs
    private func commitSampleRate(_ hz: Double) {
        let supported: Set<Double> = [44_100, 48_000, 96_000]
        preferredSampleRate = supported.contains(hz) ? hz : 48_000
    }
    private func commitBuffer(_ frames: Int) {
        let supported: Set<Int> = [128, 256, 512, 1024]
        preferredBufferFrames = supported.contains(frames) ? frames : 256
    }

    private func manageInputMonitoring() {
        // Hook for your engine to guard against feedback, etc.
    }
    private func applySpeakerOverride() {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(true, options: []) // harmless if already active
                if preferSpeaker {
                    try session.overrideOutputAudioPort(.speaker)
                } else {
                    try session.overrideOutputAudioPort(.none)
                }
            } catch {
                // Non-fatal: iOS may ignore this based on category/route/security.
            }
            refreshOutputs()
        }
}

// MARK: - Subviews (match Theme/A4 card visual language)
private struct DeviceCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selected ? Color.accentColor.opacity(0.85)
                                             : Color.secondary.opacity(0.15),
                                    lineWidth: selected ? 2 : 1)
                    )
                    .frame(height: 64)
                    .overlay(
                        Image(systemName: symbol)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .secondary)
                            .font(.system(size: 22, weight: .semibold))
                    )
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.accentColor, .white)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                        .symbolEffect(.bounce, value: selected)
                }
            }
            Text(title).font(.subheadline).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .buttonStyle(.plain)
    }
}

private struct OptionTile: View {
    let label: String
    let selected: Bool
    let tap: () -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? Color.accentColor.opacity(0.85)
                                         : Color.secondary.opacity(0.15),
                                lineWidth: selected ? 2 : 1)
                )
                .frame(height: 64)
                .overlay(
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                )
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.accentColor, .white)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                    .symbolEffect(.bounce, value: selected)
            }
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .buttonStyle(.plain)
    }
}

// MARK: - Current route badges
private struct CurrentRouteRow: View {
    let outputs: [(String, String)]  // (name, symbol)
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(outputs.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Image(systemName: item.1).imageScale(.small)
                        Text(item.0).font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Prominent, visible route picker row
private struct RoutePickerRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplayaudio")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.primary, .secondary)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Select Output").font(.subheadline.weight(.semibold))
                Text("AirPlay • Bluetooth • USB").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            RoutePickerRepresentable()
                .frame(width: 44, height: 44)   // show the native AirPlay button clearly
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct RoutePickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        v.tintColor = UIColor.label
                if #available(iOS 13.0, *) {
                    v.activeTintColor = UIColor.systemBlue
                }
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Output labels/icons
private func outputDisplayName(for port: AVAudioSessionPortDescription) -> String {
    switch port.portType {
    case .builtInSpeaker: return "Built-in Speaker"
    case .headphones:     return "Headphones"
    case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "Bluetooth"
    case .airPlay:        return "AirPlay"
    case .lineOut:        return "Line Out"
    case .usbAudio:       return "USB Audio"
    default:              return port.portName
    }
}
private func outputSymbolName(for port: AVAudioSessionPortDescription) -> String {
    switch port.portType {
    case .builtInSpeaker: return "speaker.wave.2.fill"
    case .headphones:     return "headphones"
    case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "wave.3.right.circle.fill"
    case .airPlay:        return "airplayaudio"
    case .lineOut:        return "cable.connector"
    case .usbAudio:       return "memorychip"
    default:              return "speaker.wave.2"
    }
}

private struct RateTile: View {
    let label: String
    let rate: Double
    let current: Double
    let tap: () -> Void
    var body: some View {
        OptionTile(label: label, selected: current == rate, tap: tap)
    }
}

private struct BufferTile: View {
    let size: Int
    let current: Int
    let tap: () -> Void
    var body: some View {
        OptionTile(label: "\(size)", selected: current == size, tap: tap)
    }
}

private struct EmptyDevicesFallback: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow, .white)
                .imageScale(.medium)
            Text("No input devices reported. iOS may restrict microphone access until you grant permission or start the engine.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
