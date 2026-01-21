import SwiftUI

enum PremiumModalSurface {
    static let baseFill = Color(.secondarySystemBackground)
    static let background = baseFill
    static let barBackground = Color.clear

    static var subtleShadow: some View {
        Color.black.opacity(0.08)
    }

    static func cardSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(background)
            .overlay(glassOverlay(in: shape))
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    static var barOverlayMaterial: some View {
        if #available(iOS 26.0, *) {
            Color.clear
        } else {
            Rectangle().fill(.ultraThinMaterial).opacity(0.35)
        }
    }

    @ViewBuilder
    static func glassOverlay<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial).opacity(0.65)
        }
    }
}
