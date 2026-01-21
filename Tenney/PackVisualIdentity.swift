import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum PackVisualIdentity {
    private static let curatedSymbolNames: [String] = [
        "music.quarternote.3",
        "music.note.list",
        "music.mic",
        "music.note",
        "music.note.tv",
        "waveform",
        "waveform.circle",
        "waveform.path",
        "dial.min",
        "dial.medium",
        "dial.max",
        "metronome",
        "metronome.fill",
        "guitars",
        "pianokeys",
        "pianokeys.inverse",
        "pianokeys.circle",
        "slider.horizontal.3",
        "slider.horizontal.below.rectangle",
        "slider.vertical.3",
        "circle.grid.cross",
        "circle.grid.cross.fill",
        "square.grid.3x3",
        "triangle",
        "triangle.fill",
        "hexagon",
        "hexagon.fill",
        "circle.hexagonpath",
        "circle.hexagonpath.fill",
        "circle.dotted",
        "circle.grid.2x2",
        "circle.grid.2x2.fill",
        "diamond",
        "diamond.fill",
        "seal",
        "seal.fill",
        "sparkle",
        "sparkles",
        "star.square",
        "star.square.fill",
        "shield.lefthalf.filled",
        "shield.righthalf.filled",
        "cube",
        "cube.fill",
        "pyramid",
        "pyramid.fill",
        "hifispeaker",
        "hifispeaker.fill",
        "dot.radiowaves.left.and.right",
        "dot.radiowaves.forward",
        "wave.3.forward",
        "wave.3.left",
        "wave.3.backward",
        "circlebadge.2",
        "waveform.badge.plus",
        "waveform.badge.exclamationmark",
        "circle.square",
        "circle.square.fill"
    ]

    static var symbolNames: [String] {
        let available = curatedSymbolNames.filter { isSymbolAvailable($0) }
        return available.isEmpty ? ["music.note"] : available
    }

    static let palette: [Color] = [
        Color(red: 0.32, green: 0.40, blue: 0.84),
        Color(red: 0.26, green: 0.58, blue: 0.72),
        Color(red: 0.34, green: 0.66, blue: 0.54),
        Color(red: 0.63, green: 0.58, blue: 0.32),
        Color(red: 0.78, green: 0.53, blue: 0.34),
        Color(red: 0.80, green: 0.38, blue: 0.45),
        Color(red: 0.66, green: 0.36, blue: 0.68),
        Color(red: 0.44, green: 0.44, blue: 0.68),
        Color(red: 0.30, green: 0.52, blue: 0.76),
        Color(red: 0.42, green: 0.64, blue: 0.80),
        Color(red: 0.46, green: 0.57, blue: 0.42),
        Color(red: 0.74, green: 0.64, blue: 0.48),
        Color(red: 0.70, green: 0.46, blue: 0.40),
        Color(red: 0.56, green: 0.42, blue: 0.58),
        Color(red: 0.42, green: 0.46, blue: 0.52),
        Color(red: 0.36, green: 0.36, blue: 0.40)
    ]

    static func identity(for packID: String, accent: Color) -> (symbolName: String, palette: [Color]) {
        let hash = stableSeed(for: packID)
        let symbolCandidate = symbolNames[abs(hash) % symbolNames.count]
        let symbolName = resolvedSymbolName(symbolCandidate)
        let accentHue = accent.hueComponent ?? 0.0

        var paletteIndex = abs(hash / 7) % palette.count
        var primary = palette[paletteIndex]
        if let hue = primary.hueComponent {
            let distance = abs(hue - accentHue)
            if distance < 0.08 || distance > 0.92 {
                paletteIndex = (paletteIndex + 2) % palette.count
                primary = palette[paletteIndex]
            }
        }

        let secondary = palette[(paletteIndex + 5) % palette.count].opacity(0.65)
        let neutral = Color(.secondarySystemBackground).opacity(0.9)
        let palette = [primary, secondary, neutral].map { ensureVisible($0) }
        return (symbolName, palette)
    }

    static func stableSeed(for value: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(truncatingIfNeeded: hash)
    }

    static func resolvedSymbolName(_ candidate: String) -> String {
        isSymbolAvailable(candidate) ? candidate : "music.note"
    }

    private static func isSymbolAvailable(_ candidate: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(systemName: candidate) != nil
        #elseif canImport(AppKit)
        return NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil
        #else
        return false
        #endif
    }

    private static func ensureVisible(_ color: Color, minimumAlpha: CGFloat = 0.7) -> Color {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return color
        }
        return Color(uiColor: uiColor.withAlphaComponent(max(alpha, minimumAlpha)))
        #elseif canImport(AppKit)
        guard let nsColor = NSColor(color).usingColorSpace(.deviceRGB) else {
            return color
        }
        let alpha = nsColor.alphaComponent
        return Color(nsColor.withAlphaComponent(max(alpha, minimumAlpha)))
        #else
        return color
        #endif
    }
}

private extension Color {
    var hueComponent: Double? {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }
        return Double(hue)
        #elseif canImport(AppKit)
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return nil
        }
        return Double(nsColor.hueComponent)
        #else
        return nil
        #endif
    }
}
