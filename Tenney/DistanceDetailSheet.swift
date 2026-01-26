import SwiftUI

enum DistanceDetailMetric: Hashable, Equatable {
    case tenneyTotal
    case tenneyPrime(prime: Int, exp: Int)

    var id: String {
        switch self {
        case .tenneyTotal:
            return "tenney.total"
        case .tenneyPrime(let prime, let exp):
            return "tenney.prime.\(prime).\(exp)"
        }
    }
}

struct DistanceDetailPitchSummary: Equatable {
    let hejiLabel: AttributedString
    let hejiPlain: String
    let ratioText: String
    let hzText: String
    let hzValue: Double
}

struct DistanceDetailItem: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let footnote: String?
    let copyText: String
    let shareText: String
    let usesMonospaced: Bool
}

struct DistanceDetailPart: Identifiable, Equatable {
    let prime: Int
    let label: String
    let tint: Color

    var id: Int { prime }
}

struct DistanceDetailPresentation: Identifiable, Equatable {
    let fromKey: LatticeStore.SelectionKey
    let toKey: LatticeStore.SelectionKey
    let metric: DistanceDetailMetric
    let pitchA: DistanceDetailPitchSummary
    let pitchB: DistanceDetailPitchSummary
    let heroTitle: String
    let heroValue: String
    let heroSubvalue: String?
    let detailItems: [DistanceDetailItem]
    let tenneyParts: [DistanceDetailPart]
    let summaryText: String

    var id: String {
        "\(fromKey.stableID)->\(toKey.stableID)-\(metric.id)"
    }
}

struct DistanceDetailSheet: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let presentation: DistanceDetailPresentation

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerRail
                heroCard
                detailGrid
                if !presentation.tenneyParts.isEmpty {
                    partsRow
                }
                footerActions
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .presentationBackground(reduceTransparency ? .thinMaterial : .ultraThinMaterial)
    }

    private var headerRail: some View {
        HStack(spacing: 12) {
            pitchCapsule(title: "A", pitch: presentation.pitchA)

            Image(systemName: "arrow.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            pitchCapsule(title: "B", pitch: presentation.pitchB)
        }
    }

    private func pitchCapsule(title: String, pitch: DistanceDetailPitchSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pitch.hejiLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(pitch.ratioText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)

            Text(pitch.hzText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(capsuleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pitch \(title), \(pitch.hejiPlain), ratio \(pitch.ratioText), \(pitch.hzText)")
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.heroTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(presentation.heroValue)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let subvalue = presentation.heroSubvalue {
                Text(subvalue)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private var detailGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(presentation.detailItems) { item in
                DistanceDetailCard(item: item)
            }
        }
    }

    private var partsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prime deltas")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(presentation.tenneyParts) { part in
                    Text(part.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(part.tint.opacity(0.18), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(part.tint.opacity(0.35), lineWidth: 1)
                        )
                }
            }
        }
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button {
                copyToPasteboard(presentation.summaryText)
            } label: {
                Label("Copy summary", systemImage: "doc.on.doc")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)

            ShareLink(item: presentation.summaryText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color.clear.background(.thinMaterial)
        } else {
            Color.clear.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var capsuleBackground: some View {
        if reduceTransparency {
            Color.clear.background(.thinMaterial)
        } else {
            Color.clear.background(.ultraThinMaterial)
        }
    }

    private func copyToPasteboard(_ text: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }
}

private struct DistanceDetailCard: View {
    let item: DistanceDetailItem
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.value)
                .font(item.usesMonospaced ? .callout.monospacedDigit().weight(.semibold) : .callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let footnote = item.footnote {
                Text(footnote)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            reduceTransparency ? .thinMaterial : .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            copyToPasteboard(item.copyText)
        }
        .contextMenu {
            Button("Copy") { copyToPasteboard(item.copyText) }
            ShareLink(item: item.shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + spacing > maxWidth {
                maxRowWidth = max(maxRowWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }

        maxRowWidth = max(maxRowWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(maxWidth, maxRowWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension LatticeStore.SelectionKey {
    var stableID: String {
        switch self {
        case .plane(let c):
            return "plane:\(c.e3):\(c.e5)"
        case .ghost(let g):
            return "ghost:\(g.p):\(g.e3):\(g.e5):\(g.eP)"
        }
    }
}
