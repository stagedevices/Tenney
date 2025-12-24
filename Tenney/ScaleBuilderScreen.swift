//
//  ScaleBuilderScreen.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  ScaleBuilderScreen.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation
import SwiftUI

struct ScaleBuilderScreen: View {

    @ObservedObject var store: ScaleBuilderStore

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ScaleLibraryStore
    @EnvironmentObject private var model: AppModel

    @State private var showLibraryPicker = false
    @State private var pickerSearch = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Scale") {
                    TextField("Name", text: $store.name)
                        .textInputAutocapitalization(.words)
                    TextField("Notes", text: $store.notes, axis: .vertical)
                        .lineLimit(2...6)

                    HStack {
                        Text("Root")
                        Spacer()
                        Text(String(format: "%.1f Hz", store.rootHz))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Tones") {
                    Toggle("Show enabled only", isOn: $store.showOnlyEnabled)

                    ForEach(store.visibleTones) { t in
                        ToneRow(tone: t) { id in
                            store.toggleEnabled(id)
                        }
                    }
                    .onDelete { offsets in
                        store.delete(at: offsets, using: store.visibleTones)
                    }
                    .onMove { src, dst in
                        // Only allow manual reordering when not filtered
                        guard !store.showOnlyEnabled else { return }
                        store.move(from: src, to: dst)
                    }
                }

                Section("Add tone") {
                    HStack(spacing: 10) {
                        TextField("p/q or p/q@octave", text: $store.ratioInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(.body, design: .monospaced))
                        Button("Add") { store.addToneFromInput() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.ratioInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Examples: 3/2, 5/4, 9/8@1")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showLibraryPicker = true
                    } label: {
                        Label("Insert from Library", systemImage: "square.stack.3d.up")
                    }

                    Button {
                        let scale = store.buildScale()
                        model.previewScale(scale)
                    } label: {
                        Label("Preview", systemImage: "play.circle")
                    }

                    Button {
                        store.saveToLibrary(library)
                    } label: {
                        Label("Save to Library", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Scale Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton().disabled(store.showOnlyEnabled)
                }
            }
            .sheet(isPresented: $showLibraryPicker) {
                libraryPickerSheet
            }
            .onReceive(NotificationCenter.default.publisher(for: .tenneyOpenLibraryInBuilder)) { _ in
                showLibraryPicker = true
            }
        }
    }

    private var libraryPickerSheet: some View {
        NavigationStack {
            List {
                if filteredLibraryScales.isEmpty {
                    ContentUnavailableView(
                        "No scales",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Save a scale to the library to insert it here.")
                    )
                } else {
                    ForEach(filteredLibraryScales) { s in
                        Button {
                            store.add(scale: s, includeDisabled: true)
                            showLibraryPicker = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(s.name).font(.headline)
                                    Spacer()
                                    if s.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                                }
                                if !s.descriptionText.isEmpty {
                                    Text(s.descriptionText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 10) {
                                    Label("\(s.size)", systemImage: "number")
                                    Label("≤\(s.detectedLimit)", systemImage: "leaf")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                store.replace(with: s, includeDisabled: true)
                                showLibraryPicker = false
                            } label: {
                                Label("Replace Builder With This Scale", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Insert from Library")
            .searchable(text: $pickerSearch, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showLibraryPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private var filteredLibraryScales: [TenneyScale] {
        let all = Array(library.scales.values)
        let q = pickerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all.sorted { $0.name < $1.name } }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.descriptionText.localizedCaseInsensitiveContains(q)
        }
        .sorted { $0.name < $1.name }
    }
}

private struct ToneRow: View {
    let tone: TenneyScaleTone
    let onToggle: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle(tone.id)
            } label: {
                Image(systemName: tone.isEnabled ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(ratioText(tone.ref))
                    .font(.system(.body, design: .monospaced))
                if let n = tone.name, !n.isEmpty {
                    Text(n)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if tone.ref.octave != 0 {
                Text("oct \(tone.ref.octave)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func ratioText(_ r: RatioRef) -> String {
        "\(r.p)/\(r.q)"
    }
}
