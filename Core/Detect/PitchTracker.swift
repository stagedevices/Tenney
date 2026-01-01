//
//  PitchTracker.swift
//  Tenney
//
//  Tenney real-time pitch tracker (AVAudioEngine + YIN/HPS)
//  First-party frameworks only. iOS 26+.
//
//  Notes:
//  • Mic capture via AVAudioEngine tap → mono Float32
//  • Heavy DSP (YIN/HPS) runs on a dedicated queue (never on the audio thread)
//  • RMS reported continuously via onMetrics
//  • f0: YIN first, then HPS fallback; Kalman smoothing
//  • Test tone is audible ONLY when toggled ON (never auto)
//

import Foundation
import AVFoundation
import Accelerate
import QuartzCore
import os
import os.lock

// MARK: - 1D Kalman filter (stateful, lightweight)


// Lightweight locked container for RT-safe snapshots
final class Locked<T> {
    private var value: T
    private var lock = os_unfair_lock_s()
    init(_ v: T) { value = v }
    func get() -> T {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return value
    }
    func set(_ v: T) {
        os_unfair_lock_lock(&lock); value = v; os_unfair_lock_unlock(&lock)
    }
}

final class PitchTracker {
    // MARK: - Public callbacks (UI stays untouched)
    var onHz: ((Double, Double)->Void)?
        var onMetrics: ((Float)->Void)?
    
    /// Raw mic PCM (mono Float32), for Phase Scope.
        /// Called on the audio tap thread; keep it lightweight.
        var onAudioPCM: (([Float], Double) -> Void)?
    
        /// Bind UI callbacks; forces delivery on the main actor.
        func setUICallbacks(
            onHz: @escaping @Sendable (Double, Double) -> Void,
            onMetrics: @escaping @Sendable (Float) -> Void
        ) {
            self.onHz = { f, t in
                Task { @MainActor in onHz(f, t) }
            }
            self.onMetrics = { rms in
                Task { @MainActor in onMetrics(rms) }
            }
        }

    // MARK: - Engine / Session
    private let engine = AVAudioEngine()
    private let log = Logger(subsystem: "com.stagedevices.tenney", category: "detect")

    // One-time guards
    private var sessionConfigured = false
    private var graphStarted = false
    private var tapInstalled = false

    // Nodes
    private var pullNode: AVAudioSourceNode?      // silent pull → keeps render loop alive
    private var toneNode: AVAudioSourceNode?      // audible test tone (always connected)
    private var toneMixer: AVAudioMixerNode?      // gain gate for test tone (toggle via volume)
    private var nullMixer: AVAudioMixerNode?      // mutes mic path but keeps it rendered

    // MARK: - Analysis scheduling
    private let analysisQueue = DispatchQueue(label: "Tenney.PitchAnalysis", qos: .userInitiated)
    private var analysisRunning = false
    private let analysisLock = NSLock()           // allow at most one concurrent analyze()

    // Test-tone driver (runs only when test tone is ON)
    private var toneTimer: DispatchSourceTimer?

    // Smoother
    private let kalman: Kalman1D

    // Small mono ring buffer snapshot (power-of-two)
    private let ringSize = 8192
    private var ring: [Float]
    private var writeIndex = 0
    private let ringLock = NSLock()

    // Formats
    private var sampleRate: Double = 48_000
    private var desiredFormat: AVAudioFormat?

    // Test tone state (RT-safe snapshot)
    private struct ToneState { var hz: Double; var amp: Float }
    private let toneState = Locked(ToneState(hz: 220.0, amp: 0.25)) // a bit louder so it’s obvious
    private var useTestTone = false
    private var tonePhase: Double = 0

    // DC blocker (simple one-pole HPF state)
    private var hpfX1: Float = 0
    private var hpfY1: Float = 0
    private let hpfA: Float = 0.995   // ~40–50 Hz corner at 48 kHz (safe for voice/instruments)

    // Debug counters / probes
    private var dbgTapCount = 0
    private var dbgEmitCount = 0
    private var dbgAnalyzeCount = 0
    private var dbgDiagTimer: DispatchSourceTimer?
    private var dbgLastTapPeak: Float = 0
    private var dbgLastAnalyzeRMS: Float = 0

    // IMPORTANT: heavy DSP MUST NOT run on the tap thread
    private let dbgDirectAnalyze: Bool = false

