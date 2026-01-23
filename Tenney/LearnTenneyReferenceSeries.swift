import SwiftUI

enum LearnReferenceTopic: String, CaseIterable, Identifiable, Sendable {
    case rootTonicConcert
    case a4NotLaw
    case tonicDegreeIntegrity
    case troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rootTonicConcert:
            return "Root Hz, Tonic, Concert Pitch"
        case .a4NotLaw:
            return "Why “A4=440” is not a law"
        case .tonicDegreeIntegrity:
            return "Tonic + degree integrity"
        case .troubleshooting:
            return "Troubleshooting reference"
        }
    }

    var subtitle: String {
        switch self {
        case .rootTonicConcert:
            return "Three references, three jobs"
        case .a4NotLaw:
            return "Naming is a choice, not an ontology"
        case .tonicDegreeIntegrity:
            return "Letter function before enharmonic shortcuts"
        case .troubleshooting:
            return "Quick fixes when labels look wrong"
        }
    }

    var systemImage: String {
        switch self {
        case .rootTonicConcert:
            return "tuningfork"
        case .a4NotLaw:
            return "checkmark.seal"
        case .tonicDegreeIntegrity:
            return "music.note.list"
        case .troubleshooting:
            return "wrench.and.screwdriver"
        }
    }
}

struct LearnTenneyReferenceTopicView: View {
    let topic: LearnReferenceTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch topic {
                case .rootTonicConcert:
                    RootTonicConcertReferenceView()
                case .a4NotLaw:
                    A4NotLawReferenceView()
                case .tonicDegreeIntegrity:
                    TonicDegreeIntegrityReferenceView()
                case .troubleshooting:
                    ReferenceTroubleshootingView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LearnTenneyReferenceTopicListView: View {
    @Binding var focus: LearnReferenceTopic?

    var body: some View {
        List {
            ForEach(LearnReferenceTopic.allCases) { topic in
                NavigationLink(tag: topic, selection: $focus) {
                    LearnTenneyReferenceTopicView(topic: topic)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: topic.systemImage)
                                .foregroundStyle(.secondary)
                            Text(topic.title)
                                .font(.headline)
                            Spacer()
                        }
                        Text(topic.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct RootTonicConcertReferenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LearnSummaryCard(
                title: "15-second summary",
                bullets: [
                    "Root Hz anchors ratio math (1/1 → target Hz/cents).",
                    "Tonic names 1/1 so letter degrees stay correct.",
                    "Concert Pitch (A4 Hz) anchors register and “concert” references."
                ]
            )

            ReferenceRoutingDiagram()

            ReferenceSection(title: "What it is") {
                Text("Three reference layers, each with a different job. Root Hz is the frequency anchor for ratio math. Tonic is the name of 1/1 for diatonic spelling. Concert Pitch (A4 Hz) is the register anchor for octave placement and “concert” references.")
            }

            ReferenceSection(title: "Why we must separate them") {
                NumberedList(items: [
                    "“440 Hz = A = concert pitch” is provincial and historically contingent. 440 is an A because we choose to call it that. The app must treat naming and concert reference as choices, not axioms.",
                    "Root Hz needs an explicit tonic identity for diatonic processing. Without a tonic, the system defaults to absolute pitch naming and degree function collapses into enharmonic nonsense."
                ])
            }

            ReferenceSection(title: "What it affects") {
                VStack(alignment: .leading, spacing: 10) {
                    ReferenceImpactRow(
                        title: "Root Hz",
                        bullets: [
                            "1/1 anchor for all ratio math.",
                            "Target Hz and cents offsets."
                        ]
                    )
                    ReferenceImpactRow(
                        title: "Tonic",
                        bullets: [
                            "Letter class of HEJI / note spelling.",
                            "Degree function (e.g., major 7th must be the 7th letter)."
                        ]
                    )
                    ReferenceImpactRow(
                        title: "Concert Pitch (A4 Hz)",
                        bullets: [
                            "Register and octave naming.",
                            "“Concert” comparisons or staff display."
                        ]
                    )
                }
            }

            ReferenceSection(title: "What it does NOT affect") {
                BulletList(items: [
                    "Changing Root Hz does not rename the tonic or spell new letters.",
                    "Changing Tonic does not retune Hz targets.",
                    "Changing Concert Pitch does not re-interpret ratio math."
                ])
            }

            ReferenceSection(title: "When it’s the thing to change") {
                VStack(alignment: .leading, spacing: 10) {
                    IfYouSeeCard(
                        title: "If you see “weird cents”",
                        detail: "Check Root Hz. It’s the 1/1 anchor for the math."
                    )
                    IfYouSeeCard(
                        title: "If the letter is wrong",
                        detail: "Check Tonic. It defines the diatonic letter function."
                    )
                    IfYouSeeCard(
                        title: "If the octave/register is off",
                        detail: "Check Concert Pitch (A4 Hz). That sets register."
                    )
                }
            }
        }
    }
}

private struct A4NotLawReferenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LearnSummaryCard(
                title: "15-second summary",
                bullets: [
                    "A4=440 is a convention, not a law.",
                    "440 is an A because we choose to call it that.",
                    "Tenney treats naming and concert reference as choices."
                ]
            )

            ReferenceSection(title: "What it is") {
                Text("Concert pitch is a community agreement that helps ensembles line up. It is not a natural constant. The same frequency can be called different notes in different places or eras.")
            }

            ReferenceSection(title: "What it affects") {
                BulletList(items: [
                    "Register, octave labels, and staff alignment.",
                    "How “concert A” is computed in the app."
                ])
            }

            ReferenceSection(title: "What it does NOT affect") {
                BulletList(items: [
                    "Root Hz ratio math for target frequencies.",
                    "Tonic letter spelling for degree function."
                ])
            }

            ReferenceSection(title: "When it’s the thing to change") {
                VStack(alignment: .leading, spacing: 10) {
                    IfYouSeeCard(
                        title: "If the same note feels in the wrong register",
                        detail: "Adjust Concert Pitch (A4 Hz)."
                    )
                    IfYouSeeCard(
                        title: "If you’re matching a specific ensemble standard",
                        detail: "Set A4 to their reference."
                    )
                }
            }
        }
    }
}

private struct TonicDegreeIntegrityReferenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LearnSummaryCard(
                title: "15-second summary",
                bullets: [
                    "Tonic names 1/1 so degree letters stay coherent.",
                    "Enharmonic shortcuts can be wrong for degree function.",
                    "Set tonic before you trust the letters."
                ]
            )

            ReferenceSection(title: "What it is") {
                Text("Tonic is the semantic name of 1/1. It tells the system which letter class is “home,” so every ratio resolves to the correct diatonic degree.")
            }

            ReferenceSection(title: "Worked example") {
                LearnGlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Root Hz = 415 · Tonic = G♯ · Ratio = 15/8")
                            .font(.subheadline.weight(.semibold))
                        Text("15/8 is a **major 7th** above the tonic. The 7th degree above G♯ must be the letter **F**, so the correct label is **F𝄪**, not “G.”")
                            .font(.body)
                    }
                }
            }

            ReferenceSection(title: "What it affects") {
                BulletList(items: [
                    "HEJI labels and note spelling letters.",
                    "Degree function (3rd, 5th, 7th stay on their letters)."
                ])
            }

            ReferenceSection(title: "What it does NOT affect") {
                BulletList(items: [
                    "Ratio math and Hz targets (Root Hz does that).",
                    "Octave/register labels (Concert Pitch does that)."
                ])
            }

            ReferenceSection(title: "When it’s the thing to change") {
                VStack(alignment: .leading, spacing: 10) {
                    IfYouSeeCard(
                        title: "If letters look enharmonically wrong",
                        detail: "Set a tonic explicitly (Auto or Manual)."
                    )
                    IfYouSeeCard(
                        title: "If you need degree clarity for theory work",
                        detail: "Choose a tonic that matches the key center."
                    )
                }
            }
        }
    }
}

private struct ReferenceTroubleshootingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LearnSummaryCard(
                title: "15-second summary",
                bullets: [
                    "Wrong letter → check Tonic.",
                    "Wrong register → check Concert Pitch.",
                    "Wrong cents/targets → check Root Hz."
                ]
            )

            ReferenceSection(title: "Decision tree") {
                LearnGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TroubleshootRow(issue: "Letter is wrong", fix: "Set or adjust Tonic (name of 1/1).")
                        TroubleshootRow(issue: "Octave/register is wrong", fix: "Set Concert Pitch (A4 Hz).")
                        TroubleshootRow(issue: "Cents/targets feel off", fix: "Set Root Hz (1/1 anchor).")
                    }
                }
            }

            ReferenceSection(title: "What it does NOT affect") {
                BulletList(items: [
                    "These checks do not change your ratio vocabulary.",
                    "They only re-anchor how Tenney names and displays."
                ])
            }
        }
    }
}

private struct LearnSummaryCard: View {
    let title: String
    let bullets: [String]

    var body: some View {
        LearnGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                BulletList(items: bullets)
            }
        }
    }
}

private struct ReferenceSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                }
                .font(.subheadline)
            }
        }
    }
}

private struct NumberedList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.subheadline.weight(.semibold))
                    Text(item)
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct IfYouSeeCard: View {
    let title: String
    let detail: String

    var body: some View {
        LearnGlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReferenceImpactRow: View {
    let title: String
    let bullets: [String]

    var body: some View {
        LearnGlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                BulletList(items: bullets)
            }
        }
    }
}

private struct TroubleshootRow: View {
    let issue: String
    let fix: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue)
                    .font(.subheadline.weight(.semibold))
                Text(fix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReferenceRoutingDiagram: View {
    var body: some View {
        LearnGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Routing diagram")
                    .font(.headline)
                HStack(alignment: .top, spacing: 12) {
                    DiagramColumn(
                        title: "Root Hz",
                        detail: "ratio math → target Hz / cents",
                        symbol: "waveform.path.ecg"
                    )
                    DiagramArrow()
                    DiagramColumn(
                        title: "Tonic",
                        detail: "note spelling → HEJI letters",
                        symbol: "textformat.abc"
                    )
                    DiagramArrow()
                    DiagramColumn(
                        title: "Concert Pitch",
                        detail: "register → A4 reference",
                        symbol: "music.quarternote.3"
                    )
                }
            }
        }
    }
}

private struct DiagramColumn: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .imageScale(.small)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DiagramArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
            .padding(.top, 18)
    }
}
