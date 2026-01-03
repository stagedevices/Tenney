#if targetEnvironment(macCatalyst)
import SwiftUI

struct PreferencesRootView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var tunerRailStore = TunerRailStore()
    var body: some View {
        StudioConsoleView()
            .environmentObject(tunerRailStore)
            .environmentObject(app)
            .frame(minWidth: 900, minHeight: 640)
    }
}
#endif
