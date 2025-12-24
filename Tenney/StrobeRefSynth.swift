//
//  StrobeRefSynth.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  StrobeRefSynth.swift
//  Tenney
//
//  A lightweight “strobe” phase synthesizer for UI.
//  The intent is: when measuredHz == targetHz, motion freezes (beatHz → 0).
//  When they differ, the strobe phase advances at the beat frequency.
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation

/// UI helper: produces a stable phase value (0…1) whose speed equals the beat frequency
/// between a measured pitch and a target pitch.
final class StrobeRefSynth {

    struct Config: Equatable, Sendable {
        /// Clamp beat frequency to avoid insane motion when tracking is unstable.
        var maxBeatHz: Double = 24.0

        /// One-pole smoothing for measured Hz (seconds). 0 = no smoothing.
        var smoothingSeconds: Double = 0.08

        /// Dead-zone in cents: within this, treat beat as zero (freeze).
        var deadZoneCents: Double = 1.2

        /// Quantize the strobe phase to reduce shimmer (0 = off).
        var phaseQuantizationSteps: Int = 0

        init() {}
    }

    private let sr: Double
    private let cfg: Config

    // State
    private var smoothedHz: Double?
    private var phase01: Double = 0.0
    private var lastUpdateTime: TimeInterval?

    init(sampleRate: Double, config: Config = .init()) {
        self.sr = max(1.0, sampleRate)
        self.cfg = config
    }

    /// Reset phase + smoothing history.
    func reset(phase: Double = 0) {
        smoothedHz = nil
        phase01 = phase - floor(phase)
        lastUpdateTime = nil
    }

    /// Update phase based on the newest measured frequency.
    ///
    /// - Parameters:
    ///   - measuredHz: current pitch estimate (Hz)
    ///   - targetHz: target pitch (Hz)
    ///   - frames: number of audio frames since last update (used to derive dt when callers don’t have a clock)
    /// - Returns: phase in [0, 1)
    @discardableResult
    func update(measuredHz: Double, targetHz: Double, frames: Int) -> Double {
        let dt = max(0, Double(max(frames, 0)) / sr)
        return update(measuredHz: measuredHz, targetHz: targetHz, dt: dt)
    }

    /// Same as above, but uses an explicit dt (seconds).
    @discardableResult
    func update(measuredHz: Double, targetHz: Double, dt: Double) -> Double {
        guard measuredHz.isFinite, measuredHz > 0, targetHz.isFinite, targetHz > 0 else {
            // If tracking is invalid, don’t advance phase (prevents chaos).
            return phase01
        }

        // Smooth measured Hz a bit (optional).
        let m: Double = {
            if cfg.smoothingSeconds <= 0 {
                return measuredHz
            }
            let a = 1.0 - exp(-max(0, dt) / max(1e-6, cfg.smoothingSeconds))
            if let prev = smoothedHz {
                return prev + a * (measuredHz - prev)
            } else {
                return measuredHz
            }
        }()
        smoothedHz = m

        // Freeze within dead-zone.
        let cents = 1200.0 * log2(m / targetHz)
        if abs(cents) <= cfg.deadZoneCents {
            return phase01
        }

        // Beat frequency = measured - target (signed).
        var beatHz = m - targetHz
        let lim = max(0.0, cfg.maxBeatHz)
        if lim > 0 { beatHz = max(-lim, min(lim, beatHz)) }

        // Advance phase at beat frequency.
        // phase += beatHz * dt  (cycles)
        phase01 += beatHz * max(0, dt)
        phase01 -= floor(phase01)

        // Optional quantization to reduce shimmer.
        if cfg.phaseQuantizationSteps > 1 {
            let steps = Double(cfg.phaseQuantizationSteps)
            phase01 = (phase01 * steps).rounded() / steps
            phase01 -= floor(phase01)
        }

        return phase01
    }

    /// Convenience: returns a stripe signal in [0,1] for a given phase.
    /// Useful for very cheap strobe shaders / Canvas patterns.
    func stripe(phase: Double, stripes: Int = 18, softness: Double = 0.12) -> Double {
        let s = max(1, stripes)
        let p = (phase - floor(phase)) * Double(s) // 0..stripes
        let x = p - floor(p)                      // 0..1 within stripe
        // soft pulse around center using a smoothstep-ish curve
        let d = abs(x - 0.5) * 2.0                // 0 center, 1 edges
        let t = max(0.0, min(1.0, 1.0 - d / max(1e-6, softness)))
        return t * t * (3.0 - 2.0 * t)
    }
}
