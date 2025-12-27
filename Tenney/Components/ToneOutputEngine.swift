//  ToneOutputEngine.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import AVFoundation
import Accelerate
import os


// MARK: - ENTRY POINT: One engine to run them all (MONO out; stereo only for scope)
final class ToneOutputEngine {
    private var scopeX: [Float] = []
    private var scopeY: [Float] = []

    // MARK: Singleton
    static let shared = ToneOutputEngine()
    private init() {
            loadPersistedConfigIfPresent()
        }
    // MARK: Public config (global, affects all voices)
    enum GlobalWave: String, CaseIterable, Codable { case foldedSine, triangle, saw }
    struct Config: Codable, Equatable {
        var wave: GlobalWave = .foldedSine                // (1) folded sine (Buchla-style mirror folds)
        var foldAmount: Float = 1.25                      // folds, ~0.0 … 5.0
        var drive_dB: Float = 6.0                         // pre-gain into folder, dB
        var attackMs: Double = 500.0                        // global AR
        var releaseMs: Double = 1000.0
        var outputGain_dB: Float = -6.0                   // final gain before soft limiter
        var limiterOn: Bool = true                        // soft clip safety
    }
    // Do NOT mutate from render thread.
        // Backed by a tiny lock to avoid tearing while the render thread snapshots config.
        var config: Config {
            get {
                os_unfair_lock_lock(&configLock); defer { os_unfair_lock_unlock(&configLock) }
                return _config
            }
            set {
                os_unfair_lock_lock(&configLock)
                _config = newValue
                os_unfair_lock_unlock(&configLock)
                schedulePersistConfig()
            }
        }
    
        private var _config = Config()
        private var configLock = os_unfair_lock_s()
        private var persistWork: DispatchWorkItem?

    // MARK: Public API (robust)
    // Voice handle typealias for clarity
    typealias VoiceID = Int

        private func loadPersistedConfigIfPresent() {
            guard let data = UserDefaults.standard.data(forKey: SettingsKeys.toneConfigJSON),
                  let decoded = try? JSONDecoder().decode(Config.self, from: data)
            else { return }
    
            os_unfair_lock_lock(&configLock)
            _config = decoded
            os_unfair_lock_unlock(&configLock)
        }
    
