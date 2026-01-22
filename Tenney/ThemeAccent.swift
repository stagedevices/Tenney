import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum ThemeAccent {
    static func increaseContrastEnabled() -> Bool {
        #if canImport(UIKit)
        return UIAccessibility.isDarkerSystemColorsEnabled
        #elseif canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #else
        return false
        #endif
    }

    static func gradient(from base: Color) -> LinearGradient {
        let a = base
        let b = adjusted(base, satMul: 1.15, brightMul: 0.72, brightAddIfDark: 0.18)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Accessibility-safe style (solid when Reduce Transparency or Increased Contrast).
    static func shapeStyle(
        base: Color,
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) -> AnyShapeStyle {
        if reduceTransparency || increaseContrast {
            return AnyShapeStyle(base)
        } else {
            return AnyShapeStyle(gradient(from: base))
        }
    }

    static func shapeStyle(
        base: Color,
        reduceTransparency: Bool
    ) -> AnyShapeStyle {
        shapeStyle(
            base: base,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrastEnabled()
        )
    }

    static func adjusted(
        _ color: Color,
        satMul: CGFloat,
        brightMul: CGFloat,
        brightAddIfDark: CGFloat
    ) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        let isDark = b < 0.45
        let newS = min(1, max(0, s * (isDark ? (satMul * 0.95) : satMul)))
        let newB = min(1, max(0, isDark ? (b + brightAddIfDark) : (b * brightMul)))
        return Color(UIColor(hue: h, saturation: newS, brightness: newB, alpha: a))
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ns.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a) == true else { return color }
        let isDark = b < 0.45
        let newS = min(1, max(0, s * (isDark ? (satMul * 0.95) : satMul)))
        let newB = min(1, max(0, isDark ? (b + brightAddIfDark) : (b * brightMul)))
        return Color(NSColor(hue: h, saturation: newS, brightness: newB, alpha: a))
        #else
        return color
        #endif
    }
}

extension View {
    func tenneyAccentForegroundStyle(_ base: Color) -> some View {
        modifier(TenneyAccentForeground(base: base))
    }
}

private struct TenneyAccentForeground: ViewModifier {
    let base: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.foregroundStyle(
            ThemeAccent.shapeStyle(
                base: base,
                reduceTransparency: reduceTransparency
            )
        )
    }
}
