//
//  PitchAccuracyHarness.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/27/25.
//


import Foundation

#if DEBUG
enum PitchAccuracyHarness {

    struct Stats {
        var errorsCents: [Double] = []
        mutating func push(_ e: Double) { errorsCents.append(e) }
        var median: Double {
            let s = errorsCents.sorted()
            return s.isEmpty ? 0 : s[s.count/2]
        }
        var mean: Double {
            guard !errorsCents.isEmpty else { return 0 }
            return errorsCents.reduce(0,+) / Double(errorsCents.count)
        }
        var stddev: Double {
            guard errorsCents.count >= 2 else { return 0 }
            let m = mean
            let v = errorsCents.reduce(0.0) { $0 + ($1 - m)*($1 - m) } / Double(errorsCents.count - 1)
            return sqrt(max(0, v))
        }
    }

    static func run(sampleRate sr: Double = 48_000,
                    secondsPerTone: Double = 0.6,
                    settleSeconds: Double = 0.15,
                    freqs: [Double] = stride(from: 110.0, through: 1760.0, by: 110.0).map { $0 }) {

        let fft = PitchFFT(sampleRate: sr)
        var sizerHz = 261.63

        func genSine(freq: Double, n: Int, phase: inout Double) -> [Float] {
            var out = [Float](repeating: 0, count: n)
            let w = 2.0 * Double.pi * freq / sr
            for i in 0..<n {
                out[i] = Float(sin(phase))
                phase += w
                if phase > 2.0 * Double.pi { phase -= 2.0 * Double.pi }
            }
            return out
        }

        var global = Stats()

        for f in freqs {
            // stabilize FFT size once per tone
            fft.ensureSize(cycles: 8.0, f0Guess: sizerHz)
            let N = fft.frameSize
            let hop = max(1, N / 4)

            let totalFrames = Int((secondsPerTone * sr) / Double(hop))
            let settleFrames = Int((settleSeconds * sr) / Double(hop))

            var phase = 0.0
            var buf: [Float] = []
            buf.reserveCapacity(N + hop * 4)

            var st = Stats()

            for frameIdx in 0..<totalFrames {
                // feed hop samples per analysis step (matches your live discipline)
                let hopSamples = genSine(freq: f, n: hop, phase: &phase)
                buf.append(contentsOf: hopSamples)
                if buf.count < N { continue }

                let frame = Array(buf.prefix(N))
                buf.removeFirst(min(hop, buf.count))

                let res = frame.withUnsafeBufferPointer { fft.analyze($0, f0Hint: f, hopSamples: hop) }
                let est = res.f0Fast ?? res.peakFreq
                if est.isFinite, est > 0, frameIdx >= settleFrames {
                    let cents = 1200.0 * log2(est / f)
                    st.push(cents)
                    global.push(cents)
                }
            }

            print(String(format: "[HARNESS] f=%.1f Hz  median=%+.3f¢  mean=%+.3f¢  sd=%.3f¢  n=%d",
                         f, st.median, st.mean, st.stddev, st.errorsCents.count))

            // update sizer slowly between tones
            sizerHz = 0.85 * sizerHz + 0.15 * f
        }

        print(String(format: "[HARNESS:ALL] median=%+.3f¢  mean=%+.3f¢  sd=%.3f¢  n=%d",
                     global.median, global.mean, global.stddev, global.errorsCents.count))
    }
}
#endif
