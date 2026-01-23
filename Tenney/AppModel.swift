//
//  AppModel.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//


import Foundation
import AVFoundation
import Combine
import Accelerate
import SwiftUI
import UIKit
#if DEBUG
import CryptoKit
#endif

// Lightweight global read-only handle so non-View code can read rootHz safely.
enum AppModelLocator {
    // Register a handle for helpers that need read-only access to rootHz.
    static var shared: AppModel? }

@MainActor
final class AppModel: ObservableObject {
    struct BuilderSessionState: Equatable {
        var sessionID: UUID? = nil
        var savedScaleID: TenneyScale.ID? = nil
        var isEdited: Bool = false
        var pendingAddRefs: [RatioRef]? = nil
        var draftInitialized: Bool = false
        var draftName: String = ""
        var draftDescription: String = ""
        var draftRootHz: Double = 440.0
        var draftDegrees: [RatioRef] = []
        var baselineSignature: Int? = nil
        var displayName: String = ""

        var isUnsavedDraft: Bool { savedScaleID == nil }
    }

    private var micPCMTap: (([Float], Double) -> Void)?
    func attachMicPCMTap(_ tap: @escaping ([Float], Double) -> Void) {
        micPCMTap = tap
    }

    func detachMicPCMTap() {
        micPCMTap = nil
    }

    @AppStorage(SettingsKeys.latticeSoundEnabled)
    private var latticeSoundSetting: Bool = true

