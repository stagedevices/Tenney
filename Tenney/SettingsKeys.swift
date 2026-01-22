//
//  SettingsKeys.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//
import Foundation
import SwiftUI


enum SettingsKeys {

    // Diagnostics & crash reporting
    static let crashReportingEnabled = "tenney.crashReportingEnabled"
    static let lastSessionCrashTimestamp = "tenney.lastSessionCrashTimestamp"
    static let lastCrashBannerDismissedAt = "tenney.lastCrashBannerDismissedAt"
    
    // NEW (single-value, v0.3+)
        static let latticeHexGridStrength     = "lattice.hexGrid.strength"
        static let latticeHexGridMajorEnabled = "lattice.hexGrid.major.enabled"
        static let latticeHexGridMajorEvery   = "lattice.hexGrid.major.every"

        // NOTE: keep existing v0.2 keys for migration only:
    // Lattice Grid (single set)
    static let latticeGridStyle        = "Tenney.Lattice.Grid.Style"         // String: off|cells|mesh|rails
    static let latticeGridWeight       = "Tenney.Lattice.Grid.Weight"        // String: thin|light|medium|bold|heavy
    static let latticeGridMajorEnabled = "Tenney.Lattice.Grid.Major.Enabled" // Bool
    static let latticeGridMajorEvery   = "Tenney.Lattice.Grid.Major.Every"   // Int
    
    // LEGACY: Lattice Hex Grid (old per-theme keys; retained for migration only)
    // Lattice Hex Grid (per-theme: light/dark)
    static let latticeHexGridMode = "Tenney.Lattice.HexGrid.Mode" // shared
    static let latticeHexGridEnabledLight = "Tenney.Lattice.HexGrid.Enabled.Light"
    static let latticeHexGridEnabledDark = "Tenney.Lattice.HexGrid.Enabled.Dark"
    static let latticeHexGridStrengthLight = "Tenney.Lattice.HexGrid.Strength.Light"
    static let latticeHexGridStrengthDark = "Tenney.Lattice.HexGrid.Strength.Dark"

    static let latticeHexGridMajorEnabledLight = "Tenney.Lattice.HexGrid.Major.Enabled.Light"
    static let latticeHexGridMajorEnabledDark  = "Tenney.Lattice.HexGrid.Major.Enabled.Dark"
    static let latticeHexGridMajorEveryLight   = "Tenney.Lattice.HexGrid.Major.Every.Light"
    static let latticeHexGridMajorEveryDark    = "Tenney.Lattice.HexGrid.Major.Every.Dark"
    
    
    static let lastSeenBuild = "tenney.lastSeenBuild"

    static let tenneyDistanceMode = "tenney.distance.mode"
    
    // Lattice View State
    static let latticeDefaultZoomPreset = "tenney.lattice.defaultZoomPreset" // String ("close"|"standard"|"wide"|"overview")
    static let latticeRememberLastView  = "tenney.lattice.rememberLastView"  // Bool (default true)

    
    // Tuning
    static let a4Choice      = "tenney.tuner.a4Choice"     // "440" | "442" | "custom"
    static let a4CustomHz    = "tenney.tuner.a4CustomHz"   // Double
    static let staffA4Hz     = "tenney.tuner.staffA4Hz"    // Double (cached, used by NotationFormatter)
    // Tuner UI style (Gauge vs Chrono Dial vs Scope)
    static let tunerViewStyle = "Tenney.Tuner.ViewStyle"

    // Confidence / needle behavior
    static let tunerNeedleHoldMode = "Tenney.Tuner.NeedleHoldMode"

    // NEW: Themes
    static let tenneyThemeID          = "tenney.theme.id"                 // String (builtin rawValue or "custom:<uuid>")
    static let tenneyThemeMixBasis    = "tenney.theme.mixing.basis"       // String (TenneyMixBasis)
    static let tenneyThemeMixMode     = "tenney.theme.mixing.mode"        // String (TenneyMixMode)
    static let tenneyThemeScopeMode   = "tenney.theme.scope.mode"         // String (TenneyScopeColorMode)
    static let tenneyCustomThemes     = "tenney.theme.customThemes"       // Data ([CustomTheme])

