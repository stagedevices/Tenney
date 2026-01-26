//
//  DistanceDetailSheet.swift
//  Tenney
//
//  Created by Codex.
//

import SwiftUI

struct DistanceDetailSheet: View {
    struct Model: Identifiable {
        let id: UUID
        let from: Endpoint
        let to: Endpoint
        let primaryMetricID: String
        let chips: [ChipMetric]
        let rows: [MetricRow]
        let primeDeltas: [PrimeDelta]
        let referenceA4Hz: Double?
        let melodicRatioText: String
        let melodicCentsValue: Double?
        let tint: Color
    }

    struct Endpoint {
        let ratioText: String
        let pitchLabelText: String?
        let num: Int?
        let den: Int?
        let octave: Int?
    }

    struct ChipMetric: Identifiable {
        let id: String
        let title: String
        let valueText: String
        let meaningOneLiner: String
        let learnMore: String?
        let tint: Color
    }

    struct MetricRow: Identifiable {
        let id: String
        let label: String
        let valueText: String
        let footnote: String?
        let copyText: String
    }

    struct PrimeDelta: Identifiable {
        let id: String
        let prime: Int
        let exp: Int
        let displayText: String
        let tint: Color
    }

    let model: Model

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toastText: String? = nil
    @State private var heroExpanded = false
    @State private var tenneyExpanded = false
    @State private var melodicExpanded = false
    @State private var primesExpanded = false
    @State private var selectedHeroID: String