    @Published var builderSession: BuilderSessionState = .init()
    @Published var builderSessionPayload: ScaleBuilderPayload? = nil
    @Published var builderPresented: Bool = false
    private var _recenterObserver: NSObjectProtocol?
    init() {
    
        _recenterObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard UserDefaults.standard.bool(forKey: SettingsKeys.latticeAlwaysRecenterOnQuit) else { return }
            UserDefaults.standard.set(true, forKey: SettingsKeys.latticeRecenterPending)
        }
        AppModelLocator.shared = self
        latticeAuditionOn = latticeSoundSetting
        let done = UserDefaults.standard.bool(forKey: SettingsKeys.setupWizardDone)
            self.showOnboardingWizard = !done
        DiagnosticsCenter.shared.event(category: "app", level: .info, message: "AppModel init")
        SentryService.shared.breadcrumb(category: "app", message: "AppModel init")
        registerAudioSessionObservers()
    }
    
    deinit {
        if let o = _recenterObserver { NotificationCenter.default.removeObserver(o) }
        audioSessionObservers.forEach(NotificationCenter.default.removeObserver)
    }
    
    enum MicPermissionState { case unknown, denied, granted }
    
    @Published var micPermission: MicPermissionState = .unknown
    @Published var micDenied: Bool = false
    @Published var display: TunerDisplay = .empty
    @Published var rootHz: Double = {
        // Load persisted root Hz (independent from A4 ET reference)
        let v = UserDefaults.standard.double(forKey: SettingsKeys.rootHz)
        return v == 0 ? 415.0 : v
    }() {
        didSet {
            UserDefaults.standard.set(rootHz, forKey: SettingsKeys.rootHz)
            if playTestTone { toneOutput.setFrequency(rootHz) }
            // Broadcast so interested views can react live (e.g., Lattice/Tuner)
            postSetting(SettingsKeys.rootHz, rootHz)
            LearnEventBus.shared.send(.tunerRootChanged(rootHz))
        }
    }
    @Published var tunerRootOverride: RatioRef? = nil
    @Published var primeLimit: Int = 11   // 3–11; 13 in Advanced later
    @Published var tunerPrimeLimit: Int = {
        let v = UserDefaults.standard.integer(forKey: SettingsKeys.tunerPrimeLimit)
        return (v == 0 ? 11 : v) // defaults to 11 when unset
    }() {
        didSet { UserDefaults.standard.set(tunerPrimeLimit, forKey: SettingsKeys.tunerPrimeLimit) }
    }
    
    @Published var strictness: Strictness = .performance
    @Published var playTestTone: Bool = false {
        didSet {
            if playTestTone {
                _ = toneOutput.start(frequency: rootHz)
            } else {
                toneOutput.stop()
            }
            LearnEventBus.shared.send(.tunerOutputEnabledChanged(playTestTone))
        }
    }
    /// Controls showing the onboarding wizard as a liquid-glass modal overlay.
    @Published var showOnboardingWizard: Bool = false
    // Lattice audition state (UtilityBar ↔ LatticeScreen sync)
    @Published var latticeAuditionOn: Bool = true {
        didSet {
            latticeSoundSetting = latticeAuditionOn
            postSetting(SettingsKeys.latticeSoundEnabled, latticeAuditionOn)
        }
    }
    // Library detent presentation
    @Published var showScaleLibraryDetent: Bool = false
    enum ScaleLibraryLaunchMode: Equatable {
        case recents
        case favorites
    }

    @Published var scaleLibraryLaunchMode: ScaleLibraryLaunchMode? = nil

    // Settings deep-link (Mac Catalyst)
    @Published var openSettingsToTunerRail: Bool = false
    private let audio = AudioEngineService()
    // Scene activity + desired mic state
    @Published private(set) var sceneIsActive: Bool = true
    @Published private(set) var pipelineWanted: Bool = true
    @Published private(set) var pipelineActive: Bool = false
    @Published private(set) var pipelineInterrupted: Bool = false
    private var desiredMicActive: Bool = true
    private var permissionRequestInFlight = false
    private var audioSessionObservers: [NSObjectProtocol] = []
    private let toneOutput = ToneOutputEngine.shared
    // New DSP stack
    private var stableHzForSizing: Double = 261.63
    // Hop / overlap discipline
    private var analysisHop: Int = 0              // samples (e.g. N/4)
    private var analysisFrameCount: Int = 0
    private var hopAccumulator: Int = 0
    
    // FFT resizing discipline (slow adaptation)
    private var lastSizerHz: Double = 261.63
    private var lastResizeFrame: Int = 0
    private let resizeMinFrameGap: Int = 12       // only allow resize every ~12 analysis frames
    private let resizeRelHzThreshold: Double = 0.08 // ~8% change before we consider resizing
    
    // Tiny pre-Kalman stabilizer
    private var medianWindowHz: [Double] = []
    private let medianWindowN: Int = 5
    
    private var fft: PitchFFT?
    private var phaseRefiner: PhaseRefiner?
    private var pll: DigitalPLL?
    private var smoother: PitchSmoother?
    private var strobeRef = StrobeRefSynth(sampleRate: 48_000)
    private var analysisBuffer: [Float] = []
    private var lastFFTSize: Int = 0
    private var lastHzEstimate: Double?
    private var pipelineStart = Date()
    private let ratioSolver = RatioSolver()
    
    private var lastGoodUpdate = Date.distantPast
    
    private var preferredInputPortUID: String? { UserDefaults.standard.string(forKey: SettingsKeys.preferredInputPortUID) }
    private var preferredInputDataSourceID: String? { UserDefaults.standard.string(forKey: SettingsKeys.preferredInputDataSourceID) }
    private var preferredSampleRate: Double? {
        let v = UserDefaults.standard.double(forKey: SettingsKeys.preferredSampleRate)
        return v == 0 ? nil : v
    }
    private var preferredBufferFrames: Int? {
        let v = UserDefaults.standard.integer(forKey: SettingsKeys.preferredBufferFrames)
        return v == 0 ? nil : v
    }
    
    private func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[s.count / 2]
    }

    var effectiveRootHz: Double {
        guard let ref = tunerRootOverride else { return rootHz }
        return frequencyHz(rootHz: rootHz, ratio: ref, foldToAudible: false)
    }
    
    func setTunerRootOverride(_ ref: RatioRef) {
        tunerRootOverride = ref
    }
    
    func clearTunerRootOverride() {
        tunerRootOverride = nil
    }
    
    
    // Instrument profiles you requested
    enum InstrumentProfile { case harpsichord, strings, microtonal }
    @Published var instrumentProfile: InstrumentProfile = .microtonal
    
    // MARK: - Builder staging
    
    @Published var builderPayload: ScaleBuilderPayload? = nil {
        didSet {
            guard let payload = builderPayload else { return }
            if let existing = payload.existing {
                builderLoadedScale = existing
            } else {
                builderLoadedScale = nil
            }
            builderSessionPayload = payload
            seedBuilderDraftFromPayloadIfNeeded(payload)
            initializeBuilderSessionIfNeeded()
        }
    }

    @Published var builderLoadedScale: TenneyScale? = nil {
        didSet {
            if builderLoadedScale?.id != oldValue?.id {
                clearLoadedScaleMetadata()
                builderSession.savedScaleID = builderLoadedScale?.id
                builderSession.isEdited = false
                builderSession.pendingAddRefs = nil
                if let existing = builderLoadedScale {
                    seedBuilderDraft(from: existing)
                    builderSession.displayName = normalizedScaleName(existing.name)
                    builderSession.sessionID = UUID()
                    builderSession.baselineSignature = nil
                } else {
                    builderSession = .init()
                }
            }
        }
    }

    @Published var loadedScaleDisplayNameOverride: String? = nil
    @Published var loadedScaleMetadataEdited: Bool = false
    
    /// When user taps "Add from Lattice" in Builder, we dismiss the sheet and
    /// When Builder closes with “Add from Lattice”, remember the base count.
    @Published var builderStagingBaseCount: Int? = nil

    func unloadBuilderScale() {
        builderPayload = nil
        builderLoadedScale = nil
        builderStagingBaseCount = nil
        builderPresented = false
        builderSessionPayload = nil
        builderSession = .init()
    }

    func resumeBuilderSessionFromRail() {
        guard builderSessionExists else { return }
        guard !builderPresented else { return }
        guard let payload = builderSessionPayload else {
#if DEBUG
            assertionFailure("Builder session exists without payload when resuming from rail.")
#endif
            return
        }
        builderPayload = payload
    }

    func appendBuilderDraftRefs(_ refs: [RatioRef]) {
        guard !refs.isEmpty else { return }
        if !builderSession.draftInitialized {
            if let existing = builderLoadedScale ?? builderSessionPayload?.existing {
                seedBuilderDraft(from: existing)
            } else if let payload = builderSessionPayload ?? builderPayload {
                seedBuilderDraft(from: payload)
            } else {
                builderSession.draftInitialized = true
                builderSession.draftName = "Untitled Scale"
                builderSession.draftDescription = ""
                builderSession.draftRootHz = rootHz
                builderSession.draftDegrees = []
            }
        }
        builderSession.draftDegrees.append(contentsOf: refs)
        builderSession.pendingAddRefs = nil
        ensureBuilderSessionID()
        updateBuilderSessionDisplayName(builderSession.draftName)
        updateDraftEditedState()
        syncBuilderSessionPayloadFromDraft()
    }

    func updateBuilderDraft(
        name: String,
        description: String,
        rootHz: Double,
        degrees: [RatioRef]
    ) {
        ensureBuilderSessionID()
        builderSession.draftInitialized = true
        builderSession.draftName = name
        builderSession.draftDescription = description
        builderSession.draftRootHz = rootHz
        builderSession.draftDegrees = degrees
        updateBuilderSessionDisplayName(name)
        updateDraftEditedState()
        syncBuilderSessionPayloadFromDraft()
    }

    private func seedBuilderDraft(from scale: TenneyScale) {
        builderSession.draftInitialized = true
        builderSession.draftName = scale.name
        builderSession.draftDescription = scale.descriptionText
        builderSession.draftRootHz = scale.referenceHz
        builderSession.draftDegrees = scale.degrees
        updateBuilderSessionDisplayName(scale.name)
    }

    private func seedBuilderDraft(from payload: ScaleBuilderPayload) {
        builderSession.draftInitialized = true
        builderSession.draftName = payload.existing?.name ?? payload.title
        builderSession.draftDescription = payload.existing?.descriptionText ?? payload.notes
        builderSession.draftRootHz = payload.rootHz
        builderSession.draftDegrees = payload.items
        updateBuilderSessionDisplayName(payload.existing?.name ?? payload.title)
    }

    private func seedBuilderDraftFromPayloadIfNeeded(_ payload: ScaleBuilderPayload) {
        guard !builderSession.draftInitialized else { return }
        if let existing = payload.existing {
            seedBuilderDraft(from: existing)
        } else {
            seedBuilderDraft(from: payload)
        }
    }

    private func initializeBuilderSessionIfNeeded() {
        ensureBuilderSessionID()
        updateDraftEditedState()
    }

    private func ensureBuilderSessionID() {
        if builderSession.sessionID == nil {
            builderSession.sessionID = UUID()
        }
    }

    private func normalizedScaleName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scale" : trimmed
    }

    private func updateBuilderSessionDisplayName(_ name: String) {
        builderSession.displayName = normalizedScaleName(name)
    }

    private func builderSessionSignature(
        name: String,
        description: String,
        rootHz: Double,
        degrees: [RatioRef]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(name.trimmingCharacters(in: .whitespacesAndNewlines))
        hasher.combine(description.trimmingCharacters(in: .whitespacesAndNewlines))
        hasher.combine(rootHz)
        for ref in degrees {
            hasher.combine(ref)
        }
        return hasher.finalize()
    }

    private func updateDraftEditedState() {
        guard builderSession.savedScaleID == nil else { return }
        let signature = builderSessionSignature(
            name: builderSession.draftName,
            description: builderSession.draftDescription,
            rootHz: builderSession.draftRootHz,
            degrees: builderSession.draftDegrees
        )
        if builderSession.baselineSignature == nil {
            builderSession.baselineSignature = signature
            builderSession.isEdited = false
            return
        }
        builderSession.isEdited = signature != builderSession.baselineSignature
    }

    private func syncBuilderSessionPayloadFromDraft() {
        guard let payload = builderSessionPayload ?? builderPayload else { return }
        var next = payload
        next.title = builderSession.draftName
        next.notes = builderSession.draftDescription
        next.rootHz = builderSession.draftRootHz
        next.items = builderSession.draftDegrees
        builderSessionPayload = next
    }

    func updateBuilderSessionEdited(loadedScaleEdited: Bool, metadataEdited: Bool) {
        guard builderSession.savedScaleID != nil else { return }
        let nextValue = loadedScaleEdited || metadataEdited
        if builderSession.isEdited != nextValue {
            builderSession.isEdited = nextValue
        }
    }

    func updateLoadedScaleMetadata(
        name: String,
        description: String,
        existing: TenneyScale?,
        isEdited: Bool? = nil
    ) {
        loadedScaleDisplayNameOverride = name
        if builderSession.sessionID != nil {
            updateBuilderSessionDisplayName(name)
        }
        if let isEdited {
            loadedScaleMetadataEdited = isEdited
            return
        }
        guard let existing else {
            loadedScaleMetadataEdited = false
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingName = existing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingDescription = existing.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        loadedScaleMetadataEdited = trimmedName != existingName || trimmedDescription != existingDescription
    }

    func clearLoadedScaleMetadata() {
        loadedScaleDisplayNameOverride = nil
        loadedScaleMetadataEdited = false
    }

    var builderSessionExists: Bool {
        builderSession.sessionID != nil
    }
    
    func configureAndStart() {
#if DEBUG
        PitchAccuracyHarness.run()
#endif
        DiagnosticsCenter.shared.event(category: "app", level: .info, message: "configureAndStart")
        SentryService.shared.breadcrumb(category: "app", message: "configureAndStart")
        
        // seed UI state immediately
        switch MicrophonePermission.status() {
        case .granted:      micPermission = .granted
        case .denied:       micPermission = .denied
        case .undetermined: micPermission = .unknown
        }

        // IMPORTANT: reconcilePipeline() is what will trigger the macOS prompt (via ensureGranted)
        reconcilePipeline(reason: "configureAndStart")

    }

    private func registerAudioSessionObservers() {
#if os(iOS) || targetEnvironment(macCatalyst)
        let center = NotificationCenter.default
        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] note in
                self?.handleAudioSessionInterruption(note)
            }
        )
        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                self?.reconcilePipeline(reason: "routeChange", forceRestart: true)
            }
        )
        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                self?.reconcilePipeline(reason: "mediaServicesReset", forceRestart: true)
            }
        )
