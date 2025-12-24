//
//  FrontEndMetrics.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


import Accelerate

struct FrontEndMetrics { let gated: Bool }

final class FrontEnd {
    private let sampleRate: Double
    init(sampleRate: Double) { self.sampleRate = sampleRate }

    /// In-place processing; returns simple gate metric.
    func process(_ buffer: inout [Float]) -> FrontEndMetrics {
        let n = buffer.count
        guard n > 0 else { return .init(gated: true) }

        var meanSquare: Float = 0
        vDSP_measqv(buffer, 1, &meanSquare, vDSP_Length(n)) // mean of squares
        let rms = sqrtf(meanSquare)

        // Very low threshold to avoid spurious gating.
        return .init(gated: rms < 1e-6)
    }
}
