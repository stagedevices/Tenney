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
        let referenceHz: Double?
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

    private enum SheetTab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case meaning = "Meaning"
        case primes = "Primes"

        var id: String { rawValue }
    }

    let model: Model

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: SheetTab = .summary
    @State private var toastText: String? = nil
    @State private var heroExpanded = false
    @State private var tenneyExpanded = false
    @State private var melodicExpanded = false
    @State private var centsExpanded = false
    @State private var directionExpanded = false
    @State private var referenceText: String
    @State private var referenceHz: Double?

    init(model: Model) {
        self.model = model
        let initialHz = model.referenceHz.map { String(format: "%.2f", $0) } ?? ""
        _referenceText = State(initialValue: initialHz)
        _referenceHz = State(initialValue: model.referenceHz)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                heroCard
                chipStrip

                switch tab {
                case .summary:
                    ratioCards
                    atAGlance
                    referencePanel
                case .meaning:
                    whatThisMeans
                case .primes:
                    primeMotionMap
                }
            }
            .padding(20)
        }
        .background(reduceTransparency ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(alignment: .bottom) { toastView }
        .onChange(of: referenceText) { _ in updateReferenceHz() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From \(model.from.ratioText) → \(model.to.ratioText)")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("View", selection: $tab) {
                ForEach(SheetTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(chip.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    GlassChip(text: chip.valueText, tint: chip.tint)
                }
            }
        }
    }

    private var ratioCards: some View {
        VStack(spacing: 12) {
            RatioCard(
                title: "Ratio I",
                ratioText: model.from.ratioText,
                pitchLabel: model.from.pitchLabelText,
                tint: model.tint,
                onCopy: { copyToPasteboard(model.from.ratioText, message: "Copied ratio") }
            )
            RatioCard(
                title: "Ratio II",
                ratioText: model.to.ratioText,
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
                    ForEach(resolvedRows) { row in
                        MetricRowView(row: row) {
                            copyToPasteboard(row.copyText, message: "Copied")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var referencePanel: some View {
        if shouldShowReferencePanel {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reference")
                        .font(.headline)
                    Text("Adjust the root frequency used for Hz values. This doesn’t change the lattice or selection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Hz", text: $referenceText)
                        .textFieldStyle(.roundedBorder)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    HStack(spacing: 8) {
                        ForEach([415, 432, 440], id: \.self) { value in
                            Button("\(value)") {
                                referenceText = String(format: "%d", value)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if !canComputeHzValues {
                        Text("Hz values unavailable without ratio components.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    private var whatThisMeans: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("What this means")
                    .font(.headline)
                disclosure(
                    title: "What is Tenney height?",
                    isExpanded: $tenneyExpanded,
                    text: "Tenney height sums the absolute prime-exponent changes, weighted by log₂(prime). It’s a compact proxy for harmonic complexity."
                )
                disclosure(
                    title: "What is melodic distance?",
                    isExpanded: $melodicExpanded,
                    text: "The melodic ratio is the exact interval from From → To. It preserves direction: ratios below 1 imply descending motion."
                )
                disclosure(
                    title: "How are cents computed?",
                    isExpanded: $centsExpanded,
                    text: "Cents are 1200 × log₂(ratio). Signed cents match the direction of the melodic ratio."
                )
                disclosure(
                    title: "How direction works",
                    isExpanded: $directionExpanded,
                    text: "All rows are ordered. If you swap From and To, signs and ratios reverse."
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
        model.chips.first { $0.id == model.primaryMetricID } ?? model.chips.first ??
        ChipMetric(
            id: "fallback",
            title: "Metric",
            valueText: "—",
            meaningOneLiner: "No metric available.",
            learnMore: nil,
            tint: model.tint
        )
    }

    private var resolvedRows: [MetricRow] {
        model.rows.map { row in
            guard row.id == "freq-delta" else { return row }
            guard let referenceHz, canComputeHzValues, let delta = frequencyDeltaText(referenceHz) else {
                return MetricRow(
                    id: row.id,
                    label: row.label,
                    valueText: "—",
                    footnote: "Needs reference pitch",
                    copyText: "—"
                )
            }
            return MetricRow(
                id: row.id,
                label: row.label,
                valueText: delta.text,
                footnote: nil,
                copyText: delta.copy
            )
        }
    }

    private var shouldShowReferencePanel: Bool {
        model.rows.contains { $0.id == "freq-delta" }
    }

    private var canComputeHzValues: Bool {
        model.from.num != nil && model.from.den != nil && model.to.num != nil && model.to.den != nil
    }

    private func frequencyDeltaText(_ reference: Double) -> (text: String, copy: String)? {
        guard let fromHz = endpointHz(model.from, reference: reference),
              let toHz = endpointHz(model.to, reference: reference) else { return nil }
        let delta = toHz - fromHz
        let text = String(format: "%+.2f Hz", delta)
        return (text, text)
    }

    private func endpointHz(_ endpoint: Endpoint, reference: Double) -> Double? {
        guard let num = endpoint.num, let den = endpoint.den else { return nil }
        let octave = endpoint.octave ?? 0
        let hz = RatioMath.hz(rootHz: reference, p: num, q: den, octave: octave, fold: false)
        return hz.isFinite ? hz : nil
    }

    private func updateReferenceHz() {
        let sanitized = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(sanitized), value > 0 else {
            referenceHz = nil
            return
        }
        referenceHz = value
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
    let pitchLabel: String?
    let tint: Color
    let onCopy: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(ratioText)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
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
