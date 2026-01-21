import SwiftUI

struct GlassRedCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 15.0, *) {
            content
                .background(
                    Color.clear
                        .glassEffect(.regular.tint(.red), in: Circle())
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().fill(Color.red.opacity(0.22)))
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
    }
}
