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

// Lightweight global read-only handle so non-View code can read rootHz safely.
enum AppModelLocator {
    // Register a handle for helpers that need read-only access to rootHz.
    static var shared: AppModel? }

@MainActor
final class AppModel: ObservableObject {
    init() { AppModelLocator.shared = self }
    
    enum MicPermissionState { case unknown, denied, granted }

    @Published var micPermission: MicPermissionState = .unknown
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
        @Published var latticeAuditionOn: Bool = false
        // Library detent presentation
        @Published var showScaleLibraryDetent: Bool = false
    private let audio = AudioEngineService()
    // Scene activity + desired mic state
        @Published private(set) var sceneIsActive: Bool = true
        private var desiredMicActive: Bool = true
    private let toneOutput = ToneOutputEngine.shared
    // New DSP stack
        private var fft: PitchFFT?
        private var phaseRefiner: PhaseRefiner?
        private var pll: DigitalPLL?
        private var smoother: PitchSmoother?
        private var strobeRef = StrobeRefSynth(sampleRate: 48_000)
        private var analysisBuffer: [Float] = []
        private var lastHzEstimate: Double?
    private var pipelineStart = Date()
        private let hopFrames: Int = 256
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

    // Instrument profiles you requested
        enum InstrumentProfile { case harpsichord, strings, microtonal }
        @Published var instrumentProfile: InstrumentProfile = .microtonal
    
    // MARK: - Builder staging
    
    @Published var builderPayload: ScaleBuilderPayload? = nil
    
    /// When user taps "Add from Lattice" in Builder, we dismiss the sheet and
    /// When Builder closes with “Add from Lattice”, remember the base count.
    @Published var builderStagingBaseCount: Int? = nil

    func configureAndStart() {
        AudioSession.requestMicPermission { [weak self] (granted: Bool) in
            Task { @MainActor in
                self?.micPermission = granted ? .granted : .denied
                // Only start immediately if the scene is active and we actually want the mic.
                                if self?.sceneIsActive == true, self?.desiredMicActive == true, granted {
                                    self?.restartPipeline()
                                } else {
                                    self?.audio.stop()
                                }
            }
        }
    }

    func restartPipeline() {
        audio.stop()
        fft = nil; phaseRefiner = nil; pll = nil; smoother = nil
        pipelineStart = Date()
        analysisBuffer.removeAll(); lastHzEstimate = nil

        // Only start if we are active and allowed to run.
        guard sceneIsActive, desiredMicActive, micPermission == .granted else { return }
        
        // Create the config here
        let config = AudioIOConfig(
            preferredInputPortUID: preferredInputPortUID,
            preferredInputDataSourceID: preferredInputDataSourceID,
            preferredSampleRate: preferredSampleRate,
            bufferFrames: preferredBufferFrames
        )
        
        // Pass the config to audio.start
        audio.start(config: config) { [weak self] samples, sr in
            self?.process(samples: samples, sr: sr)
        }
    }

