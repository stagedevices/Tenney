//
//  PhaseRefiner.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


import Foundation

public final class PhaseRefiner {
    private let sr: Double
    private let hop: Int
    private var lastPhase: Float?
    private var lastBin: Int?

    public init(sampleRate: Double, hop: Int) {
        self.sr = sampleRate
        self.hop = hop
    }

    public func update(peakBin: Int, phase: Float) -> Double? {
        defer { lastPhase = phase; lastBin = peakBin }

        guard let lp = lastPhase, let lb = lastBin, lb == peakBin else { return nil }

        // Phase unwrapping
        var dphi = phase - lp
        while dphi > Float.pi { dphi -= 2 * Float.pi }
        while dphi < -Float.pi { dphi += 2 * Float.pi }

        // Instantaneous frequency around the bin center:
        // omega = 2π*k/N + (Δφ - expected)/hop
        // Here we use a simplified IF estimate:
        let binHz = sr / 2048.0 // frame size should match PitchFFT.n
        let fc = Double(peakBin) * binHz
        let df = Double(dphi) * sr / (2.0 * Double.pi * Double(hop))
        return fc + df
    }

    public func reset() {
        lastPhase = nil
        lastBin = nil
    }
}
