//
//  TunerViewModel.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//
import Foundation
import Combine
import AVFoundation
@MainActor
final class TunerViewModel: ObservableObject {
    // MARK: - Phase Scope mic PCM hooks
        func attachMicPCMTap(_ cb: @escaping ([Float], Double) -> Void) {
            tracker.onAudioPCM = cb
        }
    
        func detachMicPCMTap() {
            tracker.onAudioPCM = nil
        }
    private func asResult(_ r: Ratio) -> RatioResult {
        RatioResult(num: r.n, den: r.d, octave: 0)
    }

    // Stage text
    @Published var displayRatio: String = "—"
    @Published var centsText: String = "—"
    @Published var hzText: String = "—"
    @Published var altRatios: [String] = []

    // Controls
    @Published var primeLimit: PrimeLimit = .eleven { didSet { resolver.limit = primeLimit } }
    @Published var strictness: Strictness = .performance { didSet { tracker.updateStrictness(strictness) } }
    @Published var rootHz: Double = 220.0 {
        didSet {
            resolver.rootHz = rootHz
            LearnEventBus.shared.send(.tunerRootChanged(rootHz))
        }
    }

    // Diagnostics
    @Published var inputRMS: Float = 0
    @Published var micGranted: Bool = false
    @Published private(set) var pipelineActive = false
    @Published var pipelineInterrupted: Bool = false

    // Test tone toggle (visible in UI)
    @Published var useTestTone: Bool = false {
        didSet {
            tracker.setTestTone(enabled: useTestTone, hz: 220.0)
            LearnEventBus.shared.send(.tunerOutputEnabledChanged(useTestTone))
        }
    }
    
    @Published var lastHzValue: Double = 0
    @Published var nearestTarget: RatioResult? = nil
    @Published var nearestCentsValue: Double = 0
    @Published var effectiveTarget: RatioResult? = nil
    @Published var lockedLabel: String = ""
    @Published var confidenceValue: Double = 0
    @Published var isFarValue: Bool = false

    @Published var lockedTarget: RatioResult? = nil {
        didSet {
            LearnEventBus.shared.send(.tunerLockToggled(lockedTarget != nil))
            lockedLabel = lockedTarget.map { "Locked to \(tunerDisplayRatioString($0))" } ?? ""
            let msg = lockedTarget == nil ? "unlock target" : "lock target"
            DiagnosticsCenter.shared.event(
                category: "tuner",
                level: .info,
                message: msg,
                meta: lockedTarget.flatMap { ["target": tunerDisplayRatioString($0)] }
            )
            SentryService.shared.breadcrumb(category: "tuner", message: msg)
        }
    }


    private let tracker: PitchTracker
    private let resolver = RatioResolver()
    private var lastSnapshot = Date.distantPast
    private var pipelineWanted = false
    private var permissionRequestInFlight = false
    private var audioSessionObservers: [NSObjectProtocol] = []
    
    private func confidenceFromRMS(_ rms: Float) -> Double {
        // RMS is linear 0..1-ish; tune these bounds for your input chain.
        let x = Double(rms)
        let lo = 0.008
        let hi = 0.060
        return max(0, min(1, (x - lo) / (hi - lo)))
    }


    init(tracker: PitchTracker = PitchTracker(strictness: .performance)) {
        // Configure detection
        self.tracker = tracker
        resolver.rootHz = rootHz
        resolver.limit  = primeLimit

        tracker.setUICallbacks(
                    onHz: { [weak self] hz, t in
                        guard let self else { return }
                        self.handle(hz: hz, monotonic: t)
                    },
                    onMetrics: { [weak self] rms in
                        guard let self else { return }
                        self.inputRMS = rms
                        self.confidenceValue = self.confidenceFromRMS(rms)
                    }
                )
        micGranted = (MicrophonePermission.status() == .granted)
        registerAudioSessionObservers()
    }

    deinit {
            let tracker = self.tracker
            Task { @MainActor in
                tracker.enableMicrophoneCapture(false)
                tracker.shutdown()
            }
            audioSessionObservers.forEach(NotificationCenter.default.removeObserver)
    }
    
    func setPipelineActive(_ active: Bool, reason: String? = nil) {
        pipelineWanted = active
        reconcilePipeline(reason: reason)
    }

    func suspendPipeline(reason: String? = nil) {
        guard pipelineActive || tracker.isRunning else { return }
        stopPipeline(reason: reason)
    }