        private func schedulePersistConfig() {
            // Debounce to avoid hammering UserDefaults while sliders move.
            persistWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let snapshot = self.config
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                UserDefaults.standard.set(data, forKey: SettingsKeys.toneConfigJSON)
            }
            persistWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
        }

    /// Start a sustained tone; returns VoiceID.
    @discardableResult
    func start(frequency: Double) -> VoiceID {
        if !isRunning { startEngineIfNeeded() }
        let id = sustain(freq: frequency, amp: 0.18)
        testToneID = id
        return id
    }
    /// Stop the dedicated test tone (and all voices).
    func stop() { stopAll(); testToneID = nil }

    /// Back-compat helper for AppModel: retune or start the dedicated test tone.
    func setFrequency(_ f: Double) {
        if let id = testToneID {
            retune(id: id, to: f, hardSync: false)
        } else {
            testToneID = sustain(freq: f, amp: 0.18)
        }
    }

    /// Low-level voice control
    @discardableResult
    func sustain(freq: Double, amp: Float) -> VoiceID {
        if !isRunning { startEngineIfNeeded() }

        let id = nextID; nextID &+= 1
        let cfg = config
        let sr = sampleRate

        let a = max(1, Int((cfg.attackMs  / 1000.0) * sr))
        let r = max(1, Int((cfg.releaseMs / 1000.0) * sr))

        enqueue(.sustain(id: id, freq: Float(freq), amp: amp, attackSamps: a, releaseSamps: r))
        return id
    }

    func retune(id: VoiceID, to freq: Double, hardSync: Bool = false) {
        enqueue(.retune(id: id, freq: Float(freq), hardSync: hardSync))
    }

    func release(id: VoiceID, seconds: Double) {
        let rs = max(0.0, seconds)
        let samps = max(1, Int(rs * sampleRate))
        enqueue(.release(id: id, releaseSamps: samps))
    }

    func stopAll() {
        enqueue(.stopAll)
        testToneID = nil
    }

    // MARK: Optional: stereo scope tap (not audible)
    // Called once per render with two read-only buffers for X/Y display (length = frames).
    // Hardware output remains MONO.
    var scopeTap: ((_ x: UnsafePointer<Float>, _ y: UnsafePointer<Float>, _ count: Int) -> Void)?

    // MARK: Internals

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var isRunning = false
    private var sampleRate: Double = 48_000
    private var token: NSObjectProtocol?
    private var firstRenderLogged = false
    private var testToneID: VoiceID? = nil

    // Voice
    private struct Voice {
        var id: Int = 0
        var active: Bool = false

        // synth state
        var sr: Float = 48_000
        var freq: Float = 440
        var phase: Float = 0                 // [0,1)
        var phaseInc: Float = 440/48_000     // cycles/sample

        // envelope
        var gain: Float = 0.18
        var env: Float = 0
        var envState: Int = 0                // +1 A, 0 hold, -1 R
        var attackSamps: Int = 480
        var releaseSamps: Int = 4800

        mutating func setFreq(_ f: Float) {
            freq = max(0, f)
            phaseInc = freq / sr
        }
    }
    
    private enum VoiceCommand {
        case sustain(id: Int, freq: Float, amp: Float, attackSamps: Int, releaseSamps: Int)
        case retune(id: Int, freq: Float, hardSync: Bool)
        case release(id: Int, releaseSamps: Int)
        case stopAll
        case setSampleRate(Float)
    }

    private var cmdLock = os_unfair_lock_s()
    private var pendingCmds: [VoiceCommand] = []
    private var processingCmds: [VoiceCommand] = []   // drained on the audio thread

    @inline(__always) private func enqueue(_ c: VoiceCommand) {
        os_unfair_lock_lock(&cmdLock)
        pendingCmds.append(c)
        os_unfair_lock_unlock(&cmdLock)
    }

    @inline(__always) private func drainCommands_RT() {
        // audio thread
        os_unfair_lock_lock(&cmdLock)
        swap(&pendingCmds, &processingCmds)
        os_unfair_lock_unlock(&cmdLock)
    }

    

    private var voices: [Voice] = Array(repeating: Voice(), count: 16) // polyphony=16
    private var nextID: Int = 1

    // MARK: Engine boot (mono out; robust session/route handling)
    private func startEngineIfNeeded() {
        guard !isRunning else { return }

        // Use hardware format
        let out = engine.outputNode
        let hwFmt = out.inputFormat(forBus: 0) // what output node expects from mixer
        sampleRate = hwFmt.sampleRate > 0 ? hwFmt.sampleRate : 48_000

        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, ablPtr -> OSStatus in
            guard let self = self else { return noErr }

            self.drainCommands_RT()

            if !self.processingCmds.isEmpty {
                for cmd in self.processingCmds {
                    switch cmd {
                    case let .setSampleRate(srF):
                        for i in self.voices.indices {
                            self.voices[i].sr = srF
                            self.voices[i].phaseInc = self.voices[i].freq / srF
                        }

                    case let .sustain(id, freq, amp, attackSamps, releaseSamps):
                        let slot = self.voices.firstIndex(where: { !$0.active }) ?? 0
                        var v = self.voices[slot]
                        v.id = id
                        v.active = true
                        v.gain = amp
                        v.env = 0
                        v.envState = +1
                        v.attackSamps = attackSamps
                        v.releaseSamps = releaseSamps
                        v.sr = self.voices[slot].sr   // already current
                        v.setFreq(freq)
                        self.voices[slot] = v

                    case let .retune(id, freq, hardSync):
                        if let i = self.voices.firstIndex(where: { $0.id == id && $0.active }) {
                            var v = self.voices[i]
                            v.setFreq(freq)
                            if hardSync { v.phase = 0 }
                            self.voices[i] = v
                        }

                    case let .release(id, releaseSamps):
                        if let i = self.voices.firstIndex(where: { $0.id == id && $0.active }) {
                            var v = self.voices[i]
                            v.envState = -1
                            v.releaseSamps = max(1, releaseSamps)
                            self.voices[i] = v
                        }

                    case .stopAll:
                        for i in self.voices.indices {
                            self.voices[i].active = false
                            self.voices[i].env = 0
                            self.voices[i].envState = 0
                        }
                    }
                }
                self.processingCmds.removeAll(keepingCapacity: true)
            }

            let n = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            guard abl.count >= 1,
                  let L = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            // MONO: zero L, mirror to R later if needed
            vDSP_vclr(L, 1, vDSP_Length(n))
            var R: UnsafeMutablePointer<Float>? = nil
            if abl.count >= 2 { R = abl[1].mData?.assumingMemoryBound(to: Float.self); if let R { vDSP_vclr(R, 1, vDSP_Length(n)) } }

            // scratch for scope X/Y (not audible)
            if self.scopeX.count < n {
                self.scopeX = [Float](repeating: 0, count: n)
                self.scopeY = [Float](repeating: 0, count: n)
            }


            if !self.firstRenderLogged {
                self.firstRenderLogged = true
                print("[ToneOutput] render pull: frames=\(n) ch=\(abl.count) sr=\(Int(self.sampleRate))")
            }
            if self.voices.allSatisfy({ !$0.active }) {
                // still provide blank scope
                self.scopeX.withUnsafeMutableBufferPointer { xb in
                    vDSP_vclr(xb.baseAddress!, 1, vDSP_Length(n))
                }
                self.scopeY.withUnsafeMutableBufferPointer { yb in
                    vDSP_vclr(yb.baseAddress!, 1, vDSP_Length(n))
                }
                if let tap = self.scopeTap {
                    self.scopeX.withUnsafeBufferPointer { x in
                        self.scopeY.withUnsafeBufferPointer { y in
                            tap(x.baseAddress!, y.baseAddress!, n)
                        }
                    }
                }

                // duplicate mono to R if present
                if let R { cblas_scopy(Int32(n), L, 1, R, 1) }
                return noErr
            }

            // Precompute globals
            let cfg = self.config
            let outGain = powf(10.0, cfg.outputGain_dB / 20.0)
            let drive  = powf(10.0, cfg.drive_dB / 20.0)
            let foldA  = max(0.0, cfg.foldAmount)

            // Render per sample (simple, branchless enough; 16 voices is fine @ 48k)
            for s in 0..<n {
                var mix: Float = 0
                var xForScope: Float = 0
                var yForScope: Float = 0

                for i in self.voices.indices {
                    if !self.voices[i].active { continue }
                    var v = self.voices[i]

                    // AR env
                    let aInc: Float = (v.attackSamps > 0) ? 1.0 / Float(v.attackSamps)  : 1.0
                    let rDec: Float = (v.releaseSamps > 0) ? 1.0 / Float(v.releaseSamps) : 1.0
                    switch v.envState {
                    case +1: v.env += aInc; if v.env >= 1 { v.env = 1; v.envState = 0 }
                    case -1: v.env -= rDec; if v.env <= 0 { v.env = 0; v.active = false; self.voices[i] = v; continue }
                    default: break
                    }

                    // Oscillator core: foldedSine / triangle (BLAMP) / saw (BLEP)
                    var y: Float = 0
                    switch cfg.wave {
                    case .foldedSine:
                        // Buchla-style mirror folder: pre-drive, mirror wrap (periodic sawtooth reflect)
                        // 1) drive into sine
                        let sPhase = v.phase
                        let raw = sinf(2.0 * Float.pi * sPhase) * drive
                        // 2) mirror fold around ±1 with repeated reflections
                        y = mirrorFold(raw, folds: foldA)
                    case .triangle:
                        y = triBLAMP(phase: v.phase, dphi: v.phaseInc)
                    case .saw:
                        y = sawBLEP(phase: v.phase, dphi: v.phaseInc)
                    }

                    // advance phase
                    var ph = v.phase + v.phaseInc
                    if ph >= 1 { ph -= 1 }
                    v.phase = ph

                    // accumulate
                    let samp = y * v.gain * v.env
                    mix += samp    // ← replace mix &+= samp

                    // scope pair: simple quadrature from same phase (nice lissajous)
                    // X = cos, Y = sin (of the current voice’s phase)
                    if xForScope == 0 && yForScope == 0 {
                        let ang = 2.0 * Float.pi * v.phase
                        xForScope = cosf(ang)
                        yForScope = sinf(ang)
                    }

                    self.voices[i] = v
                }

                // Mono out gain
                var out = mix * outGain

                // Soft limiter (symmetric tanh-ish) if enabled
                if cfg.limiterOn {
                    // Fast cubic soft clip
                    let absx = fabsf(out)
                    if absx > 0.95 {
                        let sign: Float = (out >= 0) ? 1 : -1
                        let t = min(1.0, (absx - 0.95) * 20.0)
                        out = sign * (0.95 + (1 - (1 - t)*(1 - t)) * 0.05)
                    }
                }

                L[s] += out
                // keep hardware output mono: copy L to R if present
                if let R { R[s] += out }

                self.scopeX[s] = xForScope
                self.scopeY[s] = yForScope

            }

            // push scope buffers
            if let tap = self.scopeTap {
                self.scopeX.withUnsafeBufferPointer { xb in
                    self.scopeY.withUnsafeBufferPointer { yb in
                        tap(xb.baseAddress!, yb.baseAddress!, n)
                    }
                }
            }

            return noErr
        }

        // Connect: source → mainMixer → output
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: max(hwFmt.channelCount, 2))!
        engine.attach(sourceNode)
        engine.disconnectNodeInput(engine.mainMixerNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: fmt)
        engine.connect(engine.mainMixerNode, to: out, format: hwFmt)

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            token = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in self?.handleRouteChange() }
        } catch {
            print("[ToneOutput] start error: \(error)")
        }
    }

    private func handleRouteChange() {
        let hw = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = hw.sampleRate > 0 ? hw.sampleRate : 48_000
        enqueue(.setSampleRate(Float(sampleRate)))
    }


    // MARK: - DSP helpers (polyBLEP/BLAMP + mirror folder)

    // polyBLEP step correction for saw (phase in [0,1))
    @inline(__always) private func polyBLEP(_ t: Float, _ dt: Float) -> Float {
        var x = t
        if x < dt {
            x /= dt
            return (x + x) - (x * x) - 1.0
        } else if x > 1.0 - dt {
            x = (x - 1.0) / dt
            return (x * x) + (x + x) + 1.0
        }
        return 0.0
    }

    // polyBLAMP corner correction (integrated BLEP) for triangle corners
    @inline(__always) private func polyBLAMP(_ t: Float, _ dt: Float) -> Float {
        var x = t
        let half: Float = 0.5
        let oneThird: Float = 1.0 / 3.0
        if x < dt {
            x /= dt
            return (half * x * x) - (oneThird * x * x * x)
        } else if x > 1.0 - dt {
            x = (x - 1.0) / dt
            return (half * x * x) + (oneThird * x * x * x)
        }
        return 0.0
    }

    // Bandlimited SAW using BLEP
    @inline(__always) private func sawBLEP(phase: Float, dphi: Float) -> Float {
        let t = phase
        let dt = dphi
        var y = (2.0 * t - 1.0)             // naive saw
        y -= polyBLEP(t, dt)                // correct discontinuity
        return y
    }

    // BLAMP triangle
    @inline(__always) private func triBLAMP(phase: Float, dphi: Float) -> Float {
        let t = phase
        let dt = dphi
        // naive tri from saw integral shape: 2*|2t-1|-1
        let s = 2.0 * t - 1.0
        var tri = 2.0 * fabsf(s) - 1.0
        tri -= polyBLAMP(t, dt)
        tri += polyBLAMP(fmodf(t + 0.5, 1.0), dt)
        return tri
    }

    // Buchla-style mirror folder: repeatedly reflect beyond [-1, +1]
    // folds ~ number/strength control; drive applied before entering
    @inline(__always) private func mirrorFold(_ x: Float, folds: Float) -> Float {
        // Map folds into an effective reflection range (more folds = more reflections opportunity)
        // Keep it stable and cheap on device.
        var y = x
        let maxIter = min(12, Int(2 + folds * 4)) // up to ~12 reflections
        for _ in 0..<maxIter {
            if y > 1.0 { y = 2.0 - y }
            else if y < -1.0 { y = -2.0 - y }
            else { break }
        }
        return y
    }
}
