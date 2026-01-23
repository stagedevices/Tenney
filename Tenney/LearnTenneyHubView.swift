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
    case lattice, tuner, builder, libraryPacks, rootPitchTuningConfig
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lattice: return "Lattice"
        case .tuner:   return "Tuner"
        case .builder: return "Builder"
        case .libraryPacks: return "Library & Packs"
        case .rootPitchTuningConfig: return "Root Pitch & Tuning Configuration"
        }
    }

    var subtitle: String {
        switch self {
        case .lattice: return "Selection, limits, axis shift, and auditioning"
        case .tuner:   return "Views, locks, confidence, limits, and stage mode"
        case .builder: return "Pads, root, and the oscilloscope"
        case .libraryPacks: return "Library basics, tags, favorites, and community packs"
        case .rootPitchTuningConfig: return "Root Hz, tonic naming, concert pitch, and troubleshooting"
        }
    }

    var systemImage: String {
        switch self {
        case .lattice: return "point.3.connected.trianglepath.dotted"
        case .tuner:   return "dial.high.fill"
        case .builder: return "pianokeys.inverse"
        case .libraryPacks: return "tray.fill"
        case .rootPitchTuningConfig: return "tuningfork"
        }
    }

    var supportsPractice: Bool {
        switch self {
        case .libraryPacks:
            return false
        case .rootPitchTuningConfig:
            return false
        default:
            return true
        }
    }

    var supportsReference: Bool {
        true
    }

    var referenceTopics: [LearnReferenceTopic] {
        switch self {
        case .rootPitchTuningConfig:
            return LearnReferenceTopic.allCases
        default:
            return []
        }
    }

    var nextModule: LearnTenneyModule? {
        let modules = LearnTenneyModule.allCases
        guard let idx = modules.firstIndex(of: self) else { return nil }
        let nextIdx = modules.index(after: idx)
        return nextIdx < modules.endIndex ? modules[nextIdx] : nil
    }
}


struct LearnTenneyHubView: View {
    let entryPoint: LearnTenneyEntryPoint

    @StateObject private var store = LearnTenneyStateStore.shared
    @State private var activeModule: LearnTenneyModule? = nil
    @Environment(\.tenneyTheme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        List {
            Section {
                ForEach(LearnTenneyModule.allCases) { m in
                    let state = stateForModule(m)
                    let totalSteps = totalSteps(for: m)
                    let stepsDone = min(max(0, state.stepIndex), totalSteps)
                    let progress = totalSteps > 0 ? Double(stepsDone) / Double(totalSteps) : 0
                    let tint = moduleTint

                    NavigationLink(tag: m, selection: $activeModule) {
                        LearnTenneyModuleView(module: m)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: m.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 30, height: 30)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(m.title)
                                        .font(.headline)

                                    LearnModuleBadge(
                                        state: state,
                                        progress: progress,
                                        tint: tint,
                                        size: sizeClass == .regular ? 16 : 14
                                    )
                                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
                                }
                                Text(m.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .overlay(alignment: .leading) {
                            if state.completed {
                                RoundedRectangle(cornerRadius: 1, style: .continuous)
                                    .fill(tint.opacity(0.7))
                                    .frame(width: 3)
                                    .padding(.vertical, 6)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(m.title))
                        .accessibilityValue(Text(accessibilityValue(for: m, state: state, totalSteps: totalSteps)))
                    }
                }
            } header: {
                Text("Modules")
            } footer: {
                Text("Each module includes practice, reference, or both — all organized by area.")
            }
        }
        .navigationTitle("Learn Tenney")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let pending = store.pendingModuleToOpen {
                activeModule = pending
                store.pendingModuleToOpen = nil
            }
        }
        .onChange(of: store.pendingModuleToOpen) { pending in
            guard let pending else { return }
            activeModule = pending
            store.pendingModuleToOpen = nil
        }
    }

    private var moduleTint: Color {
        theme.primeTint(3)._tenneyInterpolate(to: theme.primeTint(5), t: 0.5)
    }

    private func stateForModule(_ m: LearnTenneyModule) -> TenneyPracticeSnapshot.ModuleState {
        store.states[m] ?? .init(stepIndex: 0, completed: false)
    }

    private func totalSteps(for module: LearnTenneyModule) -> Int {
        if module.supportsPractice {
            return LearnStepFactory.steps(for: module).count
        }
        if module.supportsReference {
            return module.referenceTopics.count
        }
        return 0
    }

    private func accessibilityValue(for module: LearnTenneyModule, state: TenneyPracticeSnapshot.ModuleState, totalSteps: Int) -> String {
        if state.completed {
            return "Completed."
        }
        if state.stepIndex > 0, totalSteps > 0 {
            let stepNumber = min(state.stepIndex + 1, totalSteps)
            return "In progress, step \(stepNumber) of \(totalSteps)."
        }
        return "Not started."
    }
}

private struct LearnModuleBadge: View {
    let state: TenneyPracticeSnapshot.ModuleState
    let progress: Double
    let tint: Color
    let size: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isInProgress: Bool {
        state.stepIndex > 0 && !state.completed
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 2)

            if isInProgress {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 0.98))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            if state.completed {
                Circle()
                    .strokeBorder(tint, lineWidth: 2.2)
                    .shadow(color: tint.opacity(0.35), radius: 3, x: 0, y: 0)
            }

            Circle()
                .fill(innerFill)

            if state.completed {
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .offset(x: -size * 0.18, y: -size * 0.18)

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 0.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var innerFill: Color {
        if state.completed {
            return tint.opacity(0.22)
        }
        if isInProgress {
            return tint.opacity(0.12)
        }
        return reduceTransparency ? Color.secondary.opacity(0.05) : Color.clear
    }
}
