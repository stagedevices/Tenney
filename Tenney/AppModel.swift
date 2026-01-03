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

// Lightweight global read-only handle so non-View code can read rootHz safely.
enum AppModelLocator {
    // Register a handle for helpers that need read-only access to rootHz.
    static var shared: AppModel? }

@MainActor
final class AppModel: ObservableObject {
    private var micPCMTap: (([Float], Double) -> Void)?
    func attachMicPCMTap(_ tap: @escaping ([Float], Double) -> Void) {
        micPCMTap = tap
    }

    func detachMicPCMTap() {
        micPCMTap = nil
    }

    @AppStorage(SettingsKeys.latticeSoundEnabled)
    private var latticeSoundSetting: Bool = true

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
    }
    
    deinit {
        if let o = _recenterObserver { NotificationCenter.default.removeObserver(o) }
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
    
    // Settings deep-link (Mac Catalyst)
    @Published var openSettingsToTunerRail: Bool = false
    private let audio = AudioEngineService()
    // Scene activity + desired mic state
    @Published private(set) var sceneIsActive: Bool = true
    private var desiredMicActive: Bool = true
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
    
    @Published var builderPayload: ScaleBuilderPayload? = nil
    
    /// When user taps "Add from Lattice" in Builder, we dismiss the sheet and
    /// When Builder closes with “Add from Lattice”, remember the base count.
    @Published var builderStagingBaseCount: Int? = nil
    
    func configureAndStart() {
#if DEBUG
        PitchAccuracyHarness.run()
#endif
        
        // seed UI state immediately
        switch MicrophonePermission.status() {
        case .granted:      micPermission = .granted
        case .denied:       micPermission = .denied
        case .undetermined: micPermission = .unknown
        }

        // IMPORTANT: restartPipeline() is what will trigger the macOS prompt (via ensureGranted)
        if sceneIsActive && desiredMicActive {
            restartPipeline()
        }

    }
    
    func restartPipeline() {
        audio.stop(deactivateSession: false)
        fft = nil; phaseRefiner = nil; pll = nil; smoother = nil
        pipelineStart = Date()
        analysisBuffer.removeAll(); lastHzEstimate = nil
        
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

        // Pass the config to audio.start (only after permission is granted)
        MicrophonePermission.ensureGranted(
            { [weak self] in
                guard let self else { return }
                self.micPermission = .granted
                self.micDenied = false
                self.audio.start(config: config) { [weak self] samples, sr in
                    self?.process(samples: samples, sr: sr)
                }
            },
            onDenied: { [weak self] in
                guard let self else { return }
                self.micPermission = .denied
                self.micDenied = true
                self.display = .noInput(rootHz: self.effectiveRootHz)
            }
        )

    }
    
    func stop() { audio.stop(deactivateSession: true); toneOutput.stop() }
    // MARK: Mic on/off (used by ContentView when switching modes)
    // MARK: Mic on/off (used by views)
    /// Request mic activity. Will only actually start if the scene is active and permission is granted.
    func setMicActive(_ active: Bool) {
        desiredMicActive = active
        
        let shouldRunMic = sceneIsActive && desiredMicActive
        
        if shouldRunMic, micPermission == .granted {
            restartPipeline()
        } else {
            audio.stop(deactivateSession: false)
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
        let shouldRunMic = (phase == .active) && desiredMicActive
        sceneIsActive = (phase == .active)
        
        if shouldRunMic, micPermission == .granted {
            restartPipeline()
        } else {
            audio.stop(deactivateSession: true)
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
