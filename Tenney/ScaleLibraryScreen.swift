// ScaleLibraryScreen.swift
import SwiftUI

struct ScaleLibraryScreen: View {
    @Binding var isPresented: Bool
    let onSelect: (TenneyScale) -> Void
    var onPlayPreview: (TenneyScale) -> Void = { _ in }

    @ObservedObject private var library = ScaleLibraryStore.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(library.scales.values).sorted { $0.name < $1.name }) { s in
                    Button {
                        onSelect(s)
                        isPresented = false
                    } label: {
                        HStack {
                            Text(s.name)
                            Spacer()
                            Text("\(s.detectedLimit)-limit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Play") { onPlayPreview(s) }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
