//
//  HPS.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import Accelerate


struct HPSVerifier {
    static func estimate(samples: [Float], sampleRate: Double, minHz: Double = 55, maxHz: Double = 1760) -> Double? {
        let n = 2048
        guard samples.count >= n, sampleRate > 0 else { return nil }
        let x = Array(samples.prefix(n))

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var w = [Float](repeating: 0, count: n)
        vDSP_vmul(x, 1, window, 1, &w, 1, vDSP_Length(n))

        let log2n = vDSP_Length(round(log2(Float(n))))
        guard (1 << log2n) == n else { return nil }

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        // Pack to split-complex
        var real = w
        var imag = [Float](repeating: 0, count: n)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        // Magnitude spectrum
        var mag = [Float](repeating: 0, count: n/2)
        vDSP_zvabs(&split, 1, &mag, 1, vDSP_Length(n/2))

        var hps = mag
        let size = n/2
        for factor in 2...3 {
            let limit = size / factor
            for i in 0..<limit {
                hps[i] *= mag[i*factor]
            }
        }

        let minBin = max(1, Int(floor(minHz * Double(n) / sampleRate)))
        let maxBin = min(size - 2, Int(ceil(maxHz * Double(n) / sampleRate)))
        guard maxBin > minBin else { return nil }

        var bestIdx = -1
        var bestVal: Float = 0
        for i in minBin..<maxBin {
            let v = hps[i]
            if v > bestVal { bestVal = v; bestIdx = i }
        }
        guard bestIdx > 1, bestVal.isFinite, bestVal > 0 else { return nil }

        let ym1 = hps[bestIdx-1], y0 = hps[bestIdx], yp1 = hps[bestIdx+1]
        let denom = (2 * (ym1 - 2*y0 + yp1))
        var shift: Float = 0
        if abs(denom) > 1e-6 { shift = (ym1 - yp1) / denom }
        let bin = Double(bestIdx) + Double(shift)
        let hz = bin * sampleRate / Double(n)
        return hz.isFinite && hz > 0 ? hz : nil
    }
}
