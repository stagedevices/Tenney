//
//  AudioSessionController.swift
//  Tenney
//
//  Shared audio routing/controller surface for Pro Audio Settings.
//

import AVFoundation
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AudioSessionController: ObservableObject {
    static let shared = AudioSessionController()

    enum EngineState: Equatable {
        case active
        case stopped
        case interrupted
        case error(String)

        var label: String {
            switch self {
            case .active: return "Active"
            case .stopped: return "Stopped"
            case .interrupted: return "Interrupted by system"
            case .error: return "Error"
            }
        }
    }

    struct RouteOutputInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let portType: AVAudioSession.Port
        let uid: String
        let channels: Int
    }

    @Published private(set) var engineState: EngineState = .stopped
    @Published private(set) var currentRouteSummary: String = "System Output"
    @Published private(set) var routeOutputs: [RouteOutputInfo] = []
    @Published private(set) var negotiatedSampleRate: Double = 0
    @Published private(set) var negotiatedBufferFrames: Int = 0
    @Published private(set) var negotiatedOutputChannels: Int = 0
    @Published private(set) var lastRouteChangeReason: String = "Unknown"
    @Published private(set) var lastRouteChangeTimestamp: Date? = nil
    @Published private(set) var lastRouteChangeFailed: Bool = false
    @Published var routeChangeBanner: String? = nil
    @Published private(set) var availableInputs: [AVAudioSessionPortDescription] = []
    @Published private(set) var selectedInputUID: String = UserDefaults.standard.string(
        forKey: SettingsKeys.audioInputUID
    ) ?? ""

    @AppStorage(SettingsKeys.audioPreferredSampleRate)
    private var storedPreferredSampleRate: Double = 48_000
    @AppStorage(SettingsKeys.audioPreferredBufferFrames)
    private var storedPreferredBufferFrames: Int = 256
    @AppStorage(SettingsKeys.audioPreferSpeaker)
    private var storedPreferSpeaker: Bool = false

    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var isReinitializing: Bool = false
    private let outputEngine = ToneOutputEngine.shared

    private init() {
        refreshAll()
        observeSessionNotifications()
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    var isEngineActive: Bool { engineState == .active }
    var preferredSampleRate: Double { storedPreferredSampleRate }
    var preferredBufferFrames: Int { storedPreferredBufferFrames }
    var preferSpeaker: Bool { storedPreferSpeaker }
    var supportsInput: Bool { AVAudioSession.sharedInstance().isInputAvailable }

    func refreshAll() {
        refreshRouteState()
        refreshInputs()
        refreshEngineState()
    }

    func refreshInputs() {
        let session = AVAudioSession.sharedInstance()
        var inputs = session.availableInputs ?? []
        if inputs.isEmpty {
            inputs = session.currentRoute.inputs
        }
        availableInputs = inputs

        if !selectedInputUID.isEmpty,
           inputs.contains(where: { $0.uid == selectedInputUID }) {
            return
        }

        if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
            selectInput(builtIn)
        } else if let first = inputs.first {
            selectInput(first)
        } else {
            selectedInputUID = ""
        }
    }

    func selectInput(_ input: AVAudioSessionPortDescription) {
        selectedInputUID = input.uid
        UserDefaults.standard.set(selectedInputUID, forKey: SettingsKeys.audioInputUID)
    }

    func applyPreferences(sampleRate: Double? = nil, bufferFrames: Int? = nil) {
        if let sr = sampleRate {
            storedPreferredSampleRate = sr
        }
        if let frames = bufferFrames {
            storedPreferredBufferFrames = frames
        }
        applySessionPreferences()
    }

    func setPreferSpeaker(_ enabled: Bool) {
        storedPreferSpeaker = enabled
        applySpeakerOverride()
    }

    func reinitializeOutputRoute() {
        guard !isReinitializing else { return }
        isReinitializing = true

        let snapshots = outputEngine.snapshotActiveVoices()
        let fadeSeconds = snapshots.isEmpty ? 0.0 : 0.08
        if fadeSeconds > 0 {
            outputEngine.fadeOutAllVoices(releaseSeconds: fadeSeconds)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeSeconds) { [weak self] in
            self?.performRouteReinitialize(with: snapshots)
        }
    }

    func resumeEngineIfNeeded() {
        guard engineState == .interrupted else { return }
        reinitializeOutputRoute()
    }

    func diagnosticsText() -> String {
        let session = AVAudioSession.sharedInstance()
        let routeList = routeOutputs
            .map { "• \($0.name) (\($0.portType.rawValue)) uid=\($0.uid)" }
            .joined(separator: "\n")

        let categoryOptions = session.categoryOptions
        let options = [
            categoryOptions.contains(.mixWithOthers) ? "mixWithOthers" : nil,
            categoryOptions.contains(.allowBluetooth) ? "allowBluetooth" : nil,
            categoryOptions.contains(.allowBluetoothA2DP) ? "allowBluetoothA2DP" : nil,
            categoryOptions.contains(.allowAirPlay) ? "allowAirPlay" : nil,
            categoryOptions.contains(.defaultToSpeaker) ? "defaultToSpeaker" : nil
        ].compactMap { $0 }.joined(separator: ", ")

        let bufferDuration = session.ioBufferDuration
        let actualBufferFrames = Int(round(bufferDuration * session.sampleRate))
        let preferredBuffer = storedPreferredBufferFrames
        let preferredRate = storedPreferredSampleRate
        let lastReason = lastRouteChangeReason
        let lastTime = lastRouteChangeTimestamp?.description ?? "n/a"

        return """
        Route Outputs:
        \(routeList.isEmpty ? "• none" : routeList)

        Category: \(session.category.rawValue)
        Mode: \(session.mode.rawValue)
        Options: \(options.isEmpty ? "none" : options)
        IO Buffer Duration: \(String(format: "%.4f", bufferDuration))s
        Preferred SR: \(Int(preferredRate)) Hz
        Actual SR: \(Int(session.sampleRate)) Hz
        Preferred Buffer: \(preferredBuffer) frames
        Actual Buffer: \(actualBufferFrames) frames
        Last Route Change: \(lastReason) at \(lastTime)
        """
    }

    func copyDiagnostics() {
        let text = diagnosticsText()
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    private func observeSessionNotifications() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notif in
            self?.handleRouteChange(notification: notif)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notif in
            self?.handleInterruption(notification: notif)
        }
    }

    private func performRouteReinitialize(with snapshots: [ToneOutputEngine.VoiceSnapshot]) {
        let session = AVAudioSession.sharedInstance()
        var didFail = false
        outputEngine.hardStopEngine(deactivateSession: false)

        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            didFail = true
            lastRouteChangeFailed = true
            #if DEBUG
            print("[AudioSessionController] deactivate failed: \(error)")
            #endif
        }

        applySessionPreferences()
        didFail = didFail || lastRouteChangeFailed

        if !snapshots.isEmpty {
            for snap in snapshots {
                _ = outputEngine.sustain(
                    freq: snap.freq,
                    amp: snap.amp,
                    owner: snap.owner,
                    ownerKey: snap.ownerKey,
                    attackMs: nil,
                    releaseMs: nil
                )
            }
        }

        refreshAll()
        if !didFail {
            lastRouteChangeFailed = false
        }
        isReinitializing = false
    }

    private func applySessionPreferences() {
        let session = AVAudioSession.sharedInstance()
        do {
            let sr = storedPreferredSampleRate
            if sr > 0 {
                try session.setPreferredSampleRate(sr)
            }
            let actualSR = session.sampleRate > 0 ? session.sampleRate : max(1.0, storedPreferredSampleRate)
            let frames = max(32, storedPreferredBufferFrames)
            let duration = Double(frames) / actualSR
            try session.setPreferredIOBufferDuration(duration)
            try session.setActive(true, options: [])
        } catch {
            lastRouteChangeFailed = true
            #if DEBUG
            print("[AudioSessionController] applySessionPreferences error: \(error)")
            #endif
        }
        applySpeakerOverride()
        refreshRouteState()
    }

    private func applySpeakerOverride() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let isExternal = outputs.contains { port in
            port.portType == .airPlay || port.portType == .bluetoothA2DP ||
            port.portType == .bluetoothLE || port.portType == .bluetoothHFP ||
            port.portType == .usbAudio
        }

        guard session.category == .playAndRecord else { return }

        do {
            if isExternal {
                try session.overrideOutputAudioPort(.none)
                return
            }
            if storedPreferSpeaker {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            #if DEBUG
            print("[AudioSessionController] override speaker failed: \(error)")
            #endif
        }
    }

    private func refreshRouteState() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        routeOutputs = outputs.map { output in
            RouteOutputInfo(
                id: output.uid,
                name: output.portName,
                portType: output.portType,
                uid: output.uid,
                channels: output.channels.count
            )
        }
        currentRouteSummary = routeSummary(for: outputs)
        negotiatedSampleRate = session.sampleRate
        negotiatedBufferFrames = Int(round(session.ioBufferDuration * session.sampleRate))
        if outputs.isEmpty {
            negotiatedOutputChannels = 0
        } else {
            negotiatedOutputChannels = max(1, outputs.reduce(0) { $0 + max(1, $1.channels.count) })
        }
    }

    private func refreshEngineState() {
        if outputEngine.isEngineRunning {
            engineState = .active
        } else {
            engineState = .stopped
        }
    }

    private func handleRouteChange(notification: Notification) {
        let previous = currentRouteSummary
        refreshRouteState()
        refreshEngineState()

        if let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
           let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {
            lastRouteChangeReason = routeChangeReasonText(reason)
            lastRouteChangeTimestamp = Date()
        } else {
            lastRouteChangeReason = "Unknown"
            lastRouteChangeTimestamp = Date()
        }

        let current = currentRouteSummary
        if previous != current {
            routeChangeBanner = "Route changed: \(previous) → \(current)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                if self?.routeChangeBanner == "Route changed: \(previous) → \(current)" {
                    self?.routeChangeBanner = nil
                }
            }
        }
        lastRouteChangeFailed = false
        #if DEBUG
        print("[AudioSessionController] route changed: \(previous) -> \(current)")
        #endif
    }

    private func handleInterruption(notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            engineState = .interrupted
        case .ended:
            refreshEngineState()
        @unknown default:
            break
        }
    }

    private func routeSummary(for outputs: [AVAudioSessionPortDescription]) -> String {
        guard let first = outputs.first else { return "System Output" }

        let name = first.portName
        switch first.portType {
        case .usbAudio:
            return "USB Audio — \(name)"
        case .airPlay:
            return "AirPlay — \(name)"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return "Bluetooth — \(name)"
        case .headphones, .headsetMic:
            return "Headphones"
        case .builtInSpeaker:
            return "Built-in Speaker"
        default:
            return name.isEmpty ? "System Output" : name
        }
    }

    private func routeChangeReasonText(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .newDeviceAvailable: return "New device available"
        case .oldDeviceUnavailable: return "Device disconnected"
        case .categoryChange: return "Category changed"
        case .override: return "Output override"
        case .wakeFromSleep: return "Wake from sleep"
        case .noSuitableRouteForCategory: return "No suitable route"
        case .routeConfigurationChange: return "Route configuration change"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}