    private var dbgAnalyzeFirstHitLogged = false

    // MARK: - Lifecycle
    init(strictness: Strictness) {
        self.kalman = Kalman1D(q: strictness.kalmanQ, r: strictness.kalmanR)
        self.ring = [Float](repeating: 0, count: ringSize)
    }

    deinit { shutdown() }

    // MARK: - Public control
    func setTestTone(enabled: Bool, hz: Double) {
        useTestTone = enabled
        toneState.set(ToneState(hz: hz, amp: 0.15))
        log.debug("setTestTone: \(enabled ? "ON" : "OFF") @ \(hz, privacy: .public) Hz")

        // (Audible) always on the main thread for safety
                if Thread.isMainThread {
                    updateToneConnection()
                } else {
                    DispatchQueue.main.async { [weak self] in self?.updateToneConnection() }
                }

        // (Analysis) drive tone-only frames via a timer ONLY when tone is on
        if enabled {
            if toneTimer == nil {
                let t = DispatchSource.makeTimerSource(queue: analysisQueue)
                t.schedule(deadline: .now() + .milliseconds(20),
                           repeating: .milliseconds(20),
                           leeway: .milliseconds(2))
                t.setEventHandler { [weak self] in self?.processToneFrame() }
                t.resume()
                toneTimer = t
                log.debug("toneTimer started")
            }

            // Kick a proof-of-life emit to UI
            analysisQueue.async { [weak self] in
                guard let self else { return }
                let f = self.toneState.get().hz
                let smoothed = self.kalman.filter(z: f)
                self.onHz?(smoothed, CACurrentMediaTime())
                self.log.debug("emit (forced) f0=\(String(format: "%.2f", smoothed), privacy: .public) Hz")
            }
        } else {
            toneTimer?.cancel()
            toneTimer = nil
            log.debug("toneTimer stopped")
        }
    }

    func updateStrictness(_ s: Strictness) {
        kalman.configure(q: s.kalmanQ, r: s.kalmanR)
    }

