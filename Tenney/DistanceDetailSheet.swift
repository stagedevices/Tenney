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
        let monzoDelta: [Int:Int]
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
    @State private var highlightedPrime: Int? = nil

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
                                .contentShape(Capsule())
                                .onTapGesture { toggleHighlight(for: delta.prime) }
                                .accessibilityAddTraits(highlightedPrime == delta.prime ? .isSelected : [])
                        }
                    }
                }
                Text("Exponent changes in prime-factor space (Monzo delta).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                PrimeMotionDiagram(
                    monzoDelta: model.monzoDelta,
                    primeDeltas: model.primeDeltas,
                    highlightedPrime: highlightedPrime,
                    reduceMotion: reduceMotion
                )
                .frame(height: 150)
                PrimeLiftStrip(
                    primeDeltas: model.primeDeltas,
                    highlightedPrime: highlightedPrime
                )
                primeInterpretationLine
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

    private func toggleHighlight(for prime: Int) {
        if highlightedPrime == prime {
            highlightedPrime = nil
        } else {
            highlightedPrime = prime
        }
    }

    private var primeInterpretationLine: some View {
        Text(primeInterpretationText)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var primeInterpretationText: String {
        let e3 = model.monzoDelta[3, default: 0]
        let e5 = model.monzoDelta[5, default: 0]
        let absE3 = abs(e3)
        let absE5 = abs(e5)
        let dominantText: String

        if absE3 == 0 && absE5 == 0 {
            dominantText = "No 3/5 motion"
        } else if absE3 > absE5 {
            dominantText = "Mostly a \(signedValueText(e3))-in-3 move (fifths)"
        } else if absE5 > absE3 {
            dominantText = "Mostly a \(signedValueText(e5))-in-5 move (thirds)"
        } else {
            dominantText = "Mostly diagonal (\(signedValueText(e3)) in 3, \(signedValueText(e5)) in 5)"
        }

        if let smallestHigherPrime = model.monzoDelta.keys.filter({ $0 >= 7 }).sorted().first {
            return "\(dominantText), with \(smallestHigherPrime)-content."
        }
        return "\(dominantText)."
    }

    private func signedValueText(_ value: Int) -> String {
        if value == 0 { return "0" }
        return value > 0 ? "+\(value)" : "−\(abs(value))"
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

private struct PrimeMotionDiagram: View {
    let monzoDelta: [Int:Int]
    let primeDeltas: [DistanceDetailSheet.PrimeDelta]
    let highlightedPrime: Int?
    let reduceMotion: Bool

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @State private var showTooltip = false

    var body: some View {
        let tooltipText = "Δe₃=\(signedValueText(e3)), Δe₅=\(signedValueText(e5)), out-of-plane=\(outOfPlaneText)"
        let usePopover = shouldUsePopover

        ZStack {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 16)
                let scale = min(rect.width, rect.height) / CGFloat(2 * m)
                let origin = CGPoint(x: rect.midX, y: rect.midY)

                func point(x: Int, y: Int) -> CGPoint {
                    CGPoint(
                        x: origin.x + CGFloat(x) * scale,
                        y: origin.y - CGFloat(y) * scale
                    )
                }

                var gridPath = Path()
                for i in -m...m {
                    let start = point(x: i, y: -m)
                    let end = point(x: i, y: m)
                    gridPath.move(to: start)
                    gridPath.addLine(to: end)

                    let hStart = point(x: -m, y: i)
                    let hEnd = point(x: m, y: i)
                    gridPath.move(to: hStart)
                    gridPath.addLine(to: hEnd)
                }

                let dashed = StrokeStyle(lineWidth: 1, dash: [4, 4])
                context.stroke(gridPath, with: .color(.secondary.opacity(0.2)), style: dashed)

                var axisPath = Path()
                axisPath.move(to: point(x: -m, y: 0))
                axisPath.addLine(to: point(x: m, y: 0))
                axisPath.move(to: point(x: 0, y: -m))
                axisPath.addLine(to: point(x: 0, y: m))
                context.stroke(axisPath, with: .color(.secondary.opacity(0.55)), lineWidth: 1.2)

                let originDot = Path(ellipseIn: CGRect(x: origin.x - 2.5, y: origin.y - 2.5, width: 5, height: 5))
                context.fill(originDot, with: .color(.primary.opacity(0.7)))
                context.draw(Text("0").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: origin.x + 6, y: origin.y + 8))

                let tickFont = Font.caption2.weight(.semibold)
                let tickOffset: CGFloat = 10
                context.draw(Text(signedValueText(-m)).font(tickFont).foregroundStyle(.secondary),
                             at: CGPoint(x: point(x: -m, y: 0).x, y: origin.y + tickOffset))
                context.draw(Text(signedValueText(m)).font(tickFont).foregroundStyle(.secondary),
                             at: CGPoint(x: point(x: m, y: 0).x, y: origin.y + tickOffset))
                context.draw(Text(signedValueText(m)).font(tickFont).foregroundStyle(.secondary),
                             at: CGPoint(x: origin.x + tickOffset, y: point(x: 0, y: m).y))
                context.draw(Text(signedValueText(-m)).font(tickFont).foregroundStyle(.secondary),
                             at: CGPoint(x: origin.x + tickOffset, y: point(x: 0, y: -m).y))

                let endPoint = point(x: e3, y: e5)
                var arrowPath = Path()
                arrowPath.move(to: origin)
                arrowPath.addLine(to: endPoint)
                context.stroke(arrowPath, with: .color(.primary.opacity(0.8)), lineWidth: 2)

                if endPoint != origin {
                    let dx = endPoint.x - origin.x
                    let dy = endPoint.y - origin.y
                    let angle = atan2(dy, dx)
                    let headLength: CGFloat = 8
                    let headAngle: CGFloat = .pi / 7
                    let p1 = CGPoint(
                        x: endPoint.x - headLength * cos(angle - headAngle),
                        y: endPoint.y - headLength * sin(angle - headAngle)
                    )
                    let p2 = CGPoint(
                        x: endPoint.x - headLength * cos(angle + headAngle),
                        y: endPoint.y - headLength * sin(angle + headAngle)
                    )
                    var head = Path()
                    head.move(to: endPoint)
                    head.addLine(to: p1)
                    head.move(to: endPoint)
                    head.addLine(to: p2)
                    context.stroke(head, with: .color(.primary.opacity(0.8)), lineWidth: 2)
                }

                if highlightedPrime == 3 {
                    let componentEnd = point(x: e3, y: 0)
                    var component = Path()
                    component.move(to: origin)
                    component.addLine(to: componentEnd)
                    context.stroke(component, with: .color(highlightTint(for: 3).opacity(0.8)), lineWidth: 2.4)

                    var projection = Path()
                    projection.move(to: endPoint)
                    projection.addLine(to: componentEnd)
                    context.stroke(projection, with: .color(highlightTint(for: 3).opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else if highlightedPrime == 5 {
                    let componentEnd = point(x: 0, y: e5)
                    var component = Path()
                    component.move(to: origin)
                    component.addLine(to: componentEnd)
                    context.stroke(component, with: .color(highlightTint(for: 5).opacity(0.8)), lineWidth: 2.4)

                    var projection = Path()
                    projection.move(to: endPoint)
                    projection.addLine(to: componentEnd)
                    context.stroke(projection, with: .color(highlightTint(for: 5).opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                let endpointLabel = "\(signedValueText(e3)), \(signedValueText(-e5))"
                let directionHint = directionHintText
                let labelText = Text("(\(endpointLabel)) \(directionHint)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                context.draw(
                    labelText,
                    at: CGPoint(x: endPoint.x + 8, y: endPoint.y - 12),
                    anchor: .leading
                )
            }
            .accessibilityHidden(true)
            .contentShape(Rectangle())
            .onLongPressGesture { showTooltip.toggle() }

            if !usePopover, showTooltip {
                MotionTooltip(text: tooltipText)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabelText))
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: e3)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: e5)
        .modifier(PrimeMotionPopover(isPresented: $showTooltip, enabled: usePopover, text: tooltipText))
    }

    private var e3: Int { monzoDelta[3, default: 0] }
    private var e5: Int { monzoDelta[5, default: 0] }
    private var m: Int { max(abs(e3), abs(e5), 1) }

    private var directionHintText: String {
        let absE3 = abs(e3)
        let absE5 = abs(e5)
        if absE3 > absE5 { return "toward fifths" }
        if absE5 > absE3 { return "toward thirds" }
        return "diagonal"
    }

    private var outOfPlaneText: String {
        String(format: "%.2f", outOfPlaneMagnitude)
    }

    private var outOfPlaneMagnitude: Double {
        let sum = monzoDelta.keys
            .filter { $0 >= 7 }
            .reduce(0.0) { partial, prime in
                let exp = monzoDelta[prime, default: 0]
                return partial + Double(exp * exp)
            }
        return sqrt(sum)
    }

    private var accessibilityLabelText: String {
        let parts = monzoDelta.keys.sorted().compactMap { prime -> String? in
            let exp = monzoDelta[prime, default: 0]
            guard exp != 0 else { return nil }
            return "\(signedValueText(exp)) in \(prime)"
        }
        let core = parts.isEmpty ? "Prime motion: none." : "Prime motion: \(parts.joined(separator: ", "))."
        if outOfPlaneMagnitude > 0 {
            return "\(core) Out-of-plane \(outOfPlaneText)."
        }
        return core
    }

    private var shouldUsePopover: Bool {
#if os(iOS)
        return horizontalSizeClass == .regular
#else
        return true
#endif
    }

    private func highlightTint(for prime: Int) -> Color {
        primeDeltas.first(where: { $0.prime == prime })?.tint ?? .accentColor
    }

    private func signedValueText(_ value: Int) -> String {
        if value == 0 { return "0" }
        return value > 0 ? "+\(value)" : "−\(abs(value))"
    }
}

private struct PrimeLiftStrip: View {
    let primeDeltas: [DistanceDetailSheet.PrimeDelta]
    let highlightedPrime: Int?

    var body: some View {
        if !higherPrimes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(higherPrimes) { delta in
                        let magnitude = abs(delta.exp)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(delta.tint.opacity(barOpacity(for: delta.prime)))
                                .frame(width: 16, height: barHeight(for: magnitude))
                                .scaleEffect(highlightedPrime == delta.prime ? 1.08 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: highlightedPrime)
                            Text("\(delta.prime)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                    }
                }
                Text("Out-of-plane: \(outOfPlaneText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var higherPrimes: [DistanceDetailSheet.PrimeDelta] {
        primeDeltas.filter { $0.prime >= 7 }
    }

    private var maxMagnitude: Int {
        max(higherPrimes.map { abs($0.exp) }.max() ?? 0, 1)
    }

    private func barHeight(for magnitude: Int) -> CGFloat {
        let maxHeight: CGFloat = 26
        return maxHeight * CGFloat(magnitude) / CGFloat(maxMagnitude)
    }

    private func barOpacity(for prime: Int) -> Double {
        if highlightedPrime == nil || highlightedPrime == prime {
            return 0.9
        }
        return 0.5
    }

    private var outOfPlaneText: String {
        let sum = higherPrimes.reduce(0.0) { partial, delta in
            partial + Double(delta.exp * delta.exp)
        }
        return String(format: "%.2f", sqrt(sum))
    }
}

private struct MotionTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary.opacity(0.4), lineWidth: 1)
                    )
            )
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
    }
}

private struct PrimeMotionPopover: ViewModifier {
    @Binding var isPresented: Bool
    let enabled: Bool
    let text: String

    func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 16.0, macOS 13.0, *) {
                content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    MotionTooltip(text: text)
                        .frame(maxWidth: 220)
                        .padding(8)
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}
