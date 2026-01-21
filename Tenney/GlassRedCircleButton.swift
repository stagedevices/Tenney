import SwiftUI

struct GlassRedCircleButton: View {
    let isSelecting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelecting ? "chevron.left" : "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(glassBackground)
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tint(.red)
        .accessibilityLabel(isSelecting ? "Back" : "Close")
    }

    @ViewBuilder
    private var glassBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }
}