    init(model: Model) {
        self.model = model
        _selectedHeroID = State(initialValue: model.primaryMetricID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                heroCard
                chipStrip
                ratioCards
                atAGlance
                primeMotionMap
                contextualMeaning
            }
            .padding(20)
        }
        .background(reduceTransparency ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(alignment: .bottom) { toastView }
        .onChange(of: selectedHeroID) { _ in heroExpanded = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From \(model.from.ratioText) → \(model.to.ratioText)")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroCard: some View {
        GlassCard {
            let hero = heroChip
            VStack(alignment: .leading, spacing: 10) {
                Text(hero.title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(hero.valueText)
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                    .foregroundStyle(hero.tint)
                Text(hero.meaningOneLiner)
                    .font(.callout)
                    .foregroundStyle(.primary)
                if let learnMore = hero.learnMore {
                    DisclosureGroup("Learn more", isExpanded: $heroExpanded) {
                        Text(learnMore)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: heroExpanded)
                }
            }
            .padding(4)
        }
    }

    private var chipStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
            ForEach(model.chips) { chip in
                Button {
                    selectedHeroID = chip.id
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(chip.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        GlassChip(text: chip.valueText, tint: chip.tint)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedHeroID == chip.id ? chip.tint.opacity(0.6) : .clear, lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var ratioCards: some View {
        VStack(spacing: 12) {
            RatioCard(
                title: "Ratio I",
                ratioText: model.from.ratioText,
                numerator: model.from.num,
                denominator: model.from.den,
                pitchLabel: model.from.pitchLabelText,
                tint: model.tint,
                onCopy: { copyToPasteboard(model.from.ratioText, message: "Copied ratio") }
            )
            RatioCard(
                title: "Ratio II",
                ratioText: model.to.ratioText,
                numerator: model.to.num,
                denominator: model.to.den,
                pitchLabel: model.to.pitchLabelText,
                tint: model.tint,
                onCopy: { copyToPasteboard(model.to.ratioText, message: "Copied ratio") }
            )
        }
    }

    private var atAGlance: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("At a glance")
                    .font(.headline)
                VStack(spacing: 8) {
                    ForEach(model.rows) { row in
                        MetricRowView(row: row) {
                            copyToPasteboard(row.copyText, message: "Copied")
                        }
                    }
                }
            }
        }
    }

    private var primeMotionMap: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prime motion map")
                    .font(.headline)
                if model.primeDeltas.isEmpty {
                    Text("No prime motion between these points.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(model.primeDeltas) { delta in
                            GlassChip(text: delta.displayText, tint: delta.tint)
                        }
                    }
                }
                Text("Exponent changes in prime-factor space (Monzo delta).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                PrimeAxisDiagram()
                    .frame(height: 120)
                    .accessibilityHidden(true)
            }
        }
    }

    private var contextualMeaning: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Contextual meaning")
                    .font(.headline)
                disclosure(
                    title: "Prime-factor delta",
                    isExpanded: $primesExpanded,
                    text: primeDeltaExplanation
                )
                disclosure(
                    title: "Interval summary",
                    isExpanded: $melodicExpanded,
                    text: melodicIntervalExplanation
                )
                disclosure(
                    title: "Tenney height context",
                    isExpanded: $tenneyExpanded,
                    text: tenneyContextExplanation
                )
            }
        }
    }

    private func disclosure(title: String, isExpanded: Binding<Bool>, text: String) -> some View {
        DisclosureGroup(title, isExpanded: isExpanded) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: isExpanded.wrappedValue)
    }

    private var toastView: some View {
        Group {
            if let toastText {
                GlassChip(text: toastText, tint: model.tint)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: toastText)
    }

    private var heroChip: ChipMetric {
        model.chips.first { $0.id == selectedHeroID } ?? model.chips.first ??
        ChipMetric(
            id: "fallback",
            title: "Metric",
            valueText: "—",
            meaningOneLiner: "No metric available.",
            learnMore: nil,
            tint: model.tint
        )
    }
    private var primeDeltaExplanation: String {
        let summary = model.primeDeltas.map(\.displayText).joined(separator: ", ")
        if summary.isEmpty {
            return "From → To does not change any prime factors in the current limit."
        }
        return "From → To changes prime factors by: \(summary). Positive means multiplying by that prime; negative means dividing."
    }

    private var melodicIntervalExplanation: String {
        let centsValue = model.melodicCentsValue ?? .nan
        guard centsValue.isFinite else {
            return "This move’s interval could not be resolved from the available ratio data."
        }
        let centsText = String(format: "%+.1f¢", centsValue)
        let direction: String
        if centsValue == 0 {
            direction = "a unison"
        } else if centsValue > 0 {
            direction = "an ascending interval"
        } else {
            direction = "a descending interval"
        }
        return "This move is \(direction) of \(centsText) (To/From = \(model.melodicRatioText))."
    }

    private var tenneyContextExplanation: String {
        let tenneyRow = model.rows.first { $0.id == "tenney-height" }?.valueText ?? "H —"
        let primeSummary = model.rows.first { $0.id == "prime-motion" }?.valueText ?? "—"
        return "Tenney height summarizes the magnitude of prime-factor motion. Here: \(tenneyRow), with prime motion \(primeSummary)."
    }

    private func copyToPasteboard(_ text: String, message: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
        showToast(message)
    }

    private func showToast(_ message: String) {
        toastText = message
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                toastText = nil
            }
        }
    }
}

private struct RatioCard: View {
    let title: String
    let ratioText: String
    let numerator: Int?
    let denominator: Int?
    let pitchLabel: String?
    let tint: Color
    let onCopy: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ratioDisplay
                if let pitchLabel {
                    Text(pitchLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    if #available(iOS 16.0, macOS 13.0, *) {
                        ShareLink(item: ratioText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ratioDisplay: some View {
        if let numerator, let denominator {
            VStack(spacing: 4) {
                Text("\(numerator)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Rectangle()
                    .fill(tint.opacity(0.4))
                    .frame(height: 1)
                    .frame(maxWidth: 120)
                Text("\(denominator)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
        } else {
            Text(ratioText)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}

private struct MetricRowView: View {
    let row: DistanceDetailSheet.MetricRow
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.valueText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                if let footnote = row.footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy") { onCopy() }
        }
    }
}

private struct PrimeAxisDiagram: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            let diagonal = Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            context.stroke(diagonal, with: .color(.secondary.opacity(0.25)), lineWidth: 1)

            let labels = [("3", CGPoint(x: rect.maxX, y: rect.midY)),
                          ("5", CGPoint(x: rect.midX, y: rect.minY)),
                          ("7", CGPoint(x: rect.minX, y: rect.maxY))]
            for (text, point) in labels {
                context.draw(Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary), at: point)
            }
        }
    }
}