    func stop() { audio.stop(); toneOutput.stop() }
    // MARK: Mic on/off (used by ContentView when switching modes)
    // MARK: Mic on/off (used by views)
        /// Request mic activity. Will only actually start if the scene is active and permission is granted.
        func setMicActive(_ active: Bool) {
            desiredMicActive = active
            guard sceneIsActive else {
                // If turning off while inactive, still stop immediately.
                if !active { audio.stop() }
                return
            }
            if active, micPermission == .granted {
                restartPipeline()
            } else {
                audio.stop()
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
            let nowActive = (phase == .active)
            sceneIsActive = nowActive
            if nowActive {
                // Restore pipeline only if caller wanted it.
                if desiredMicActive, micPermission == .granted { restartPipeline() }
            } else {
                // Quiesce immediately when leaving foreground.
                audio.stop()
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
            if pll == nil { pll = DigitalPLL(sampleRate: sr, hop: hopFrames) }
            if smoother == nil { smoother = PitchSmoother(sampleRate: sr, hop: hopFrames) }
    
            // Accumulate into analysis buffer (need N = ~6–12 cycles)
            let guess = lastHzEstimate ?? 261.63
            fft!.ensureSize(cycles: 8.0, f0Guess: guess) // shorter window → faster lock
            let needed = fft!.frameSize
            analysisBuffer.append(contentsOf: samples)
            if analysisBuffer.count < needed { return }
            // Take the most recent N samples
            let frame = Array(analysisBuffer.suffix(needed))
            // Keep buffer bounded
            if analysisBuffer.count > needed * 2 { analysisBuffer.removeFirst(analysisBuffer.count - needed * 2) }
    
            // FFT fast path
#if DEBUG
        // quick zero-crossing sanity against the same frame
        let zcHz = zeroCrossHz(frame, sr: sr)
        if let z = zcHz {
            print(String(format: "[ZC] %.3f Hz (sr=%.1f N=%d)", z, sr, frame.count))
        }
        #endif
        let res = frame.withUnsafeBufferPointer { fft!.analyze($0) }
            var fFast = res.f0Fast ?? res.peakFreq
    
            // Phase refinement (instantaneous frequency around the peak bin)
            if phaseRefiner == nil { phaseRefiner = PhaseRefiner(sampleRate: sr, hop: hopFrames) }
            if let fPhase = phaseRefiner?.update(peakBin: res.peakBin, phase: res.spectrumPhaseAtPeak) {
                fFast = 0.7 * fPhase + 0.3 * fFast
            }
            guard fFast.isFinite, fFast > 0 else { return }
    
            // PLL for low-jitter center
            let fPLL = pll!.update(measuredHz: fFast, confidence: res.confidence)
    
            // Slow path: inharmonicity fit (guarded to prevent subharmonic drifts)
                        // Accept only if the fitted f0 stays close to BOTH the PLL and the FFT peak.
                        var fSlow = fPLL
                        if !res.partials.isEmpty {
                            let ps = res.partials.map { (k: $0.index, freq: $0.freq, snrDB: Double(max(0, $0.snr))) }
                            if let fit = HarmonicModel.fitF0Beta(initialF0: fPLL, partials: ps) {
                                // stricter quality + proximity checks
                                let r2OK = fit.r2 > 0.92
                                let relToPLL  = abs(fit.f0 - fPLL) / max(fPLL, 1e-9)
                                let relToPeak = abs(fit.f0 - res.peakFreq) / max(res.peakFreq, 1e-9)
                                if r2OK && relToPLL < 0.06 && relToPeak < 0.06 {
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
                        let relToPeak = abs(fProfile - res.peakFreq) / max(res.peakFreq, 1e-9)
                        let secondsSinceStart = Date().timeIntervalSince(pipelineStart)
                        let largeJumpFromLast = lastHzEstimate.map {
                            abs(fProfile - $0) / max(fProfile, 1e-9) > 0.02   // ~35 cents
                        } ?? true
                        let fastAcquire = (secondsSinceStart < 0.6) || largeJumpFromLast || (relToPeak > 0.03)
            
                        var fCandidate = fProfile
                        if fastAcquire {
                            // snap to the FFT peak while acquiring
                            fCandidate = res.peakFreq
                            // reset smoothing so we don't spend seconds ramping
                            smoother = PitchSmoother(sampleRate: sr, hop: hopFrames)
                        } else {
                            // normal guard: if somehow far, clamp to peak
                            if abs(fCandidate - res.peakFreq) / max(res.peakFreq, 1e-9) > 0.08 {
                                fCandidate = res.peakFreq
                            }
                        }
    
            // Map to nearest tempered index just for hysteresis state (JI labeling stays yours)
            let midiIdx = Int(round(69 + 12 * log2(fCandidate / 440.0)))
            // Boost confidence during fast-acquire so the smoother trusts the step
                        let confUsed = fastAcquire ? max(res.confidence, 0.9) : res.confidence
                        let (fSmoothed, _) = smoother!.push(hz: fCandidate, conf: confUsed, mappedNoteIndex: midiIdx)
            lastHzEstimate = fSmoothed
    
            // Your JI mapping & display (preserve RatioSolver & neighbors)
            let pack = ratioSolver.nearestWithNeighbors(for: fSmoothed, rootHz: rootHz, primeLimit: tunerPrimeLimit)
            let view = TunerDisplay(
                ratioText: pack.main.ratioString,
                cents: signedCents(actualHz: fSmoothed, rootHz: rootHz, target: pack.main),
                hz: fSmoothed,
                confidence: res.confidence,
                lowerText: pack.lower.ratioString,
                higherText: pack.higher.ratioString
            )
    
            Task { @MainActor in
                self.display = view
                self.lastGoodUpdate = Date()
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
