//
//  OctaveNudger.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/24/25.
//


import SwiftUI
import UIKit

struct OctaveNudger: View {
    let canDown: Bool
    let canUp: Bool
    let stepDown: () -> Void
    let stepUp: () -> Void
    var compact: Bool = true     // smaller for pads

    @State private var downTimer: Timer?
    @State private var upTimer: Timer?

    var body: some View {
        HStack(spacing: 8) {
            nudgerButton(system: "chevron.down", enabled: canDown,
                         onTap: { stepDown(); hapticTap() },
                         onRepeatStart: { startRepeat(&downTimer, action: stepDown) },
                         onRepeatEnd: { stopRepeat(&downTimer) })

            nudgerButton(system: "chevron.up", enabled: canUp,
                         onTap: { stepUp(); hapticTap() },
                         onRepeatStart: { startRepeat(&upTimer, action: stepUp) },
                         onRepeatEnd: { stopRepeat(&upTimer) })
        }
    }

    private func nudgerButton(system: String,
                              enabled: Bool,
                              onTap: @escaping () -> Void,
                              onRepeatStart: @escaping () -> Void,
                              onRepeatEnd: @escaping () -> Void) -> some View {
        let size: CGFloat = compact ? 28 : 34
        return Button(action: onTap) {
            Image(systemName: system)
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(RoundedRectangle(cornerRadius: size/2, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(GlassPill(enabled: enabled))
        .disabled(!enabled)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in onRepeatStart() })
        .highPriorityGesture(DragGesture(minimumDistance: 0).onEnded { _ in onRepeatEnd() }, including: .gesture)
        .onDisappear { onRepeatEnd() }
        .accessibilityLabel(system == "chevron.up" ? "Octave up" : "Octave down")
        .accessibilityHint("Hold to auto-repeat")
    }

    private func startRepeat(_ timer: inout Timer?, action: @escaping () -> Void) {
        guard timer == nil else { return }
        hapticTap()
        action()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            action(); hapticSoft()
        }
    }
    private func stopRepeat(_ timer: inout Timer?) { timer?.invalidate(); timer = nil }

    private func hapticTap()  { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func hapticSoft() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.35) }
}

// Liquid-glass capsule with graceful fallback
struct GlassPill: ViewModifier {
    var enabled: Bool
    func body(content: Content) -> some View {
        let alpha: CGFloat = enabled ? 1.0 : 0.35
        content
            .overlay(
                Group {
                    if #available(iOS 26.0, *) {
                        content
                            .glassEffect(.regular, in: Capsule())
                            .opacity(alpha)
                    } else {
                        Capsule().fill(.thinMaterial)
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .opacity(alpha)
                    }
                }
                .allowsHitTesting(false)
            )
    }
}
