
// TenneyApp.swift
// Tenney
//
// Created by Sebastian Suarez-Solis
//

import SwiftUI
import AVFAudio

@main
struct TenneyApp: App {
    @StateObject private var latticeStore = LatticeStore()
    @StateObject private var appModel = AppModel()

    init() {
        configureAudioSessionFromDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(latticeStore)
                .environmentObject(appModel)
                    .onAppear { appModel.configureAndStart() }
        }
    }

    // MARK: - Audio Session
    private func configureAudioSessionFromDefaults() {
        let s = AVAudioSession.sharedInstance()

        // Keep it conservative but capable: input + output, Bluetooth, AirPlay routes, etc.
        let preferSpeaker = UserDefaults.standard.bool(forKey: SettingsKeys.audioPreferSpeaker)

        var options: AVAudioSession.CategoryOptions = [
            .allowBluetooth,
            .allowBluetoothA2DP,
            .mixWithOthers
        ]
        if preferSpeaker { options.insert(.defaultToSpeaker) }

        do {
            try s.setCategory(.playAndRecord, mode: .default, options: options)

            // Optional tuning knobs (safe no-ops if you don’t set them)
            let sr = UserDefaults.standard.double(forKey: SettingsKeys.proAudioPreferredSampleRate)
            if sr > 0 { try s.setPreferredSampleRate(sr) }

            let io = UserDefaults.standard.double(forKey: SettingsKeys.proAudioPreferredIOBufferDuration)
            if io > 0 { try s.setPreferredIOBufferDuration(io) }

            try s.setActive(true, options: [])
        } catch {
            // Don’t crash on audio config; just proceed with system defaults.
            // You can log this if you have a logger.
        }
    }
}
