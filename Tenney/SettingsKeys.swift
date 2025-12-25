//
//  SettingsKeys.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//
import Foundation
import SwiftUI


enum SettingsKeys {
    static let lastSeenBuild = "tenney.lastSeenBuild"

    static let tenneyDistanceMode = "tenney.distance.mode"
    
    // Lattice View State
    static let latticeDefaultZoomPreset = "tenney.lattice.defaultZoomPreset" // String ("close"|"standard"|"wide"|"overview")
    static let latticeRememberLastView  = "tenney.lattice.rememberLastView"  // Bool (default true)

    
    // Tuning
    static let a4Choice      = "tenney.tuner.a4Choice"     // "440" | "442" | "custom"
    static let a4CustomHz    = "tenney.tuner.a4CustomHz"   // Double
    static let staffA4Hz     = "tenney.tuner.staffA4Hz"    // Double (cached, used by NotationFormatter)
    
    // First-run wizard
        static let hasRunSetupV1   = "Tenney.Setup.HasRunV1"
        static let startDefaultTab = "Tenney.Setup.StartDefaultTab" // "lattice" / "tuner"
    
        // Initial Root Pitch (used by Lattice/Tuner root)
        static let rootHz          = "Tenney.Root.Hz" // Double (e.g. 415)

    // Labels
    static let labelDefault       = "tenney.label.default"       // "ratio" | "heji"
    static let showRatioAlongHeji = "tenney.label.showRatio"     // Bool

    // Lattice UI
    static let nodeSize      = "tenney.ui.nodeSize"        // "s" | "m" | "mplus" | "l"
    static let labelDensity  = "tenney.ui.labelDensity"    // Double 0...1
    static let guidesOn      = "tenney.ui.guidesOn"        // Bool
    static let overlay7      = "tenney.ui.overlay7"        // Bool
    static let overlay11     = "tenney.ui.overlay11"       // Bool
    static let foldAudible   = "tenney.lattice.foldAud"    // Bool (fold 20–5k)
    
    // Stage mode customization
    static let stageDimLevel     = "tenney.stage.dimLevel"        // Double 0.0...1.0 (how dark outside area gets)
    static let stageAccent       = "tenney.stage.accent"          // "system" | "amber" | "red"
    static let stageHideStatus   = "tenney.stage.hideStatus"      // Bool
    static let stageKeepAwake    = "tenney.stage.keepAwake"       // Bool
    static let stageMinimalUI    = "tenney.stage.minimalUI"       // Bool

    // Sound
    static let attackMs   = "tenney.audio.attackMs"        // Double
    static let releaseSec = "tenney.audio.releaseSec"      // Double
    static let safeAmp    = "tenney.audio.safeAmp"         // Double

    // Builder (present, but used later)
    static let nearDupWarn   = "tenney.builder.nearDupWarn"
    static let nearDupThresh = "tenney.builder.nearDupThresh"
    static let softWarnAt    = "tenney.builder.softWarnAt"
    static let hardCap       = "tenney.builder.hardCap"
    
    static let latticeThemeID = "latticeThemeID" // persisted theme choice
    static let latticeThemeStyle = "latticeThemeStyle" // "system" | "light" | "dark"
    
    // Tuner-local (walled off from Lattice)
    static let tunerPrimeLimit = "tenney.tuner.primeLimit" // Int (default 11)
    static let tunerStageMode  = "tenney.tuner.stageMode"  // Bool
    static let tunerMode       = "tenney.tuner.mode"       // "auto" | "strict" | "live"
    
    // Audio Settings
       static let audioPreferredInputPortUID = "tenney.audio.preferredInputPortUID"
       static let audioPreferredInputDataSourceID = "tenney.audio.preferredInputDataSourceID"
       static let audioPreferredSampleRate = "tenney.audio.preferredSampleRate"
       static let audioPreferredBufferFrames = "tenney.audio.preferredBufferFrames"
}

// Console → live screens signal

func postSetting<K>(_ key: String, _ value: K) {
    NotificationCenter.default.post(name: .settingsChanged, object: nil, userInfo: [key: value])
}
// MARK: - Onboarding & roots
extension SettingsKeys {
    /// First-run startup wizard completion flag
    static let setupWizardDone = "setupWizardDone"
    /// Preferred initial view at launch ("lattice" | "tuner")
    static let defaultView = "defaultView"
    
    // Back-compat aliases (older call sites)
    static let preferredInputPortUID       = audioPreferredInputPortUID
    static let preferredInputDataSourceID  = audioPreferredInputDataSourceID
    static let preferredSampleRate         = audioPreferredSampleRate
    static let preferredBufferFrames       = audioPreferredBufferFrames

}


extension SettingsKeys {
    // Routing prefs
    static let audioOutputUID     = "audio.output.uid"

    // Pro-audio tuning
    static let proAudioPreferredSampleRate        = "pro.audio.preferred.sampleRate"         // Double (Hz)
    static let proAudioPreferredIOBufferDuration  = "pro.audio.preferred.ioBufferDuration"   // Double (seconds)
}
