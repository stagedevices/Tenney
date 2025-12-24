//
//  TunerDisplay.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//
//  View-model types for the tuner readout + shared enums.

import Foundation

struct TunerDisplay: Equatable {
    var ratioText: String
    var cents: Double
    var hz: Double
    var confidence: Double
    var lowerText: String
    var higherText: String

    static let empty = TunerDisplay(
        ratioText: "—",
        cents: 0,
        hz: 0,
        confidence: 0,
        lowerText: "",
        higherText: ""
    )

    static func noInput(rootHz: Double) -> TunerDisplay {
        TunerDisplay(
            ratioText: "—",
            cents: 0,
            hz: rootHz,
            confidence: 0,
            lowerText: "",
            higherText: ""
        )
    }
}

enum InstrumentProfile: String, CaseIterable, Identifiable {
    case harpsichord
    case strings
    case microtonal
    var id: String { rawValue }
}

enum MicPermissionState: String {
    case unknown
    case denied
    case granted
}

// MARK: - Utilities

/// Signed cents offset of `actualHz` vs a target ratio (including octave) against `rootHz`.
func signedCents(actualHz: Double, rootHz: Double, target: RatioResult) -> Double {
    let targetHz = rootHz * pow(2.0, Double(target.octave)) * (Double(target.num) / Double(target.den))
    return 1200.0 * log2(actualHz / targetHz)
}
