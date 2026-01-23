//
//  TenneyLimitA11yViews.swift
//  Tenney
//

import SwiftUI

struct TenneyLimitGlyph: View {
    let bucket: TenneyLimitBucket
    let fill: Color
    let stroke: Color
    let strokeWidth: CGFloat
    let showPattern: Bool

    var body: some View {
        LimitShape(bucket: bucket)
            .fill(fill)
            .overlay(patternOverlay)
            .overlay(
                LimitShape(bucket: bucket)
                    .stroke(stroke, lineWidth: strokeWidth)
            )
            .overlay(innerRingOverlay)
    }
    @ViewBuilder
    private var patternOverlay: some View {
        if showPattern, let kind = TenneyLimitPattern.kind(for: bucket) {
            switch kind {
            case .stroke:
                LimitPatternShape(bucket: bucket)
                    .stroke(stroke.opacity(0.65), lineWidth: max(0.8, strokeWidth * 0.6))
                    .clipShape(LimitShape(bucket: bucket))
            case .dots:
                LimitPatternShape(bucket: bucket)
                    .fill(stroke.opacity(0.65))
                    .clipShape(LimitShape(bucket: bucket))
            }
        } else {
            EmptyView()
        }
    }


    @ViewBuilder
    private var innerRingOverlay: some View {
        if showPattern, bucket.rawValue >= TenneyLimitBucket.limit17.rawValue {
            LimitShape(bucket: bucket)
                .stroke(stroke.opacity(0.75), lineWidth: max(1.2, strokeWidth))
                .overlay(
                    LimitShape(bucket: bucket)
                        .fill(fill.opacity(0.35))
                        .scaleEffect(0.62)
                )
                .clipShape(LimitShape(bucket: bucket))
        } else {
            EmptyView()
        }
    }
}

private struct LimitPatternShape: Shape {
    let bucket: TenneyLimitBucket

    func path(in rect: CGRect) -> Path {
        TenneyLimitPattern.path(bucket: bucket, in: rect) ?? Path()
    }
}

struct TenneyPrimeLimitChip: View {
    let prime: Int
    let isOn: Bool
    let tint: Color
    let encoding: TenneyA11yEncoding
    let action: () -> Void

    var body: some View {
        let bucket = bucket(forPrime: prime)
        let stroke = Color.primary.opacity(encoding.strokeContrast)
        let fill = isOn ? tint.opacity(0.22) : Color.clear
        let lineWidth: CGFloat = isOn ? 2.0 : 1.0

        Button(action: action) {
            HStack(spacing: 6) {
                TenneyLimitGlyph(
                    bucket: bucket,
                    fill: fill,
                    stroke: stroke,
                    strokeWidth: lineWidth,
                    showPattern: isOn && encoding.limitSymbolStyle == .shapeAndHatch
                )
                .frame(width: 14, height: 14)

                Text("\(prime)")
                    .font(.caption2.weight(isOn ? .semibold : .regular))

                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stroke)
                }
            }
            .foregroundStyle(isOn ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(stroke.opacity(isOn ? 0.75 : 0.35), lineWidth: lineWidth)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("Prime limit \(prime). Shape \(bucket.shapeName). \(isOn ? "Enabled" : "Disabled").")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct TenneyPrimeLimitBadge: View {
    let prime: Int
    let tint: Color
    let encoding: TenneyA11yEncoding

    var body: some View {
        let bucket = bucket(forPrime: prime)
        let stroke = Color.primary.opacity(encoding.strokeContrast)

        HStack(spacing: 4) {
            TenneyLimitGlyph(
                bucket: bucket,
                fill: tint.opacity(0.20),
                stroke: stroke,
                strokeWidth: 1.2,
                showPattern: encoding.limitSymbolStyle == .shapeAndHatch
            )
            .frame(width: 12, height: 12)

            Text("\(prime)")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(stroke.opacity(0.25), lineWidth: 1)
        )
        .accessibilityLabel("Prime limit \(prime). Shape \(bucket.shapeName).")
    }
}
