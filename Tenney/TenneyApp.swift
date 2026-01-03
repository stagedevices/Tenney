
// TenneyApp.swift
// Tenney
//
// Created by Sebastian Suarez-Solis
//

import SwiftUI
import AVFAudio

enum ThemeStyleChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

@main
struct TenneyApp: App {
    
    private func seedLatticeSoundDefaultIfNeeded() {
        let ud = UserDefaults.standard
        if ud.object(forKey: SettingsKeys.latticeSoundEnabled) == nil {
            ud.set(true, forKey: SettingsKeys.latticeSoundEnabled)
        }
        if ud.object(forKey: SettingsKeys.tenneyThemeID) == nil,
           let legacy = ud.string(forKey: SettingsKeys.latticeThemeID) {
            ud.set(legacy, forKey: SettingsKeys.tenneyThemeID)
        }
    }

    @AppStorage(SettingsKeys.latticeThemeStyle)
    private var themeStyleRaw: String = ThemeStyleChoice.system.rawValue

    private var appScheme: ColorScheme? {
        switch ThemeStyleChoice(rawValue: themeStyleRaw) ?? .system {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    @StateObject private var appModel = AppModel()
    @StateObject private var latticeStore = LatticeStore()

    init() {
        seedLatticeSoundDefaultIfNeeded()
        configureAudioSessionFromDefaults()
    }

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            MacRootView()
                .environmentObject(latticeStore)
                .environmentObject(appModel)
                .preferredColorScheme(appScheme)
                .onAppear { appModel.configureAndStart() }
        }
        .defaultSize(width: 1320, height: 820)

        WindowGroup(id: "preferences") {
            MacPreferencesRootView()
                .environmentObject(appModel)
                .preferredColorScheme(appScheme)
        }

        .commands {
            MacCommands()
        }
#else
        WindowGroup {
            ContentView()
                .environmentObject(latticeStore)
                .environmentObject(appModel)
                .preferredColorScheme(appScheme)   // ← global scheme driven by Settings
                .onAppear { appModel.configureAndStart() }

        }
#endif
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
            let sr = UserDefaults.standard.double(forKey: SettingsKeys.audioPreferredSampleRate)
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