#endif
    }

    private func suspendPipeline(reason: String?, deactivateSession: Bool) {
        guard pipelineActive || audio.running else { return }
        audio.stop(deactivateSession: deactivateSession)
        pipelineActive = false
        if let reason {
            DiagnosticsCenter.shared.event(category: "audio", level: .info, message: "suspend pipeline", meta: ["reason": reason])
        }
        SentryService.shared.breadcrumb(category: "audio", message: "suspend pipeline")
    }

    private func reconcilePipeline(reason: String? = nil, forceRestart: Bool = false) {
        guard pipelineWanted, sceneIsActive else {
            if !sceneIsActive {
                suspendPipeline(reason: reason, deactivateSession: true)
            } else if !pipelineWanted {
                suspendPipeline(reason: reason, deactivateSession: false)
                pipelineInterrupted = false
            }
            return
        }

        let status = MicrophonePermission.status()
        switch status {
        case .granted:
            micPermission = .granted
            micDenied = false
            if forceRestart || !audio.running {
                restartPipeline(ensurePermission: false)
            } else {
                pipelineActive = audio.running
                pipelineInterrupted = false
            }
        case .denied:
            micPermission = .denied
            micDenied = true
            pipelineActive = false
            suspendPipeline(reason: reason, deactivateSession: true)
            display = .noInput(rootHz: effectiveRootHz)
        case .undetermined:
            micPermission = .unknown
            guard !permissionRequestInFlight else { return }
            permissionRequestInFlight = true
            MicrophonePermission.ensure { [weak self] granted in
                guard let self else { return }
                self.permissionRequestInFlight = false
                self.micPermission = granted ? .granted : .denied
                self.micDenied = !granted
                guard granted, self.pipelineWanted, self.sceneIsActive else {
                    if !granted {
                        self.display = .noInput(rootHz: self.effectiveRootHz)
                    }
                    return
                }
                self.restartPipeline(ensurePermission: false)
            }
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            pipelineInterrupted = true
            suspendPipeline(reason: "interruptionBegan", deactivateSession: false)
        case .ended:
            pipelineInterrupted = false
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            if options.contains(.shouldResume) {
                reconcilePipeline(reason: "interruptionEnded", forceRestart: true)
            }
        @unknown default:
            pipelineInterrupted = false
        }
    }
    
    func restartPipeline(ensurePermission: Bool = true) {
        audio.stop(deactivateSession: false)
        pipelineActive = false
        fft = nil; phaseRefiner = nil; pll = nil; smoother = nil
        pipelineStart = Date()
        analysisBuffer.removeAll(); lastHzEstimate = nil
        DiagnosticsCenter.shared.event(category: "audio", level: .info, message: "restartPipeline")
        SentryService.shared.breadcrumb(category: "audio", message: "restartPipeline")
        
        // Only start if we are active and allowed to run.
        guard sceneIsActive, desiredMicActive else { return }

        // Create the config here
        let config = AudioIOConfig(
            preferredInputPortUID: preferredInputPortUID,
            preferredInputDataSourceID: preferredInputDataSourceID,
            preferredSampleRate: preferredSampleRate,
            bufferFrames: preferredBufferFrames
        )
        print("mic status:", MicrophonePermission.status())

        let startAudio: () -> Void = { [weak self] in
            guard let self else { return }
            self.micPermission = .granted
            self.micDenied = false
            self.audio.start(config: config) { [weak self] samples, sr in
                self?.process(samples: samples, sr: sr)
            }
            self.pipelineActive = self.audio.running
            self.pipelineInterrupted = false
        }

        if ensurePermission {
            permissionRequestInFlight = true
            // Pass the config to audio.start (only after permission is granted)
            MicrophonePermission.ensureGranted(
                { [weak self] in
                    guard let self else { return }
                    self.permissionRequestInFlight = false
                    startAudio()
                },
                onDenied: { [weak self] in
                    guard let self else { return }
                    self.permissionRequestInFlight = false
                    self.micPermission = .denied
                    self.micDenied = true
                    self.pipelineActive = false
                    self.display = .noInput(rootHz: self.effectiveRootHz)
                }
            )
        } else {
            startAudio()
        }

    }
    
    func stop() { audio.stop(deactivateSession: true); toneOutput.stop() }
    // MARK: Mic on/off (used by ContentView when switching modes)
    // MARK: Mic on/off (used by views)
    /// Request mic activity. Will only actually start if the scene is active and permission is granted.
    func setMicActive(_ active: Bool) {
        desiredMicActive = active
        pipelineWanted = active
        if !active {
            pipelineInterrupted = false
        }
        reconcilePipeline(reason: "setMicActive")
    }

    func setPipelineActive(_ active: Bool, reason: String? = nil) {
        setMicActive(active)
        if let reason {
            DiagnosticsCenter.shared.event(
                category: "tuner",
                level: .info,
                message: "practice mic \(active ? "on" : "off")",
                meta: ["reason": reason]
            )
        }
    }
    
    // MARK: - Scale Library actions
    
    func openBuilder(with scale: TenneyScale) {
        NotificationCenter.default.post(
            name: .tenneyOpenBuilderFromScaleLibrary,
            object: scale
        )
    }
    
    func addToBuilder(scale: TenneyScale) {
        NotificationCenter.default.post(
            name: .tenneyAddScaleToBuilderFromLibrary,
            object: scale
        )
    }
    
    func previewScale(_ scale: TenneyScale) {
        // Update library metadata (best-effort)
        var updated = scale
        updated.lastPlayed = Date()
        ScaleLibraryStore.shared.updateScale(updated)
        
        NotificationCenter.default.post(
            name: .tenneyPreviewScaleFromLibrary,
            object: updated
        )
        
        // Short audible ping (keeps this “preview” behavior simple + reliable)
        _ = toneOutput.start(frequency: updated.rootHz)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.toneOutput.stop()
        }
    }
    
    
    // MARK: Scene phase
    func scenePhaseDidChange(_ phase: ScenePhase) {
        sceneIsActive = (phase == .active)
        if sceneIsActive {
            reconcilePipeline(reason: "sceneActive", forceRestart: true)
        } else {
            suspendPipeline(reason: "sceneInactive", deactivateSession: true)
        }
    }
    
    // MARK: - New core: dual-path fusion + PLL + smoothing
    private func process(samples: [Float], sr: Double) {
        guard !samples.isEmpty else { return }
        // Extra guard: if scene went inactive between capture and process, drop frame.
        guard sceneIsActive else { return }
        
        // Lazy init DSP
        if fft == nil {
            let f = PitchFFT(sampleRate: sr)
#if DEBUG
            f.debugHook = { print($0) }
#endif
            fft = f
        }
        if pll == nil { pll = DigitalPLL(sampleRate: sr, hop: max(1, analysisHop)) }
        if smoother == nil { smoother = PitchSmoother(sampleRate: sr, hop: max(1, analysisHop)) }
        
        // --- slow FFT size adaptation (don’t resize every frame) ---
        analysisFrameCount += 1
        let relHzDelta = abs(stableHzForSizing - lastSizerHz) / max(lastSizerHz, 1e-9)
        let canResize = (analysisFrameCount - lastResizeFrame) >= resizeMinFrameGap
        if canResize && relHzDelta >= resizeRelHzThreshold {
            fft!.ensureSize(cycles: 8.0, f0Guess: stableHzForSizing)
            lastSizerHz = stableHzForSizing
            lastResizeFrame = analysisFrameCount
        }
        
        // FFT frame + hop (25% hop => 75% overlap)
        let needed = fft!.frameSize
        let desiredHop = max(1, needed / 4)
        if analysisHop != desiredHop {
            analysisHop = desiredHop
            hopAccumulator = 0
            pll = DigitalPLL(sampleRate: sr, hop: analysisHop)
            smoother = PitchSmoother(sampleRate: sr, hop: analysisHop)
            phaseRefiner?.reset()
        }
        
        // Buffer incoming audio
        analysisBuffer.append(contentsOf: samples)
        
        // Process as many hop-steps as are available
        while analysisBuffer.count >= needed {
            let frame = Array(analysisBuffer.prefix(needed))
            
            let res = frame.withUnsafeBufferPointer {
                fft!.analyze($0, f0Hint: nil, hopSamples: analysisHop)
            }
            
            // advance by exactly one hop
            analysisBuffer.removeFirst(min(analysisHop, analysisBuffer.count))
            
            
            
            let refHz = res.f0Fast ?? res.peakFreq
            var fFast = refHz
            // Tiny stabilizer: median-of-5 on Hz (pre-PLL)
            medianWindowHz.append(fFast)
            if medianWindowHz.count > medianWindowN { medianWindowHz.removeFirst(medianWindowHz.count - medianWindowN) }
            if medianWindowHz.count >= 3, let m = median(medianWindowHz) {
                fFast = m
            }
            
            // Phase refinement (phase-coherent IF on a stable bin; converts harmonic IF → f0).
            if phaseRefiner == nil { phaseRefiner = PhaseRefiner(sampleRate: sr, hop: max(1, analysisHop)) }
            
            if res.confidence >= 0.6 && res.refineSNRdB >= 8 {
                if let fIF = phaseRefiner?.update(peakBin: res.refineBin, phase: res.spectrumPhaseAtRefine, fftSize: res.fftSize) {
                    let f0IF = fIF / Double(max(1, res.refineHarmonic))
                    if f0IF.isFinite, f0IF > 0 {
                        // Keep the phase path as a refinement, not the primary estimate.
                        fFast = 0.3 * f0IF + 0.7 * fFast
                    }
                }
            }
            guard fFast.isFinite, fFast > 0 else { continue }
            let snrConf = max(0.0, min(1.0, (Double(res.refineSNRdB) - 6.0) / 18.0)) // ~0 at 6dB, ~1 at 24dB
            let confForFilters = max(0.0, min(1.0, 0.65 * res.confidence + 0.35 * snrConf))
            let fPLL = pll!.update(measuredHz: fFast, confidence: confForFilters)
            
            // Slow path: inharmonicity fit (guarded to prevent subharmonic drifts)
            // Accept only if the fitted f0 stays close to BOTH the PLL and the FFT peak.
            var fSlow = fPLL
            if !res.partials.isEmpty {
                let ps = res.partials.map { (k: $0.index, freq: $0.freq, snrDB: Double(max(0, $0.snr))) }
                if let fit = HarmonicModel.fitF0Beta(initialF0: fPLL, partials: ps) {
                    // stricter quality + proximity checks
                    let r2OK = fit.r2 > 0.92
                    let relToPLL  = abs(fit.f0 - fPLL) / max(fPLL, 1e-9)
                    let relToRef  = abs(fit.f0 - refHz) / max(refHz, 1e-9)
                    if r2OK && relToPLL < 0.06 && relToRef < 0.06 {
                        // modest blend; keep PLL dominant
                        fSlow = 0.6 * fPLL + 0.4 * fit.f0
                    } else {
                        fSlow = fPLL
                    }
                }
            }
            
            // Instrument profile tweaks
            let fProfile: Double = {
                switch instrumentProfile {
                case .harpsichord:
                    // still allow some slow influence but keep PLL primary
                    return 0.4 * fSlow + 0.6 * fPLL
                case .strings:
                    return 0.2 * fSlow + 0.8 * fPLL
                case .microtonal:
                    // previously returned fSlow; that could wander to a subharmonic.
                    return 0.2 * fSlow + 0.8 * fPLL
                }
            }()
            // --- Fast-acquire logic ---
            // If we're just starting, or we see a large jump, momentarily bypass slow/PLL inertia.
            let relToRef = abs(fProfile - refHz) / max(refHz, 1e-9)
            let secondsSinceStart = Date().timeIntervalSince(pipelineStart)
            let largeJumpFromLast = lastHzEstimate.map {
                abs(fProfile - $0) / max(fProfile, 1e-9) > 0.02   // ~35 cents
            } ?? true
            let fastAcquire = (secondsSinceStart < 0.6) || largeJumpFromLast || (relToRef > 0.03)
            
            var fCandidate = fProfile
            if fastAcquire {
                // snap to the FFT peak while acquiring
                fCandidate = refHz
                // reset smoothing so we don't spend seconds ramping
                smoother = PitchSmoother(sampleRate: sr, hop: max(1, analysisHop))
            } else {
                // normal guard: if somehow far, clamp to peak
                if abs(fCandidate - refHz) / max(refHz, 1e-9) > 0.08 {
                    fCandidate = refHz
                }
            }
            
            // Map to nearest tempered index just for hysteresis state (JI labeling stays yours)
            let midiIdx = Int(round(69 + 12 * log2(fCandidate / 440.0)))
            // Boost confidence during fast-acquire so the smoother trusts the step
            let baseConf = confForFilters
            let confUsed = fastAcquire ? max(baseConf, 0.9) : baseConf
            let (fSmoothed, _) = smoother!.push(hz: fCandidate, conf: confUsed, mappedNoteIndex: midiIdx)
            lastHzEstimate = fSmoothed
            // Slow sizer tracking (prevents FFT size from chasing momentary shifts)
            stableHzForSizing = 0.92 * stableHzForSizing + 0.08 * fSmoothed
            
            
            // Your JI mapping & display (preserve RatioSolver & neighbors)
            let pack = ratioSolver.nearestWithNeighbors(for: fSmoothed, rootHz: effectiveRootHz, primeLimit: tunerPrimeLimit)
            let view = TunerDisplay(
                ratioText: tunerDisplayRatioString(pack.main),
                cents: signedCents(actualHz: fSmoothed, rootHz: effectiveRootHz, target: pack.main),
                hz: fSmoothed,
                confidence: res.confidence,
                lowerText: tunerDisplayRatioString(pack.lower),
                higherText: tunerDisplayRatioString(pack.higher)
            )
            
            Task { @MainActor in
                self.display = view
                self.lastGoodUpdate = Date()
            }
        }
    }
}

// MARK: - Helpers

// Zero-crossing estimator (robust): positive-going only + median period
private func zeroCrossHz(_ x: [Float], sr: Double) -> Double? {
    guard !x.isEmpty else { return nil }
    var last = x[0]
    var up: [Int] = []
    up.reserveCapacity(64)
    for i in 1..<x.count {
        let s = x[i]
        if last < 0 && s >= 0 { up.append(i) }   // positive-going only
        last = s
    }
    guard up.count >= 2 else { return nil }
    var periods: [Int] = []
    periods.reserveCapacity(up.count - 1)
    for i in 1..<up.count { periods.append(up[i] - up[i-1]) }
    periods.sort()
    let mid = periods[periods.count/2]
    guard mid > 0 else { return nil }
    return sr / Double(mid)
}

#if DEBUG
extension AppModel {
    static func debugDegreeHash(_ refs: [RatioRef]) -> String {
        let body = refs.map { "\($0.p)/\($0.q)@\($0.octave)" }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(body.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
