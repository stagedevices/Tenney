//
//  HejiRatioDisplay.swift
//  Tenney
//
//  Shared HEJI ratio label helper.
//

import Foundation

func spellHejiRatioDisplay(
    ratio: RatioRef,
    tonic: TonicSpelling,
    rootHz: Double,
    noteNameA4Hz: Double,
    concertA4Hz: Double,
    accidentalPreference: AccidentalPreference,
    maxPrime: Int,
    allowApproximation: Bool,
    showCents: Bool = false,
    applyAccidentalPreference: Bool
) -> String {
    if ratio.p == 1 && ratio.q == 1 {
        return tonic.displayText
    }
    let preference = applyAccidentalPreference ? accidentalPreference : .auto
    let context = HejiContext(
        concertA4Hz: concertA4Hz,
        noteNameA4Hz: noteNameA4Hz,
        rootHz: rootHz,
        rootRatio: nil,
        preferred: preference,
        maxPrime: maxPrime,
        allowApproximation: allowApproximation,
        scaleDegreeHint: ratio,
        tonicE3: tonic.e3
    )
    let spelling = HejiNotation.spelling(forRatio: ratio, context: context)
    return String(HejiNotation.textLabel(spelling, showCents: showCents).characters)
}
