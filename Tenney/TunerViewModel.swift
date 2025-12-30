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
    @Published var rootHz: Double = 220.0 { didSet { resolver.rootHz = rootHz } }

    // Diagnostics
    @Published var inputRMS: Float = 0
    @Published var micGranted: Bool = false

    // Test tone toggle (visible in UI)
    @Published var useTestTone: Bool = false {
        didSet { tracker.setTestTone(enabled: useTestTone, hz: 220.0) }
    }
    
    @Published var lastHzValue: Double = 0
    @Published var nearestTarget: RatioResult? = nil
    @Published var nearestCentsValue: Double = 0
    @Published var confidenceValue: Double = 0
    @Published var isFarValue: Bool = false


    private let tracker: PitchTracker
    private let resolver = RatioResolver()
    
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

        // 1) Always start the analysis loop (even with no mic)
        tracker.startDetection()

        // 2) Ask for mic; if granted, enable capture (analysis is already running)
        MicrophonePermission.ensure { [weak self] (granted: Bool) in
            guard let self else { return }
            self.micGranted = granted
            self.tracker.enableMicrophoneCapture(granted)
        }
    }

    deinit { tracker.shutdown() }

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

        nearestTarget = best.target
        nearestCentsValue = best.cents

        // “too far” threshold (post-selection)
        isFarValue = abs(best.cents) > 120

        displayRatio = "\(best.target.num)/\(best.target.den)"
        centsText = String(format: "%+0.1f cents", best.cents)
        hzText = String(format: "%0.2f Hz", hz)
        altRatios = alts.map { "\($0.num)/\($0.den)" }
    }

}
