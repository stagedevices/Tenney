import Combine
import Foundation

struct SettingsDeepLink: Equatable {
    let category: StudioConsoleView.SettingsCategory
    var latticePage: SettingsDeepLinkLatticePage? = nil
    var oscilloscopePage: SettingsDeepLinkOscilloscopePage? = nil
    var audioPage: SettingsDeepLinkAudioPage? = nil
}

enum SettingsDeepLinkLatticePage: String, Equatable {
    case view
    case grid
    case distance
}

enum SettingsDeepLinkOscilloscopePage: String, Equatable {
    case view
    case trace
    case persistence
    case snapping
}

enum SettingsDeepLinkAudioPage: String, Equatable {
    case device
    case tone
    case envelope
    case headroom
}

@MainActor
final class SettingsDeepLinkCenter: ObservableObject {
    static let shared = SettingsDeepLinkCenter()
    @Published var pending: SettingsDeepLink? = nil

    func open(_ link: SettingsDeepLink) {
        pending = link
    }
}
