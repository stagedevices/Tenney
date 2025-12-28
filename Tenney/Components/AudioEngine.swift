//  AudioEngine.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import Accelerate
import AVFoundation

final class AudioEngineService {
    private let engine = AVAudioEngine()
    private var isRunning = false
    private let hopFrames: AVAudioFrameCount = 256
    private var frontEnd: FrontEnd?
    private var routeObserver: NSObjectProtocol?
    private var frontEndSR: Double?
    private var tapInstalled = false
    private var didLogTapFormat = false

    func start(config: AudioIOConfig, callback: @escaping ([Float], Double) -> Void) {
        guard !isRunning else { return }
        // Ensure all AVAudioSession and engine mutations happen on the main thread.
                if !Thread.isMainThread {
                    DispatchQueue.main.sync { self.start(config: config, callback: callback) }
                    return
                }
#if os(iOS) || targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        // 1) Handle mic permission first
        switch session.recordPermission {
        case .undetermined:
            session.requestRecordPermission { _ in
                DispatchQueue.main.async { self.start(config: config, callback: callback) }
            }
            return
        case .denied:
            // Fall back to playback-only. Don’t touch input at all.
            do {
                let sr = config.preferredSampleRate ?? 48_000
                let frames: AVAudioFrameCount = {
                    if let f = config.bufferFrames, f > 0 { return AVAudioFrameCount(f) }
                    return hopFrames
                }()
                try session.setPreferredSampleRate(sr)
                try session.setPreferredIOBufferDuration(Double(frames) / sr)
            } catch { print("[AudioSession] playback-only error: \(error)") }
        case .granted:
            do {
                try session.setCategory(.playAndRecord,
                                        mode: .measurement,
                                        options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
                try session.setPreferredSampleRate(48_000)
                try session.setPreferredIOBufferDuration(Double(hopFrames) / 48_000.0)
                try session.setActive(true, options: [])
            } catch {
                print("[AudioSession] configure error: \(error)")
            }
        @unknown default:
            break
        }
        #endif


        // We DO NOT connect input → mixer (can crash on some routes/permissions).
                // If you need silent input stabilization, leave mainMixer alone; the tap is enough.
           let input = engine.inputNode
                let inFmt = input.outputFormat(forBus: 0)
        
        // Force tap to mono Float32, non-interleaved (AVAudioEngine will convert).
        let tapFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: inFmt.sampleRate,
                                   channels: 1,
                                   interleaved: false)
        
        // Install tap only if the format looks valid; otherwise wait for a route change.
                if tapInstalled { input.removeTap(onBus: 0); tapInstalled = false }
                if inFmt.sampleRate > 0.0 && inFmt.channelCount >= 1 {
                    input.installTap(onBus: 0, bufferSize: hopFrames, format: tapFmt) { [weak self] buffer, _ in
                        guard let self = self else { return }
                        guard let (mono, srBuf) = self.extractMono(from: buffer) else { return }

                        // Rebuild frontEnd if SR changed across routes.
                        if self.frontEnd == nil || self.frontEndSR != srBuf {
                            self.frontEnd = FrontEnd(sampleRate: srBuf)
                            self.frontEndSR = srBuf
                        }

                        if var feBuf = Optional(mono), let fe = self.frontEnd {
                            let metrics = fe.process(&feBuf)
                            if metrics.gated { return }
                            callback(feBuf, srBuf)
                        } else {
                            callback(mono, srBuf)
                    }
                                }
                                tapInstalled = true
                            } else {
                                print("[AudioEngine] input format invalid (sr=\(inFmt.sampleRate) ch=\(inFmt.channelCount)); will wait for route change.")
                            }
        
                do {
                    engine.prepare()
                    try engine.start()
                    isRunning = true
                } catch {
                    print("[AudioEngine] start error: \(error)")
                }
        
                // Reinstall tap on route changes (e.g., BT/Wired headset).
                routeObserver = NotificationCenter.default.addObserver(
                    forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    guard let self = self else { return }
                    if self.tapInstalled { self.engine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
                    let fmt = self.engine.inputNode.outputFormat(forBus: 0)
                    if fmt.sampleRate > 0.0 && fmt.channelCount >= 1 {
                        let tapFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                       sampleRate: fmt.sampleRate,
                                                       channels: 1,
                                                       interleaved: false)
                        self.engine.inputNode.installTap(onBus: 0, bufferSize: self.hopFrames, format: tapFmt) { [weak self] buffer, _ in
                            guard let self = self else { return }
                            let srBuf = buffer.format.sampleRate
                            let ch = Int(buffer.format.channelCount)
                            let n = Int(buffer.frameLength)
                            guard n > 0, let chans = buffer.floatChannelData else { return }
                            if self.frontEnd == nil || self.frontEndSR != srBuf {
                                self.frontEnd = FrontEnd(sampleRate: srBuf)
                                self.frontEndSR = srBuf
                            }
                            var mono = [Float](repeating: 0, count: n)
                            if ch == 1 {
                                mono.withUnsafeMutableBufferPointer { $0.baseAddress!.assign(from: chans[0], count: n) }
                            } else {
                                for c in 0..<ch { vDSP_vadd(chans[c], 1, mono, 1, &mono, 1, vDSP_Length(n)) }
                                var scale = Float(1.0 / Float(ch))
                                vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(n))
                            }
                            if var feBuf = Optional(mono), let fe = self.frontEnd {
                                let m = fe.process(&feBuf); if m.gated { return }
                                callback(feBuf, srBuf)
                            } else {
                                callback(mono, srBuf)
                            }
                        }
                        self.tapInstalled = true
                    } else {
                        print("[AudioEngine] route change, invalid input fmt; tap deferred (sr=\(fmt.sampleRate) ch=\(fmt.channelCount))")
                    }
                }
    }
    
    private func extractMono(from buffer: AVAudioPCMBuffer) -> (mono: [Float], sr: Double)? {
        let fmt = buffer.format
        let sr = fmt.sampleRate
        let ch = Int(fmt.channelCount)
        let n  = Int(buffer.frameLength)
        guard n > 0 else { return nil }

        if !didLogTapFormat {
            didLogTapFormat = true
            print("[AudioEngineService] tap fmt sr=\(sr) ch=\(ch) interleaved=\(fmt.isInterleaved) common=\(fmt.commonFormat)")
        }

        guard let chans = buffer.floatChannelData else { return nil }

        if fmt.isInterleaved {
            // interleaved: chans[0] is [L0,R0,L1,R1,...]
            let inter = chans[0]
            if ch <= 1 {
                return (Array(UnsafeBufferPointer(start: inter, count: n)), sr)
            }
            var mono = [Float](repeating: 0, count: n)
            for i in 0..<n {
                var acc: Float = 0
                let base = i * ch
                for c in 0..<ch { acc += inter[base + c] }
                mono[i] = acc / Float(ch)
            }
            return (mono, sr)
        } else {
            // planar: chans[c] is per-channel
            var mono = [Float](repeating: 0, count: n)
            if ch == 1 {
                mono.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress!.assign(from: chans[0], count: n)
                }
            } else {
                for c in 0..<ch { vDSP_vadd(chans[c], 1, mono, 1, &mono, 1, vDSP_Length(n)) }
                var scale = Float(1.0 / Float(ch))
                vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(n))
            }
            return (mono, sr)
        }
    }


    func stop() { stop(deactivateSession: true) }
    func stop(deactivateSession: Bool) {
        // Always safe to call; idempotent.
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.stop(deactivateSession: deactivateSession) }
            return
        }

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.disconnectNodeInput(engine.mainMixerNode)
        if engine.isRunning { engine.stop() }

    #if os(iOS) || targetEnvironment(macCatalyst)
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    #endif

        if let obs = routeObserver { NotificationCenter.default.removeObserver(obs) }
        routeObserver = nil
        isRunning = false
    }

}

