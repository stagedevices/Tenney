//
//  LearnTenneyTour.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import SwiftUI

struct LearnTourStep: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let bullets: [String]
    let tryIt: String
}

struct LearnTenneyTourView: View {
    let module: LearnTenneyModule

    @AppStorage(SettingsKeys.learnLatticeTourCompleted) private var latticeDone: Bool = false
    @AppStorage(SettingsKeys.learnTunerTourCompleted) private var tunerDone: Bool = false
    @AppStorage(SettingsKeys.learnBuilderTourCompleted) private var builderDone: Bool = false

    @State private var idx: Int = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let steps = tourSteps(for: module)
        ScrollView {
            VStack(spacing: 14) {
                LearnGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(steps[idx].title)
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Text("\(idx + 1)/\(steps.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(steps[idx].bullets, id: \.self) { b in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(b).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.body)
                            }
                        }

                        Divider().opacity(0.7)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Try it")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(steps[idx].tryIt)
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HStack(spacing: 10) {
                    Button {
                        if idx > 0 { idx -= 1 }
                    } label: {
                        Text("Back")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(idx == 0)

                    Button {
                        if idx < steps.count - 1 {
                            idx += 1
                        } else {
                            markCompleted(module)
                            dismiss()
                        }
                    } label: {
                        Text(idx < steps.count - 1 ? "Next" : "Finish")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)

                Button {
                    dismiss()
                } label: {
                    Text("Exit Tour")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func markCompleted(_ m: LearnTenneyModule) {
        switch m {
        case .lattice: latticeDone = true
        case .tuner: tunerDone = true
        case .builder: builderDone = true
        case .rootPitchTuningConfig: break
        }
    }

    private func tourSteps(for m: LearnTenneyModule) -> [LearnTourStep] {
        switch m {
        case .lattice:
            return [
                .init(
                    title: "What Lattice is",
                    bullets: [
                        "Lattice is a playable map of just-intonation ratios around your root.",
                        "Everything you do is about selecting a ratio, hearing it, and navigating constraints."
                    ],
                    tryIt: "Open Practice and tap a few nodes to see how selection behaves."
                ),
                .init(
                    title: "Tap-select nodes",
                    bullets: [
                        "Tap a node to select it (selection drives what you see and what you hear).",
                        "Selection is the “current target” for auditioning and building."
                    ],
                    tryIt: "Tap one node, then tap a different node—watch the selected state change."
                ),
                .init(
                    title: "Auditioning",
                    bullets: [
                        "Auditioning lets you quickly hear a node’s ratio against your root.",
                        "Turn on Audition (speaker icon) in the utility bar so taps can produce sound."
                    ],
                    tryIt: "Turn on Audition in the bottom utility bar, then tap-select a node to hear it."
                ),
                .init(
                    title: "Limit chips",
                    bullets: [
                        "Limit chips constrain what ratios are considered / shown / emphasized.",
                        "They are also a status readout: your current constraint set at a glance."
                    ],
                    tryIt: "Find the limit chips, change the limit, then observe how the lattice surface responds."
                ),
                .init(
                    title: "Press-and-hold on limit chips",
                    bullets: [
                        "Press-and-hold reveals the “deeper” action for a control.",
                        "On the prime-limit chips, press-and-hold toggles all higher limits on/off in one move."
                    ],
                    tryIt: "Press-and-hold a prime-limit chip to toggle the higher-limit set on/off."
                ),
                .init(
                    title: "Axis shift",
                    bullets: [
                        "Axis shift transposes the lattice along prime axes without changing the geometry.",
                        "If things feel “lost,” reset axis shift to recover the familiar neighborhood."
                    ],
                    tryIt: "Open Axis Shift, change one prime by ±1, then reset back to zero."
                )
            ]

        case .tuner:
            return [
                .init(
                    title: "Three tuner types",
                    bullets: [
                        "Gauge is minimal and calm; Chrono is more technical / explicit; Scope is more professional",
                        "Both read the same pitch engine—only presentation changes."
                    ],
                    tryIt: "Switch between Gauge, Chrono, and Scope and notice what information is emphasized."
                ),
                .init(
                    title: "Confidence",
                    bullets: [
                        "Confidence is: how sure Tenney is that the detected pitch is stable + real.",
                        "Low confidence usually means noise, breath, room tone, or unstable partials."
                    ],
                    tryIt: "Hum a steady tone, then stop—watch confidence rise/fall with stability."
                ),
                .init(
                    title: "Lock target (long-press)",
                    bullets: [
                        "Lock fixes your target so the UI stops “chasing” nearby ratios.",
                        "Use lock when practicing intonation against one goal."
                    ],
                    tryIt: "Long-press the target control to lock."
                ),
                .init(
                    title: "Unlock target (long-press)",
                    bullets: [
                        "Long-press the tuner dial again to unlock the target."
                    ],
                    tryIt: "Long-press the tuner dial to unlock."
                ),
                .init(
                    title: "Prime limit chips",
                    bullets: [
                        "Prime limit changes which ratios are eligible matches.",
                        "Lower limit = simpler vocabulary; higher limit = more nuance (and more ambiguity)."
                    ],
                    tryIt: "Change prime limit and watch the suggested ratio set tighten/expand."
                ),
                .init(
                    title: "ET vs JI readouts",
                    bullets: [
                        "ET shows tempered note context; JI shows ratio context.",
                        "They are complementary: ET for quick naming, JI for exactness."
                    ],
                    tryIt: "Play a stable pitch and compare the ET label vs the JI ratio."
                ),
                .init(
                    title: "Stage mode",
                    bullets: [
                        "Stage mode prioritizes readability and performance behavior.",
                        "Expect fewer distractions and stronger visibility choices."
                    ],
                    tryIt: "Toggle stage mode and observe what UI elements simplify."
                )
            ]

        case .builder:
            return [
                .init(
                    title: "Builder = performance surface",
                    bullets: [
                        "Pads are playable triggers for your scale-in-progress.",
                        "Builder is where you collect and order a tuning vocabulary."
                    ],
                    tryIt: "Tap a few pads to hear how the surface behaves as an instrument."
                ),
                .init(
                    title: "Add root (1/1)",
                    bullets: [
                        "Root (1/1) anchors the ratios you’ve collected.",
                        "Adding it makes the Builder content a complete scale."
                    ],
                    tryIt: "Add the root so 1/1 is part of the set."
                ),
                .init(
                    title: "Play 1/1",
                    bullets: [
                        "Once you add root, 1/1 is available as a pad.",
                        "Play 1/1 to hear the anchor before exploring other ratios."
                    ],
                    tryIt: "Tap the 1/1 pad to hear the root anchor."
                ),
                .init(
                    title: "Oscilloscope (visual feedback)",
                    bullets: [
                        "The oscilloscope is not a deep diagnostic tool here.",
                        "Use it as immediate visual feedback: stability, motion, and blend."
                    ],
                    tryIt: "Make two tones interact (or use pads) and watch the shape evolve."
                )
            ]
        case .rootPitchTuningConfig:
            return []
        }
    }
}

// Minimal “glass card” so Learn screens match Tenney’s language without depending on internal helpers.
struct LearnGlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
    }
}
