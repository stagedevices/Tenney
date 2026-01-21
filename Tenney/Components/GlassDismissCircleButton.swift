import SwiftUI

struct GlassDismissCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Diagnosis: applying GlassBlueCircle to a Circle fills it with .primary,
                // which blocks the glass background (seen as "clear" in Settings).
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .modifier(GlassBlueCircle())
        }
        .buttonStyle(.plain)
    }
}
