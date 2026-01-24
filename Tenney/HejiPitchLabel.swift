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

    var body: some View {
        let unsupported = spelling.unsupportedPrimes
        VStack(spacing: mode == .combined ? 4 : 0) {
            if mode == .staff || mode == .combined {
                let layout = HejiNotation.staffLayout(spelling, context: context)
                HejiStaffSnippetView(layout: layout)
                    .accessibilityHidden(true)
            }

            if mode == .text || mode == .combined {
                let label = HejiNotation.textLabelString(spelling, showCents: showCentsWhenApproximate)
                Text(verbatim: label)
                    .font(.headline.monospaced())
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
