//
//  PitchFFT.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//  Updated by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation
import Accelerate
import os.lock

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
    // Phase-refinement plumbing
        public let fftSize: Int
        public let refineBin: Int
        public let refineHarmonic: Int
        public let spectrumPhaseAtRefine: Float
        public let refineSNRdB: Float
}

public final class PitchFFT {

    public struct Config: Sendable {
        public var consensusMaxHarmonics: Int = 8          // how many harmonics to fuse
        public var consensusMinHarmonics: Int = 2          // require at least this many
        public var consensusMinSNRdB: Float = 6            // ignore harmonics below this SNR
        public var phaseRefineEnabled: Bool = true         // gate phase vocoder path
        public var phaseRefineMaxJumpCents: Double = 80     // reject insane phase jumps

        public var maxHarmonics: Int = 16
        public var maxHpsHarmonics: Int = 4
        public var peakSearchHz: ClosedRange<Double> = 40...3000

        /// Safety bounds for adaptive FFT sizing.
        public var minFFTSize: Int = 4096
        public var maxFFTSize: Int = 16384

        public init() {}
    }

    // Phase-vocoder memory (per-bin phases from last analyze)
    private var prevPhaseByBin: [Int: Float] = [:]
    private var hasPrevPhase: Bool = false

    // Concurrency guard (PitchFFT can still get called from multiple queues)
    private var analyzeLock = os_unfair_lock_s()

    private let sr: Double
    private let config: Config

    // FFT state
    private var n: Int = 2048
    private var log2n: vDSP_Length = 11
    private var fftSetup: FFTSetup?

    // Buffers
    private var window: [Float] = []
    private var scratch: [Float] = []

    private var real: [Float] = []   // length n
    private var imag: [Float] = []   // length n

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
        guard cycles.isFinite, cycles > 0, f0Guess.isFinite else { return }

        // Prevent crazy upstream guesses (e.g. ZC blowups) from resizing FFT to nonsense.
        let g = min(max(f0Guess, config.peakSearchHz.lowerBound), config.peakSearchHz.upperBound)
        guard g > 0 else { return }

        let target = Int((sr * cycles) / g)
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

        real = Array(repeating: 0, count: n)
        imag = Array(repeating: 0, count: n)
        
        #if DEBUG
        debugHook?("[PitchFFT] resizeFFT n=\(n) log2n=\(log2n) sr=\(sr)")
        #endif
        
