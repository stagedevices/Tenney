//
//  PitchFFT.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//  Updated by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation
import Accelerate

public struct FFTPartial: Sendable {
    public let index: Int        // harmonic index (1 = fundamental)
    public let freq: Double      // Hz
    public let mag: Float        // linear magnitude (power)
    public let snr: Float        // dB SNR estimate for this partial
}

public struct FFTResult: Sendable {
    public let f0Fast: Double?   // Hz (fast-path estimate)
    public let peakBin: Int
    public let peakFreq: Double  // Hz
    public let confidence: Double
    public let partials: [FFTPartial]
    public let spectrumPhaseAtPeak: Float
}

public final class PitchFFT {

    public struct Config: Sendable {
        public var maxHarmonics: Int = 16
        public var maxHpsHarmonics: Int = 4
        public var peakSearchHz: ClosedRange<Double> = 40...3000

        /// Safety bounds for adaptive FFT sizing.
        public var minFFTSize: Int = 1024
        public var maxFFTSize: Int = 16384

        public init() {}
    }

    private let sr: Double
    private let config: Config

    // FFT state
    private var n: Int = 2048
    private var log2n: vDSP_Length = 11
    private var fftSetup: FFTSetup?

    // Buffers
    private var window: [Float] = []
    private var scratch: [Float] = []

    private var real: [Float] = []   // length n/2
    private var imag: [Float] = []   // length n/2

    public var frameSize: Int { n }

    /// Optional debug hook to mirror your AppModel expectations.
    public var debugHook: ((String) -> Void)?

    public init(sampleRate: Double, config: Config = .init()) {
        self.sr = max(1.0, sampleRate)
        self.config = config
        resizeFFT(to: 2048)
    }

    deinit {
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
        fftSetup = nil
    }

    /// Adaptive sizing used by AppModel: choose an FFT size that captures roughly `cycles`
    /// of the current f0 guess.
    public func ensureSize(cycles: Double, f0Guess: Double) {
        guard cycles.isFinite, cycles > 0, f0Guess.isFinite, f0Guess > 0 else { return }
        let target = Int((sr * cycles) / f0Guess)
        let clamped = max(config.minFFTSize, min(config.maxFFTSize, target))
        let size = nextPow2(clamped)
        if size != n { resizeFFT(to: size) }
    }

    private func resizeFFT(to size: Int) {
        let sizePow2 = nextPow2(max(16, size))
        n = sizePow2
        log2n = vDSP_Length(round(log2(Double(n))))

        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        // Hann window (manual; avoids API differences across SDKs)
        window = makeHannWindow(count: n)
        scratch = Array(repeating: 0, count: n)

        real = Array(repeating: 0, count: n/2)
        imag = Array(repeating: 0, count: n/2)

        debugHook?("[PitchFFT] resizeFFT n=\(n) log2n=\(log2n) sr=\(sr)")
    }

