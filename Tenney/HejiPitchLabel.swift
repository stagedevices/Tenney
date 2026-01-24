//
//  HejiPitchLabel.swift
//  Tenney
//

import SwiftUI

enum HejiPitchSource: Hashable {
    case ratio(RatioRef)
    case frequency(Double)
}

struct HejiPitchLabel: View {
    let context: HejiContext
    let pitch: HejiPitchSource
    var modeOverride: HejiNotationMode? = nil
    var showCentsWhenApproximate: Bool = true

    @AppStorage(SettingsKeys.infoCardNotationMode) private var notationModeRaw: String = HejiNotationMode.staff.rawValue

    private var mode: HejiNotationMode {
        if let override = modeOverride { return override }
        return HejiNotationMode(rawValue: notationModeRaw) ?? .staff
    }

    private var spelling: HejiSpelling {
        switch pitch {
        case .ratio(let ratio):
            return HejiNotation.spelling(forRatio: ratio, context: context)
        case .frequency(let hz):
            return HejiNotation.spelling(forFrequency: hz, context: context)
        }
    }

    private var ratioSpelling: HejiRatioSpelling? {
        guard case .ratio(let ratio) = pitch else { return nil }
        let pref = context.preferred
        let anchor = resolveRootAnchor(rootHz: context.rootHz, a4Hz: context.noteNameA4Hz, preference: pref)
        let ratioContext = PitchContext(
            a4Hz: context.noteNameA4Hz,
            rootHz: context.rootHz,
            rootAnchor: anchor,
            accidentalPreference: pref,
            maxPrime: context.maxPrime
        )
        let (adjP, adjQ) = applyOctaveToPQ(p: ratio.p, q: ratio.q, octave: ratio.octave)
        return spellRatio(p: adjP, q: adjQ, context: ratioContext)
    }

    private var ratioTextLabel: String? {
        guard case .ratio(let ratio) = pitch else { return nil }
        guard let tonicE3 = context.tonicE3 else { return ratioSpelling?.labelText }
        let tonic = TonicSpelling(e3: tonicE3)
        return spellHejiRatioDisplay(
            ratio: ratio,
            tonic: tonic,
            rootHz: context.rootHz,
            noteNameA4Hz: context.noteNameA4Hz,
            concertA4Hz: context.concertA4Hz,
            accidentalPreference: context.preferred,
            maxPrime: context.maxPrime,
            allowApproximation: context.allowApproximation,
            showCents: showCentsWhenApproximate,
            applyAccidentalPreference: true
        )
    }

    var body: some View {
        let unsupported = ratioSpelling?.unsupportedPrimes ?? spelling.unsupportedPrimes
        VStack(spacing: mode == .combined ? 4 : 0) {
            if mode == .staff || mode == .combined {
                let layout = HejiNotation.staffLayout(spelling, context: context)
                HejiStaffSnippetView(layout: layout)
                    .accessibilityHidden(true)
            }

            if mode == .text || mode == .combined {
                if let ratioTextLabel {
                    Text(ratioTextLabel)
                        .font(.headline.monospaced())
                } else {
                    Text(HejiNotation.textLabel(spelling, showCents: showCentsWhenApproximate))
                        .font(.headline.monospaced())
                }
            }

            if !unsupported.isEmpty {
                Text("Unsupported primes")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .accessibilityLabel(Text(HejiNotation.accessibilityLabel(spelling)))
    }
}