        prevPhaseByBin.removeAll(keepingCapacity: true)
        hasPrevPhase = false

    }

    public func analyze(_ x: UnsafeBufferPointer<Float>, f0Hint: Double? = nil, hopSamples: Int? = nil) -> FFTResult {
        os_unfair_lock_lock(&analyzeLock)
        defer { os_unfair_lock_unlock(&analyzeLock) }

        precondition(x.count == n, "analyze() expects \(n) samples")

        guard let fftSetup else {
            prevPhaseByBin.removeAll(keepingCapacity: true)
            hasPrevPhase = false
            return FFTResult(f0Fast: nil, peakBin: 0, peakFreq: 0, confidence: 0, partials: [], spectrumPhaseAtPeak: 0, fftSize: n, refineBin: 0, refineHarmonic: 1, spectrumPhaseAtRefine: 0, refineSNRdB: -120)
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

                // Complex FFT: write into the *currently-borrowed* buffers (no nested borrowing)
                                scratch.withUnsafeBufferPointer { sbuf in
                                    rbuf.baseAddress!.assign(from: sbuf.baseAddress!, count: n)
                                }
                                vDSP_vclr(ibuf.baseAddress!, 1, vDSP_Length(n)) // imag = 0
                
                                vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))


                // Magnitude squared (packed real FFT is fine for bins 1..n/2-1)
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n/2))

                let binHz = sr / Double(n)
                let kMin = max(1, Int(config.peakSearchHz.lowerBound / binHz))
                let kMax = min(mags.count - 2, Int(config.peakSearchHz.upperBound / binHz))

                var peakIndex = max(1, min(mags.count - 2, kMin))

                if let hint = f0Hint, hint.isFinite, hint > 0 {
                    let h = min(max(hint, config.peakSearchHz.lowerBound), config.peakSearchHz.upperBound)
                    let kHint = max(kMin, min(kMax, Int((h / binHz).rounded())))

                    // Search a local window around the hint (± ~6% of kHint, min 6 bins).
                    let w = max(6, Int(0.06 * Double(kHint)))
                    let a = max(kMin, kHint - w)
                    let b = min(kMax, kHint + w)

                    var best = a
                    var bestV = mags[a]
                    if b > a {
                        for i in (a + 1)...b {
                            let v = mags[i]
                            if v > bestV { bestV = v; best = i }
                        }
                    }
                    peakIndex = best
                } else {
                    // Fallback: global max in range (your current behavior)
                    var bestV = mags[peakIndex]
                    if kMax > peakIndex {
                        for i in (peakIndex + 1)...kMax {
                            let v = mags[i]
                            if v > bestV { bestV = v; peakIndex = i }
                        }
                    }
                }

                // Phase at peak (valid for bins 1..n/2-1)
                let peakPhase = atan2f(split.imagp[peakIndex], split.realp[peakIndex])

                // Sub-bin interpolation (Quinn’s w/ parabolic fallback)
                let (dPeak, confPeakC) = jacobsenDelta(split: split, mags: mags, k: peakIndex)
                let peakBinInterp = Double(peakIndex) + dPeak
                let peakFreq = sr * peakBinInterp / Double(n)
                let confQ = confPeakC // keep your downstream weighting unchanged

                // Coarse f0 via HPS (within peakSearchHz)
                let (f0HpsRaw, confHps) = coarseHPS(mags: mags, sr: sr, n: n, peakBin: peakIndex)
                let f0Hps = promoteIfSubharmonic(f0: f0HpsRaw, mags: mags, peakBin: peakIndex, sr: sr, n: n)
                
                #if DEBUG
                 debugHook?("[PitchFFT] peak=\(String(format:"%.2f", peakFreq))Hz (bin \(peakIndex))  hps=\(String(format:"%.2f", f0Hps ?? -1))Hz")
                #endif
                
                let floorPow = estimateNoiseFloorPow(mags: mags, sr: sr, n: n)
                // ---- Multi-harmonic consensus + optional phase refinement ----
                let usePhase = config.phaseRefineEnabled && hasPrevPhase && (hopSamples ?? 0) > 0

                // choose a base bin from HPS (fallback to peak)
                let baseBin: Int = {
                    if let f0Hps, f0Hps.isFinite, f0Hps > 0 {
                        return max(1, min(mags.count - 2, Int((f0Hps / binHz).rounded())))
                    } else {
                        return max(1, min(mags.count - 2, peakIndex))
                    }
                }()

                let maxH = min(config.consensusMaxHarmonics, (mags.count - 2) / max(1, baseBin))

                var sumW = 0.0
                var sumF0 = 0.0
                var usedH = 0

                var bestUsedBin = baseBin
                var bestUsedH = 1
                var bestUsedW = -Double.infinity

                var currPhaseByBin: [Int: Float] = [:]
                currPhaseByBin.reserveCapacity(maxH + 2)

                if maxH >= 1 {
                    for h in 1...maxH {
                        let kk = baseBin * h
                        if kk <= 1 || kk + 1 >= mags.count { continue }

                        // SNR (power domain)
                        let p = max(1e-12, Double(mags[kk]))
                        let snrDb = 10.0 * log10(p / max(1e-12, floorPow))
                        if Float(snrDb) < config.consensusMinSNRdB { continue }

                        // complex sub-bin at this harmonic
                        let (dH, _) = jacobsenDelta(split: split, mags: mags, k: kk)
                        let fMagHz = (Double(kk) + dH) * binHz

                        // phase-vocoder refinement (optional)
                        let phiNow = Double(atan2f(split.imagp[kk], split.realp[kk]))
                        currPhaseByBin[kk] = Float(phiNow)

                        var fUseHz = fMagHz
                        if usePhase, let hop = hopSamples, hop > 0, let phiPrevF = prevPhaseByBin[kk] {
                            let fPhaseHz = phaseVocoderFreqHz(bin: kk, phiPrev: Double(phiPrevF), phiNow: phiNow, hop: hop, sr: sr, n: n)
                            let centsJump = 1200.0 * log2(max(1e-9, fPhaseHz) / max(1e-9, fMagHz))
                            if abs(centsJump) <= config.phaseRefineMaxJumpCents {
                                fUseHz = fPhaseHz
                            }
                        }

                        let f0h = fUseHz / Double(h)

                        // weight: SNR-weighted, favor low harmonics
                        let w = max(0.0, (snrDb - 6.0) / 18.0) * (1.0 / Double(h))
                        if w <= 0 { continue }

                        sumW += w
                        sumF0 += w * f0h
                        usedH += 1

                        if w > bestUsedW {
                            bestUsedW = w
                            bestUsedBin = kk
                            bestUsedH = h
                        }
                    }
                }

                let f0Consensus: Double? = (usedH >= config.consensusMinHarmonics && sumW > 0) ? (sumF0 / sumW) : nil

                // Base bin from HPS (fallback to peak)
                var refineBin = bestUsedBin
                var refineH = bestUsedH
                let refineMag = mags[refineBin]

                let refinePhase: Float = currPhaseByBin[refineBin] ?? atan2f(split.imagp[refineBin], split.realp[refineBin])
                prevPhaseByBin.removeAll(keepingCapacity: true)
                prevPhaseByBin.merge(currPhaseByBin) { _, new in new }
                hasPrevPhase = true
                let refineSNRdB: Float = {
                    let p = max(1e-12, Double(refineMag))
                    let snr = 10.0 * log10(p / max(1e-12, floorPow))
                    return Float(snr.isFinite ? snr : -120.0)
                }()
        
                let f0Out = f0Consensus ?? f0Hps
                let (partials, harmScore) = partialsAndHarmonicity(mags: mags, sr: sr, n: n, f0: f0Out)
                let conf = max(0.0, min(1.0,
                    0.5 * (confQ ?? 0) + 0.3 * (confHps ?? 0) + 0.2 * harmScore
                ))
                return FFTResult(
                    f0Fast: f0Out,
                    peakBin: peakIndex,
                    peakFreq: peakFreq,
                    confidence: conf,
                    partials: partials,
                    spectrumPhaseAtPeak: peakPhase,
                    fftSize: n,
                    refineBin: refineBin,
                    refineHarmonic: refineH,
                    spectrumPhaseAtRefine: refinePhase,
                    refineSNRdB: refineSNRdB                )
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

    // Wrap angle to (-pi, +pi]
    private func wrapPi(_ x: Double) -> Double {
        let twoPi = 2.0 * Double.pi
        var y = (x + Double.pi).truncatingRemainder(dividingBy: twoPi)
        if y < 0 { y += twoPi }
        return y - Double.pi
    }

    // Phase-vocoder instantaneous frequency at integer bin k
    private func phaseVocoderFreqHz(bin k: Int, phiPrev: Double, phiNow: Double, hop: Int, sr: Double, n: Int) -> Double {
        let twoPi = 2.0 * Double.pi
        let omega = twoPi * Double(k) / Double(n)                 // rad/sample at bin center
        let expected = omega * Double(hop)                        // expected phase advance
        let dphi = wrapPi((phiNow - phiPrev) - expected)          // residual
        let omegaTrue = omega + dphi / Double(hop)                // rad/sample
        return (omegaTrue * sr) / twoPi                           // Hz
    }

    // Jacobsen / complex-bin interpolation delta (uses complex neighbors, not mags-only)
    private func jacobsenDelta(split: DSPSplitComplex, mags: [Float], k: Int) -> (Double, Double?) {
        guard k > 1, k + 1 < mags.count else { return (0.0, nil) }

        // X[k-1], X[k], X[k+1]
        let r1 = Double(split.realp[k - 1]), i1 = Double(split.imagp[k - 1])
        let r0 = Double(split.realp[k]),     i0 = Double(split.imagp[k])
        let r2 = Double(split.realp[k + 1]), i2 = Double(split.imagp[k + 1])

        // num = X[k-1] - X[k+1]
        let numR = r1 - r2
        let numI = i1 - i2

        // den = 2X[k] - X[k-1] - X[k+1]
        let denR = 2.0 * r0 - r1 - r2
        let denI = 2.0 * i0 - i1 - i2

        // d = num / den (complex division)
        let denMag2 = denR * denR + denI * denI
        if denMag2 < 1e-24 { return (0.0, nil) }

        let dR = (numR * denR + numI * denI) / denMag2
        // let dI = (numI * denR - numR * denI) / denMag2   // not needed; we use Re(d)

        let delta = max(-0.5, min(0.5, dR))

        // Confidence (reuse your “peaky” idea)
        let a = Double(mags[k - 1]), b = Double(mags[k]), c = Double(mags[k + 1])
        let peaky = b / max(1e-12, 0.5 * (a + c))
        let conf = max(0.0, min(1.0, (peaky - 1.0) / 6.0))
        return (delta, conf)
    }

    // MARK: - HPS coarse f0

    private func coarseHPS(mags: [Float], sr: Double, n: Int, peakBin: Int) -> (Double?, Double?) {
        let binHz = sr / Double(n)

        let kMin = max(1, Int(config.peakSearchHz.lowerBound / binHz))
        let kMax = min(mags.count - 2, Int(config.peakSearchHz.upperBound / binHz))
        guard kMax > kMin else { return (nil, nil) }

        // Power-spectrum noise floor (median in a mid-band). We already have this helper in-file.
        let floorPow = estimateNoiseFloorPow(mags: mags, sr: sr, n: n)
        let floorF = Float(floorPow)

        let maxH = max(2, min(config.maxHpsHarmonics, 8))
        let eps: Float = 1e-12

        // Weighted harmonic sum with a *strong* fundamental term + soft penalty if fundamental is missing.
        // This prevents the classic HPS failure: picking f/2 for pure tones (because 2k hits the only peak).
        var bestK = kMin
        var bestScore = -Float.infinity

        // Candidate fundamentals must plausibly generate the observed peak as a harmonic.
        // This prevents HPS picking ~222 Hz when the true peak is ~415 Hz at N=4096.
        var cand = Set<Int>()
        for h in 1...maxH {
            let kc = Int((Double(peakBin) / Double(h)).rounded())
            for dk in -1...1 {
                let k = kc + dk
                if k >= kMin && k <= kMax { cand.insert(k) }
            }
        }

        // Fallback to full scan only if something is truly off
        let ks: [Int] = cand.isEmpty ? Array(kMin...kMax) : cand.sorted()

        for k in ks {
            let m1 = mags[k]
            let snr1 = m1 / (floorF + eps)

            var score = 2.6 * logf(m1 + eps)

            if maxH >= 2 {
                for h in 2...maxH {
                    let kk = k * h
                    if kk >= mags.count { break }
                    score += (1.0 / Float(h)) * logf(mags[kk] + eps)
                }
            }

            if snr1 < 2.0      { score -= 8.0 }
            else if snr1 < 4.0 { score -= 3.0 }

            if score > bestScore {
                bestScore = score
                bestK = k
            }
        }


        // Subharmonic promotion safeguard:
        // If bestK’s fundamental bin is near noise but a multiple is strong, promote to that multiple.
        // (This is the exact fix for: 415 -> ~210, 660 -> ~328.)
        var finalK = bestK
        let base = mags[bestK]
        if base < floorF * 2.0 {
            for mult in 2...maxH {
                let kk = bestK * mult
                if kk >= mags.count { break }
                let up = mags[kk]
                if up > floorF * 20.0 { // ~13 dB above floor (power domain)
                    finalK = kk
                    break
                }
            }
        }

        let f0 = Double(finalK) * binHz

        // Confidence: compare bestScore to local mean score neighborhood (same scoring, small window).
        let left = max(kMin, finalK - 2)
        let right = min(kMax, finalK + 2)

        var meanScore: Float = 0
        var c: Float = 0
        for k in left...right {
            let m1 = mags[k]
            let snr1 = m1 / (floorF + eps)

            var score = 2.6 * logf(m1 + eps)
            if maxH >= 2 {
                for h in 2...maxH {
                    let kk = k * h
                    if kk >= mags.count { break }
                    score += (1.0 / Float(h)) * logf(mags[kk] + eps)
                }
            }
            if snr1 < 2.0 { score -= 8.0 }
            else if snr1 < 4.0 { score -= 3.0 }

            meanScore += score
            c += 1
        }
        meanScore /= max(1, c)

        let conf = Double(max(0.0, min(1.0, (bestScore - meanScore) / 6.0)))
        return (f0, conf)
    }

    /// Correct the common HPS “octave-under” failure on near-sine inputs:
    /// - If HPS picks k where the spectrum energy is actually concentrated at 2k (and there aren't other strong harmonics),
    ///   promote f0 by ×2 (or ×3/×4 in rarer cases).
    /// - But if multiple harmonics are strong (missing-fundamental scenario), keep the lower f0.
    private func promoteIfSubharmonic(
        f0: Double?,
        mags: [Float],
        peakBin: Int,
        sr: Double,
        n: Int
    ) -> Double? {
        guard var f0, f0.isFinite, f0 > 0 else { return nil }

        let binHz = sr / Double(n)
        if !binHz.isFinite || binHz <= 0 { return f0 }

        // Base bin for f0
        var k0 = Int((f0 / binHz).rounded())
        k0 = max(1, min(mags.count - 2, k0))

        // If k0 is already near the peak, there's nothing to “promote”.
        if abs(k0 - peakBin) <= 2 { return f0 }

        let p0 = mags[k0]

        // Look for the case where the *peak* sits at an integer multiple of k0 (usually ×2),
        // and the spectrum does NOT show a full harmonic series (i.e., not missing-fundamental).
        let maxSeriesH = min(8, (mags.count - 1) / max(1, k0))

        for mult in 2...4 {
            let km = k0 * mult
            if km >= mags.count { break }

            // Only consider this promotion if that multiple is essentially the peak.
            if abs(km - peakBin) > 2 { continue }

            let pm = mags[km]
            if pm <= 0 { continue }

            // Count other strong harmonics besides `mult`.
            // If many are strong, that indicates a real fundamental at k0 (missing-fundamental), so do NOT promote.
            var strongOthers = 0
            if maxSeriesH >= 3 {
                for h in 2...maxSeriesH {
                    if h == mult { continue }
                    let kk = k0 * h
                    if kk >= mags.count { break }
                    if mags[kk] > pm * 0.22 { strongOthers += 1 }
                }
            }

            // Promotion condition: fundamental bin is weak relative to the peak harmonic,
            // and there aren't other strong harmonics supporting k0 as the true fundamental.
            if strongOthers == 0 && p0 < pm * 0.12 {
                f0 *= Double(mult)
                break
            }
        }

        return f0
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
// MARK: - Noise floor helper

    /// Median power estimate in a mid-band region to approximate noise floor (power spectrum input).
    private func estimateNoiseFloorPow(mags: [Float], sr: Double, n: Int) -> Double {
        let binHz = sr / Double(n)
        let lo = max(2, Int(80.0 / binHz))
        let hi = min(mags.count - 2, Int(5000.0 / binHz))
        if hi <= lo { return 1e-12 }

        var band = Array(mags[lo..<hi])
        band.sort()
        let mid = band[band.count / 2]
        return max(1e-12, Double(mid))
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
