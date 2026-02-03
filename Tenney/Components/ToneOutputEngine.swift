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
    


    func installScopeTap(_ cb: @escaping ([Float], Double) -> Void) {
        phaseScopeTap = cb
        installTapIfNeeded()
    }

    func removeScopeTap() {
        phaseScopeTap = nil
        // optional: remove tap if you want; leaving it installed is fine if guarded by phaseScopeTap != nil
    }

    private func publishScopeSamples(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let phaseScopeTap else { return }
        guard let ch0 = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        phaseScopeTap(Array(UnsafeBufferPointer(start: ch0, count: n)), sampleRate)
    }

    
// MARK: - Phase Scope contract
    
    

    private func installTapIfNeeded() {
        guard !phaseScopeTapInstalled else { return }
        phaseScopeTapInstalled = true


        //  Install exactly once on the node that contains the synth render.
        // Prefer: your synth source/mixer node. Acceptable: your main mixer.
        let tapNode: AVAudioNode = /* TODO: replace with your synth mixer/source if you have it */ engine.mainMixerNode
        let format = tapNode.outputFormat(forBus: 0)

        tapNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let self else { return }
            self.publishScopeSamples(buf, sampleRate: format.sampleRate)
        }
    }

        
            func setEnabled(_ on: Bool) {
                // route to existing enable/disable
                // e.g. masterGain = on ? 1 : 0
            }
    private let scopeStateLock = NSLock()
    private var scopeMode: ScopeMode = .liveActiveSignals([])
    private var scopePendingFadeSamples: Int = 0

    private var scopePrevAssign: ([Int],[Int]) = ([],[])  // (xIDs, yIDs)
    private var scopeNextAssign: ([Int],[Int]) = ([],[])
    private var scopeIdlePhase: Double = 0
    
    private var scopeEpoch: UInt32 = 0
    private var scopeEpochRT: UInt32 = 0

    private var scopeX: [Float] = []
    private var scopeY: [Float] = []

    // MARK: Singleton
    static let shared = ToneOutputEngine()
    // ===== Phase Scope contract =====
    private var phaseScopeTap: (([Float], Double) -> Void)? = nil
    private var phaseScopeTapInstalled: Bool = false

    private init() {
            loadPersistedConfigIfPresent()
        }
    // MARK: Public config (global, affects all voices)
    enum GlobalWave: String, CaseIterable, Codable { case foldedSine, triangle, saw }
    struct Config: Codable, Equatable {
        var wave: GlobalWave = .foldedSine                // (1) folded sine (Buchla-style mirror folds)
        var foldAmount: Float = 1.25                      // folds, ~0.0 … 5.0
        var drive_dB: Float = 6.0                         // pre-gain into folder, dB
        var attackMs: Double = 120000.0                        // global AR
        var releaseMs: Double = 120000.0
        var outputGain_dB: Float = -6.0                   // final gain before soft limiter
        var limiterOn: Bool = true                        // soft clip safety
    }
    
    // MARK: - SafeAmp → output gain mapping (dBFS below ~0 dB ceiling)

    /// Canonical mapping from safeAmp detents into output gain in dBFS.
    /// Values are relative to a nominal 0 dBFS limiter ceiling.
    /// Safe   = 0.12 → ~ -18 dBFS
    /// Normal = 0.18 → ~ -14 dBFS
    /// Loud   = 0.24 → ~ -10 dBFS
    /// Hot    = 0.30 → ~  -6 dBFS
    /// Max    = 0.36 → ~  -3 dBFS
    static func outputGain(forSafeAmp safeAmp: Double) -> Float {
        let table: [(Double, Float)] = [
            (0.12, -18.0),
            (0.18, -14.0),
            (0.24, -10.0),
            (0.30,  -6.0),
            (0.36,  -3.0)
        ]

        guard let first = table.first, let last = table.last else {
            return -14.0
        }

        let v = max(first.0, min(last.0, safeAmp))

        if v <= first.0 { return first.1 }
        if v >= last.0  { return last.1  }

        for i in 0..<(table.count - 1) {
            let (v0, d0) = table[i]
            let (v1, d1) = table[i + 1]
            if v >= v0 && v <= v1 {
                let t = Float((v - v0) / (v1 - v0))
                return d0 + (d1 - d0) * t
            }
        }

        return -14.0
    }

    private func releaseAll(excluding owners: Set<VoiceOwner>, seconds: Double) {
            let ids = metaAll().compactMap { (id, m) -> VoiceID? in
                owners.contains(m.owner) ? nil : id
            }
            for id in ids { release(id: id, seconds: seconds) }
        }
    
        private func releaseAll(owner: VoiceOwner, seconds: Double) {
            let ids = metaAll().compactMap { (id, m) -> VoiceID? in
                (m.owner == owner) ? id : nil
           }
           for id in ids { release(id: id, seconds: seconds) }
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
    
    enum VoiceOwner: String, Codable { case lattice, builder, testTone, other }

    struct VoiceSnapshot: Hashable {
        let freq: Double
        let amp: Float
        let owner: VoiceOwner
        let ownerKey: String
    }

    private struct VoiceMeta {
        var freq: Double
        var amp: Float
        var owner: VoiceOwner
        var ownerKey: String
    }

    private var metaLock = os_unfair_lock_s()
    private var metaByID: [VoiceID: VoiceMeta] = [:]

    private var ownerLock = os_unfair_lock_s()
    private var activeVoicesByOwner: [String: VoiceID] = [:]

    // Builder suspend stash (what we restore on dismiss)
    private var builderSuspended: [VoiceSnapshot] = []

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
        let id = sustain(freq: frequency, amp: 0.18, owner: .testTone, attackMs: 8, releaseMs: 40)

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
            testToneID = sustain(freq: f, amp: 0.18, owner: .testTone, attackMs: 8, releaseMs: 40)

        }
    }

    /// Low-level voice control
    @discardableResult
    func sustain(freq: Double, amp: Float, callsite: StaticString = #fileID, line: Int = #line) -> VoiceID {
        sustain(freq: freq, amp: amp, owner: .other, ownerKey: nil, attackMs: nil, releaseMs: nil, callsite: callsite, line: line)
    }
    @discardableResult
    func sustain(
        freq: Double,
        amp: Float,
        owner: VoiceOwner,
        ownerKey: String? = nil,
        attackMs: Double?,
        releaseMs: Double?,
        callsite: StaticString = #fileID,
        line: Int = #line
    ) -> VoiceID {
        if !isRunning { startEngineIfNeeded() }

        let resolvedOwnerKey = ownerKey ?? owner.rawValue
        if let existingID = ownerVoiceID(for: resolvedOwnerKey) {
            retune(id: existingID, to: freq, hardSync: false)
            metaSet(existingID, VoiceMeta(freq: freq, amp: amp, owner: owner, ownerKey: resolvedOwnerKey))
#if DEBUG
            logVoiceEvent(
                "UPDATE",
                ownerKey: resolvedOwnerKey,
                freq: freq,
                attackMs: attackMs ?? config.attackMs,
                releaseMs: releaseMs ?? config.releaseMs,
                callsite: callsite,
                line: line
            )
#endif
            return existingID
        }

        let id = nextID; nextID &+= 1
        let cfg = config
        let sr = sampleRate

        let aMs = attackMs ?? cfg.attackMs
        let rMs = releaseMs ?? cfg.releaseMs

        let a = max(1, Int((aMs / 1000.0) * sr))
        let r = max(1, Int((rMs / 1000.0) * sr))

        enqueue(.sustain(id: id, freq: Float(freq), amp: amp, attackSamps: a, releaseSamps: r))
        metaSet(id, VoiceMeta(freq: freq, amp: amp, owner: owner, ownerKey: resolvedOwnerKey))
        setOwnerVoiceID(id, for: resolvedOwnerKey)
#if DEBUG
        logVoiceEvent(
            "START",
            ownerKey: resolvedOwnerKey,
            freq: freq,
            attackMs: aMs,
            releaseMs: rMs,
            callsite: callsite,
            line: line
        )
#endif
        return id
    }
    
    func snapshotActiveVoices(excluding owners: Set<VoiceOwner> = []) -> [VoiceSnapshot] {
        metaAll()
            .filter { !owners.contains($0.1.owner) }
            .map { (_, m) in VoiceSnapshot(freq: m.freq, amp: m.amp, owner: m.owner, ownerKey: m.ownerKey) }
    }

    var isEngineRunning: Bool { isRunning }

    func activeVoiceCount() -> Int {
        metaAll().count
    }

    func fadeOutAllVoices(releaseSeconds: Double) {
        let ids = metaAll().map { $0.0 }
        for id in ids {
            release(id: id, seconds: releaseSeconds)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseSeconds) { [weak self] in
            self?.stopAll()
        }
    }

    func hardStopEngine(deactivateSession: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { hardStopEngine(deactivateSession: deactivateSession) }
            return
        }

        if engine.isRunning { engine.stop() }
        engine.reset()

        if let sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
        phaseScopeTapInstalled = false

        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil

        os_unfair_lock_lock(&cmdLock)
        pendingCmds.removeAll(keepingCapacity: true)
        processingCmds.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&cmdLock)

        os_unfair_lock_lock(&metaLock)
        metaByID.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&metaLock)
        clearAllOwnerVoices()

        for i in voices.indices {
            voices[i].active = false
            voices[i].env = 0
            voices[i].envState = 0
        }

        testToneID = nil
        firstRenderLogged = false
        isRunning = false

