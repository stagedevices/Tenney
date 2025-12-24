//
//  DigitalPLL.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


import Foundation

public final class DigitalPLL {
    public struct Config {
        public var kp: Double = 0.015
        public var ki: Double = 0.0008
        public var maxStepHz: Double = 80.0
        public init() {}
    }

    private let sr: Double
    private let hop: Int
    private let cfg: Config

    private var freq: Double = 0
    private var integ: Double = 0

    public init(sampleRate: Double, hop: Int, config: Config = .init()) {
        self.sr = sampleRate
        self.hop = hop
        self.cfg = config
    }

    public func reset(to hz: Double) {
        freq = hz
        integ = 0
    }

    public func update(measuredHz: Double, confidence: Double) -> Double {
        guard measuredHz.isFinite, measuredHz > 0 else { return freq }
        let dt = Double(hop) / sr

        let err = measuredHz - freq
        let step = max(-cfg.maxStepHz, min(cfg.maxStepHz, err)) * max(0.0, min(1.0, confidence))

        // PI
        integ += cfg.ki * step * dt
        let corr = cfg.kp * step + integ

        freq = max(0, freq + corr)
        return freq
    }

    public var currentFrequency: Double { max(0, freq) }
}
