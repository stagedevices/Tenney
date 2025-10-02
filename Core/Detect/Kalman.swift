//
//  Kalman.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Simple 1D scalar Kalman filter for frequency smoothing
final class Kalman1D {
    private var x: Double = 0         // state (Hz)
    private var p: Double = 1         // covariance
    private var q: Double             // process noise
    private var r: Double             // measurement noise
    private var initialised = false

    init(q: Double, r: Double) {
        self.q = q
        self.r = r
    }

    func configure(q: Double, r: Double) {
        self.q = q; self.r = r
    }

    func reset() {
        initialised = false
        x = 0; p = 1
    }

    func filter(z: Double) -> Double {
        if !initialised {
            x = z; p = 1; initialised = true
            return z
        }
        // predict
        let xPred = x
        let pPred = p + q

        // update
        let k = pPred / (pPred + r)
        x = xPred + k * (z - xPred)
        p = (1 - k) * pPred
        return x
    }
}
