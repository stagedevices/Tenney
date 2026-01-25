//
//  HejiRatioDisplay.swift
//  Tenney
//
//  Shared HEJI ratio label helper.
//

import Foundation
import SwiftUI

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
) -> AttributedString {
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
    return HejiNotation.textLabel(
        for: ratio,
        context: context,
        showCents: showCents,
        textStyle: .footnote,
        weight: .semibold,
        design: .default
    )
}