    public func analyze(_ x: UnsafeBufferPointer<Float>) -> FFTResult {
        precondition(x.count == n, "analyze() expects \(n) samples")

        guard let fftSetup else {
            return FFTResult(f0Fast: nil, peakBin: 0, peakFreq: 0, confidence: 0, partials: [], spectrumPhaseAtPeak: 0)
        }

        // Window into scratch: scratch = x * window
        window.withUnsafeBufferPointer { w in
            vDSP_vmul(x.baseAddress!, 1, w.baseAddress!, 1, &scratch, 1, vDSP_Length(n))
        }

        // Pack real signal for vDSP_fft_zrip:
        // interpret scratch as interleaved complex (real=s[0], imag=s[1], …)
        var mags = [Float](repeating: 0, count: n/2)

        let result: FFTResult = real.withUnsafeMutableBufferPointer { rbuf in
            imag.withUnsafeMutableBufferPointer { ibuf in
                var split = DSPSplitComplex(realp: rbuf.baseAddress!, imagp: ibuf.baseAddress!)

                scratch.withUnsafeBufferPointer { sbuf in
                    sbuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n/2) { cpx in
                        vDSP_ctoz(cpx, 1, &split, 1, vDSP_Length(n/2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // Magnitude squared (packed real FFT is fine for bins 1..n/2-1)
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n/2))

                // Peak search (ignore DC at bin 0)
                var peakIndex = 1
                if mags.count > 2 {
                    var maxVal = mags[1]
                    for i in 2..<mags.count {
                        let v = mags[i]
                        if v > maxVal { maxVal = v; peakIndex = i }
                    }
                }

                // Phase at peak (valid for bins 1..n/2-1)
                let peakPhase = atan2f(split.imagp[peakIndex], split.realp[peakIndex])

                // Sub-bin interpolation (Quinn’s w/ parabolic fallback)
                let (delta, confQ) = quinnSecond(mags: mags, k: peakIndex)
                let peakBinInterp = Double(peakIndex) + delta
                let peakFreq = sr * peakBinInterp / Double(n)

                // Coarse f0 via HPS (within peakSearchHz)
                let (f0Hps, confHps) = coarseHPS(mags: mags, sr: sr, n: n)

                // Partials + harmonicity
                let (partials, harmScore) = partialsAndHarmonicity(mags: mags, sr: sr, n: n, f0: f0Hps)

                let conf = max(0.0, min(1.0,
                    0.5 * (confQ ?? 0) + 0.3 * (confHps ?? 0) + 0.2 * harmScore
                ))

                return FFTResult(
                    f0Fast: f0Hps,
                    peakBin: peakIndex,
                    peakFreq: peakFreq,
                    confidence: conf,
                    partials: partials,
                    spectrumPhaseAtPeak: peakPhase
                )
            }
        }

        return result
    }

    // MARK: - Quinn’s second estimator (w/ safe fallback)

    private func quinnSecond(mags: [Float], k: Int) -> (Double, Double?) {
        guard k > 1, k + 1 < mags.count else { return (0.0, nil) }

        let a = Double(mags[k - 1])
        let b = Double(mags[k])
        let c = Double(mags[k + 1])

        if b <= 0 || (a <= 0 && c <= 0) {
            let denom = (a - 2*b + c)
            if abs(denom) < 1e-12 { return (0.0, nil) }
            let delta = 0.5 * (a - c) / denom
            return (max(-0.5, min(0.5, delta)), nil)
        }

        let alpha = a / b
        let beta  = c / b

        let ap = alpha / (1.0 + alpha)
        let bp = beta  / (1.0 + beta)

        let d1 = ap - bp
        let d2 = ap + bp

        let delta = d1 + 0.5 * d1 * d2

        let peaky = b / max(1e-12, 0.5*(a + c))
        let conf = max(0.0, min(1.0, (peaky - 1.0) / 6.0))
        return (max(-0.5, min(0.5, delta)), conf)
    }

    // MARK: - HPS coarse f0

    private func coarseHPS(mags: [Float], sr: Double, n: Int) -> (Double?, Double?) {
        let binHz = sr / Double(n)

        let kMin = max(1, Int(config.peakSearchHz.lowerBound / binHz))
        let kMax = min(mags.count - 2, Int(config.peakSearchHz.upperBound / binHz))
        guard kMax > kMin else { return (nil, nil) }

        var bestK = kMin
        var best = -Float.infinity

        let maxH = max(2, min(config.maxHpsHarmonics, 8))

        for k in kMin...kMax {
            var acc: Float = 0
            for h in 1...maxH {
                let kk = k * h
                if kk < mags.count { acc += logf(mags[kk] + 1e-12) }
            }
            if acc > best { best = acc; bestK = k }
        }

        let f0 = Double(bestK) * binHz

        // Confidence: compare best score to neighborhood mean
        let left = max(kMin, bestK - 2)
        let right = min(kMax, bestK + 2)
        var neighborhood: Float = 0
        var count: Float = 0
        for k in left...right {
            neighborhood += logf(mags[k] + 1e-12)
            count += 1
        }
        let mean = neighborhood / max(1, count)
        let conf = Double(max(0.0, min(1.0, (best - mean) / 6.0)))
        return (f0, conf)
    }

    // MARK: - Partials + harmonicity

    private func partialsAndHarmonicity(mags: [Float], sr: Double, n: Int, f0: Double?) -> ([FFTPartial], Double) {
        guard let f0, f0 > 0 else { return ([], 0.0) }
        let binHz = sr / Double(n)

        // Noise floor estimate: median magnitude in mid band.
        let lo = max(2, Int(80.0 / binHz))
        let hi = min(mags.count - 2, Int(5000.0 / binHz))
        if hi <= lo { return ([], 0.0) }

        var band = Array(mags[lo..<hi])
        band.sort()
        let floorPow = max(1e-12, Double(band[band.count / 2]))

        let maxK = max(1, Int((sr * 0.5) / f0))
        let K = min(config.maxHarmonics, maxK)

        var parts: [FFTPartial] = []
        parts.reserveCapacity(K)

        var harmAcc = 0.0
        var harmW = 0.0

        for k in 1...K {
            let targetHz = Double(k) * f0
            let targetBin = targetHz / binHz
            let i = Int(targetBin.rounded())

            guard i > 1, i + 1 < mags.count else { continue }

            // local max search ±1 bin
            var bestI = i
            var bestP = mags[i]
            for j in (i - 1)...(i + 1) {
                if mags[j] > bestP { bestP = mags[j]; bestI = j }
            }

            let pow = Double(bestP)
            let snr = 10.0 * log10(pow / floorPow)
            let hz = Double(bestI) * binHz

            parts.append(FFTPartial(index: k, freq: hz, mag: bestP, snr: Float(snr)))

            // Harmonicity score: reward high SNR at low harmonics
            let w = 1.0 / Double(k)
            harmAcc += w * max(0.0, min(1.0, (snr - 3.0) / 18.0))
            harmW += w
        }

        let harmScore = harmW > 0 ? max(0.0, min(1.0, harmAcc / harmW)) : 0.0
        return (parts, harmScore)
    }
}

// MARK: - Utils

private func nextPow2(_ x: Int) -> Int {
    var v = max(1, x)
    v -= 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    return v + 1
}

private func makeHannWindow(count n: Int) -> [Float] {
    guard n > 1 else { return [1] }
    let twoPi = 2.0 * Double.pi
    return (0..<n).map { i in
        let t = Double(i) / Double(n - 1)
        return Float(0.5 * (1.0 - cos(twoPi * t)))
    }
}
