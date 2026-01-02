#if targetEnvironment(macCatalyst)
import SwiftUI

struct PreferencesRootView: View {
    @EnvironmentObject private var app: AppModel

    private let categories: [SettingsCategory] = [.lattice, .tuner, .oscilloscope, .theme, .audio, .general]

    var body: some View {
        TabView {
            ForEach(categories, id: \.self) { cat in
                StudioConsoleView(initialCategory: cat)
                    .environmentObject(app)
                    .tabItem {
                        Label(cat.title, systemImage: cat.icon)
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
    }
}
#endif
