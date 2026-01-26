import SwiftUI

private struct UtilityBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var utilityBarHeight: CGFloat {
        get { self[UtilityBarHeightKey.self] }
        set { self[UtilityBarHeightKey.self] = newValue }
    }
}
