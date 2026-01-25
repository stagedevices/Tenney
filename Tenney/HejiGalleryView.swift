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
    @AppStorage(SettingsKeys.staffA4Hz) private var concertA4Hz: Double = 440
    @AppStorage(SettingsKeys.noteNameA4Hz) private var noteNameA4Hz: Double = 440
    @AppStorage(SettingsKeys.tonicNameMode) private var tonicNameModeRaw: String = TonicNameMode.auto.rawValue
    @AppStorage(SettingsKeys.tonicE3) private var tonicE3: Int = 0
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let pref = AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
        let mode = TonicNameMode(rawValue: tonicNameModeRaw) ?? .auto
        let resolvedTonicE3 = TonicSpelling.resolvedTonicE3(
            mode: mode,
            manualE3: tonicE3,
            rootHz: 440,
            noteNameA4Hz: noteNameA4Hz,
            preference: pref
        )
        let context = HejiContext(
            concertA4Hz: concertA4Hz,
            noteNameA4Hz: noteNameA4Hz,
            rootHz: 440,
            rootRatio: RatioRef(p: 1, q: 1, octave: 0, monzo: [:]),
            preferred: pref,
            maxPrime: max(3, app.primeLimit),
            allowApproximation: false,
            scaleDegreeHint: nil,
            tonicE3: resolvedTonicE3
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
