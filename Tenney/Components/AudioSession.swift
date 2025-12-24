
//
//  AudioSession.swift
//  Tenney
//
//  Audio session helpers used by the capture/pitch pipeline.
//

import Foundation
import AVFoundation

enum AudioSession {

    // MARK: - Permissions

    static func requestMicPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: - Discovery

    static func listAvailableInputs() -> [AVAudioSessionPortDescription] {
        AVAudioSession.sharedInstance().availableInputs ?? []
    }

    static func listDataSources(forPortUID deviceUID: String) -> [AVAudioSessionDataSourceDescription] {
        guard let port = (AVAudioSession.sharedInstance().availableInputs ?? [])
            .first(where: { $0.uid == deviceUID }) else { return [] }
        return port.dataSources ?? []
    }

    // MARK: - Configuration

    /// Configure the session for low-latency measurement + mic capture.
    /// - Parameters:
    ///   - sampleRate: Preferred SR (actual SR may differ depending on the route).
    ///   - bufferFrames: Preferred IO buffer size in frames (converted to duration).
    static func configureSession(sampleRate: Double = 48_000, bufferFrames: Int = 256) {
        let duration = max(0.0001, Double(max(32, bufferFrames)) / max(1.0, sampleRate))
        configureSession(sampleRate: sampleRate, bufferDuration: duration)
    }

    /// Underlying session configuration that accepts IO buffer duration directly.
    static func configureSession(sampleRate: Double = 48_000, bufferDuration: Double) {
        let session = AVAudioSession.sharedInstance()
        do {
            // Measurement mode minimizes processing (AGC/noise suppression) on many routes.
            // Keep `.playAndRecord` so the app can optionally monitor.
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [
                                        .mixWithOthers,
                                        .allowBluetooth,
                                        .allowBluetoothA2DP,
                                        .defaultToSpeaker
                                    ])
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(bufferDuration)
            try session.setActive(true, options: [])
        } catch {
            print("[AudioSession] Error configuring session: \(error)")
        }
    }

    /// Prefer a specific input port by UID (e.g., a USB mic).
    static func setPreferredInput(deviceUID: String) {
        let session = AVAudioSession.sharedInstance()

        // Get all available inputs and filter by the desired UID.
        if let availableInputs = session.availableInputs {
            if let preferredInput = availableInputs.first(where: { $0.uid == deviceUID }) {
                do {
                    try session.setPreferredInput(preferredInput)
                } catch {
                    print("[AudioSession] Error setting preferred input: \(error)")
                }
            } else {
                print("[AudioSession] Device with UID \(deviceUID) not found in available inputs.")
            }
        } else {
            print("[AudioSession] No available inputs.")
        }
    }

    /// Prefer a specific input port + (optional) data source.
    /// `dataSourceID` should match either the dataSourceID's stringValue OR the dataSourceName.
    static func setPreferredInput(deviceUID: String, dataSourceID: String?) {
        setPreferredInput(deviceUID: deviceUID)

        guard let dataSourceID, !dataSourceID.isEmpty else { return }

        let session = AVAudioSession.sharedInstance()
        guard let sources = session.inputDataSources, !sources.isEmpty else { return }

        if let match = sources.first(where: {
            if $0.dataSourceID.stringValue == dataSourceID { return true }
            return $0.dataSourceName == dataSourceID
        }) {
            do {
                try session.setInputDataSource(match)
            } catch {
                print("[AudioSession] Error setting input data source: \(error)")
            }
        }
    }

    /// Back-compat label used in earlier iterations.
    static func setPreferredInput(deviceUID: String, dataSourceUID: String?) {
        setPreferredInput(deviceUID: deviceUID, dataSourceID: dataSourceUID)
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[AudioSession] Error deactivating session: \(error)")
        }
    }
}
