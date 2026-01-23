import SwiftUI

struct LearnControlRef: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let location: String
    let gesture: String
    let short: String
    let long: String
    let focus: LearnPracticeFocus?
}

struct LearnTenneyReferenceTopicsListView: View {
    let module: LearnTenneyModule
    @Binding var selectedTopic: LearnReferenceTopic?

    var body: some View {
        List {
            ForEach(module.referenceTopics) { topic in
                NavigationLink(tag: topic, selection: $selectedTopic) {
                    LearnTenneyReferenceTopicView(topic: topic, module: module)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: topic.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 30, height: 30)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.title)
                                .font(.headline)
                            Text(topic.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(topic.title))
                    .accessibilityValue(Text(topic.subtitle))
                }
            }
        }
    }
}

struct LearnTenneyReferenceListView: View {
    let module: LearnTenneyModule
    var onTryInPractice: (LearnPracticeFocus) -> Void

    @State private var query: String = ""

    var body: some View {
        let all = controls(for: module)
        let filtered = all.filter { item in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            let q = query.lowercased()
            return item.name.lowercased().contains(q)
                || item.location.lowercased().contains(q)
                || item.gesture.lowercased().contains(q)
                || item.short.lowercased().contains(q)
        }

        List {
            ForEach(filtered) { item in
                NavigationLink {
                    LearnTenneyReferenceDetailView(item: item, onTry: { focus in
                        onTryInPractice(focus)
                    })
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name).font(.headline)
                            Spacer()
                        }
                        Text("\(item.location) · \(item.gesture)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(item.short)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search controls")
    }

    private func controls(for m: LearnTenneyModule) -> [LearnControlRef] {
        switch m {
        case .lattice:
            return [
                .init(
                    name: "Tap-select node",
                    location: "Lattice surface",
                    gesture: "Tap",
                    short: "Selects a ratio as your current focus/target.",
                    long: "Tapping a node makes it the current selection. Selection drives what the UI highlights and what many actions operate on.",
                    focus: .latticeTapSelect
                ),
                .init(
                    name: "Long-press node",
                    location: "Selected node",
                    gesture: "Long-press",
                    short: "Reveals deeper/context actions for that ratio.",
                    long: "Long-press is the ‘more options’ gesture in Lattice. Use it when you want actions tied to the selected ratio rather than just selecting.",
                    focus: .latticeLongPress
                ),
                .init(
                    name: "Limit chips",
                    location: "Top rail / utility area",
                    gesture: "Tap",
                    short: "Constrains what ratios are considered / shown.",
                    long: "Limit chips set your current constraint vocabulary. They also act as a status readout: you can tell at a glance what limits are active.",
                    focus: .latticeLimitChips
                ),
                .init(
                    name: "Axis shift",
                    location: "Axis Shift screen",
                    gesture: "Tap / step",
                    short: "Transposes along prime axes; reset returns you home.",
                    long: "Axis shift changes the meaning (ratios) of the lattice neighborhood without changing its geometry. Reset all shifts to return to the default neighborhood.",
                    focus: .latticeAxisShift
                )
            ]

        case .tuner:
            return [
                .init(
                    name: "Tuner Styles",
                    location: "Tuner top controls",
                    gesture: "Tap",
                    short: "Switches presentation style (same engine).",
                    long: "Gauge is minimal; Chrono is more explicit; Scope shows scopes to find beat patterns. Both show the same underlying pitch tracking and ratio resolution.",
                    focus: .tunerViewSwitch
                ),
                .init(
                    name: "Confidence",
                    location: "Tuner readout",
                    gesture: "Read-only",
                    short: "How stable/real the detected pitch is.",
                    long: "Confidence rises with stable, pitched input and falls with noise or unstable partials. Use it to interpret whether the reading is trustworthy.",
                    focus: .tunerConfidence
                ),
                .init(
                    name: "Lock target",
                    location: "Target control / dial area",
                    gesture: "Long-press",
                    short: "Freezes the target so the UI stops chasing.",
                    long: "Lock is for practice: keep one target fixed while you adjust your pitch. Unlock to resume automatic target updates.",
                    focus: .tunerLockTarget
                ),
                .init(
                    name: "Prime limit",
                    location: "Prime limit chips",
                    gesture: "Tap",
                    short: "Changes allowed ratio vocabulary.",
                    long: "Lower prime limits yield simpler matches; higher limits allow richer ratios but can increase ambiguity. Choose based on context and repertoire.",
                    focus: .tunerPrimeLimit
                ),
                .init(
                    name: "Stage mode",
                    location: "Stage settings / stage toggle",
                    gesture: "Tap",
                    short: "Performance readability + simplified layout.",
                    long: "Stage mode emphasizes visibility and reduces non-essential UI elements. Use it when playing live or in low light.",
                    focus: .tunerStageMode
                ),
                .init(
                    name: "ET vs JI",
                    location: "Tuner labels",
                    gesture: "Read-only",
                    short: "Tempered naming vs ratio truth.",
                    long: "ET is useful for quick naming and ensemble context; JI is the exact ratio match Tenney resolves. Together they explain what you’re hearing and why.",
                    focus: .tunerETvsJI
                )
            ]

        case .builder:
            return [
                .init(
                    name: "Pads",
                    location: "Builder pad grid",
                    gesture: "Tap",
                    short: "Plays entries like an instrument surface.",
                    long: "Pads are meant to be performed. They trigger the pitches in your evolving scale and make it easy to rehearse the set musically.",
                    focus: .builderPads
                ),
                .init(
                    name: "Add root (1/1)",
                    location: "Builder toolbar",
                    gesture: "Tap",
                    short: "Adds the 1/1 anchor for your scale.",
                    long: "Root (1/1) defines the reference for your Builder ratios. Add it so 1/1 appears as a playable pad.",
                    focus: .builderAddRoot
                ),
                .init(
                    name: "Oscilloscope",
                    location: "Builder / scope view",
                    gesture: "Look",
                    short: "Visual feedback (not deep diagnostics).",
                    long: "Treat the oscilloscope as immediate visual feedback: stability, blend, and motion. It’s intentionally not a full analysis suite here.",
                    focus: .builderOscilloscope
                )
            ]
        case .rootPitchTuningConfig:
            return []
        }
    }
}

private struct LearnTenneyReferenceDetailView: View {
    let item: LearnControlRef
    var onTry: (LearnPracticeFocus) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LearnGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.name)
                            .font(.title3.weight(.semibold))
                        Text("\(item.location) · \(item.gesture)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(item.long)
                            .font(.body)
                    }
                }

                if let focus = item.focus {
                    Button {
                        onTry(focus)
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Try it in Practice")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationTitle("Reference")
        .navigationBarTitleDisplayMode(.inline)
    }
}
