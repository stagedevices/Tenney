//
//  LockField.swift
//  Tenney
//
//  Created by OpenAI on 2025-02-17.
//

import SwiftUI

struct LockFieldMatchedGeometry {
    let namespace: Namespace.ID
    let backgroundID: String
    let ratioID: String
}

struct LockFieldPill: View {
    @Environment(\.tenneyTheme) private var theme

    enum Size {
        case compact
        case large

        var maxWidth: CGFloat {
#if os(macOS) || targetEnvironment(macCatalyst)
            switch self {
            case .compact: return 160
            case .large: return 160
            }
#else
            switch self {
            case .compact: return 120
            case .large: return 120
            }
#endif
        }

        var font: Font {
            switch self {
            case .compact: return .footnote.weight(.semibold)
            case .large: return .footnote.weight(.semibold)
            }
        }

        var iconFont: Font {
            switch self {
            case .compact: return .footnote.weight(.semibold)
            case .large: return .footnote.weight(.semibold)
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .compact: return EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
            case .large: return EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
            }
        }

        var minHeight: CGFloat {
            switch self {
            case .compact: return 34
            case .large: return 34
            }
        }

        var caretHeight: CGFloat {
            switch self {
            case .compact: return 16
            case .large: return 16
            }
        }
    }

    let size: Size
    let isLocked: Bool
    let displayText: String?
    let tint: Color
    let placeholderShort: String
    let placeholderLong: String
    let matchedGeometry: LockFieldMatchedGeometry?
    let isExpanded: Bool
    let action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var caretPulse = false

    init(
        size: Size,
        isLocked: Bool,
        displayText: String?,
        tint: Color,
        // lock target pill
        placeholderShort: String = "",
        placeholderLong: String = "",
        matchedGeometry: LockFieldMatchedGeometry? = nil,
        isExpanded: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.size = size
        self.isLocked = isLocked
        self.displayText = displayText
        self.tint = tint
        self.placeholderShort = placeholderShort
        self.placeholderLong = placeholderLong
        self.matchedGeometry = matchedGeometry
        self.isExpanded = isExpanded
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                lockFieldBody
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
#if os(macOS) || targetEnvironment(macCatalyst)
            .help("Edit Lock (⌘L)")
#endif
        } else {
            lockFieldBody
        }
    }

    private var lockFieldBody: some View {
        ViewThatFits(in: .horizontal) {
            pillSingleLine(showTag: isLocked)
            pillSingleLine(showTag: false)
            pillTwoLine
        }
        .padding(size.padding)
        .frame(minHeight: size.minHeight)
        .frame(maxWidth: size.maxWidth)
        .background(pillBackground)
        .overlay(pillStroke)
          .shadow(color: isLocked ? tint.opacity(theme.isDark ? 0.28 : 0.18) : .clear, radius: 8, y: 4)
    }

    private var pillBackground: some View {
        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(tint.opacity(isLocked ? 0.32 : 0.18)), in: Capsule())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(tint.opacity(isLocked ? 0.22 : 0.12))
                    )
            }
        }
        .applyMatchedGeometry(matchedGeometry, reduceMotion: reduceMotion, id: \.backgroundID)
    }

    private var pillStroke: some View {
        Capsule()
            .strokeBorder(tint.opacity(isLocked ? 0.7 : 0.32), lineWidth: isLocked ? 1.4 : 1)
    }

    private func pillSingleLine(showTag: Bool) -> some View {
        HStack(spacing: 8) {
            lockIcon
            ratioField
            if showTag && isLocked {
                lockTag
            }
            if action != nil {
                editGlyph
            }
        }
    }

    private var pillTwoLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                lockIcon
                Text(isLocked ? "LOCK" : "TARGET")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if action != nil {
                    editGlyph
                }
            }
            ratioField
        }
    }

    private var lockIcon: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock")
            .font(size.iconFont)
            .foregroundStyle(isLocked ? .primary : .secondary)
            .padding(6)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .strokeBorder(tint.opacity(isLocked ? 0.5 : 0.25), lineWidth: 1)
                    )
            )
            .shadow(color: isLocked ? tint.opacity(0.25) : .clear, radius: 3, y: 2)
    }

    private var editGlyph: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(size.iconFont)
            .foregroundStyle(.secondary)
            .padding(6)
            .background(
                Circle()
                    .fill(.thinMaterial)
            )
    }

    private var ratioField: some View {
        let trimmed = displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratio = (trimmed?.isEmpty == false) ? trimmed : nil
        return LockRatioField(
            ratioText: ratio,
            placeholderShort: placeholderShort,
            placeholderLong: placeholderLong,
            font: size.font,
            tint: tint,
            caretHeight: size.caretHeight,
            caretPulse: $caretPulse
        )
        .applyMatchedGeometry(matchedGeometry, reduceMotion: reduceMotion, id: \.ratioID)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                caretPulse = true
            }
        }
    }

    private var lockTag: some View {
        Text("LOCK")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tint.opacity(theme.isDark ? 0.28 : 0.18))
            )
    }
}

