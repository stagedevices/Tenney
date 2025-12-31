//
//  LearnStepFactory.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/30/25.
//


//  LearnStepFactory.swift
//  Tenney

import Foundation

enum LearnStepFactory {
    static func steps(for module: LearnTenneyModule) -> [LearnStep] {
        switch module {

        case .lattice:
            return [
                LearnStep(
                    title: "Tap-select nodes",
                    bullets: [
                        "Tap a node to select it (selection drives what you see and what you hear).",
                        "Selection is the “current target” for auditioning and building."
                    ],
                    tryIt: "Tap any node (dot) to select it.",
                    gate: .init(), // no gating for now
                    validate: { event in
                        if case .latticeNodeSelected = event { return true }
                        return false
                    }
                ),

                LearnStep(
                    title: "Auditioning",
                    bullets: [
                        "Auditioning lets you quickly hear a ratio against your root.",
                        "Turn on Audition (speaker) in the utility bar so taps can produce sound."
                    ],
                    tryIt: "Turn on Audition in the bottom bar.",
                    gate: .init(), // no gating for now
                    validate: { event in
                        if case .latticeAuditionEnabledChanged(true) = event { return true }
                        return false
                    }
                ),

                // swapped: Limit chips BEFORE long-press behavior
                LearnStep(
                    title: "Limit chips",
                    bullets: [
                        "Prime chips constrain what primes are “in play”.",
                        "They’re also a status readout: your current constraint set at a glance."
                    ],
                    tryIt: "Tap the 7 limit prime chip (purple, top left) to toggle 7 limit ratios on/off, etc.",
                    gate: .init(), // no gating for now
                    validate: { event in
                        if case .latticePrimeChipToggled = event { return true }
                        return false
                    }
                ),

                LearnStep(
                    title: "Long-press behavior",
                    bullets: [
                        "Press-and-hold reveals the “deeper” action for a control.",
                        "On the prime chips, press-and-hold toggles all higher primes on/off in one move."
                    ],
                    tryIt: "Press-and-hold a prime chip to toggle the higher-prime set. Try it on the 7 limit chip",
                    gate: .init(), // no gating for now
                    validate: { event in
                        if case .latticePrimeChipHiToggle = event { return true }
                        return false
                    }
                )
            ]


        case .tuner:
            return [
                LearnStep(
                    title: "Pick a target",
                    instruction: "Choose what you’re trying to match so the UI stops feeling ambiguous.",
                    tryIt: "Pick any target ratio.",
                    gate: .init(allowedTargets: ["tuner_target"], isActive: true),
                    validate: { if case .tunerTargetPicked = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Lock target",
                    instruction: "Lock fixes your target so the UI stops ‘chasing’ nearby ratios.",
                    tryIt: "Toggle lock on/off.",
                    gate: .init(allowedTargets: ["tuner_lock"], isActive: true),
                    validate: { if case .tunerLockToggled = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Root pitch",
                    instruction: "Root is your reference. Changing it re-centers the whole JI world.",
                    tryIt: "Change root once.",
                    gate: .init(allowedTargets: ["tuner_root"], isActive: true),
                    validate: { if case .tunerRootChanged = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Pitch history",
                    instruction: "History helps you see stability over time, not just instantaneous wiggle.",
                    tryIt: "Open pitch history.",
                    gate: .init(allowedTargets: ["tuner_history"], isActive: true),
                    validate: { $0 == .tunerPitchHistoryOpened }
                ),
                LearnStep(
                    title: "Confidence",
                    instruction: "Confidence is how sure Tenney is that the pitch is stable + real.",
                    tryIt: "Adjust the confidence gate once.",
                    gate: .init(allowedTargets: ["tuner_confidence"], isActive: true),
                    validate: { if case .tunerConfidenceGateChanged = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Output",
                    instruction: "Output lets you practice against a generated reference tone.",
                    tryIt: "Toggle output on/off.",
                    gate: .init(allowedTargets: ["tuner_output"], isActive: true),
                    validate: { if case .tunerOutputEnabledChanged = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Wave",
                    instruction: "Wave changes the character of the reference tone.",
                    tryIt: "Pick a different wave.",
                    gate: .init(allowedTargets: ["tuner_wave"], isActive: true),
                    validate: { if case .tunerOutputWaveChanged = $0 { return true } else { return false } }
                )
            ]

        case .builder:
            return [
                LearnStep(
                    title: "Builder = performance surface",
                    instruction: "Pads are playable triggers for your scale-in-progress.",
                    tryIt: "Trigger a pad.",
                    gate: .init(allowedTargets: ["builder_pad"], isActive: true),
                    validate: { if case .builderPadTriggered = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Octave stepping",
                    instruction: "Octave stepping shifts pads up/down without rewriting the underlying ratios.",
                    tryIt: "Change octave for one pad.",
                    gate: .init(allowedTargets: ["builder_octave"], isActive: true),
                    validate: { if case .builderPadOctaveChanged = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Selecting",
                    instruction: "Selection lets you focus edits and exports on specific content.",
                    tryIt: "Select something in the builder.",
                    gate: .init(allowedTargets: ["builder_select"], isActive: true),
                    validate: { if case .builderSelectionChanged = $0 { return true } else { return false } }
                ),
                LearnStep(
                    title: "Clear selection",
                    instruction: "Clear selection to return to the whole-surface view.",
                    tryIt: "Clear selection.",
                    gate: .init(allowedTargets: ["builder_clear_selection"], isActive: true),
                    validate: { $0 == .builderSelectionCleared }
                ),
                LearnStep(
                    title: "Exporting",
                    instruction: "Export produces shareable artifacts that reflect the scale you built.",
                    tryIt: "Open export.",
                    gate: .init(allowedTargets: ["builder_export"], isActive: true),
                    validate: { $0 == .builderExportOpened }
                ),
                LearnStep(
                    title: "Oscilloscope",
                    instruction: "Use the scope as immediate visual feedback: stability, motion, blend.",
                    tryIt: "Observe the oscilloscope once.",
                    gate: .init(allowedTargets: ["builder_scope"], isActive: true),
                    validate: { $0 == .builderOscilloscopeObserved }
                )
            ]
        }
    }
}

