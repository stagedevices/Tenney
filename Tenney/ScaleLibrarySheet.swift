// /Users/seb/Tenney/Tenney/ScaleLibrarySheet.swift

import Foundation
import SwiftUI

struct ScaleLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = ScaleLibraryStore.shared

    @State private var showOnlyFavorites = false
    @State private var actionTarget: TenneyScale? = nil
    // Helps the compiler pick the non-Binding ForEach initializer inside Picker.
    private let sortKeys: [ScaleLibraryStore.SortKey] = ScaleLibraryStore.SortKey.allCases

    private let limits: [Int] = [5, 7, 11, 13, 17, 19, 23, 29]

    // simple sort/local filter
    private var filteredScales: [TenneyScale] {
        var items = Array(library.scales.values)

        if showOnlyFavorites { items = items.filter { $0.favorite } }

        let q = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                (!$0.descriptionText.isEmpty && $0.descriptionText.localizedCaseInsensitiveContains(q))
            }
        }

        switch library.sortKey {
        case .recent:
            items.sort { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .alpha:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            items.sort { $0.size > $1.size }
        case .limit:
            items.sort { $0.detectedLimit < $1.detectedLimit }
        }

        return items
    }

    var body: some View {
        NavigationStack {
            List {
                if library.scales.isEmpty {
                    ContentUnavailableView(
                        "No saved scales",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Save a scale from Builder, or start by browsing limits.")
                    )
                } else {
                    Section {
                        HStack {
                            Toggle("Favorites only", isOn: $showOnlyFavorites)
                            Spacer()
                            Picker("Sort", selection: $library.sortKey) {
                                ForEach(sortKeys, id: \.self) { (k: ScaleLibraryStore.SortKey) in
                                    Text(k.label).tag(k)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Section("My Scales") {
                        if filteredScales.isEmpty {
                            Text("No scales match your filters.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredScales) { s in
                                Button {
                                    actionTarget = s
                                } label: {
                                    ScaleRow(scale: s)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        var t = s
                                        t.favorite.toggle()
                                        library.updateScale(t)
                                    } label: {
                                        Label(
                                            s.favorite ? "Unfavorite" : "Favorite",
                                            systemImage: s.favorite ? "star.slash" : "star"
                                        )
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        library.deleteScale(id: s.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: deleteScales)
                        }
                    }
                }

                Section("Collections by Limit") {
                    ForEach(limits, id: \.self) { limit in
                        NavigationLink("\(limit)-limit") {
                            ScaleLimitBrowserView(limit: limit) { selected in
                                actionTarget = selected
                            }
                            .environmentObject(model)
                        }
                    }
                }
            }
            .navigationTitle("Scale Library")
            .searchable(
                text: $library.searchText,
                placement: .navigationBarDrawer(displayMode: .always)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $actionTarget) { s in
                ScaleActionsSheet(
                    scale: s,
                    onOpen: { openInBuilder(s) },
                    onAdd: { addToBuilder(s) },
                    onPlay: { playScalePreview(s) }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - List Delete

    private func deleteScales(at offsets: IndexSet) {
        let current = filteredScales
        for i in offsets {
            guard current.indices.contains(i) else { continue }
            library.deleteScale(id: current[i].id)
        }
    }

    // MARK: - Actions

    private func openInBuilder(_ s: TenneyScale) {
        model.openBuilder(with: s)
        dismiss()
    }

    private func addToBuilder(_ s: TenneyScale) {
        model.addToBuilder(scale: s)
        dismiss()
    }

    private func playScalePreview(_ s: TenneyScale) {
        model.previewScale(s)
    }
}

// MARK: - Rows / Sheets

private struct ScaleRow: View {
    let scale: TenneyScale
    var onMore: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(scale.name).font(.headline)
                Spacer()
                if scale.favorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }

            if !scale.descriptionText.isEmpty {
                Text(scale.descriptionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Label("\(scale.size)", systemImage: "number")
                Label("≤\(scale.detectedLimit)", systemImage: "leaf")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct ScaleActionsSheet: View {
    let scale: TenneyScale
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onOpen) { Label("Open in Builder", systemImage: "hammer") }
                    Button(action: onAdd) { Label("Add to Builder", systemImage: "plus.circle") }
                    Button(action: onPlay) { Label("Preview", systemImage: "play.circle") }
                }

                Section {
                    NavigationLink {
                        ScaleDetailSheet(scale: scale)
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(scale.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ScaleDetailSheet: View {
    let scale: TenneyScale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(scale.name).font(.title2).bold()

                if !scale.descriptionText.isEmpty {
                    Text(scale.descriptionText).foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 6)

                Text("Degrees").font(.headline)
                ForEach(Array(scale.degrees.enumerated()), id: \.offset) { i, d in
                    Text("\(i + 1). \(String(describing: d))")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
            }
            .padding(16)
        }
        .navigationTitle("Details")
    }
}
