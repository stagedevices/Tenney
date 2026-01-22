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

    var body: some View {
        VStack(spacing: mode == .combined ? 4 : 0) {
            if mode == .staff || mode == .combined {
                let layout = HejiNotation.staffLayout(spelling, context: context)
                HejiStaffSnippetView(layout: layout)
                    .accessibilityHidden(true)
            }

            if mode == .text || mode == .combined {
                Text(HejiNotation.textLabel(spelling, showCents: showCentsWhenApproximate))
                    .font(.headline.monospaced())
            }

            if !spelling.unsupportedPrimes.isEmpty {
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
