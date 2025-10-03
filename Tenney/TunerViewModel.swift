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

    private let tracker: PitchTracker
    private let resolver = RatioResolver()

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
                        self?.inputRMS = rms
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
            let (r, cents, alts) = resolver.resolve(frequencyHz: hz, monotonicTime: monotonic)
        displayRatio = "\(r.n)/\(r.d)"
                centsText = String(format: "%+0.1f cents", cents)
                hzText = String(format: "%0.2f Hz", hz)
                altRatios = alts.map { "\($0.n)/\($0.d)" }
        }
}
