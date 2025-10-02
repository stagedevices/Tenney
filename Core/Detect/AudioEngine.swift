//
//  AudioEngine.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import AVFoundation

/// Sprint-0: session + engine scaffold; no DSP yet.
final class AudioEngineManager {
    private let engine = AVAudioEngine()

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .allowBluetoothA2DP])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(128.0 / 48_000.0)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let bus = 0
        let format = input.outputFormat(forBus: bus)

        input.installTap(onBus: bus, bufferSize: 512, format: format) { _, _ in
            // Sprint-1: feed Detect pipeline (YIN/MPM + Kalman)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