    /// Start analysis loop and build graph (one-time)
    func startDetection() {
        ensureSessionAndGraphOnce()
        analysisRunning = true
        log.debug("startDetection: ready (tap-driven)")

        // 1 Hz diagnostic ticker
        if dbgDiagTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: analysisQueue)
            t.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                self.log.debug("diag: tapPeak=\(String(format: "%.6f", self.dbgLastTapPeak), privacy: .public)  lastRMS=\(String(format: "%.6f", self.dbgLastAnalyzeRMS), privacy: .public)  emits=\(self.dbgEmitCount, privacy: .public)")
            }
            t.resume()
            dbgDiagTimer = t
        }
    }

    /// Enable/disable microphone capture without touching the graph
    func enableMicrophoneCapture(_ enable: Bool) {
        ensureSessionAndGraphOnce()
        if enable {
            log.debug("enableMicrophoneCapture: ON")
            installInputTapOnce()
        } else {
            log.debug("enableMicrophoneCapture: OFF")
            removeInputTapIfAny()
        }
    }

    func shutdown() {
        analysisRunning = false
        toneTimer?.cancel()
        toneTimer = nil
        dbgDiagTimer?.cancel()
        dbgDiagTimer = nil
        removeInputTapIfAny()
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Session + graph
    private func ensureSessionAndGraphOnce() {
        guard !sessionConfigured || !graphStarted else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.defaultToSpeaker, .mixWithOthers])
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
            _ = try? session.setPreferredInputNumberOfChannels(1)
            _ = try? session.setPreferredSampleRate(48_000)
            _ = try? session.setPreferredIOBufferDuration(128.0 / 48_000.0)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            self.sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000
            self.desiredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: self.sampleRate,
                                               channels: 1,
                                               interleaved: false)
            self.sessionConfigured = true

            // Nodes: null mixer (mute mic), tone node (detached by default), silent pull
            self.ensureNullMixerOnce()
            self.ensureToneNodeOnce()
            self.ensureSilentPullNodeOnce()

            // Wire input → nullMixer (muted) → mainMixer → output
            let input = self.engine.inputNode
            let inFmt = input.outputFormat(forBus: 0)

            if let nm = self.nullMixer {
                if self.engine.outputConnectionPoints(for: input, outputBus: 0).isEmpty {
                    self.engine.connect(input, to: nm, format: inFmt)
                }
                if self.engine.outputConnectionPoints(for: nm, outputBus: 0).isEmpty {
                    self.engine.connect(nm, to: self.engine.mainMixerNode, format: inFmt)
                }
                nm.outputVolume = 0.0 // fully muted (we keep render alive with a tiny tap)
                nm.removeTap(onBus: 0)
                nm.installTap(onBus: 0, bufferSize: 256, format: nil) { _, _ in /* pull-through */ }
            }

            // Tone node connection (off by default; update on toggle)
            self.updateToneConnection()

            if !self.engine.isRunning {
                self.engine.prepare()
                try self.engine.start()
            }
            self.graphStarted = true

            let route = session.currentRoute
            let ins = route.inputs.map { "\($0.portType.rawValue)" }.joined(separator: ",")
            let outs = route.outputs.map { "\($0.portType.rawValue)" }.joined(separator: ",")
            self.log.debug("Graph up. in=[\(ins, privacy: .public)] out=[\(outs, privacy: .public)] sr=\(self.sampleRate, privacy: .public)")
        } catch {
            self.log.error("ensureSessionAndGraphOnce error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureNullMixerOnce() {
        guard nullMixer == nil else { return }
        let m = AVAudioMixerNode()
        engine.attach(m)
        nullMixer = m
    }

    private func ensureSilentPullNodeOnce() {
        guard pullNode == nil else { return }
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        let node = AVAudioSourceNode { _, _, _, ablPtr -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            for b in abl { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        pullNode = node
    }

    private func ensureToneNodeOnce() {
        guard toneNode == nil else { return }
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, ablPtr -> OSStatus in
            guard let self else { return noErr }
            let s = self.toneState.get()                      // atomic snapshot
            let sr = max(1.0, self.sampleRate)
            let w = 2.0 * .pi * s.hz / sr
            let amp = s.amp

            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            for b in abl {
                guard let p = b.mData else { continue }
                let out = p.bindMemory(to: Float.self, capacity: Int(frameCount))
                for i in 0..<Int(frameCount) {
                    out[i] = sinf(Float(self.tonePhase)) * amp
                    self.tonePhase += w
                    if self.tonePhase > 2 * .pi { self.tonePhase -= 2 * .pi }
                }
            }
            return noErr
        }
        engine.attach(node)
        toneNode = node
        
                // Create a dedicated mixer for the tone and connect it once
                if toneMixer == nil {
                    let m = AVAudioMixerNode()
                    engine.attach(m)
                    toneMixer = m
                }
                let mixer = engine.mainMixerNode
                let mainFmt = mixer.outputFormat(forBus: 0)
                if let toneNode, let toneMixer {
                    if engine.outputConnectionPoints(for: toneNode, outputBus: 0).isEmpty {
                        engine.connect(toneNode, to: toneMixer, format: mainFmt)
                    }
                    if engine.outputConnectionPoints(for: toneMixer, outputBus: 0).isEmpty {
                        engine.connect(toneMixer, to: mixer, format: mainFmt)
                    }
                    toneMixer.outputVolume = 0.0 // start muted; toggle via updateToneConnection()
                }    }

    private func updateToneConnection() {
            if Thread.isMainThread {
                toneMixer?.outputVolume = useTestTone ? 1.0 : 0.0
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.toneMixer?.outputVolume = self.useTestTone ? 1.0 : 0.0
                }
            }
        }

    // MARK: - Tap (input) → Float32 mono → ring
    private func installInputTapOnce() {
        guard sessionConfigured, !tapInstalled else { return }
        let input = engine.inputNode
        let bus = 0
        input.removeTap(onBus: bus) // idempotent
        let inFmt = input.outputFormat(forBus: bus)
        let tapFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: inFmt.sampleRate,
                                   channels: 1,
                                   interleaved: false)
        log.debug("Input tap format(in): ch=\(inFmt.channelCount, privacy: .public) sr=\(inFmt.sampleRate, privacy: .public) kind=\(String(describing: inFmt.commonFormat), privacy: .public)")
        log.debug("Input tap format(tap): ch=\(tapFmt?.channelCount ?? 0, privacy: .public) sr=\(tapFmt?.sampleRate ?? 0, privacy: .public) interleaved=\(tapFmt?.isInterleaved == true ? "Y" : "N", privacy: .public) kind=\(String(describing: tapFmt?.commonFormat), privacy: .public)")
        // Use a modest buffer; ring snapshots handle windowing for DSP
        input.installTap(onBus: bus, bufferSize: 1024, format: tapFmt) { [weak self] buffer, _ in
            self?.handleTapBuffer(buffer)
        }
        tapInstalled = true
        log.debug("Input tap installed")
    }

    private func removeInputTapIfAny() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
        log.debug("Input tap removed")
    }

    private func handleTapBuffer(_ buffer: AVAudioPCMBuffer) {
        // One-shot: confirm we see real buffers
        if dbgTapCount == 0 {
            let f = buffer.format
            log.debug("tap buffer seen: ch=\(f.channelCount, privacy: .public) sr=\(f.sampleRate, privacy: .public) kind=\(String(describing: f.commonFormat), privacy: .public) frames=\(buffer.frameLength, privacy: .public)")
        }

        // Robust: extract mono Float32 regardless of layout
        guard let mono = extractMonoFloat32(buffer) else {
            log.error("tap: extractMonoFloat32 failed (ch=\(buffer.format.channelCount, privacy: .public) interleaved=\(buffer.format.isInterleaved ? "Y" : "N", privacy: .public))")
            return
        }
        
        // Phase Scope contract: publish raw mic PCM
        onAudioPCM?(mono, buffer.format.sampleRate)

        // Feed ring + quick peak on the audio thread (no allocations)
        mono.withUnsafeBufferPointer { ptr in
            writeToRing(from: ptr.baseAddress!, frames: mono.count)
        }

        // NO HEAVY WORK HERE — schedule analysis if none in-flight
        if !dbgDirectAnalyze, analysisLock.try() {
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.processRingFrame()
                self.analysisLock.unlock()
            }
        }

        // Debug-only path (off by default)
        if dbgDirectAnalyze { analyze(buf: mono) }
    }

    /// Extracts mono Float32 from any AVAudioPCMBuffer layout
    private func extractMonoFloat32(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }
        let fmt = buffer.format
        guard fmt.commonFormat == .pcmFormatFloat32 else { return nil }

        let ch = Int(fmt.channelCount)
        if ch == 0 { return nil }

        // Interleaved
        if fmt.isInterleaved {
            guard let base = buffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            if ch == 1 {
                return Array(UnsafeBufferPointer(start: base, count: frames))
            } else if ch == 2 {
                var mono = [Float](repeating: 0, count: frames)
                vDSP_vadd(base, vDSP_Stride(ch), base.advanced(by: 1), vDSP_Stride(ch), &mono, 1, vDSP_Length(frames))
                var half: Float = 0.5
                vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(frames))
                return mono
            } else {
                var mono = [Float](repeating: 0, count: frames)
                for c in 0..<ch {
                    vDSP_vadd(base.advanced(by: c), vDSP_Stride(ch), mono, 1, &mono, 1, vDSP_Length(frames))
                }
                var invN: Float = 1.0 / Float(ch)
                vDSP_vsmul(mono, 1, &invN, &mono, 1, vDSP_Length(frames))
                return mono
            }
        }

        // Planar
        guard let planes = buffer.floatChannelData else { return nil }
        if ch == 1 {
            return Array(UnsafeBufferPointer(start: planes[0], count: frames))
        } else if ch == 2 {
            var mono = [Float](repeating: 0, count: frames)
            vDSP_vadd(planes[0], 1, planes[1], 1, &mono, 1, vDSP_Length(frames))
            var half: Float = 0.5
            vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(frames))
            return mono
        } else {
            var mono = [Float](repeating: 0, count: frames)
            for c in 0..<ch {
                vDSP_vadd(planes[c], 1, mono, 1, &mono, 1, vDSP_Length(frames))
            }
            var invN: Float = 1.0 / Float(ch)
            vDSP_vsmul(mono, 1, &invN, &mono, 1, vDSP_Length(frames))
            return mono
        }
    }

    private func writeToRing(from ptr: UnsafePointer<Float>, frames: Int) {
        let c = min(frames, ringSize)
        guard c > 0 else { return }
        ringLock.lock()
        let mask = ringSize - 1
        var wi = writeIndex
        for i in 0..<c {
            ring[wi] = ptr[i]
            wi = (wi + 1) & mask
        }
        writeIndex = wi
        ringLock.unlock()

        // Debug: show tap activity
        dbgTapCount &+= 1
        if dbgTapCount % 30 == 0 {
            log.debug("tap -> ring ok (\(self.dbgTapCount, privacy: .public))")
        }

        // Track peak of incoming block
        var peak: Float = 0
        vDSP_maxmgv(ptr, 1, &peak, vDSP_Length(c))
        dbgLastTapPeak = peak
        if dbgTapCount % 60 == 0 {
            self.log.debug("tap peak=\(String(format: "%.6f", peak), privacy: .public)")
        }
    }

    // Mic ring → analysis
    private func processRingFrame() {
        guard analysisRunning else { return }

        let N = 4096
        if N > ringSize { return } // shouldn’t happen

        var buf = [Float](repeating: 0, count: N)
        ringLock.lock()
        let mask = ringSize - 1
        let start = (writeIndex - N + ringSize) & mask
        if start + N <= ringSize {
            for i in 0..<N { buf[i] = ring[start + i] }
        } else {
            let head = ringSize - start
            for i in 0..<head { buf[i] = ring[start + i] }
            let tail = N - head
            for i in 0..<tail { buf[head + i] = ring[i] }
        }
        ringLock.unlock()

        analyze(buf: buf)
    }

    // Test-tone synth → analysis (timer-driven when tone is ON)
    private func processToneFrame() {
        guard analysisRunning else { return }
        var buf = [Float](repeating: 0, count: 4096)
        let s = toneState.get()
        let sr = max(1.0, sampleRate)
        let w = 2.0 * .pi * s.hz / sr
        let amp = s.amp
        for i in 0..<buf.count {
            buf[i] = sinf(Float(tonePhase)) * amp
            tonePhase += w
            if tonePhase > 2 * .pi { tonePhase -= 2 * .pi }
        }
        analyze(buf: buf)
    }

    // MARK: - Analysis (runs on analysisQueue)
    private func analyze(buf: [Float]) {
        var x = buf

        // First-hit probe (once)
        if !dbgAnalyzeFirstHitLogged {
            dbgAnalyzeFirstHitLogged = true
            self.log.debug("analyze: FIRST HIT")
        }
        dbgAnalyzeCount &+= 1
        if self.dbgAnalyzeCount % 50 == 0 {
            self.log.debug("analyze: frame #\(self.dbgAnalyzeCount, privacy: .public)")
        }

        // 1-pole HPF to remove DC/rumble (stable, cheap)
        var y = [Float](repeating: 0, count: x.count)
        var x1 = hpfX1, y1 = hpfY1, a = hpfA
        for i in 0..<x.count {
            let yi = x[i] - x1 + a * y1
            y[i] = yi
            x1 = x[i]; y1 = yi
        }
        hpfX1 = x1; hpfY1 = y1
        x = y

        // RMS (continuous)
        var rms: Float = 0
                        vDSP_rmsqv(x, 1, &rms, vDSP_Length(x.count))
                        dbgLastAnalyzeRMS = rms
        self.onMetrics?(rms)

        // Gate out true silence only (very low threshold)
        if !rms.isFinite || rms < 5e-8 {
            if dbgAnalyzeCount % 25 == 0 {
                self.log.debug("analyze: gated (rms=\(String(format: "%.8f", rms), privacy: .public))")
            }
            return
        }

        // TRY IN ORDER: YIN → (if tone enabled) toneHz → HPS
        var f0: Double?
        var source = "nil"

        if let yin = YIN.detect(samples: x, sampleRate: sampleRate) {
            f0 = yin
            source = "YIN"
        } else if useTestTone {
            f0 = toneState.get().hz
            source = "TONE"
        } else if let hps = HPSVerifier.estimate(samples: x, sampleRate: sampleRate) {
            f0 = hps
            source = "HPS"
        }

        // No f0 this frame — fine, keep going
        if f0 == nil {
            if dbgAnalyzeCount % 25 == 0 {
                self.log.debug("detect: no f0 (rms=\(String(format: "%.6f", self.dbgLastAnalyzeRMS), privacy: .public))")
            }
            return
        }

        let primary = f0!
        let smoothed = kalman.filter(z: primary)
        self.onHz?(smoothed, CACurrentMediaTime())

        // Debug: one line per emit
        dbgEmitCount &+= 1
        log.debug("emit[\(source, privacy: .public)] f0=\(String(format: "%.2f", smoothed), privacy: .public) Hz  rms=\(String(format: "%.4f", rms), privacy: .public)")
    }
}
