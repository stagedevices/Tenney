//
//  AudioIOConfig.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  AudioIOConfig.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation
import AVFoundation

/// Captures the user’s preferred audio route + performance parameters.
/// This is designed to be handed to AudioEngineService.start(config:callback:)
/// and/or persisted via UserDefaults/Codable.
struct AudioIOConfig: Codable, Equatable, Sendable {

    /// Preferred input port UID (e.g. a USB mic). nil = system default.
    var preferredInputPortUID: String?

    /// Preferred input data source ID/name (route-dependent). nil = default.
    var preferredInputDataSourceID: String?

    /// Preferred sample rate (Hz). nil = system default.
    var preferredSampleRate: Double?

    /// Preferred IO buffer size (frames). nil = system default.
    var bufferFrames: Int?

    init(
        preferredInputPortUID: String? = nil,
        preferredInputDataSourceID: String? = nil,
        preferredSampleRate: Double? = nil,
        bufferFrames: Int? = nil
    ) {
        self.preferredInputPortUID = preferredInputPortUID
        self.preferredInputDataSourceID = preferredInputDataSourceID
        self.preferredSampleRate = preferredSampleRate
        self.bufferFrames = bufferFrames
    }

    /// Compute a preferred IO buffer duration from frames + sampleRate.
    /// If either value is unavailable, returns nil.
    func preferredBufferDurationSeconds(actualOrPreferredSR sr: Double) -> Double? {
        guard let frames = bufferFrames, frames > 0, sr.isFinite, sr > 0 else { return nil }
        return Double(frames) / sr
    }

    // MARK: - Session apply

    /// Apply configuration to AVAudioSession in a conservative “measurement” setup.
    /// Safe to call repeatedly.
    ///
    /// Note: If you already centralize session management elsewhere, you can ignore this
    /// and have AudioEngineService apply config in its own way.
    func applyToAVAudioSession(
        categoryOptions: AVAudioSession.CategoryOptions = [
            .mixWithOthers,
            .allowBluetooth,
            .allowBluetoothA2DP,
            .defaultToSpeaker
        ]
    ) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: categoryOptions)

            if let sr = preferredSampleRate, sr.isFinite, sr > 0 {
                try session.setPreferredSampleRate(sr)
            }

            let srNow = session.sampleRate > 0 ? session.sampleRate : (preferredSampleRate ?? 48_000)
            if let dur = preferredBufferDurationSeconds(actualOrPreferredSR: srNow), dur.isFinite, dur > 0 {
                try session.setPreferredIOBufferDuration(dur)
            }

            // Preferred input (by UID)
            if let uid = preferredInputPortUID, !uid.isEmpty {
                if let ports = session.availableInputs,
                   let port = ports.first(where: { $0.uid == uid }) {
                    try session.setPreferredInput(port)
                }
            }

            // Preferred data source (by dataSourceID string OR name)
            if let ds = preferredInputDataSourceID, !ds.isEmpty,
               let sources = session.inputDataSources, !sources.isEmpty {
                if let match = sources.first(where: {
                    if $0.dataSourceID.stringValue == ds { return true }
                    return $0.dataSourceName == ds
                }) {
                    try session.setInputDataSource(match)
                }
            }

            try session.setActive(true, options: [])
        } catch {
            print("[AudioIOConfig] applyToAVAudioSession error: \(error)")
        }
    }
}
