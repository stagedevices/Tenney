//
//  DistanceDetailSheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/25/26.
//


import SwiftUI

// MARK: - Distance Detail Sheet

struct DistanceDetailSheet: View {

    // The sheet is a *presentation layer* over values you already compute for chips.
    // No new tuning/identity pipeline should be introduced here.
    struct Model: Identifiable {
        let id = UUID()

        // Endpoints (authoritative selected nodes)
        let from: Endpoint
        let to: Endpoint

        // Which chip was tapped (used for hero)
        let heroTitle: String
        let heroValue: String            // e.g. "+498.0¢", "3.21 Tenney", "+183.3 Hz"
        let heroSubvalue: String?        // e.g. "Interval: 4/3 ↑ (inv. 3/4)"

        // Detail grid values (prefer to pass what chips already compute)
        let directedRatioText: String
        let inversionRatioText: String
        let centsText: String
        let deltaHzText: String

        // Optional extras (only show if you already have them)
        let tenneyDistanceText: String?
        let monzoDeltaText: String?
    }

    struct Endpoint {
        let hejiPlain: String
        let hejiAttributed: AttributedString
        let ratioText: String            // e.g. "13/8"
        let hzText: String?              // e.g. "715.0Hz" (optional)
        let staffView: AnyView?          // optional mini staff glyph (prebuilt by caller)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let model: Model

    // Plumb these from existing helpers (do not duplicate pasteboard logic in multiple places).
    let copyToPasteboard: (String) -> Void

    // Optional actions (only present if caller provides them safely).
    let auditionAtoB: (() -> Void)?
    let swapAandB: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                headerRail

                heroCard

                detailGrid

                if model.tenneyDistanceText != nil || model.monzoDeltaText != nil {
                    moreSection
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            footerActions
        }
        .background(reduceTransparency ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header Rail

    private var headerRail: some View {
        HStack(spacing: 10) {
            endpointCapsule(title: "A", ep: model.from)

            VStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let swap = swapAandB {
                    Button(action: swap) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption.weight(.semibold))
                            .padding(8)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Swap")
                }
            }
            .frame(minWidth: 34)

            endpointCapsule(title: "B", ep: model.to)
        }
    }

    private func endpointCapsule(title: String, ep: Model.Endpoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())

                Spacer(minLength: 0)
            }

            // HEJI primary (typographic)
            Text(ep.hejiAttributed)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.7)

            // ratio + tiny Hz secondary (optional)
            HStack(spacing: 8) {
                Text(ep.ratioText)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(.primary)

                if let hz = ep.hzText {
                    Text(hz)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let staff = ep.staffView {
                staff
                    .opacity(0.9)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button("Copy HEJI") { copyToPasteboard(ep.hejiPlain) }
            Button("Copy ratio") { copyToPasteboard(ep.ratioText) }
            if let hz = ep.hzText { Button("Copy Hz") { copyToPasteboard(hz) } }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.heroTitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(model.heroValue)
                .font(.system(size: 44, weight: .bold, design: .default).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let sub = model.heroSubvalue {
                Text(sub)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Button("Copy summary") { copyToPasteboard(summaryText) }
        }
    }

    // MARK: - Detail Grid

    private var detailGrid: some View {
        let cols: [GridItem] = [
            .init(.flexible(minimum: 120), spacing: 12),
            .init(.flexible(minimum: 120), spacing: 12)
        ]

        return LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
            metricCard(label: "Directed ratio (A→B)", value: model.directedRatioText, copy: model.directedRatioText)
            metricCard(label: "Inversion", value: model.inversionRatioText, copy: model.inversionRatioText)
            metricCard(label: "Cents", value: model.centsText, copy: model.centsText)
            metricCard(label: "Δf", value: model.deltaHzText, copy: model.deltaHzText)
        }
    }

    private func metricCard(label: String, value: String, copy: String) -> some View {
        Button {
            copyToPasteboard(copy)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button("Copy") { copyToPasteboard(copy) }
        }
    }

    // MARK: - More

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                if let tenney = model.tenneyDistanceText {
                    labeledRow("Tenney distance", tenney, copy: tenney)
                }
                if let monzo = model.monzoDeltaText {
                    labeledRow("Monzo Δ", monzo, copy: monzo)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private func labeledRow(_ label: String, _ value: String, copy: String) -> some View {
        Button {
            copyToPasteboard(copy)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Copy") { copyToPasteboard(copy) } }
    }

    // MARK: - Footer

    private var footerActions: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.22)

            HStack(spacing: 14) {

                Button {
                    copyToPasteboard(summaryText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy summary")

                if #available(iOS 16.0, macOS 13.0, *) {
                    ShareLink(item: summaryText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("Share")
                }

                if let audition = auditionAtoB {
                    Button(action: audition) {
                        Label("Audition", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Audition A to B")
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(reduceTransparency ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
    }

    // MARK: - Summary

    private var summaryText: String {
        var lines: [String] = []
        lines.append("A: \(model.from.hejiPlain) (\(model.from.ratioText)\(model.from.hzText.map { ", \($0)" } ?? ""))")
        lines.append("B: \(model.to.hejiPlain) (\(model.to.ratioText)\(model.to.hzText.map { ", \($0)" } ?? ""))")
        lines.append("\(model.heroTitle): \(model.heroValue)")
        lines.append("Directed ratio: \(model.directedRatioText)")
        lines.append("Inversion: \(model.inversionRatioText)")
        lines.append("Cents: \(model.centsText)")
        lines.append("Δf: \(model.deltaHzText)")
        if let tenney = model.tenneyDistanceText { lines.append("Tenney: \(tenney)") }
        if let monzo = model.monzoDeltaText { lines.append("Monzo Δ: \(monzo)") }
        return lines.joined(separator: "\n")
    }
}
