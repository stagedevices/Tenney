//
//  HejiGalleryView.swift
//  Tenney
//

import SwiftUI

#if DEBUG
struct HejiGalleryView: View {
    private let samples: [(String, RatioRef)] = [
        ("1/1", RatioRef(p: 1, q: 1, octave: 0, monzo: [:])),
        ("3/2", RatioRef(p: 3, q: 2, octave: 0, monzo: [:])),
        ("4/3", RatioRef(p: 4, q: 3, octave: 0, monzo: [:])),
        ("5/4", RatioRef(p: 5, q: 4, octave: 0, monzo: [:])),
        ("7/4", RatioRef(p: 7, q: 4, octave: 0, monzo: [:])),
        ("11/8", RatioRef(p: 11, q: 8, octave: 0, monzo: [:])),
        ("13/8", RatioRef(p: 13, q: 8, octave: 0, monzo: [:]))
    ]

    @AppStorage(SettingsKeys.accidentalPreference) private var accidentalPreferenceRaw: String = AccidentalPreference.auto.rawValue
    @AppStorage(SettingsKeys.staffA4Hz) private var staffA4Hz: Double = 440

    var body: some View {
        let pref = AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
        let context = HejiContext(
            referenceA4Hz: staffA4Hz,
            rootHz: 440,
            rootRatio: RatioRef(p: 1, q: 1, octave: 0, monzo: [:]),
            preferred: pref,
            maxPrime: 13,
            allowApproximation: false,
            scaleDegreeHint: nil
        )

        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                ForEach(samples, id: \.0) { label, ratio in
                    let spelling = HejiNotation.spelling(forRatio: ratio, context: context)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HejiPitchLabel(context: context, pitch: .ratio(ratio), modeOverride: .combined)

                        Text(HejiNotation.accessibilityLabel(spelling))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
        }
        .navigationTitle("HEJI Gallery")
    }
}
#endif

