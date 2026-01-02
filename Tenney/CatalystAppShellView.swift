#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

 enum CatalystDestination: String, CaseIterable, Identifiable {
    case lattice, tuner, library, learn, preferences
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lattice: return "Lattice"
        case .tuner: return "Tuner"
        case .library: return "Library"
        case .learn: return "Learn"
        case .preferences: return "Preferences"
        }
    }

    var systemImage: String {
        switch self {
        case .lattice: return "hexagon"
        case .tuner: return "gauge"
        case .library: return "books.vertical"
        case .learn: return "graduationcap"
        case .preferences: return "gearshape"
        }
    }
}

struct CatalystAppShellView: View {
    @EnvironmentObject private var latticeStore: LatticeStore
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow

    @State private var selection: CatalystDestination = .lattice
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var inspectorVisible: Bool = true
    @State private var latticeViewSize: CGSize = .zero

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            detail
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { latticeViewSize = proxy.size }
                            .onChange(of: proxy.size) { latticeViewSize = $0 }
                    }
                )
        } detail: {
            inspector
        }
        .frame(minWidth: 980, minHeight: 680)
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .onAppear { enforceWindowSizing() }
    }

    private var sidebar: some View {
        List {
            Section("Navigate") {
                ForEach(CatalystDestination.allCases.filter { $0 != .preferences }) { dest in
                    Button {
                        selection = dest
                    } label: {
                        Label(dest.title, systemImage: dest.systemImage)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .listRowBackground(selection == dest ? Color.primary.opacity(0.10) : Color.clear)
                    .help(dest.title)
                }

                Button {
                    openWindow(id: "preferences")
                } label: {
                    Label(CatalystDestination.preferences.title, systemImage: CatalystDestination.preferences.systemImage)
                }
                .help("Preferences")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Tenney")
    }


    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .lattice:
            LatticeScreen(store: latticeStore)
                .environmentObject(app)
                .id("lattice")
        case .tuner:
            NavigationStack {
                TunerCard(stageActive: .constant(false))
                    .environmentObject(app)
                    .padding(20)
                    .navigationTitle("Tuner")
            }
        case .library:
            NavigationStack {
                ScaleLibrarySheet()
                    .environmentObject(app)
                    .navigationTitle("Library")
            }
        case .learn:
            NavigationStack {
                LearnTenneyHubView(entryPoint: .onboarding)
                    .navigationTitle("Learn")
            }
        case .preferences:
            Color.clear
                .onAppear { openWindow(id: "preferences") }
        }
    }

    private var inspector: some View {
        Group {
            if inspectorVisible {
                CatalystInspectorView(
                    latticeStore: latticeStore,
                    destination: selection
                )
                .environmentObject(app)
                .frame(minWidth: 280)
            } else {
                EmptyView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItemGroup(placement: .navigationBarLeading) {
            Picker("Mode", selection: $selection) {
                Label("Lattice", systemImage: "hexagon").tag(CatalystDestination.lattice)
                Label("Tuner", systemImage: "gauge").tag(CatalystDestination.tuner)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            if selection == .lattice {
                Button { latticeStore.camera.reset() } label: {
                    Label("Reset Camera", systemImage: "arrow.uturn.backward.circle")
                }

                Button {
                    let size = latticeViewSize == .zero ? CGSize(width: 1200, height: 760) : latticeViewSize
                    withAnimation(.snappy) { latticeStore.resetView(in: size) }
                } label: {
                    Label("Center", systemImage: "dot.circle.and.hand.point.up.left.fill")
                }
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                withAnimation(.easeInOut) {
                    inspectorVisible.toggle()
                    columnVisibility = inspectorVisible ? .all : .doubleColumn
                }
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help(inspectorVisible ? "Hide Inspector" : "Show Inspector")
        }
    }


    private func enforceWindowSizing() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let restrictions = scene.sizeRestrictions else { return }
        restrictions.minimumSize = CGSize(width: 980, height: 680)
        restrictions.maximumSize = CGSize(width: 2400, height: 1600)
    }
}

struct CatalystCommands: Commands {
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
