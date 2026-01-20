import Foundation

enum SelectionTrayClearBehavior: String, CaseIterable, Identifiable {
    case contextual = "contextual"
    case neverUnload = "neverUnload"
    case alwaysUnloadWhenLoaded = "alwaysUnloadWhenLoaded"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contextual:
            return "Contextual"
        case .neverUnload:
            return "Never unload"
        case .alwaysUnloadWhenLoaded:
            return "Always unload when loaded"
        }
    }
}