#if os(iOS) || targetEnvironment(macCatalyst)
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
#endif
    }

    /// Called when Builder sheet appears.
    /// Fades out anything currently playing (typically lattice + maybe test tone),
    /// but does NOT touch the AVAudioSession.
    func builderWillPresent() {
        releaseAll(excluding: [.builder], seconds: 0.02)
    }

    /// Called when Builder sheet dismisses.
    /// Fades out builder pad voices, then restores the pre-builder snapshot.
    func builderDidDismiss() {
        releaseAll(owner: .builder, seconds: 0.04)
    }



    func retune(id: VoiceID, to freq: Double, hardSync: Bool = false, callsite: StaticString = #fileID, line: Int = #line) {
        enqueue(.retune(id: id, freq: Float(freq), hardSync: hardSync))
        if let m = metaAll().first(where: { $0.0 == id })?.1 {
            metaSet(id, VoiceMeta(freq: freq, amp: m.amp, owner: m.owner, ownerKey: m.ownerKey))
        }

    }

    func release(id: VoiceID, seconds: Double, callsite: StaticString = #fileID, line: Int = #line) {
        let rs = max(0.0, seconds)
        let samps = max(1, Int(rs * sampleRate))
        enqueue(.release(id: id, releaseSamps: samps))
#if DEBUG
        let releaseMs = rs * 1000.0
        if let meta = metaGet(id) {
            logVoiceEvent(
                "STOP",
                ownerKey: meta.ownerKey,
                freq: meta.freq,
                attackMs: nil,
                releaseMs: releaseMs,
                callsite: callsite,
                line: line
            )
        } else {
            logVoiceEvent(
                "STOP",
                ownerKey: "unknown",
                freq: nil,
                attackMs: nil,
                releaseMs: releaseMs,
                callsite: callsite,
                line: line
            )
        }
#endif
        
    }

    func stop(ownerKey: String, releaseSeconds: Double = 0.0, callsite: StaticString = #fileID, line: Int = #line) {
        guard let id = ownerVoiceID(for: ownerKey) else { return }
        release(id: id, seconds: releaseSeconds, callsite: callsite, line: line)
        clearOwnerVoiceID(for: ownerKey)
        metaRemove(id)
    }

    func stopAll(callsite: StaticString = #fileID, line: Int = #line) {
#if DEBUG
        for (_, meta) in metaAll() {
            logVoiceEvent(
                "STOP",
                ownerKey: meta.ownerKey,
                freq: meta.freq,
                attackMs: nil,
                releaseMs: 0,
                callsite: callsite,
                line: line
            )
        }
#endif
        enqueue(.stopAll)
        os_unfair_lock_lock(&metaLock)
        metaByID.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&metaLock)
        clearAllOwnerVoices()

        testToneID = nil
    }
    
    // MARK: - Live XY scope routing (pads/voices -> X/Y)
    private func scopeAssign(from ordered: [ScopeSignal]) -> ([Int],[Int]) {
        let ids = ordered.map(\.voiceID)

        switch ids.count {
        case 0:
            return ([], [])
        case 1:
            // keep contract: x == y for a single source
            return ([ids[0]], [ids[0]])
        default:
            // interleave: positions 0,2,4,... -> X ; positions 1,3,5,... -> Y
            var x: [Int] = []
            var y: [Int] = []
            x.reserveCapacity((ids.count + 1) / 2)
            y.reserveCapacity(ids.count / 2)

            for (i, id) in ids.enumerated() {
                if (i & 1) == 0 { x.append(id) } else { y.append(id) }
            }
            return (x, y)
        }
    }


    public struct ScopeSignal: Hashable {
        public let voiceID: Int
        public let label: String   // e.g. "Pad 3" (UI uses this)
        public init(voiceID: Int, label: String) { self.voiceID = voiceID; self.label = label }
    }

    public enum ScopeMode: Equatable {
        case liveActiveSignals([ScopeSignal])   // ordered, stable
        case syntheticRatios                    // existing lissajous closure path (optional)
    }

    public func setScopeMode(_ mode: ScopeMode) {
        scopeStateLock.lock()
        scopeMode = mode
        scopePendingFadeSamples = Int(sampleRate * 0.20) // ~200ms crossfade
        scopeEpoch &+= 1
        scopeStateLock.unlock()
    }


    // MARK: Optional: stereo scope tap (not audible)
    // Called once per render with two read-only buffers for X/Y display (length = frames).
    // Hardware output remains MONO.
    var xyScopeTap: ((_ x: UnsafePointer<Float>, _ y: UnsafePointer<Float>, _ count: Int) -> Void)?

    
    @inline(__always) private func metaSet(_ id: VoiceID, _ m: VoiceMeta) {
        os_unfair_lock_lock(&metaLock); metaByID[id] = m; os_unfair_lock_unlock(&metaLock)
    }
    @inline(__always) private func metaRemove(_ id: VoiceID) {
        os_unfair_lock_lock(&metaLock); metaByID.removeValue(forKey: id); os_unfair_lock_unlock(&metaLock)
    }
    @inline(__always) private func metaGet(_ id: VoiceID) -> VoiceMeta? {
        os_unfair_lock_lock(&metaLock); defer { os_unfair_lock_unlock(&metaLock) }
        return metaByID[id]
    }
    @inline(__always) private func metaAll() -> [(VoiceID, VoiceMeta)] {
        os_unfair_lock_lock(&metaLock); defer { os_unfair_lock_unlock(&metaLock) }
        return Array(metaByID)
    }

    @inline(__always) private func ownerVoiceID(for ownerKey: String) -> VoiceID? {
        os_unfair_lock_lock(&ownerLock); defer { os_unfair_lock_unlock(&ownerLock) }
        return activeVoicesByOwner[ownerKey]
    }

    @inline(__always) private func setOwnerVoiceID(_ id: VoiceID, for ownerKey: String) {
        os_unfair_lock_lock(&ownerLock); activeVoicesByOwner[ownerKey] = id; os_unfair_lock_unlock(&ownerLock)
    }

    @inline(__always) private func clearOwnerVoiceID(for ownerKey: String) {
        os_unfair_lock_lock(&ownerLock); activeVoicesByOwner.removeValue(forKey: ownerKey); os_unfair_lock_unlock(&ownerLock)
    }

    @inline(__always) private func clearAllOwnerVoices() {
        os_unfair_lock_lock(&ownerLock); activeVoicesByOwner.removeAll(keepingCapacity: true); os_unfair_lock_unlock(&ownerLock)
    }

