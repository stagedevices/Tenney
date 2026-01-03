#if os(macOS)
import SwiftUI

struct MacPreferencesRootView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var tunerRailStore = TunerRailStore()
    var body: some View {
        StudioConsoleView()
            .environmentObject(tunerRailStore)
            .environmentObject(app)
            .frame(minWidth: 900, minHeight: 640)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .padding(18)
    }
}

struct MacCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Preferences…") {
                openWindow(id: "preferences")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
#endif
