
// TenneyApp.swift
// Tenney
//
// Created by Sebastian Suarez-Solis
//

import SwiftUI

import AVFAudio
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum ThemeStyleChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

@main
struct TenneyApp: App {
   
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKeys.crashReportingEnabled)
    private var crashReportingEnabled: Bool = false
    
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
        BravuraFontRegistrar.registerIfNeeded()
        Heji2FontRegistry.registerIfNeeded()
        seedLatticeSoundDefaultIfNeeded()
        configureAudioSessionFromDefaults()
        let crashInfo = SessionCrashMarker.shared.onLaunch()
        if let crashInfo {
            DiagnosticsCenter.shared.log(
                "Previous session flagged as crash",
                level: .warning,
                category: "crash",
                meta: ["timestamp": ISO8601DateFormatter().string(from: crashInfo.timestamp)]
            )
            SessionCrashMarker.shared.clearCrashBannerDismissalOnNewCrash()
        } else {
            UserDefaults.standard.set(0, forKey: SettingsKeys.lastSessionCrashTimestamp)
        }
        if crashReportingEnabled { SentryService.shared.setEnabled(true) }
#if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            SessionCrashMarker.shared.markCleanTermination()
        }
#elseif os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            SessionCrashMarker.shared.markCleanTermination()
        }
#endif
    }

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            MacRootView()
                .environmentObject(latticeStore)
                .environmentObject(appModel)
                .preferredColorScheme(appScheme)
                .onAppear {
                    appModel.configureAndStart()
                    if scenePhase == .active {
                        latticeStore.performBootSelectionClearIfNeeded()
                    }
                }
                .onChange(of: crashReportingEnabled) { SentryService.shared.setEnabled($0) }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        latticeStore.performBootSelectionClearIfNeeded()
                    }
                    appModel.scenePhaseDidChange(phase)
                    if phase == .background || phase == .inactive {
                        SessionCrashMarker.shared.markCleanTermination()
                    }
                }
        }
        .defaultSize(width: 1320, height: 820)

        WindowGroup(id: "preferences") {
            MacPreferencesRootView()
                .environmentObject(appModel)
                .preferredColorScheme(appScheme)
                .onChange(of: crashReportingEnabled) { SentryService.shared.setEnabled($0) }
                .onChange(of: scenePhase) { phase in
                    if phase == .background || phase == .inactive {
                        SessionCrashMarker.shared.markCleanTermination()
                    }
                }
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
                .onAppear {
                    appModel.configureAndStart()
                    if scenePhase == .active {
                        latticeStore.performBootSelectionClearIfNeeded()
                    }
                }
                .onChange(of: crashReportingEnabled) { SentryService.shared.setEnabled($0) }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        latticeStore.performBootSelectionClearIfNeeded()
                    }
                    appModel.scenePhaseDidChange(phase)
                    if phase == .background || phase == .inactive {
                        SessionCrashMarker.shared.markCleanTermination()
                    }
                }

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