struct LockPill: View {
    let isLocked: Bool
    let displayText: String?
    let tint: Color
    let width: CGFloat
    let matchedGeometry: LockFieldMatchedGeometry?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                ratioField
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, iconSlotWidth)

                HStack {
                    lockIcon
                        .frame(width: iconSlotWidth, height: iconSlotWidth)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: iconSlotWidth, height: iconSlotWidth)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: width, height: 34)
            .background(pillBackground)
            .overlay(pillStroke)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private var lockIcon: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isLocked ? .primary : .secondary)
            .padding(5)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .strokeBorder(tint.opacity(isLocked ? 0.5 : 0.25), lineWidth: 1)
                    )
            )
            .shadow(color: isLocked ? tint.opacity(0.25) : .clear, radius: 3, y: 2)
    }

    private var iconSlotWidth: CGFloat { 24 }

    private var ratioField: some View {
        let trimmed = displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratio = (trimmed?.isEmpty == false) ? trimmed : nil
        let text = ratio ?? "Lock ratio"
        let color: Color = ratio == nil ? .secondary : .primary

        return ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
        }
        .mask(FadeEdgeMask())
        .applyMatchedGeometry(matchedGeometry, reduceMotion: reduceMotion, id: \.ratioID)
    }

    private var pillBackground: some View {
        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(tint.opacity(isLocked ? 0.32 : 0.18)), in: Capsule())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(tint.opacity(isLocked ? 0.22 : 0.12))
                    )
            }
        }
        .applyMatchedGeometry(matchedGeometry, reduceMotion: reduceMotion, id: \.backgroundID)
    }

    private var pillStroke: some View {
        Capsule()
            .strokeBorder(tint.opacity(isLocked ? 0.7 : 0.32), lineWidth: isLocked ? 1.4 : 1)
    }
}

private struct LockRatioField: View {
    let ratioText: String?
    let placeholderShort: String
    let placeholderLong: String
    let font: Font
    let tint: Color
    let caretHeight: CGFloat
    @Binding var caretPulse: Bool

    var body: some View {
        if let ratioText {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(ratioText)
                    .font(font.monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
            }
            .mask(FadeEdgeMask())
        } else {
            HStack(spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    Text(placeholderLong)
                    Text(placeholderShort)
                }
                .font(font.monospacedDigit())
                .foregroundStyle(.secondary)
                Rectangle()
                    .fill(tint.opacity(0.7))
                    .frame(width: 2, height: caretHeight)
                    .opacity(caretPulse ? 0.35 : 0.75)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct FadeEdgeMask: View {
    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fade = min(18, width * 0.18)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: fade / width),
                    .init(color: .black, location: 1 - (fade / width)),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private extension View {
    func applyMatchedGeometry(
        _ matched: LockFieldMatchedGeometry?,
        reduceMotion: Bool,
        id: KeyPath<LockFieldMatchedGeometry, String>
    ) -> some View {
        guard let matched, !reduceMotion else { return AnyView(self) }
        return AnyView(self.matchedGeometryEffect(id: matched[keyPath: id], in: matched.namespace))
    }
}
