import SwiftUI

enum WaveformSymbol {
    static func systemName(for waveform: ToneOutputEngine.GlobalWave) -> String {
        if #available(iOS 17.0, macOS 14.0, *) {
            switch waveform {
            case .foldedSine:
                return "waveform"
            case .triangle:
                return "triangleshape"
            case .saw:
                return "righttriangle"
            @unknown default:
                return "waveform"
            }
        }

        return "waveform"
    }

    static func a11yLabel(for waveform: ToneOutputEngine.GlobalWave) -> String {
        switch waveform {
        case .foldedSine:
            return "Folded sine wave"
        case .triangle:
            return "Triangle wave"
        case .saw:
            return "Saw wave"
        @unknown default:
            return "Waveform"
        }
    }
}

struct WaveformIcon: View {
    let waveform: ToneOutputEngine.GlobalWave

    @Environment(\.colorScheme) private var scheme

    private let slot: CGFloat = 26

    var body: some View {
        Image(systemName: WaveformSymbol.systemName(for: waveform))
            .font(.system(size: 22, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(scheme == .dark ? Color.white : Color.primary)
            .frame(width: slot, height: slot, alignment: .center)
            .accessibilityLabel(WaveformSymbol.a11yLabel(for: waveform))
    }
}
