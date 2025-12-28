//
//  LatticeScreen.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  LatticeScreen.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI
import CoreGraphics



/// Wrapper around `LatticeView` that:
/// - owns the `LatticeStore`
/// - stops audition audio on background/disappear
/// - provides a clean, iOS-26-native toolbar surface
struct LatticeScreen: View {
    @StateObject private var store = LatticeStore()
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var app: AppModel
    
    @AppStorage(SettingsKeys.latticeAlwaysRecenterOnQuit)
        private var latticeAlwaysRecenterOnQuit: Bool = false
    
    @AppStorage(SettingsKeys.latticeRecenterPending)
        private var latticeRecenterPending: Bool = false

    var body: some View {
        LatticeView()
            .environmentObject(store)
            .onAppear {
                // If your app sets AppModelLocator.shared in TenneyApp/ContentView already, this is harmless.
                // Keep the root provider updated (future-proof if you migrate LatticeStore to use it).
                LatticeStore.rootHzProvider = { AppModelLocator.shared?.rootHz ?? 415.0 }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active {
                    // Kill sustained tones when the app backgrounds or goes inactive.
                    store.stopSelectionAudio(hard: true)
                   store.stopAllLatticeVoices(hard: true)
                }
                // “Quit” proxy: set a pending recenter only when we actually go to background.
                // If we come back active (not terminated), cancel the pending flag so it won’t surprise-recenter later.
                if latticeAlwaysRecenterOnQuit {
                    if phase == .background {
                        latticeRecenterPending = true
                    } else if phase == .active {
                        latticeRecenterPending = false
                    }
                }
            }
            .onChange(of: app.builderPresented) { presented in
                           if presented {
                               store.stopAllLatticeVoices(hard: false)
                           } else {
                               store.reAuditionSelectionIfNeeded()
                           }
                       }
            .onDisappear {
                store.stopSelectionAudio(hard: true)
               store.stopAllLatticeVoices(hard: true)
            }
            .navigationTitle("Lattice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Left cluster: mode + undo/redo
        ToolbarItemGroup(placement: .topBarLeading) {
            Menu {
                Picker("Mode", selection: $store.mode) {
                    Text("Explore").tag(LatticeStore.LatticeMode.explore)
                    Text("Select").tag(LatticeStore.LatticeMode.select)
                }

                Divider()

                Button {
                    store.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }

                Button {
                    store.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
            }
        }

        // Right cluster: guides + audition + clear
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                store.guidesOn.toggle()
            } label: {
                Image(systemName: store.guidesOn ? "grid.circle.fill" : "grid.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(store.guidesOn ? "Hide guides" : "Show guides")

            Button {
                store.auditionEnabled.toggle()
            } label: {
                Image(systemName: store.auditionEnabled ? "speaker.wave.2.circle.fill" : "speaker.wave.2.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(store.auditionEnabled ? "Stop audition" : "Start audition")

            Button(role: .destructive) {
                store.clearSelection()
            } label: {
                ZStack {
                    Image(systemName: "xmark.circle")
                        .symbolRenderingMode(.hierarchical)

                    if store.selectedCount > 0 {
                        Text("\(store.selectedCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .offset(x: 10, y: -10)
                    }
                }
            }
            .accessibilityLabel("Clear selection")
        }
    }
}
