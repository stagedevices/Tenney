//
//  LearnTenneyHubView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import SwiftUI

enum LearnTenneyEntryPoint: Sendable {
    case settings
    case onboarding
}

enum LearnTenneyModule: String, CaseIterable, Identifiable, Sendable {
    case lattice, tuner, builder
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lattice: return "Lattice"
        case .tuner:   return "Tuner"
        case .builder: return "Builder"
        }
    }

    var subtitle: String {
        switch self {
        case .lattice: return "Selection, limits, axis shift, and auditioning"
        case .tuner:   return "Views, locks, confidence, limits, and stage mode"
        case .builder: return "Pads, exporting, and the oscilloscope"
        }
    }

    var systemImage: String {
        switch self {
        case .lattice: return "circle.grid.3x3.fill"
        case .tuner:   return "dial.high.fill"
        case .builder: return "pianokeys.inverse"
        }
    }
}


struct LearnTenneyHubView: View {
    let entryPoint: LearnTenneyEntryPoint

    @AppStorage(SettingsKeys.learnLatticeTourCompleted) private var latticeDone: Bool = false
    @AppStorage(SettingsKeys.learnTunerTourCompleted) private var tunerDone: Bool = false
    @AppStorage(SettingsKeys.learnBuilderTourCompleted) private var builderDone: Bool = false

    var body: some View {
        List {
            Section {
                ForEach(LearnTenneyModule.allCases) { m in
                    NavigationLink {
                        LearnTenneyModuleView(module: m)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: m.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 30, height: 30)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title)
                                    .font(.headline)
                                Text(m.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if isCompleted(m) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Tour completed")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Modules")
            } footer: {
                Text("Each module includes a short tour through an interactive practice sandbox and a searchable control glossary.")
            }
        }
        .navigationTitle("Learn Tenney")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isCompleted(_ m: LearnTenneyModule) -> Bool {
        switch m {
        case .lattice: return latticeDone
        case .tuner:   return tunerDone
        case .builder: return builderDone
        }
    }
}

