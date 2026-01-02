#if targetEnvironment(macCatalyst)
import SwiftUI

struct PreferencesRootView: View {
    var body: some View {
        StudioConsoleView()
            .frame(minWidth: 900, minHeight: 640)
    }
}
#endif
