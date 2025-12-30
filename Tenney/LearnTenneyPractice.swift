//
//  LearnTenneyPractice.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import SwiftUI

struct LearnTenneyPracticeView: View {
    let module: LearnTenneyModule
    @Binding var focus: LearnPracticeFocus?

    @Environment(\.dismiss) private var dismiss

    @State private var baseline: TenneyPracticeSnapshot? = nil
    @State private var trackedBaseline: TenneyPracticeSnapshot? = nil
    @State private var resetToken = UUID()

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch module {
                case .lattice:
                    LatticeScreen()
                        .id(resetToken)

                case .tuner:
                    TunerPracticeHost()
                        .id(resetToken)

                case .builder:
                    BuilderPracticeHost()
                        .id(resetToken)
                }
            }
            .ignoresSafeArea(.keyboard)

            LearnPracticeOverlay(
                title: overlayTitle,
                instruction: overlayInstruction,
                onReset: resetPractice,
                onDone: exitPractice
            )
            .padding(.top, 10)
            .padding(.horizontal, 12)
        }
        .onAppear {
            if baseline == nil {
                let snap = TenneyPracticeSnapshot()
                baseline = snap
                trackedBaseline = snap
            }
        }
        .onDisappear {
            // Safety: restore if user swipes back.
            trackedBaseline?.restore()
        }
    }

    private var overlayTitle: String {
        switch module {
        case .lattice: return "Practice · Lattice"
        case .tuner: return "Practice · Tuner"
        case .builder: return "Practice · Builder"
        }
    }

    private var overlayInstruction: String {
        // Focus-driven micro-instructions (short, actionable).
        switch focus {
        case .latticeTapSelect:
            return "Tap a node to select it, then tap a different node to compare selection behavior."
        case .latticeLongPress:
            return "Long-press a selected node to reveal its deeper/context action."
        case .latticeLimitChips:
            return "Find the limit chips and change the limit; watch the lattice surface respond."
        case .latticeAxisShift:
            return "Open Axis Shift, change a prime by ±1, then reset to zero."

        case .tunerViewSwitch:
            return "Switch between tuner styles and notice what information is emphasized."
        case .tunerLockTarget:
            return "Long-press the target to lock, then unlock."
        case .tunerConfidence:
            return "Sustain a steady tone; watch confidence rise with stability."
        case .tunerPrimeLimit:
            return "Change prime limit; observe how the suggested ratio vocabulary changes."
        case .tunerStageMode:
            return "Toggle stage mode; confirm readability and simplified layout."
        case .tunerETvsJI:
            return "Compare ET naming vs JI ratio for the same stable pitch."

        case .builderPads:
            return "Tap pads like an instrument—aim for a steady rhythm and listen for tuning color."
        case .builderOctaveStepping:
            return "Shift a pad up/down an octave, then return it to neutral."
        case .builderExport:
            return "Open export and verify what will be included before sharing."
        case .builderOscilloscope:
            return "Watch the oscilloscope as tones interact; treat it as visual feedback, not diagnosis."

        case .none:
            return "Try the main controls you’re curious about. Use Reset to get back to a clean slate."
        }
    }

    private func resetPractice() {
        guard let base = baseline else { return }
        // Remove keys created since baseline, then restore baseline values.
        let strict = base.trackingNewKeys(since: base)
        strict.restore()
        resetToken = UUID()
        // Keep focus; user is usually mid-task.
    }

    private func exitPractice() {
        trackedBaseline?.restore()
        dismiss()
    }
}

private struct LearnPracticeOverlay: View {
    let title: String
    let instruction: String
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)

                Button(action: onDone) {
                    Text("Done")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
            }

            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct TunerPracticeHost: View {
    @State private var stageActive = false
    var body: some View {
        TunerCard(stageActive: $stageActive)
    }
}

private struct BuilderPracticeHost: View {
    @StateObject private var store = ScaleBuilderStore(
        payload: ScaleBuilderPayload(rootHz: 440.0, primeLimit: 5, items: [])
    )
    var body: some View {
        ScaleBuilderScreen(store: store)
    }
}

