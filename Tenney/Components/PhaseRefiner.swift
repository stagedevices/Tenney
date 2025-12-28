//
//  PhaseRefiner.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


import Foundation

/// Phase-coherent instantaneous-frequency refinement for a chosen FFT bin.
///
/// - Requires the same `peakBin` AND the same `fftSize` across successive calls.
/// - Uses the classic phase-vocoder instantaneous-frequency estimate:
///   df = (sr / (2π*hop)) * princ(Δφ - 2π*k*hop/N)
public final class PhaseRefiner {
    private let sr: Double
    private let hop: Int
    private var lastPhase: Float?
    private var lastBin: Int?
    private var lastFFTSize: Int?

    public init(sampleRate: Double, hop: Int) {
        self.sr = sampleRate
        self.hop = hop
    }

    /// Returns an instantaneous frequency (Hz) estimate for `peakBin`, or nil if we don't have a
        /// valid previous frame to compare against.
        public func update(peakBin: Int, phase: Float, fftSize: Int) -> Double? {
            defer {
                lastPhase = phase
                lastBin = peakBin
                lastFFTSize = fftSize
            }

            guard let lp = lastPhase, let lb = lastBin, let ln = lastFFTSize,
                  lb == peakBin, ln == fftSize else {
                return nil
            }

            // Unwrapped phase delta in (-π, π]
        var dphi = phase - lp
        dphi = princ(dphi)

                // Expected phase advance for bin k over `hop` samples
        let expected = Float(2.0 * Double.pi) * Float(peakBin * hop) / Float(fftSize)

        // Instantaneous frequency deviation around bin center
                let e = princ(dphi - expected)
                let df = Double(e) * sr / (2.0 * Double.pi * Double(hop))
        
                let fc = Double(peakBin) * sr / Double(fftSize)
        return fc + df
    }

    public func reset() {
        lastPhase = nil
        lastBin = nil
        lastFFTSize = nil
    }
}
@inline(__always)
private func princ(_ x: Float) -> Float {
    var y = x
    let twoPi = Float(2.0 * Double.pi)
    while y > Float.pi { y -= twoPi }
    while y <= -Float.pi { y += twoPi }
    return y
}
