//
//  LatticeTone.swift
//  Tenney
//
//  Polyphonic, lightweight sine synth for lattice audition.
//  API matches:
//    sustain(freq:amp:attackMs:) -> Int
//    release(id:releaseSeconds:)
//    stopAll()
//

import Foundation
import AVFAudio
import os

final class LatticeTone {
    static let shared = LatticeTone()

    private struct Voice {
        var id: Int
        var freq: Float
        var amp: Float
        var phase: Float
        var phaseInc: Float

        // Envelope
        var env: Float
        var attackStep: Float
        var releaseStep: Float
        var state: State

        enum State {
            case attack(remaining: Int)
            case sustain
            case release(remaining: Int)
        }
    }

    private let engine = AVAudioEngine()
    private let log = Logger(subsystem: "com.StageDevices.Tenney", category: "LatticeTone")

    private var source: AVAudioSourceNode!
    private var sampleRate: Double = 44_100.0
    private var channels: AVAudioChannelCount = 2

    private var voices: [Int: Voice] = [:]
    private var nextID: Int = 1

    // Keep this lock extremely short on the main thread; audio thread will also use it.
    private var lock = os_unfair_lock_s()

    private init() {
        configureAudioGraph()
    }

    // MARK: - Public API

    /// Start (or retrigger) a sustained sine at `freq` with `amp` and an attack ramp.
    /// Returns a voice id you can later release.
    func sustain(freq: Double, amp: Float, attackMs: Double) -> Int {
        ensureEngineRunning()

        let sr = sampleRate
        let aSec = max(0.0, attackMs / 1000.0)
        let attackSamples = max(1, Int(sr * aSec))
        let attackStep = 1.0 / Float(attackSamples)

        let f = Float(max(0.0, freq))
        let inc = Float(2.0 * Double.pi) * f / Float(sr)

        os_unfair_lock_lock(&lock)
        let id = nextID
        nextID &+= 1
        voices[id] = Voice(
            id: id,
            freq: f,
            amp: max(0, amp),
            phase: 0,
            phaseInc: inc,
            env: 0,
            attackStep: attackStep,
            releaseStep: 0,
            state: .attack(remaining: attackSamples)
        )
        os_unfair_lock_unlock(&lock)

        return id
    }

    /// Release an active voice by id using a linear fade of `releaseSeconds`.
    func release(id: Int, releaseSeconds: Double) {
        let rs = max(0.0, releaseSeconds)
        let releaseSamples = max(1, Int(sampleRate * rs))

        os_unfair_lock_lock(&lock)
        guard var v = voices[id] else {
            os_unfair_lock_unlock(&lock)
            return
        }
        v.releaseStep = max(0.000_001, v.env / Float(releaseSamples))
        v.state = .release(remaining: releaseSamples)
        voices[id] = v
        os_unfair_lock_unlock(&lock)
    }

    /// Hard-stop everything immediately (silence).
    func stopAll() {
        os_unfair_lock_lock(&lock)
        voices.removeAll()
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Graph

    private func configureAudioGraph() {
        let session = AVAudioSession.sharedInstance()
        sampleRate = session.sampleRate > 0 ? session.sampleRate : 44_100.0
        channels = 2

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!

        source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }

            let n = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)

            // Zero buffers
            for buf in abl {
                guard let mData = buf.mData else { continue }
                let out = mData.assumingMemoryBound(to: Float.self)
                out.assign(repeating: 0, count: n)
            }

            // Render voices
            os_unfair_lock_lock(&self.lock)
            if self.voices.isEmpty {
                os_unfair_lock_unlock(&self.lock)
                return noErr
            }

            // We’ll accumulate into the first channel then copy to others (simple, cheap).
            guard let mData0 = abl.first?.mData else {
                os_unfair_lock_unlock(&self.lock)
                return noErr
            }
            let out0 = mData0.assumingMemoryBound(to: Float.self)

            // Render sample-by-sample (small voice count; stable, easy).
            let keys = Array(self.voices.keys)
            let twoPi = Float(2.0 * Double.pi)
            for i in 0..<n {
                var s: Float = 0

                for id in keys {
                    guard var v = self.voices[id] else { continue }

                    switch v.state {
                    case .attack(let remaining):
                        v.env = min(1, v.env + v.attackStep)
                        let rem = remaining - 1
                        if rem <= 0 || v.env >= 1 {
                            v.env = min(1, v.env)
                            v.state = .sustain
                        } else {
                            v.state = .attack(remaining: rem)
                        }

                    case .sustain:
                        break

                    case .release(let remaining):
                        v.env = max(0, v.env - v.releaseStep)
                        let rem = remaining - 1
                        if rem <= 0 || v.env <= 0.00001 {
                            self.voices.removeValue(forKey: id)
                            continue
                        } else {
                            v.state = .release(remaining: rem)
                        }
                    }


                    s += sin(v.phase) * v.amp * v.env
                    v.phase += v.phaseInc
                    if v.phase > twoPi { v.phase -= twoPi }

                    self.voices[id] = v
                }

                out0[i] = s
            }

            os_unfair_lock_unlock(&self.lock)

            // Copy channel 0 → other channels (stereo mirror)
            if abl.count > 1 {
                for ch in 1..<abl.count {
                    guard let mData = abl[ch].mData else { continue }
                    let out = mData.assumingMemoryBound(to: Float.self)
                    out.assign(from: out0, count: n)
                }
            }

            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    private func ensureEngineRunning() {
        if engine.isRunning { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // Conservative defaults; your Pro Audio / routing layer can override category/options elsewhere if needed.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            log.error("AVAudioSession configure failed: \(String(describing: error))")
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            log.error("AVAudioEngine start failed: \(String(describing: error))")
        }
    }
}