    func reconcilePipeline(reason: String? = nil, forceRestart: Bool = false) {
        if !pipelineWanted {
            stopPipeline(reason: reason)
            pipelineInterrupted = false
            return
        }

        let status = MicrophonePermission.status()
        switch status {
        case .granted:
            micGranted = true
            if forceRestart || !tracker.isRunning {
                stopPipeline(reason: reason)
                activatePipeline(reason: reason)
            } else if !pipelineActive {
                activatePipeline(reason: reason)
            }
        case .denied:
            micGranted = false
            stopPipeline(reason: reason)
        case .undetermined:
            guard !permissionRequestInFlight else { return }
            permissionRequestInFlight = true
            MicrophonePermission.ensure { [weak self] granted in
                guard let self else { return }
                self.permissionRequestInFlight = false
                self.micGranted = granted
                guard granted, self.pipelineWanted else {
                    if !granted { self.stopPipeline(reason: reason) }
                    return
                }
                self.reconcilePipeline(reason: reason, forceRestart: forceRestart)
            }
        }
    }

    private func activatePipeline(reason: String?) {
        guard !pipelineActive else { return }
        tracker.startDetection()
        tracker.enableMicrophoneCapture(true)
        pipelineActive = tracker.isRunning
        if let reason {
            DiagnosticsCenter.shared.event(category: "tuner", level: .info, message: "start detection", meta: ["reason": reason])
        } else {
            DiagnosticsCenter.shared.event(category: "tuner", level: .info, message: "start detection")
        }
        SentryService.shared.breadcrumb(category: "tuner", message: "start detection")
    }

    private func stopPipeline(reason: String?) {
        guard pipelineActive || tracker.isRunning else { return }
        pipelineActive = false
        tracker.enableMicrophoneCapture(false)
        tracker.shutdown()
        if let reason {
            DiagnosticsCenter.shared.event(category: "tuner", level: .info, message: "stop detection", meta: ["reason": reason])
        }
        SentryService.shared.breadcrumb(category: "tuner", message: "stop detection")
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

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            pipelineInterrupted = true
            suspendPipeline(reason: "interruptionBegan")
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

    private func handle(hz: Double, monotonic: Double) {
        lastHzValue = hz

        // Keep existing resolver call; but prefer an overload that returns RatioResult + alts as RatioResult.
        let (r0, cents0, alts0) = resolver.resolve(frequencyHz: hz, monotonicTime: monotonic)
        let r = asResult(r0)
        let alts = alts0.map(asResult)

        // Start from resolver’s primary result.
        var best = (target: r, cents: cents0)

        // If resolver provides alternates, pick the one that minimizes |cents|.
        if !alts.isEmpty {
            for a in alts {
                let cAlt = signedCents(actualHz: hz, rootHz: rootHz, target: a)
                if abs(cAlt) < abs(best.cents) {
                    best = (a, cAlt)
                }
            }
        }

        let huntingTarget = best.target
        let currentEffectiveTarget = lockedTarget ?? huntingTarget
        let centsForUI = signedCents(actualHz: hz, rootHz: rootHz, target: currentEffectiveTarget)

        nearestTarget = huntingTarget
        nearestCentsValue = best.cents
        effectiveTarget = currentEffectiveTarget

        // “too far” threshold (post-selection)
        isFarValue = abs(centsForUI) > 120

        displayRatio = tunerDisplayRatioString(currentEffectiveTarget)
        centsText = String(format: "%+0.1f cents", centsForUI)
        hzText = String(format: "%0.2f Hz", hz)
        altRatios = alts.map { tunerDisplayRatioString($0) }

        let now = Date()
        if now.timeIntervalSince(lastSnapshot) > 0.35 {
            lastSnapshot = now
            DiagnosticsCenter.shared.recordTunerSnapshot(
                cents: best.cents,
                confidence: confidenceValue,
                mode: strictness.rawValue,
                viewStyle: UserDefaults.standard.string(forKey: SettingsKeys.tunerViewStyle) ?? "unknown",
                locked: lockedTarget != nil,
                target: tunerDisplayRatioString(huntingTarget)
            )
        }
    }

    func lockTarget(_ target: RatioResult) {
        lockedTarget = target
    }

    func unlockTarget() {
        lockedTarget = nil
    }

    func setLockedTargetFromText(_ s: String, octave: Int = 0) -> Bool {
        guard let pq = parseRatioTextPQ(s) else { return false }
        lockedTarget = RatioResult(num: pq.p, den: pq.q, octave: octave)
        return true
    }

}
