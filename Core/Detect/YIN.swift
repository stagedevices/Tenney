//
//  YIN.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import Accelerate

enum YIN {
    /// Canonical, safe YIN over a 4096- (or 2048-) sample window; returns Hz or nil.
    static func detect(samples: [Float],
                       sampleRate: Double,
                       minHz: Double = 55,
                       maxHz: Double = 1760) -> Double? {
        let nFull = samples.count
        guard nFull >= 2048, sampleRate > 0 else { return nil }

        // Choose window size (prefer 4096; fall back to 2048)
        let N = nFull >= 4096 ? 4096 : 2048
        let start = (nFull - N) / 2
        var x = Array(samples[start ..< start + N])

        // DC remove + Hann
        var mean: Float = 0
        vDSP_meanv(x, 1, &mean, vDSP_Length(N))
        var neg = -mean
        vDSP_vsadd(x, 1, &neg, &x, 1, vDSP_Length(N))

        var hann = [Float](repeating: 0, count: N)
        vDSP_hann_window(&hann, vDSP_Length(N), Int32(vDSP_HANN_NORM))
        vDSP_vmul(x, 1, hann, 1, &x, 1, vDSP_Length(N))

        // τ bounds
        let maxTau = min(N - 2, Int(floor(sampleRate / minHz)))
        let minTau = max(2, Int(floor(sampleRate / maxHz)))
        guard maxTau > minTau else { return nil }

        // Difference function d(τ) and cumulative sum S(τ)
        var d = [Float](repeating: 0, count: maxTau + 1)
        var S = [Float](repeating: 0, count: maxTau + 1)

        // Reusable scratch buffer to avoid overlap-unsafe ops
        var diff = [Float](repeating: 0, count: N)

        x.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            for tau in 1...maxTau {
                let len = N - tau
                // diff[0..len-1] = x[0..len-1] - x[tau..tau+len-1]
                vDSP_vsub(base + tau, 1, base, 1, &diff, 1, vDSP_Length(len))
                var sq: Float = 0
                vDSP_svesq(diff, 1, &sq, vDSP_Length(len))
                d[tau] = sq
                S[tau] = S[tau - 1] + sq
            }
        }

        // CMND
        var cmnd = [Float](repeating: 1, count: maxTau + 1)
        for tau in minTau...maxTau {
            let denom = S[tau] / Float(tau)
            cmnd[tau] = denom > 0 ? d[tau] / denom : 1
        }

        // Pick first local min under threshold, else global min
        let threshold: Float = 0.15
        var bestTau = -1
        var bestVal: Float = 1

        for t in max(minTau + 1, 2)...maxTau - 1 {
            let y0 = cmnd[t]
            if y0 < threshold, y0 <= cmnd[t - 1], y0 <= cmnd[t + 1] {
                bestTau = t; bestVal = y0; break
            }
        }
        if bestTau < 0 {
            for t in minTau...maxTau {
                let v = cmnd[t]
                if v < bestVal { bestVal = v; bestTau = t }
            }
        }
        guard bestTau > 1 else { return nil }

        // Parabolic interpolation
        let t = bestTau
        let ym1 = cmnd[max(t - 1, minTau)]
        let y0  = cmnd[t]
        let yp1 = cmnd[min(t + 1, maxTau)]
        let denom = (2 * (ym1 - 2*y0 + yp1))
        var shift: Float = 0
        if fabsf(denom) > 1e-6 {
            shift = (ym1 - yp1) / denom
            shift = max(-1, min(1, shift))
        }

        let tau = Double(t) + Double(shift)
        guard tau > 0 else { return nil }
        let hz = sampleRate / tau
        return (hz.isFinite && hz >= minHz && hz <= maxHz) ? hz : nil
    }
}

