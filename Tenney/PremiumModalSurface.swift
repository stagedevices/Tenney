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
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
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
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            shape.fill(.ultraThinMaterial).opacity(0.65)
        }
    }
        @ViewBuilder
        static func barGlass<S: Shape>(in shape: S) -> some View {
            if #available(iOS 26.0, *) {
                ZStack {
                            // glass MUST be applied to a clear source view; `shape` defines the region.
                            Color.clear
                                .glassEffect(.regular, in: shape)
                
                            // debug tint (keep while verifying; remove after)
                            shape.fill(Color.green.opacity(0.08))
                
                            // edge cue
                            shape.stroke(Color.white.opacity(0.14), lineWidth: 0.75)
                        }
                        .compositingGroup()
            } else {
                shape.fill(.ultraThinMaterial).opacity(0.75)
            }
        }
}