#if DEBUG
    private func logVoiceEvent(
        _ kind: String,
        ownerKey: String,
        freq: Double?,
        attackMs: Double?,
        releaseMs: Double?,
        callsite: StaticString,
        line: Int
    ) {
        let ts = String(format: "%.3f", Date().timeIntervalSince1970)
        let freqStr = freq.map { String(format: "%.2f", $0) } ?? "n/a"
        let attackStr = attackMs.map { String(format: "%.1f", $0) } ?? "n/a"
        let releaseStr = releaseMs.map { String(format: "%.1f", $0) } ?? "n/a"
        print("[ToneOutput] \(kind) owner=\(ownerKey) freq=\(freqStr) attackMs=\(attackStr) releaseMs=\(releaseStr) ts=\(ts) from=\(callsite):\(line)")
    }
#endif

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
        
        var scopePhase: Float = 0
        var scopePhaseInc: Float = 440/48_000

        // envelope
        var gain: Float = 0.18
        var env: Float = 0
        var envState: Int = 0                // +1 A, 0 hold, -1 R
        var attackSamps: Int = 480
        var releaseSamps: Int = 4800

        mutating func setFreq(_ f: Float) {
            freq = max(0, f)
            phaseInc = freq / sr
            scopePhaseInc = freq / sr
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
    @inline(__always)
    private func frequencyForVoiceID(_ id: Int) -> Float {
        for v in voices where v.active && v.id == id { return v.freq }
        return 0
    }

    @inline(__always)
    private func fastSoftClip(_ x: Float) -> Float {
        // Cheap symmetric soft clip (cubic), then hard clamp
        // y = x - x^3/3 for |x|<=1
        var y = x
        if y > 1 { y = 1 }
        if y < -1 { y = -1 }
        return y - (y * y * y) * (1.0 / 3.0)
    }

    // MARK: Engine boot (mono out; robust session/route handling)
    private func startEngineIfNeeded() {
#if os(iOS) || targetEnvironment(macCatalyst)
try? AVAudioSession.sharedInstance().setActive(true, options: [])
#endif
        guard !isRunning else { return }

        // Use hardware format
        let out = engine.outputNode
        let hwFmt = out.inputFormat(forBus: 0) // what output node expects from mixer
        sampleRate = hwFmt.sampleRate > 0 ? hwFmt.sampleRate : 48_000
        let srF = Float(sampleRate)
        for i in voices.indices {
            voices[i].sr = srF
            voices[i].phaseInc = voices[i].freq / srF
            voices[i].scopePhaseInc = voices[i].freq / srF
        }

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
                            self.voices[i].scopePhaseInc = self.voices[i].freq / srF

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
                        v.sr = self.voices[slot].sr
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

            var R: UnsafeMutablePointer<Float>? = nil
            if abl.count >= 2 {
                R = abl[1].mData?.assumingMemoryBound(to: Float.self)
            }

            if self.scopeX.count < n {
                self.scopeX = [Float](repeating: 0, count: n)
                self.scopeY = [Float](repeating: 0, count: n)
            }

            if !self.firstRenderLogged {
                self.firstRenderLogged = true
                print("[ToneOutput] render pull: frames=\(n) ch=\(abl.count) sr=\(Int(self.sampleRate))")
            }

            // Fast idle: silence + blank scope
            if self.voices.allSatisfy({ !$0.active }) {
                vDSP_vclr(L, 1, vDSP_Length(n))
                if let R { vDSP_vclr(R, 1, vDSP_Length(n)) }

                self.scopeX.withUnsafeMutableBufferPointer { xb in
                    vDSP_vclr(xb.baseAddress!, 1, vDSP_Length(n))
                }
                self.scopeY.withUnsafeMutableBufferPointer { yb in
                    vDSP_vclr(yb.baseAddress!, 1, vDSP_Length(n))
                }

                if let tap = self.xyScopeTap {
                    self.scopeX.withUnsafeBufferPointer { x in
                        self.scopeY.withUnsafeBufferPointer { y in
                            tap(x.baseAddress!, y.baseAddress!, n)
                        }
                    }
                }

                return noErr
            }

            // Globals
            let cfg = self.config
            let outGain = powf(10.0, cfg.outputGain_dB / 20.0)
            let drive  = powf(10.0, cfg.drive_dB / 20.0)
            let foldA  = max(0.0, cfg.foldAmount)

            let fadeTotal = max(1, Int(self.sampleRate * 0.20))

            var localMode: ScopeMode
            var fadeLeft: Int
            var prevAssign: ([Int],[Int])
            var nextAssign: ([Int],[Int])
            var epoch: UInt32

            self.scopeStateLock.lock()
            localMode  = self.scopeMode
            fadeLeft   = self.scopePendingFadeSamples
            prevAssign = self.scopePrevAssign
            nextAssign = self.scopeNextAssign
            epoch      = self.scopeEpoch
            self.scopeStateLock.unlock()

            @inline(__always) func containsID(_ ids: [Int], _ id: Int) -> Bool {
                for x in ids { if x == id { return true } }
                return false
            }

            if fadeLeft > 0, case .liveActiveSignals(let sigs) = localMode {
                let next = self.scopeAssign(from: sigs)
                if nextAssign.0 != next.0 || nextAssign.1 != next.1 {
                    prevAssign = nextAssign
                    nextAssign = next
                }
            }

            
            if epoch != self.scopeEpochRT {
                self.scopeEpochRT = epoch
                self.scopeIdlePhase = 0

                for i in self.voices.indices {
                    if !self.voices[i].active { continue }
                    let id = self.voices[i].id
                    if containsID(prevAssign.0, id) ||
                        containsID(prevAssign.1, id) ||
                        containsID(nextAssign.0, id) ||
                        containsID(nextAssign.1, id) {
                        self.voices[i].scopePhase = 0
                    }
                }
            }

            for s in 0..<n {
                var mix: Float = 0

                var xA: Float = 0, yA: Float = 0, xB: Float = 0, yB: Float = 0
                var xAC = 0, yAC = 0, xBC = 0, yBC = 0

                for i in self.voices.indices {
                    if !self.voices[i].active { continue }
                    var v = self.voices[i]

                    // AR env
                    let aInc: Float = (v.attackSamps > 0) ? 1.0 / Float(v.attackSamps)  : 1.0
                    let rDec: Float = (v.releaseSamps > 0) ? 1.0 / Float(v.releaseSamps) : 1.0
                    switch v.envState {
                    case +1:
                        v.env += aInc
                        if v.env >= 1 { v.env = 1; v.envState = 0 }
                    case -1:
                        v.env -= rDec
                        if v.env <= 0 {
                            v.env = 0
                            v.active = false
                            self.voices[i] = v
                            continue
                        }
                    default:
                        break
                    }

                    // Oscillator
                    var y: Float = 0
                    switch cfg.wave {
                    case .foldedSine:
                        let raw = sinf(2.0 * Float.pi * v.phase) * drive
                        y = self.mirrorFold(raw, folds: foldA)
                    case .triangle:
                        y = self.triBLAMP(phase: v.phase, dphi: v.phaseInc)
                    case .saw:
                        y = self.sawBLEP(phase: v.phase, dphi: v.phaseInc)
                    }

                    // Advance phase
                    var ph = v.phase + v.phaseInc
                    if ph >= 1 { ph -= 1 }
                    v.phase = ph

                    let samp = y * v.gain * v.env
                    mix += samp

                    // Deterministic scope signal (independent of audio oscillator phase)
                    let scopeWave = sinf(2.0 * Float.pi * v.scopePhase)
                    var sph = v.scopePhase + v.scopePhaseInc
                    if sph >= 1 { sph -= 1 }
                    v.scopePhase = sph
                    let scopeSamp = scopeWave * v.gain * v.env

                    if containsID(prevAssign.0, v.id) { xA += scopeSamp; xAC += 1 }
                    if containsID(prevAssign.1, v.id) { yA += scopeSamp; yAC += 1 }
                    if containsID(nextAssign.0, v.id) { xB += scopeSamp; xBC += 1 }
                    if containsID(nextAssign.1, v.id) { yB += scopeSamp; yBC += 1 }

                    self.voices[i] = v
                }

                if xAC > 0 { xA *= (1.0 / Float(xAC)) }
                if yAC > 0 { yA *= (1.0 / Float(yAC)) }
                if xBC > 0 { xB *= (1.0 / Float(xBC)) }
                if yBC > 0 { yB *= (1.0 / Float(yBC)) }

                let t: Float = (fadeLeft > 0) ? (1.0 - Float(fadeLeft) / Float(fadeTotal)) : 1.0
                var xForScope = xA + (xB - xA) * t
                var yForScope = yA + (yB - yA) * t

                // 0 pads idle trace
                if case .liveActiveSignals(let sigs) = localMode, sigs.isEmpty {
                    let amp: Double = 0.06
                    self.scopeIdlePhase += (2.0 * Double.pi) * (0.35 / Double(self.sampleRate))
                    if self.scopeIdlePhase > 2.0 * Double.pi { self.scopeIdlePhase -= 2.0 * Double.pi }
                    xForScope = Float(amp * sin(self.scopeIdlePhase))
                    yForScope = Float(amp * cos(self.scopeIdlePhase))
                }

                // 1 pad circle mode
                if case .liveActiveSignals(let sigs) = localMode, sigs.count == 1 {
                    let f = self.frequencyForVoiceID(sigs[0].voiceID)
                    self.scopeIdlePhase += (2.0 * Double.pi) * (Double(f) / Double(self.sampleRate))
                    if self.scopeIdlePhase > 2.0 * Double.pi { self.scopeIdlePhase -= 2.0 * Double.pi }
                    let amp: Double = 0.85
                    xForScope = Float(amp * sin(self.scopeIdlePhase))
                    yForScope = Float(amp * cos(self.scopeIdlePhase))
                }

                xForScope = self.fastSoftClip(xForScope)
                yForScope = self.fastSoftClip(yForScope)
                self.scopeX[s] = xForScope
                self.scopeY[s] = yForScope

                let outSample = mix * outGain
                let outClipped = cfg.limiterOn ? self.fastSoftClip(outSample) : outSample
                L[s] = outClipped
                if let R { R[s] = outClipped }

                if fadeLeft > 0 { fadeLeft -= 1 }
            }

            self.scopeStateLock.lock()
            self.scopePendingFadeSamples = fadeLeft
            self.scopePrevAssign = prevAssign
            self.scopeNextAssign = nextAssign
            self.scopeStateLock.unlock()

            if let tap = self.xyScopeTap {
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
#if os(iOS) || targetEnvironment(macCatalyst)
            token = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in self?.handleRouteChange() }
#endif
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
