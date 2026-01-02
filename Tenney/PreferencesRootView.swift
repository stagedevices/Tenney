#if targetEnvironment(macCatalyst)
import SwiftUI

struct PreferencesRootView: View {
    @StateObject private var tunerRailStore = TunerRailStore()
    var body: some View {
        StudioConsoleView()
            .environmentObject(tunerRailStore)
            .frame(minWidth: 900, minHeight: 640)
    }
}
#endif