    //scope tuner
    static let tunerScopePartial = "Tenney.Tuner.ScopePartial"
    static let tunerScopeReferenceOn = "Tenney.Tuner.ScopeReferenceOn"

    // First-run wizard
        static let hasRunSetupV1   = "Tenney.Setup.HasRunV1"
        static let startDefaultTab = "Tenney.Setup.StartDefaultTab" // "lattice" / "tuner"
    
        // Initial Root Pitch (used by Lattice/Tuner root)
        static let rootHz          = "Tenney.Root.Hz" // Double (e.g. 415)

    // Labels
    static let labelDefault       = "tenney.label.default"       // "ratio" | "heji"
    static let showRatioAlongHeji = "tenney.label.showRatio"     // Bool
    static let infoCardNotationMode = "tenney.label.notationMode" // "staff" | "text" | "combined"
    static let accidentalPreference = "tenney.label.accidentalPreference" // "auto" | "preferSharps" | "preferFlats"

    // Lattice UI
    static let nodeSize      = "tenney.ui.nodeSize"        // "s" | "m" | "mplus" | "l"
    static let labelDensity  = "tenney.ui.labelDensity"    // Double 0...1
    static let guidesOn      = "tenney.ui.guidesOn"        // Bool
    static let overlay7      = "tenney.ui.overlay7"        // Bool
    static let overlay11     = "tenney.ui.overlay11"       // Bool
    static let foldAudible   = "tenney.lattice.foldAud"    // Bool (fold 20–5k)
    
    static let latticeConnectionMode = "Tenney.Lattice.Connection.Mode" // String: chain|loop|gridPath
    static let builderExportCustomA4Hz = "Tenney.Builder.ExportCustomA4Hz"
    static let latticeSoundEnabled = "Tenney.Latticetice.SoundEnabled"
    
    // MARK: Learn Tenney
        static let learnLatticeTourCompleted = "Tenney.Learn.latticeTourCompleted" // Bool
        static let learnTunerTourCompleted   = "Tenney.Learn.tunerTourCompleted"   // Bool
        static let learnBuilderTourCompleted = "Tenney.Learn.builderTourCompleted" // Bool
        static let learnLastTipDayStamp      = "Tenney.Learn.lastTipDayStamp"      // String "YYYY-MM-DD"
        static let learnTipsMode             = "Tenney.Learn.tipsMode"             // String ("learnOnly" | "learnAndUI")
    

    static let builderExportFormats   = "Tenney.Builder.ExportFormats"
        static let builderExportRootMode  = "Tenney.Builder.ExportRootMode"
    
    // Stage mode customization
    static let stageDimLevel     = "tenney.stage.dimLevel"        // Double 0.0...1.0 (how dark outside area gets)
    static let stageAccent       = "tenney.stage.accent"          // "system" | "amber" | "red"
    static let stageHideStatus   = "tenney.stage.hideStatus"      // Bool
    static let stageKeepAwake    = "tenney.stage.keepAwake"       // Bool
    static let stageMinimalUI    = "tenney.stage.minimalUI"       // Bool
    static let selectionTrayClearBehavior = "tenney.lattice.selectionTrayClearBehavior" // String

    // Sound
    static let attackMs   = "tenney.audio.attackMs"        // Double
    static let releaseSec = "tenney.audio.releaseSec"      // Double
    static let safeAmp    = "tenney.audio.safeAmp"         // Double

    // Library filters
    static let libraryFiltersJSON = "tenney.library.filters.json"
    static let librarySearchText = "tenney.library.search"
    static let libraryFavoritesOnly = "tenney.library.favoritesOnly"
    static let librarySortKey = "tenney.library.sortKey"
    static let libraryFavoriteIDsJSON = "tenney.library.favorites.json"
    static let communityPackLastPreviewedScaleIDs = "tenney.communityPacks.lastPreviewedScaleIDs"

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

    // Mac Catalyst: Tuner Rail
    static let tunerRailShow            = "tenney.tunerRail.show"
    static let tunerRailActivePresetID  = "tenney.tunerRail.activePresetID"
    static let tunerRailPresetsJSON     = "tenney.tunerRail.presetsJSON"
    static let tunerRailIntervalTapeMs  = "tenney.tunerRail.intervalTape.ms"
    
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
