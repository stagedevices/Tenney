//
//  PhaseScopeViewModel.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import Foundation
import Combine
import AVFoundation
import QuartzCore
import CoreGraphics

@MainActor
final class PhaseScopeViewModel: ObservableObject {
    // Render points for the XY trace, normalized to [-1,1]
    @Published private(set) var points: [CGPoint] = []

    // Beat-rate (capped display)
    @Published private(set) var beatRateDisplay: Double = 0
    @Published private(set) var beatHUDText: String = "—"
    @Published private(set) var directionHUDText: String = "—"
    @Published private(set) var centsSign: Double = 0

    private weak var app: AppModel?
    private weak var store: TunerStore?

    private var cancellables = Set<AnyCancellable>()

    // Buffers
    private let refRB = FloatRingBuffer(capacity: 4096)
    private let micRB = FloatRingBuffer(capacity: 8192)

    // Narrowband state
    private var srRef: Double = 48000
    private var srMic: Double = 48000
    private var ownsTestTone: Bool = false

    private var partial: Int = 1
    private var referenceOn: Bool = false

    // beat-rate method A/B stability tracking
    private var aEMA: Double = 0
    private var bEMA: Double = 0
    private var aVar: Double = 1
    private var bVar: Double = 1

    // phase drift estimator
    private var lastPhase: Double = 0
    private var lastPhaseT: Double = 0

    func attach(app: AppModel, store: TunerStore) {
        self.app = app
        self.store = store

        app.$rootHz
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.referenceOn else { return }
                self.updateReferenceHz()
            }
            .store(in: &cancellables)
        
        app.$tunerRootOverride
            .removeDuplicates { lhs, rhs in
                lhs?.id == rhs?.id
            }
            .sink { [weak self] _ in
                guard let self, self.referenceOn else { return }
                self.updateReferenceHz()
            }
            .store(in: &cancellables)

        // 1) ToneOutputEngine reference tap (unchanged)
        ToneOutputEngine.shared.installScopeTap { [weak self] (samples: [Float], sampleRate: Double) in
            guard let self else { return }
            self.srRef = sampleRate
            self.refRB.push(samples)
        }

        // 2) Mic PCM tap (now on AppModel — see section 4)
        app.attachMicPCMTap { [weak self] (samples: [Float], sampleRate: Double) in
            guard let self else { return }
            self.srMic = sampleRate
            self.micRB.push(samples)
        }

        // 3) drive UI updates ~60fps (unchanged)
        Timer.publish(every: 1.0/60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)

