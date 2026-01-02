//
//  TinyTone.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  TinyTone.swift
//  VenueCalibrator
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import AVFAudio

/// Minimal, click-free tone generator for the App Clip.
/// Playback-only; no mic; safe ramping; live frequency updates.
final class TinyTone {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let session = AVAudioSession.sharedInstance()

    // State (atomic-ish via serial queue)
    private let q = DispatchQueue(label: "tenney.clip.tone")
    private var sampleRate: Double = 48000
    private var phase: Double = 0
    private var freq: Double = 440
    private var amp: Double = 0         // current linear amplitude
    private var targetAmp: Double = 0   // desired amplitude
    private var playing = false

    // Tunables
    private let maxAmp: Double = 0.3            // headroom (~-10 dBFS-ish perceived)
    private let attackSec: Double = 0.08
    private let releaseSec: Double = 0.06

    init() {
        configureSession()
        buildGraph()
    }

    private func configureSession() {
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }

    private func buildGraph() {
        let fmt = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = fmt.sampleRate

        source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            let twoPi = 2.0 * Double.pi

            // copy state locally
            var localPhase = self.phase
            var localFreq  = self.freq
            var localAmp   = self.amp
            let wantAmp    = self.targetAmp
            let sr         = self.sampleRate

            // per-sample linear ramp for amplitude (dezipper)
            let atkStep = (self.maxAmp / max(1.0, self.attackSec * sr))
            let relStep = (self.maxAmp / max(1.0, self.releaseSec * sr))

            for f in 0..<frames {
                // dezipper amp
                if wantAmp > localAmp {
                    localAmp = min(wantAmp, localAmp + atkStep)
                } else if wantAmp < localAmp {
                    localAmp = max(wantAmp, localAmp - relStep)
                }

                // folded sine: abs(sin), remapped to centered –1…+1
                let s = sin(twoPi * localPhase)
                let folded = (abs(s) * 2.0) - 1.0
                let sample = Float(localAmp * folded)

                // advance phase (wrap 0..1)
                localPhase += localFreq / sr
                if localPhase >= 1.0 { localPhase -= 1.0 }

                for buf in abl {
                    let ptr = buf.mData!.assumingMemoryBound(to: Float.self)
                    ptr[f] = sample
                }
            }

            // write-back
            self.phase = localPhase
            self.amp   = localAmp
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.outputNode, format: fmt)
    }

    // MARK: API

    func start() {
        if !engine.isRunning {
            try? engine.start()
        }
    }

    func setPlaying(_ on: Bool) {
        q.sync {
            self.targetAmp = on ? maxAmp : 0.0
            self.playing = on
        }
    }

    func setFrequency(_ hz: Double) {
        q.sync { self.freq = max(20.0, min(2000.0, hz)) }
    }
}
