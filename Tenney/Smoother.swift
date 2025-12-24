//
//  PitchSmoother.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


import Foundation

public final class PitchSmoother {
    public struct Config {
        public var attackHz: Double = 35.0
        public var releaseHz: Double = 6.0
        public var hysteresisCents: Double = 10.0
        public var holdFrames: Int = 4
        public var confThresh: Double = 0.65
        public init() {}
    }

    private let cfg: Config
    private let sr: Double
    private let hop: Int

    private var lastHz: Double?
    private var lastNoteIndex: Int?
    private var stableCount: Int = 0
    private var recentHz: [Double] = []

    public init(sampleRate: Double, hop: Int, config: Config = .init()) {
        self.cfg = config
        self.sr = sampleRate
        self.hop = hop
    }

    public func push(hz: Double, conf: Double, mappedNoteIndex: Int?) -> (Double, Int?) {
        guard hz.isFinite, hz > 0 else { return (lastHz ?? hz, lastNoteIndex) }

        recentHz.append(hz); if recentHz.count > 3 { recentHz.removeFirst() }
        let median = recentHz.sorted()[recentHz.count/2]

        let dt = Double(hop) / sr
        if let prev = lastHz {
            let diff = median - prev
            let tau = diff >= 0 ? 1.0 / cfg.attackHz : 1.0 / cfg.releaseHz
            let a = 1.0 - exp(-dt / tau)
            lastHz = prev + a * diff
        } else {
            lastHz = median
        }

        if let idx = mappedNoteIndex {
            if let committed = lastNoteIndex {
                if idx == committed {
                    stableCount = min(1000, stableCount + 1)
                } else {
                    let centsErr = abs(centsBetween(hz: lastHz!, noteIndex: committed))
                    if centsErr > cfg.hysteresisCents, conf >= cfg.confThresh {
                        stableCount += 1
                        if stableCount >= cfg.holdFrames { lastNoteIndex = idx; stableCount = 0 }
                    } else {
                        stableCount = 0
                    }
                }
            } else if conf >= cfg.confThresh {
                stableCount += 1
                if stableCount >= cfg.holdFrames { lastNoteIndex = idx; stableCount = 0 }
            }
        }

        return (lastHz ?? hz, lastNoteIndex)
    }

    public func reset() {
        lastHz = nil; lastNoteIndex = nil; stableCount = 0; recentHz.removeAll()
    }

    private func centsBetween(hz: Double, noteIndex: Int) -> Double {
        let targetHz = 440.0 * pow(2.0, (Double(noteIndex) - 69.0)/12.0)
        return 1200.0 * log2(hz / targetHz)
    }
}