        // 4) cents sign comes from AppModel.display now
        app.$display
            .map { $0.cents }
            .sink { [weak self] c in self?.centsSign = c }
            .store(in: &cancellables)
    }


    func detach() {
        cancellables.removeAll()
        ToneOutputEngine.shared.removeScopeTap()
        app?.detachMicPCMTap()

        if ownsTestTone {
            app?.playTestTone = false
            ownsTestTone = false
        }

        points = []
        referenceOn = false
    }

    func setPartial(_ p: Int) {
        partial = max(1, min(16, p))
        updateReferenceHz()
    }

    func setReferenceEnabled(_ on: Bool) {
        referenceOn = on
        guard let app else { return }

        if on {
            // start the shared “test tone” pathway used elsewhere
            ownsTestTone = true
            app.playTestTone = true
            updateReferenceHz()
        } else {
            // stop only if we were the one who turned it on
            if ownsTestTone {
                app.playTestTone = false
                ownsTestTone = false
            }
        }
    }


    func onLockChanged() {
        if referenceOn { updateReferenceHz() }
    }

    // MARK: - Core tick
    private func parseRatio(_ s: String) -> RatioResult? {
        let parts = s.split(separator: "/")
        guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]) else { return nil }
        return RatioResult(num: n, den: d, octave: 0)
    }

    private func tick() {
        guard let app else { return }

        let display = app.display
        let detectedHz  = display.hz
        let confidence  = display.confidence
        let cents       = display.cents

        centsSign = cents

        guard referenceOn else {

            beatRateDisplay = 0
            beatHUDText = "—"
            directionHUDText = "—"
            points = []
            return
        }

        let refHz = app.effectiveRootHz * Double(partial)

        // Build a short scope frame
        buildScopeFrame(refHz: refHz, confidence: confidence)

        // Beat-rate A: |f_detected - f_refFundamentalOrPartial|
        let a = abs(detectedHz - refHz)

        // Beat-rate B: from phase drift (analytic-ish, narrowband)
        let b = phaseDriftBeatHz(refHz: refHz)

        // Auto-switch to whichever is more stable (lower variance proxy)
        let chosen = chooseStableBeat(a: a, b: b, confidence: confidence)

        // Cap behavior
        let cap = 12.0
        let disp = min(cap, chosen)
        beatRateDisplay = disp

        if chosen >= cap { beatHUDText = "≥12 beats/s" }
        else if chosen > 0.05 { beatHUDText = String(format: "~%.1f beats/s", chosen) }
        else { beatHUDText = "~0.0 beats/s" }

        directionHUDText = (cents > 0.2 ? "Sharp" : (cents < -0.2 ? "Flat" : "In"))
    }

    // MARK: - Reference control

    private func updateReferenceHz() {
        guard referenceOn, let app else { return }
        let refHz = app.effectiveRootHz * Double(partial)
        ToneOutputEngine.shared.setFrequency(refHz)

        // waveform/timbre is already governed by ToneOutputEngine settings (spec 2.1)
    }

    // MARK: - Scope frame

    private func buildScopeFrame(refHz: Double, confidence: Double) {
        // Pull a short chunk from ref + mic, align lengths, normalize to [-1,1]
        let n = 512

        let ref = refRB.readLatest(count: n)
        let micRaw = micRB.readLatest(count: Int(Double(n) * (srMic / srRef)))

        guard ref.count == n, micRaw.count > 8 else {
            points = []
            return
        }

        // Resample mic chunk to match ref length
        let mic = (micRaw.count == n) ? micRaw : linearResample(micRaw, to: n)

        // Narrowband mic around refHz
        let y = narrowband(mic, sr: srRef, centerHz: refHz)

        // Normalize
        let xNorm = normalize(ref)
        let yNorm = normalize(y)

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            pts.append(CGPoint(x: CGFloat(xNorm[i]), y: CGFloat(yNorm[i])))
        }

        // Confidence behavior: keep alive but soften (spec 6.1 handled in view via opacity/blur)
        points = pts
    }

    // MARK: - Beat B (phase drift)

    private func phaseDriftBeatHz(refHz: Double) -> Double {
        // Use last ~256 samples of narrowband mic to estimate instantaneous phase vs ref
        let n = 256
        let micRaw = micRB.readLatest(count: Int(Double(n) * (srMic / srRef)))
        guard micRaw.count > 16 else { return 0 }

        let mic = (micRaw.count == n) ? micRaw : linearResample(micRaw, to: n)
        let y = narrowband(mic, sr: srRef, centerHz: refHz)

        // Estimate phase of y at end via quadrature correlator
        let (I, Q) = quadratureCorrelation(y, sr: srRef, hz: refHz)

        let phase = atan2(Q, I) // [-pi, pi]
        let nowT = CACurrentMediaTime()

        if lastPhaseT == 0 {
            lastPhase = phase
            lastPhaseT = nowT
            return 0
        }

        // unwrap minimal
        var dphi = phase - lastPhase
        while dphi > Double.pi { dphi -= 2*Double.pi }
        while dphi < -Double.pi { dphi += 2*Double.pi }

        let dt = max(1e-3, nowT - lastPhaseT)
        lastPhase = phase
        lastPhaseT = nowT

        // phase drift rate => frequency offset: dphi/dt = 2pi * df
        let df = abs(dphi / (2 * Double.pi * dt))
        return df
    }

    private func chooseStableBeat(a: Double, b: Double, confidence: Double) -> Double {
        // If confidence is low, A can be junk (detector jumps), B can also be junk (noise).
        // We track a simple EMA + variance proxy and pick the lower-variance one.
        let conf = max(0, min(1, confidence.isFinite ? confidence : 0))
        let alpha = 0.06 + 0.10 * conf

        func update(_ x: Double, ema: inout Double, v: inout Double) {
            let d = x - ema
            ema += alpha * d
            v = (1 - alpha) * (v + alpha * d * d)
        }

        update(a, ema: &aEMA, v: &aVar)
        update(b, ema: &bEMA, v: &bVar)

        // Guardrails:
        // - if b is NaN/inf, fall back to a
        // - if detector hz is obviously absent, b tends to be more usable (but only if variance isn’t exploding)
        if !b.isFinite { return a }
        if aVar <= bVar { return aEMA } else { return bEMA }
    }
}

// MARK: - DSP helpers

private func normalize(_ x: [Float]) -> [Float] {
    var peak: Float = 1e-6
    for v in x { peak = max(peak, abs(v)) }
    let g = 1.0 / peak
    return x.map { $0 * g }
}

private func linearResample(_ x: [Float], to n: Int) -> [Float] {
    guard n > 1, x.count > 1 else { return Array(repeating: 0, count: max(0, n)) }
    let m = x.count
    var y = [Float](repeating: 0, count: n)
    for i in 0..<n {
        let t = Float(i) * Float(m - 1) / Float(n - 1)
        let i0 = Int(floor(t))
        let i1 = min(m - 1, i0 + 1)
        let frac = t - Float(i0)
        y[i] = x[i0] * (1 - frac) + x[i1] * frac
    }
    return y
}

// Heterodyne to baseband + one-pole lowpass I/Q, then reconstruct narrowband
private func narrowband(_ x: [Float], sr: Double, centerHz: Double) -> [Float] {
    let w = 2 * Double.pi * centerHz / sr
    var I: Double = 0
    var Q: Double = 0
    let lp = 0.08 // UI smoothing
    var out = [Float](repeating: 0, count: x.count)

    for i in 0..<x.count {
        let t = Double(i)
        let c = cos(w * t)
        let s = sin(w * t)
        let v = Double(x[i])
        I += lp * ((v * c) - I)
        Q += lp * ((v * s) - Q)

        // Reconstruct a clean-ish sinusoid at centerHz with extracted I/Q
        let y = I * c + Q * s
        out[i] = Float(y)
    }
    return out
}

private func quadratureCorrelation(_ x: [Float], sr: Double, hz: Double) -> (Double, Double) {
    let w = 2 * Double.pi * hz / sr
    var I: Double = 0
    var Q: Double = 0
    for i in 0..<x.count {
        let t = Double(i)
        let c = cos(w * t)
        let s = sin(w * t)
        let v = Double(x[i])
        I += v * c
        Q += v * s
    }
    return (I, Q)
}
