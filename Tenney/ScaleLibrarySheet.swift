//
//  ScaleLibrarySheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

private func recentlyPlayedChipLabel(_ filter: LibraryFilters.RecentlyPlayed) -> String {
    switch filter {
    case .any:
        return "Played"
    case .days7:
        return "Played 7d"
    case .days30:
        return "Played 30d"
    case .days90:
        return "Played 90d"
    }
}

struct ScaleLibrarySheet: View {
    @State private var libraryPage: Int = 0
    @State private var didApplyLaunchMode = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @AppStorage(SettingsKeys.libraryFiltersJSON) private var libraryFiltersJSON: String = ""
    @AppStorage(SettingsKeys.librarySearchText) private var librarySearchText: String = ""
    @AppStorage(SettingsKeys.libraryFavoritesOnly) private var libraryFavoritesOnly: Bool = false
    @AppStorage(SettingsKeys.librarySortKey) private var librarySortKeyRaw: String = ScaleLibraryStore.SortKey.recent.rawValue
    @State private var filters: LibraryFilters = .defaultValue
    @State private var showFilterSheet = false
    @State private var didLoadFilters = false
    @State private var actionTarget: TenneyScale? = nil   // ← selected row for the action sheet
    @State private var isSearchPresented = false

    // simple sort/local filter
    private var filteredScales: [TenneyScale] {
        var items = Array(library.scales.values)
        items = items.filter { scale in
            filters.matches(
                scale: scale,
                tagStore: tagStore,
                favoritesOnly: libraryFavoritesOnly,
                searchText: librarySearchText,
                favoriteIDs: library.favoriteIDs
            )
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

    private var selectedTagRefs: [TagRef] {
        tagStore.tags(for: Array(filters.selectedTagIDs))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var activeFilterChips: [FilterChipItem] {
        var chips: [FilterChipItem] = []

        if libraryFavoritesOnly {
            chips.append(
                FilterChipItem(
                    id: "favorites",
                    label: "Favorites",
                    systemImage: "star.fill",
                    action: { libraryFavoritesOnly = false }
                )
            )
        }

        if filters.source != .all {
            chips.append(
                FilterChipItem(
                    id: "source",
                    label: "Source \(filters.source.label)",
                    systemImage: "tray",
                    action: { filters.source = .all }
                )
            )
        }

        if filters.maxLimit != .none {
            chips.append(
                FilterChipItem(
                    id: "limit",
                    label: "\(filters.maxLimit.label) limit",
                    systemImage: "dial.min",
                    action: { filters.maxLimit = .none }
                )
            )
        }

        if filters.sizeRange != .any {
            chips.append(
                FilterChipItem(
                    id: "size",
                    label: filters.sizeRange.label,
                    systemImage: "number",
                    action: { filters.sizeRange = .any }
                )
            )
        }

        if filters.rootHzRange != .any {
            chips.append(
                FilterChipItem(
                    id: "root",
                    label: "Root \(filters.rootHzRange.label)",
                    systemImage: "waveform",
                    action: { filters.rootHzRange = .any }
                )
            )
        }

        if filters.notesFilter == .hasNotes {
            chips.append(
                FilterChipItem(
                    id: "notes",
                    label: "Has notes",
                    systemImage: "note.text",
                    action: { filters.notesFilter = .any }
                )
            )
        }

        if filters.recentlyPlayed != .any {
            chips.append(
                FilterChipItem(
                    id: "recent",
                    label: recentlyPlayedChipLabel(filters.recentlyPlayed),
                    systemImage: "clock",
                    action: { filters.recentlyPlayed = .any }
                )
            )
        }

        return chips
    }

    private let limits = [3,5,7,11,13,17,19]
    private func count(for limit: Int) -> Int {
        filteredScales.filter { $0.detectedLimit <= limit }.count
    }

    var body: some View {
        let isSearchActive = isSearchPresented || !librarySearchText.isEmpty
        NavigationStack {
            ZStack {
                libraryGlassBackground
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    
                    // card below the search bar
                    LibraryControlsCard(
                        sortKey: $library.sortKey,
                        showOnlyFavorites: $libraryFavoritesOnly,
                        showFilterSheet: $showFilterSheet,
                        selectedTagRefs: selectedTagRefs,
                        filterChips: activeFilterChips,
                        onRemoveTag: { filters.selectedTagIDs.remove($0) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    
                    GeometryReader { proxy in
                        TabView(selection: $libraryPage) {
                            
                            MyScalesPageList(
                                filteredScales: filteredScales,
                                onPickScale: { actionTarget = $0 },
                                openInBuilder: openInBuilder,
                                addToBuilder: addToBuilder,
                                playScalePreview: playScalePreview,
                                onClearFilters: clearAllFilters
                            )
                            .tag(0)
                            
                            CollectionsByLimitPageList(
                                limits: limits,
                                countForLimit: { count(for: $0) },
                                filteredSavedScales: filteredScales,
                                hasResults: !filteredScales.isEmpty,
                                isFiltering: filters.isFiltering(
                                    searchText: librarySearchText,
                                    favoritesOnly: libraryFavoritesOnly
                                ),
                                onClearFilters: clearAllFilters,
                                onChooseScale: { chosen in addToBuilder(chosen) }
                            )
                            .tag(1)

                            CommunityPacksPageList(
                                sortKey: library.sortKey,
                                filters: filters,
                                favoritesOnly: libraryFavoritesOnly,
                                searchText: librarySearchText,
                                onClearFilters: clearAllFilters,
                                onPreviewRequested: handleCommunityPackPreviewRequest
                            )
                                .tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .background(Color.clear)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    
                    PagePips(page: $libraryPage, labels: ["My Scales", "Collections by Limit", "Community Packs"])
                        .padding(.bottom, 10)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .searchable(
                text: $librarySearchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .automatic)
            )
            
            // Per-scale actions presented as a medium detent sheet
            .sheet(item: $actionTarget) { s in
                ScaleActionsSheet(
                    scale: s,
                    onOpen: { openInBuilder(s) },
                    onAdd:  { addToBuilder(s) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showFilterSheet) {
                LibraryFilterSheet(
                    filters: $filters,
                    favoritesOnly: $libraryFavoritesOnly,
                    onClearAll: clearAllFilters,
                    onDone: { showFilterSheet = false }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .overlay(alignment: .topTrailing) {
                    // Overlay keeps dismissal off the nav bar and anchored to the sheet's top edge.
                    if !isSearchActive {
                        GlassDismissCircleButton { dismiss() }
                            .padding(.top, 20)
                            .padding(.trailing, 20)
                    }
                }
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationBackground(.clear)
        .onAppear {
            loadFiltersIfNeeded()
            if let storedSort = ScaleLibraryStore.SortKey(rawValue: librarySortKeyRaw) {
                library.sortKey = storedSort
            } else {
                library.sortKey = .recent
                librarySortKeyRaw = library.sortKey.rawValue
            }
            guard !didApplyLaunchMode else { return }
            didApplyLaunchMode = true

            guard let mode = model.scaleLibraryLaunchMode else { return }
            // consume it so it’s one-shot
            model.scaleLibraryLaunchMode = nil

            libraryPage = 0
            library.sortKey = .recent

            switch mode {
            case .recents:
                libraryFavoritesOnly = false
            case .favorites:
                libraryFavoritesOnly = true
            }
        }
        .onChange(of: filters) { _ in
            persistFilters()
        }
        .onChange(of: library.sortKey) { newValue in
            librarySortKeyRaw = newValue.rawValue
        }
    }
    @ViewBuilder
    private var libraryGlassBackground: some View {
        let shape = Rectangle()
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private func handleCommunityPackPreviewRequest(_ request: CommunityPackPreviewRequest) {
        DispatchQueue.main.async {
            libraryPage = 0
            actionTarget = request.scale
        }
    }

}

private struct LibraryControlsCard: View {
    @Binding var sortKey: ScaleLibraryStore.SortKey
    @Binding var showOnlyFavorites: Bool
    @Binding var showFilterSheet: Bool
    let selectedTagRefs: [TagRef]
    let filterChips: [FilterChipItem]
    let onRemoveTag: (TagID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // A) Sort “pills” (replaces segmented picker)
            LibrarySortPills(selection: $sortKey)

            // B) Filter + star row (star moved here, right side)
            HStack(spacing: 10) {
                Button {
                    showFilterSheet = true
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    showOnlyFavorites.toggle()
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: {
                    ZStack {
                        favoriteCircleBackground
                        Image(systemName: showOnlyFavorites ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(showOnlyFavorites ? .yellow : .secondary)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showOnlyFavorites ? "Show all scales" : "Show favorites only")
            }

            // C) Selected tag chips row (same logic as before)
            if selectedTagRefs.isEmpty && filterChips.isEmpty {
                Text("All filters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filterChips) { chip in
                            Button {
                                chip.action()
                            } label: {
                                FilterChip(label: chip.label, systemImage: chip.systemImage)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(selectedTagRefs, id: \TagRef.id) { tag in
                            Button { onRemoveTag(tag.id) } label: {
                                TagChip(tag: tag, size: .small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder private var favoriteCircleBackground: some View {
        let shape = Circle()
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.thinMaterial)
        }
    }
}

private struct FilterChipItem: Identifiable {
    let id: String
    let label: String
    let systemImage: String?
    let action: () -> Void
}

private struct FilterChip: View {
    let label: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(label)
                .font(.caption2.weight(.semibold).monospaced())
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(chipBackground)
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var chipBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.thinMaterial)
        }
    }
}

private struct LibraryFilterSheet: View {
    @Binding var filters: LibraryFilters
    @Binding var favoritesOnly: Bool
    let onClearAll: () -> Void
    let onDone: () -> Void
    @ObservedObject private var tagStore = TagStore.shared

    private var selectedTagRefs: [TagRef] {
        tagStore.tags(for: Array(filters.selectedTagIDs))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        !filters.isDefault || favoritesOnly
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if hasActiveFilters {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                if favoritesOnly {
                                    FilterChip(label: "Favorites", systemImage: "star.fill")
                                }
                                if filters.source != .all {
                                    FilterChip(label: "Source \(filters.source.label)", systemImage: "tray")
                                }
                                if filters.maxLimit != .none {
                                    FilterChip(label: "\(filters.maxLimit.label) limit", systemImage: "dial.min")
                                }
                                if filters.sizeRange != .any {
                                    FilterChip(label: filters.sizeRange.label, systemImage: "number")
                                }
                                if filters.rootHzRange != .any {
                                    FilterChip(label: "Root \(filters.rootHzRange.label)", systemImage: "waveform")
                                }
                                if filters.notesFilter == .hasNotes {
                                    FilterChip(label: "Has notes", systemImage: "note.text")
                                }
                                if filters.recentlyPlayed != .any {
                                    FilterChip(label: recentlyPlayedChipLabel(filters.recentlyPlayed), systemImage: "clock")
                                }
                                ForEach(selectedTagRefs, id: \TagRef.id) { tag in
                                    TagChip(tag: tag, size: .small)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } else {
                        Text("No active filters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Clear All") {
                        onClearAll()
                    }
                    .disabled(!hasActiveFilters)
                } header: {
                    Text("Active Filters")
                }

                Section("Filter by") {
                    NavigationLink {
                        TagFilterSheet(selectedTagIDs: selectedTagBinding)
                            .navigationTitle("Tags")
                    } label: {
                        FilterRow(title: "Tags", value: tagSummary)
                    }

                    NavigationLink {
                        LibraryFilterPicker(
                            title: "Source",
                            selection: $filters.source,
                            resetValue: .all,
                            label: { $0.label }
                        )
                    } label: {
                        FilterRow(title: "Source", value: filters.source.label)
                    }

                    NavigationLink {
                        LibraryFilterPicker(
                            title: "Max prime limit",
                            selection: $filters.maxLimit,
                            resetValue: .none,
                            label: { $0.label }
                        )
                    } label: {
                        FilterRow(title: "Max prime limit", value: filters.maxLimit.label)
                    }

                    NavigationLink {
                        LibraryFilterPicker(
                            title: "Size",
                            selection: $filters.sizeRange,
                            resetValue: .any,
                            label: { $0.label }
                        )
                    } label: {
                        FilterRow(title: "Size", value: filters.sizeRange.label)
                    }

                    NavigationLink {
                        LibraryFilterPicker(
                            title: "Root Hz",
                            selection: $filters.rootHzRange,
                            resetValue: .any,
                            label: { $0.label }
                        )
                    } label: {
                        FilterRow(title: "Root Hz", value: filters.rootHzRange.label)
                    }

                    NavigationLink {
                        LibraryFilterPicker(
                            title: "Has notes",
                            selection: $filters.notesFilter,
                            resetValue: .any,
                            label: { $0.label }
                        )
                    } label: {
                        FilterRow(title: "Has notes", value: filters.notesFilter.label)
                    }

                    NavigationLink {
                        LibraryFilterPicker(
                            title: "Recently played",
                            selection: $filters.recentlyPlayed,
                            resetValue: .any,
                            label: { $0.label }
                        )
                    } label: {
                        FilterRow(title: "Recently played", value: filters.recentlyPlayed.label)
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                    }
                }
            }
        }
    }

    private var selectedTagBinding: Binding<Set<TagID>> {
        Binding(
            get: { filters.selectedTagIDs },
            set: { filters.selectedTagIDs = $0 }
        )
    }

    private var tagSummary: String {
        let count = filters.selectedTagIDs.count
        if count == 0 { return "Any" }
        if count == 1, let tag = selectedTagRefs.first { return tag.name }
        return "\(count) tags"
    }
}

private struct FilterRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LibraryFilterPicker<Option: Hashable & CaseIterable & Identifiable>: View {
    let title: String
    @Binding var selection: Option
    let resetValue: Option
    let label: (Option) -> String

    var body: some View {
        List {
            Section {
                Picker(title, selection: $selection) {
                    ForEach(Array(Option.allCases)) { option in
                        Text(label(option))
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                Button("Reset") {
                    selection = resetValue
                }
            }
        }
        .navigationTitle(title)
    }
}


private struct MyScalesPageList: View {
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared

    let filteredScales: [TenneyScale]
    let onPickScale: (TenneyScale) -> Void
    let openInBuilder: (TenneyScale) -> Void
    let addToBuilder: (TenneyScale) -> Void
    let playScalePreview: (TenneyScale) -> Void
    let onClearFilters: () -> Void

    var body: some View {
        if #available(iOS 16.0, *) {
            listBody
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        } else {
            listBody
        }
    }

    private var listBody: some View {
        List {
            if library.scales.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No saved scales yet",
                        systemImage: "music.quarternote.3",
                        description: Text("Save a scale from the Builder, or start by browsing limits.")
                    )
                }
            } else if filteredScales.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "No matching scales",
                            systemImage: "magnifyingglass",
                            description: Text("Try clearing filters or adjusting your search.")
                        )
                        Button("Clear filters") {
                            onClearFilters()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Section("My Scales (\(filteredScales.count))") {
                    ForEach(filteredScales) { s in
                        Button { onPickScale(s) } label: {
                            ScaleRow(scale: s, tagRefs: tagStore.tags(for: s.tagIDs), disclosure: true)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Open") { openInBuilder(s) }.tint(.accentColor)
                            Button("Add")  { addToBuilder(s) }.tint(.blue)
                            Button("Play") { playScalePreview(s) }.tint(.gray)
                            Button(role: .destructive) {
                                library.deleteScale(id: s.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                library.toggleFavorite(id: s.id)
                            } label: {
                                Label(
                                    s.favorite ? "Unfavorite" : "Favorite",
                                    systemImage: s.favorite ? "star.slash" : "star"
                                )
                            }
                            .tint(.yellow)
                        }
                        .contextMenu {
                            Button("Open in Builder") { openInBuilder(s) }
                            Button("Add to Builder") { addToBuilder(s) }
                            Button("Play Scale") { playScalePreview(s) }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)

        .listStyle(.insetGrouped)
    }
}

private struct CollectionsByLimitPageList: View {
    let limits: [Int]
    let countForLimit: (Int) -> Int
    let filteredSavedScales: [TenneyScale]
    let hasResults: Bool
    let isFiltering: Bool
    let onClearFilters: () -> Void
    let onChooseScale: (TenneyScale) -> Void

    var body: some View {
        if #available(iOS 16.0, *) {
            listBody
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        } else {
            listBody
        }
    }

    private var listBody: some View {
        List {
            if isFiltering && !hasResults {
                Section {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "No matching scales",
                            systemImage: "magnifyingglass",
                            description: Text("Try clearing filters or adjusting your search.")
                        )
                        Button("Clear filters") {
                            onClearFilters()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Section("Collections by Limit") {
                    ForEach(limits, id: \.self) { p in
                        NavigationLink {
                            ScaleLimitBrowserView(limit: p, filteredSavedScales: filteredSavedScales) { chosen in
                                onChooseScale(chosen)
                            }
                        } label: {
                            HStack {
                                Text("\(p)-limit")
                                Spacer()
                                let c = countForLimit(p)
                                if c > 0 {
                                    Text("\(c)")
                                        .font(.caption2.monospacedDigit())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)

        .listStyle(.insetGrouped)
    }
}


// MARK: - Row
private struct ScaleRow: View {
    let scale: TenneyScale
    let tagRefs: [TagRef]
    var disclosure: Bool = false
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                VStack(spacing: 2) {
                    Text("\(scale.size)")
                        .font(.headline.monospacedDigit())
                    Text("notes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                // Bolded name aligns with “Open in Builder” as the primary action
                Text(scale.name).font(.headline.weight(.semibold))
                HStack(spacing: 8) {
                    Text("\(scale.detectedLimit)-limit").font(.caption).foregroundStyle(.secondary)
                    Text("Root \(Int(scale.referenceHz)) Hz").font(.caption).foregroundStyle(.secondary)
                }
                if let provenance = scale.provenance, provenance.kind == .communityPack {
                    CommunityPackBadge(packName: provenance.packName)
                }
                if !tagRefs.isEmpty {
                    TagChipRow(tags: tagRefs, maxCount: 3)
                }
            }
            Spacer()
            if scale.favorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            if disclosure {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
// MARK: - Actions & Helpers
private extension ScaleLibrarySheet {
    func openInBuilder(_ s: TenneyScale) {
        // Open THIS file (not a new buffer)
        model.builderPayload = ScaleBuilderPayload(
            rootHz: s.referenceHz,
            primeLimit: s.detectedLimit,
            axisShift: [:],
            items: s.degrees,
            autoplayAll: model.latticeAuditionOn,
            startInLibrary: false,
            existing: s
        )
        // Close the medium detent; Builder sheet will present
        model.showScaleLibraryDetent = false
    }
    func addToBuilder(_ s: TenneyScale) {
        // Create a working buffer seeded with this scale (does NOT bind to file)
        model.builderPayload = ScaleBuilderPayload(
            rootHz: s.referenceHz,
            primeLimit: s.detectedLimit,
            axisShift: [:],
            items: s.degrees,
            autoplayAll: model.latticeAuditionOn,
            startInLibrary: false,
            existing: nil
        )
        model.showScaleLibraryDetent = false
    }
    func playScalePreview(_ s: TenneyScale) {
        let root = s.referenceHz
        for (i, r) in s.degrees.enumerated() {
            let when = DispatchTime.now() + .milliseconds(180 * i)
            DispatchQueue.main.asyncAfter(deadline: when) {
                let (cn, cd) = canonicalPQUnit(r.p, r.q)
                let f = foldToAudible(root * (Double(cn) / Double(cd)))
                guard (UserDefaults.standard.object(forKey: "Tenney.SoundOn") as? Bool ?? true) else { return }
                let id = ToneOutputEngine.shared.sustain(
                    freq: f,
                    amp: 0.16,
                    owner: .other,
                    ownerKey: "scaleLibrary:preview",
                    attackMs: nil,
                    releaseMs: nil
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                    ToneOutputEngine.shared.release(id: id, seconds: 0.0)
                                }
            }
        }
    }
    // Keep 1 ≤ p/q < 2 so 3/2 never shows/plays as 3/1
    func canonicalPQUnit(_ p: Int, _ q: Int) -> (Int, Int) {
        guard p > 0 && q > 0 else { return (p, q) }
        var n = p, d = q
        while Double(n)/Double(d) >= 2 { d &*= 2 }
        while Double(n)/Double(d) <  1 { n &*= 2 }
        var a = n, b = d
        while b != 0 { let t = a % b; a = b; b = t }
        let g = max(1, a)
        return (n/g, d/g)
    }
    func foldToAudible(_ f: Double, minHz: Double = 20, maxHz: Double = 5000) -> Double {
        guard f.isFinite && f > 0 else { return f }
        var x = f; while x < minHz { x *= 2 }; while x > maxHz { x *= 0.5 }; return x
    }

    func clearAllFilters() {
        filters = .defaultValue
        libraryFavoritesOnly = false
        librarySearchText = ""
    }

    func loadFiltersIfNeeded() {
        guard !didLoadFilters else { return }
        didLoadFilters = true
        guard !libraryFiltersJSON.isEmpty,
              let data = libraryFiltersJSON.data(using: .utf8)
        else { return }
        if let decoded = try? JSONDecoder().decode(LibraryFilters.self, from: data) {
            filters = decoded
        }
    }

    func persistFilters() {
        if let data = try? JSONEncoder().encode(filters),
           let json = String(data: data, encoding: .utf8) {
            libraryFiltersJSON = json
        }
    }
}
// MARK: - Per-scale Action Sheet (Open • Add • Play)
struct ScaleActionsSheet: View {
    @State private var isDronePlaying: Bool = false

    let scale: TenneyScale
    let onOpen: () -> Void
    let onAdd:  () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @ObservedObject private var communityPacks = CommunityPacksStore.shared
    @AppStorage(SettingsKeys.staffA4Hz) private var staffA4Hz: Double = 440
    @AppStorage(SettingsKeys.builderExportFormats) private var exportFormatsRaw: Int = ExportFormat.default.rawValue
    @AppStorage(SettingsKeys.builderExportRootMode) private var exportA4ModeRaw: String = ExportA4Mode.appDefault.rawValue
    @AppStorage(SettingsKeys.builderExportCustomA4Hz) private var customExportA4Hz: Double = 440.0
    @AppStorage("Tenney.SoundOn") private var soundOn: Bool = true
    @AppStorage(SettingsKeys.safeAmp) private var safeAmp: Double = 0.18
    @State private var playback = ScalePreviewPlayer()
    @State private var page: Int = 0
    @State private var tagsDetent: PresentationDetent = .medium
    @State private var tagsEditorPresented: Bool = false

    @State private var playbackMode: ScalePlaybackMode = .arp
    @State private var focusedDegreeID: String? = nil
    @State private var showExportSheet = false
    @State private var exportErrorMessage: String? = nil
    @State private var exportURLs: [URL] = []
    @State private var isPresentingShareSheet = false
    @State private var showTagsSheet = false
    @State private var showDeleteConfirm = false
    @State private var showUninstallConfirm = false
    @State private var copyMessage: String? = nil
    
    @AppStorage(SettingsKeys.lissaDotSize) private var lissaDotSize: Double = 4
    @AppStorage(SettingsKeys.lissaGridDivs) private var lissaGridDivs: Int = 3
    @AppStorage(SettingsKeys.lissaShowGrid) private var lissaShowGrid: Bool = true
    @AppStorage(SettingsKeys.lissaShowAxes) private var lissaShowAxes: Bool = true
    @AppStorage(SettingsKeys.lissaStrokeWidth) private var lissaRibbonWidth: Double = 2
    @AppStorage(SettingsKeys.lissaDotMode) private var lissaDotMode: Bool = false
    @AppStorage(SettingsKeys.lissaLiveSamples) private var lissaLiveSamples: Int = 768
    @AppStorage(SettingsKeys.lissaGlobalAlpha) private var lissaGlobalAlpha: Double = 1.0
    @AppStorage(SettingsKeys.latticeThemeID) private var latticeThemeID: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.latticeThemeStyle) private var themeStyleRaw: String = ThemeStyleChoice.system.rawValue

    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var effectiveIsDark: Bool {
        (themeStyleRaw == "dark") || (themeStyleRaw == "system" && systemScheme == .dark)
    }

    private var theme: LatticeTheme {
        ThemeRegistry.theme(LatticeThemeID(rawValue: latticeThemeID) ?? .classicBO, dark: effectiveIsDark)
    }

    private var oscEffectiveValues: LissajousPreviewConfigBuilder.EffectiveValues {
        LissajousPreviewConfigBuilder.effectiveValues(
            liveSamples: lissaLiveSamples,
            globalAlpha: lissaGlobalAlpha,
            dotSize: lissaDotSize,
            persistenceEnabled: true,
            halfLife: 0.6,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }


    private func isRootDegree(_ r: RatioRef) -> Bool {
        let (p, q) = RatioMath.canonicalPQUnit(r.p, r.q)
        return p == 1 && q == 1 && r.octave == 0
    }

    private func isRoot(_ r: RatioRef) -> Bool {
        r.p == 1 && r.q == 1 && r.octave == 0
    }

    private func ensureDroneFocus() {
        if let id = focusedDegreeID,
           let current = degreesSorted.first(where: { $0.id == id }),
           !isRoot(current) {
            return
        }
        focusedDegreeID = degreesSorted.first(where: { !isRoot($0) })?.id
    }

    private func toggleDrone() {
        guard soundOn else { return }

        ensureDroneFocus()

        let rootHz = RatioMath.foldToAudible(currentScale.referenceHz)
        guard
            let id = focusedDegreeID,
            let focus = degreesSorted.first(where: { $0.id == id })
        else { return }

        let focusHz = RatioMath.hz(rootHz: currentScale.referenceHz, p: focus.p, q: focus.q, octave: focus.octave, fold: true)
        isDronePlaying = playback.toggleDrone(rootHz: rootHz, focusHz: focusHz, safeAmp: safeAmp)
    }


    private func commitScaleRename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentScale.name else { return }
        var updated = currentScale
        updated.name = trimmed
        updated.lastPlayed = Date()
        library.updateScale(updated)
    }
    
    private var currentScale: TenneyScale {
        library.scales[scale.id] ?? scale
    }

    private var communityPackID: String? {
        guard currentScale.provenance?.kind == .communityPack else { return nil }
        return currentScale.provenance?.packID
    }

    private var communityPackTitle: String {
        let raw = currentScale.provenance?.packName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "this pack" : raw
    }

    private var shouldOfferUninstall: Bool {
        guard let packID = communityPackID else { return false }
        return communityPacks.isInstalled(packID)
    }

    private var exportFormats: ExportFormat {
        ExportFormat(rawValue: exportFormatsRaw)
    }

    private var exportA4Mode: ExportA4Mode {
        ExportA4Mode(rawValue: exportA4ModeRaw) ?? .appDefault
    }

    private var exportA4ModeBinding: Binding<ExportA4Mode> {
        Binding(
            get: { ExportA4Mode(rawValue: exportA4ModeRaw) ?? .appDefault },
            set: { exportA4ModeRaw = $0.rawValue }
        )
    }

    private var exportA4Hz: Double {
        switch exportA4Mode {
        case .appDefault:
            return 440.0
        case .hz440:
            return 440.0
        case .custom:
            return max(1.0, customExportA4Hz)
        }
    }

    private var degreesSorted: [RatioRef] {
        currentScale.degrees.enumerated().sorted { lhs, rhs in
            let l = degreeFrequency(lhs.element)
            let r = degreeFrequency(rhs.element)
            if l == r { return lhs.offset < rhs.offset }
            return l < r
        }.map(\.element)
    }

    private var tagRefs: [TagRef] {
        tagStore.tags(for: currentScale.tagIDs)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var headerSummary: String {
        let rootNote = NotationFormatter.spelledETNote(freqHz: currentScale.referenceHz, a4Hz: staffA4Hz)
        let hzInt = Int(round(currentScale.referenceHz))
        return "\(currentScale.size) notes · \(currentScale.detectedLimit)-limit · Root: \(rootNote.letter)\(rootNote.accidental)\(rootNote.octave) (\(hzInt) Hz)"
    }

    private var referenceSummary: String {
        let hzInt = Int(round(staffA4Hz))
        return "A4 = \(hzInt) Hz"
    }

    private var exportSummaryText: String {
        let exts: [String] = [
            exportFormats.contains(.scl)     ? ".scl"      : nil,
            exportFormats.contains(.kbm)     ? ".kbm"      : nil,
            exportFormats.contains(.ableton) ? ".ascl"     : nil,
            exportFormats.contains(.freqs)   ? "freqs.txt" : nil,
            exportFormats.contains(.cents)   ? "cents.txt" : nil
        ].compactMap { $0 }

        if exts.isEmpty {
            return "Select at least one format to export."
        }

        let formatsPart = "Will export: " + exts.joined(separator: ", ")

        let a4Label: String
        switch exportA4Mode {
        case .appDefault:
            let hzInt = Int(round(exportA4Hz))
            a4Label = "A4: App default (\(hzInt) Hz)"
        case .hz440:
            a4Label = "A4: 440 Hz"
        case .custom:
            let hzInt = Int(round(exportA4Hz))
            a4Label = "A4: Custom (\(hzInt) Hz)"
        }

        return "\(formatsPart) • \(a4Label)"
    }

    private var builderRootSummary: String {
        let hz = currentScale.referenceHz
        let (name, oct) = NotationFormatter.staffNoteName(freqHz: hz)
        let hzInt = Int(round(hz))
        return "Root: \(name)\(oct) (\(hzInt) Hz)"
    }

    var body: some View {
        VStack(spacing: 12) {

            GeometryReader { proxy in
                Group {
                    if #available(iOS 18.0, *) {
                        TabView(selection: $page) {
                            OverviewPage(
                                title: currentScale.name,
                                headerSummary: headerSummary,
                                referenceSummary: referenceSummary,
                                tags: tagRefs,
                                onOpen: { onOpen(); dismiss() },
                                onAdd: { onAdd(); dismiss() },
                                onExport: { showExportSheet = true },
                                onCopyRatios: { copyRatios() },
                                onCopyJSON: { copyJSON() },
                                onCopySCL: { copySCL() },
                                onCommitTitle: { commitScaleRename($0) },
                                onTags: { showTagsSheet = true },
                                onDelete: {
                                    if shouldOfferUninstall {
                                        showUninstallConfirm = true
                                    } else {
                                        showDeleteConfirm = true
                                    }
                                },
                                destructiveTitle: shouldOfferUninstall ? "Uninstall Pack" : "Delete"
                            )
                            .tag(0)

                            HearPage(
                                lissaE3: theme.e3,
                                lissaE5: theme.e5,
                                lissaSamples: oscEffectiveValues.liveSamples,
                                lissaGridDivs: lissaGridDivs,
                                lissaShowGrid: lissaShowGrid,
                                lissaShowAxes: lissaShowAxes,
                                lissaRibbonWidth: lissaRibbonWidth,
                                lissaDotMode: lissaDotMode,
                                lissaDotSize: oscEffectiveValues.dotSize,
                                lissaGlobalAlpha: oscEffectiveValues.alpha,
                                playbackMode: $playbackMode,
                                focusedDegreeID: focusedDegreeID,
                                focusedDegreeLabel: focusedDegreeLabel(),
                                degrees: degreesSorted,
                                rootHz: currentScale.referenceHz,
                                onSelectDegree: { selectDegree(id: $0) },
                                isDronePlaying: isDronePlaying,
                                onPlay: { playScale() },
                                onToggleDrone: { toggleDrone() }
                            )
                            .tag(1)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 16)
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let copyMessage {
                    Text(copyMessage)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                PagePips(page: $page, labels: ["Overview", "Hear"])
            }
            .padding(.bottom, 10)
        }

        .sheet(isPresented: $showExportSheet) {
            ScrollView {
                ScaleExportSheet(
                    title: resolvedName(),
                    builderRootSummary: builderRootSummary,
                    exportSummaryText: exportSummaryText,
                    exportFormats: exportFormats,
                    exportErrorMessage: exportErrorMessage,
                    onToggleFormat: { toggleFormat($0) },
                    onExport: { performExportNow() },
                    onDone: { showExportSheet = false },
                    exportA4Mode: exportA4ModeBinding,
                    customA4Hz: $customExportA4Hz
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isPresentingShareSheet) {
            ActivityView(activityItems: exportURLs)
        }

        .sheet(isPresented: $showTagsSheet) {
            NavigationStack {
                VStack(spacing: 0) {
                    TagsModalHeader(title: "Tags") {
                        showTagsSheet = false
                    }

                    TagEditorView(
                        scale: currentScale,
                        detent: $tagsDetent,
                        editorPresented: $tagsEditorPresented
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
            }

            .presentationDetents([.medium, .large], selection: $tagsDetent)
            .presentationDragIndicator(tagsEditorPresented ? .hidden : .hidden)
            .interactiveDismissDisabled(tagsEditorPresented)
        }
        .onChange(of: playbackMode) { newMode in
            if newMode == .drone {
                ensureDroneFocus()
            } else if isDronePlaying {
                playback.stop()
                isDronePlaying = false
            }
        }

        .onChange(of: showTagsSheet) { presented in
            if presented {
                tagsDetent = .medium
                tagsEditorPresented = false
            }
        }
        .alert("Delete scale?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                library.deleteScale(id: currentScale.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove “\(currentScale.name)” from your Library.")
        }
        .alert("Uninstall “\(communityPackTitle)”?", isPresented: $showUninstallConfirm) {
            Button("Uninstall Pack", role: .destructive) {
                guard let packID = communityPackID else { return }
                Task {
                    await communityPacks.uninstallPack(packID: packID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes this pack’s scales from this device. You can reinstall later.")
        }
        .onDisappear {
            playback.stop()
            isDronePlaying = false

        }
    }

    private struct TagsModalHeader: View {
        let title: String
        let onDone: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    Spacer()

                    Button(action: onDone) {
                        ZStack {
                            Circle()
                                .modifier(GlassBlueCircle())
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44) // TRUE 44×44, not nav-bar-clamped
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Save")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            }
        }

        @ViewBuilder
        private var headerBackground: some View {
            let shape = Rectangle()
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    
    private func playScale() {
        guard soundOn else { return }
        let focus = degreesSorted.first { $0.id == focusedDegreeID }
        playback.play(
            mode: playbackMode,
            scale: currentScale,
            degrees: degreesSorted,
            focus: focus,
            safeAmp: safeAmp
        )
    }

    private func focusedDegreeLabel() -> String? {
        guard let id = focusedDegreeID,
              let ratio = degreesSorted.first(where: { $0.id == id }) else { return nil }
        let label = ratioDisplay(ratio).label
        if ratio.octave != 0 {
            return "\(label) (\(ratio.octave > 0 ? "+\(ratio.octave)" : "\(ratio.octave)") oct)"
        }
        return label
    }

    private func degreeFrequency(_ ratio: RatioRef) -> Double {
        RatioMath.hz(rootHz: currentScale.referenceHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: false)
    }

    private func ratioDisplay(_ ratio: RatioRef) -> (label: String, octave: Int) {
        let (p, q) = RatioMath.canonicalPQUnit(ratio.p, ratio.q)
        return ("\(p)/\(q)", ratio.octave)
    }

    private func selectDegree(id: String) {
        guard focusedDegreeID != id else { return }
        focusedDegreeID = id
        if playbackMode == .drone, isDronePlaying {
            toggleDrone()      // stop
            toggleDrone()      // start with new focus
        }

#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }

    private func copyRatios() {
        let lines = degreesSorted.map { ratio -> String in
            let display = ratioDisplay(ratio)
            if display.octave != 0 {
                return "\(display.label) [\(display.octave)]"
            }
            return display.label
        }
        copyToPasteboard(lines.joined(separator: "\n"), message: "Copied ratios")
    }

    private func copyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(currentScale)
            if let string = String(data: data, encoding: .utf8) {
                copyToPasteboard(string, message: "Copied JSON")
            }
        } catch {
            copyToPasteboard("{}", message: "Copy failed")
        }
    }

    private func copySCL() {
        let text = ScalaExporter.sclText(
            scaleName: resolvedName(),
            description: currentScale.descriptionText,
            degrees: currentScale.degrees
        )
        copyToPasteboard(text, message: "Copied .scl")
    }

    private func copyToPasteboard(_ string: String, message: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = string
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
#endif
        showCopyMessage(message)
    }

    private func showCopyMessage(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            copyMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                copyMessage = nil
            }
        }
    }

    private func toggleFormat(_ format: ExportFormat) {
        var current = exportFormats
        if current.contains(format) {
            current.remove(format)
        } else {
            current.insert(format)
        }
        exportFormatsRaw = current.rawValue
        if exportErrorMessage != nil {
            exportErrorMessage = nil
        }
    }

    private func performExportNow() {
        exportErrorMessage = nil

        let degrees = currentScale.degrees
        guard !degrees.isEmpty else {
            exportErrorMessage = "Scale has no degrees to export."
            return
        }

        let name = sanitizedFilename(from: resolvedName())
        let desc = currentScale.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootHz = exportA4Hz

        var urls: [URL] = []

        if exportFormats.contains(.scl) {
            let text = ScalaExporter.sclText(
                scaleName: resolvedName(),
                description: desc,
                degrees: degrees
            )
            if let url = writeExportFile(named: "\(name).scl", contents: text) {
                urls.append(url)
            }
        }

        if exportFormats.contains(.kbm) {
            let text = ScalaExporter.kbmText(
                referenceHz: rootHz,
                scaleSize: max(1, degrees.count)
            )
            if let url = writeExportFile(named: "\(name).kbm", contents: text) {
                urls.append(url)
            }
        }

        if exportFormats.contains(.freqs) {
            let lines: [String] = degrees.map { r in
                let ratio = (Double(r.p) / Double(r.q)) * pow(2.0, Double(r.octave))
                let hz = ratio * currentScale.referenceHz
                return String(format: "%.8f", hz)
            }
            if let url = writeExportFile(named: "\(name)_freqs.txt", contents: lines.joined(separator: "\n")) {
                urls.append(url)
            }
        }

        if exportFormats.contains(.cents) {
            let lines: [String] = degrees.map { r in
                let ratio = (Double(r.p) / Double(r.q)) * pow(2.0, Double(r.octave))
                let cents = 1200.0 * log2(ratio)
                return String(format: "%.8f", cents)
            }
            if let url = writeExportFile(named: "\(name)_cents.txt", contents: lines.joined(separator: "\n")) {
                urls.append(url)
            }
        }

        if exportFormats.contains(.ableton) {
            let text = ScalaExporter.sclText(
                scaleName: resolvedName(),
                description: desc,
                degrees: degrees
            )
            if let url = writeExportFile(named: "\(name).ascl", contents: text) {
                urls.append(url)
            }
        }

        if let readmeURL = writeReadmeFile(baseName: name, degrees: degrees) {
            urls.append(readmeURL)
        }

        guard !urls.isEmpty else {
            exportErrorMessage = "Nothing was exported."
            return
        }

        exportErrorMessage = nil
        exportURLs = urls
        isPresentingShareSheet = true
    }

    private func writeReadmeFile(baseName: String, degrees: [RatioRef]) -> URL? {
        let scaleName = resolvedName()
        let desc = currentScale.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let a4Hz = exportA4Hz
        let rootHz = currentScale.referenceHz
        let (rootName, rootOct) = NotationFormatter.staffNoteName(freqHz: rootHz)

        let a4ModeLabel: String = {
            switch exportA4Mode {
            case .appDefault: return "App default"
            case .hz440:      return "440 Hz"
            case .custom:     return "Custom"
            }
        }()

        var lines: [String] = []
        lines.append("Name: \(scaleName)")
        lines.append("Description: \(desc)")
        lines.append(String(format: "A4 reference: %.4f Hz (%@)", a4Hz, a4ModeLabel))
        lines.append(String(format: "Builder root: %@%d (%.4f Hz)", rootName, rootOct, rootHz))
        lines.append("Prime limit: \(currentScale.detectedLimit)-limit JI")
        lines.append("Degrees (p/q [octave]):")

        for (idx, r) in degrees.enumerated() {
            lines.append("\(idx + 1): \(r.p)/\(r.q) [\(r.octave)]")
        }

        let text = lines.joined(separator: "\n")
        return writeExportFile(named: "\(baseName)_README.txt", contents: text)
    }

    private func writeExportFile(named: String, contents: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(named)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            exportErrorMessage = "Could not write export files. Please try again."
            return nil
        }
    }

    private func sanitizedFilename(from name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        if cleaned.isEmpty { return "Untitled_Scale" }
        return cleaned
    }

    private func resolvedName() -> String {
        let n = currentScale.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Untitled Scale" : n
    }

}

private struct PagePips: View {
    @Binding var page: Int
    let labels: [String]

    var body: some View {
        let count = labels.count
        if count <= 1 { EmptyView() }
        else {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { i in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            page = i
                        }
                    } label: {
                        Circle()
                            .fill(i == page
                                  ? Color.primary.opacity(0.85)
                                  : Color.secondary.opacity(0.35))
                            .frame(width: i == page ? 7 : 6, height: i == page ? 7 : 6)
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labels[i])
                    .accessibilityAddTraits(i == page ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(pipsBackground)
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var pipsBackground: some View {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}


private struct TagEditorView: View {
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    let scale: TenneyScale
    @Binding var detent: PresentationDetent
    @Binding var editorPresented: Bool

    @State private var searchText = ""
    @State private var addText = ""
    @State private var editingTagID: TagID?
    @State private var isCreatingNewTag = false

    private let chipColumns: [GridItem] = [GridItem(.adaptive(minimum: 88), spacing: 8)]
    private var currentScale: TenneyScale {
        library.scales[scale.id] ?? scale
    }

    private var attachedTags: [TagRef] {
        tagStore.tags(for: currentScale.tagIDs)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var suggestedTags: [TagRef] {
        var counts: [TagID: Int] = [:]
        for scale in library.scales.values {
            for id in scale.tagIDs {
                counts[id, default: 0] += 1
            }
        }
        let exclude = Set(currentScale.tagIDs)
        let sorted = counts
            .filter { !exclude.contains($0.key) }
            .sorted {
                if $0.value == $1.value {
                    return tagStore.tag(for: $0.key)?.name ?? "" < tagStore.tag(for: $1.key)?.name ?? ""
                }
                return $0.value > $1.value
            }
            .compactMap { tagStore.tag(for: $0.key) }
        return Array(sorted.prefix(12))
    }

    private var filteredTags: [TagRef] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return tagStore.allTags
        }
        return tagStore.allTags.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var editorActive: Bool { editingTagID != nil }


    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                TagsBrowseView(
                    attachedTags: attachedTags,
                    suggestedTags: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? suggestedTags : [],
                    allTags: filteredTags,
                    chipColumns: chipColumns,
                    isTagAttached: { currentScale.tagIDs.contains($0.id) },
                    onToggleTag: toggle,
                    onEditTag: { editingTagID = $0.id },
                    addText: $addText,
                    onAddTag: addTag,
                    searchText: $searchText
                )
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, editorActive ? 260 : 0)
            }
            .disabled(editorActive)

            if editorActive {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { editingTagID = nil } // keeps it “modal-y”
            }

            if let editingTagID {
                TagEditorDrawer(
                    tagID: editingTagID,
                    onDone: { self.editingTagID = nil },
                    onUpdateTagID: { self.editingTagID = $0 }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: editorActive)
        .onChange(of: editingTagID) { newValue in
            let active = (newValue != nil)
            editorPresented = active
            if active { detent = .large }
            if isCreatingNewTag { isCreatingNewTag = false }
        }

    }

    private func toggle(_ tag: TagRef) {
        var ids = Set(currentScale.tagIDs)
        if ids.contains(tag.id) {
            ids.remove(tag.id)
        } else {
            ids.insert(tag.id)
        }
        updateScaleTags(ids)
    }

    private func addTag() {
        let trimmed = addText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = tagStore.lookupByName(trimmed) {
            var ids = Set(currentScale.tagIDs)
            ids.insert(existing.id)
            updateScaleTags(ids)
            addText = ""
            return
        }
        let newTag = tagStore.createTag(name: trimmed)
        var ids = Set(currentScale.tagIDs)
        ids.insert(newTag.id)
        updateScaleTags(ids)
        addText = ""
        isCreatingNewTag = true
        editingTagID = newTag.id
        editorPresented = true
        detent = .large
    }

    private func updateScaleTags(_ ids: Set<TagID>) {
        var updated = currentScale
        updated.tagIDs = tagStore.sortedTagIDs(ids)
        updated.lastPlayed = Date()
        library.updateScale(updated)
    }
}

private struct TagsBrowseView: View {
    let attachedTags: [TagRef]
    let suggestedTags: [TagRef]
    let allTags: [TagRef]
    let chipColumns: [GridItem]
    let isTagAttached: (TagRef) -> Bool
    let onToggleTag: (TagRef) -> Void
    let onEditTag: (TagRef) -> Void
    @Binding var addText: String
    let onAddTag: () -> Void
    @Binding var searchText: String

    private var trimmedAddText: String {
        addText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            attachedSection
            addBar
            if !suggestedTags.isEmpty {
                suggestedSection
            }
            allTagsSection
        }
    }

    private var attachedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attached")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if attachedTags.isEmpty {
                Text("No tags yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: chipColumns, spacing: 8) {
                    ForEach(attachedTags, id: \.id) { tag in
                        Button {
                            onToggleTag(tag)
                        } label: {
                            TagChip(tag: tag, size: .regular)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit…") {
                                onEditTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Add tag…", text: $addText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onAddTag() }

                Button("Add") { onAddTag() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedAddText.isEmpty)
            }

            HStack(spacing: 6) {
                Text("Press Return to create")
                Text("•")
                Text("Tap a tag to attach")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: chipColumns, spacing: 8) {
                ForEach(suggestedTags, id: \.id) { tag in
                    Button { onToggleTag(tag) } label: {
                        TagChip(tag: tag, size: .regular)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit…") {
                            onEditTag(tag)
                        }
                    }
                }
            }
        }
    }

    private var allTagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All tags")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            TextField("Search tags", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if allTags.isEmpty {
                Text("No tags found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(allTags, id: \.id) { tag in
                        Button {
                            onToggleTag(tag)
                        } label: {
                            HStack {
                                TagChip(tag: tag, size: .small, isSelected: isTagAttached(tag))
                                Spacer()
                                if isTagAttached(tag) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit…") {
                                onEditTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TagEditorDrawer: View {
    @ObservedObject private var tagStore = TagStore.shared
    let tagID: TagID
    let onDone: () -> Void
    let onUpdateTagID: (TagID) -> Void

    @State private var renameText = ""

    private var tag: TagRef? {
        tagStore.tag(for: tagID)
    }

    var body: some View {
        Group {
            if let tag {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Tag Editor")
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 12)


                    let tagTint = colorFromHex(tag.resolvedHex)

                    HStack(alignment: .center, spacing: 12) {
                        TagChip(tag: tag, size: .regular)
                            .scaleEffect(1.22, anchor: .leading)

                        Spacer()

                        Button {
                            onDone()
                        } label: {
                            Text("Done")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(glassCapsuleBackground)
                                .overlay(
                                    Capsule().stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }


                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon")
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        TagIconPicker(
                            selection: Binding<String?>(
                                get: { tag.sfSymbolName },
                                set: { tagStore.setTagIcon(id: tag.id, sfSymbolName: $0) }
                            ),
                            chipTint: tagTint
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color")
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        TagColorPalette(selection: tag.color) { color in
                            tagStore.setTagColor(id: tag.id, color: color)
                        }

                        HStack(spacing: 10) {
                            Button {
                                applyRandomHex(to: tag)
                            } label: {
                                Label("Random Hex", systemImage: "die.face.5.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(glassCapsuleBackground)
                                    .overlay(
                                        Capsule().stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            Text(tag.resolvedHex)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .onTapGesture {
                                    #if canImport(UIKit)
                                    UIPasteboard.general.string = tag.resolvedHex
                                    #endif
                                }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Name")
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            TextField("Tag name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospaced())
                                .onSubmit { commitRename(for: tag) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(drawerBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onAppear {
                    renameText = tag.name
                }
                .onChange(of: tagID) { _ in
                    renameText = tagStore.tag(for: tagID)?.name ?? ""
                }
            } else {
                Color.clear
                    .frame(height: 1)
                    .onAppear { onDone() }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var drawerBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            Color.clear
                .background(.ultraThinMaterial)
        }
    }
    
    private func colorFromHex(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .accentColor }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8)  & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }

    @ViewBuilder
    private var glassCapsuleBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }


    private func applyRandomHex(to tag: TagRef) {
        let hex = String(format: "#%06X", UInt32.random(in: 0...0xFFFFFF))
        tagStore.setTagCustomHex(id: tag.id, hex: hex)
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func commitRename(for tag: TagRef) {
        let normalized = TagNameNormalizer.normalize(renameText)
        guard !normalized.isEmpty else { return }
        tagStore.renameTag(id: tag.id, newName: normalized)
        if let updated = tagStore.tag(for: tag.id) {
            renameText = updated.name
        } else if let merged = tagStore.lookupByName(normalized) {
            renameText = merged.name
            onUpdateTagID(merged.id)
        }
    }
}

private struct TagFilterSheet: View {
    @ObservedObject private var tagStore = TagStore.shared
    @Binding var selectedTagIDs: Set<TagID>
    @State private var searchText = ""

    private var filteredTags: [TagRef] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return tagStore.allTags
        }
        return tagStore.allTags.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search tags", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredTags.isEmpty {
                Text("No tags found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredTags, id: \.id) { (tag: TagRef) in
                            Button {
                                toggle(tag)
                            } label: {
                                HStack {
                                    TagChip(tag: tag, size: .regular, isSelected: selectedTagIDs.contains(tag.id))
                                    Spacer()
                                    if selectedTagIDs.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !selectedTagIDs.isEmpty {
                Button("Clear filters") {
                    selectedTagIDs.removeAll()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }

    private func toggle(_ tag: TagRef) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }
}

private struct OverviewPage: View {
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    let title: String
    let headerSummary: String
    let referenceSummary: String
    let tags: [TagRef]
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onExport: () -> Void
    let onCopyRatios: () -> Void
    let onCopyJSON: () -> Void
    let onCopySCL: () -> Void
    let onCommitTitle: (String) -> Void
    let onTags: () -> Void
    let onDelete: () -> Void
    let destructiveTitle: String

    private func beginTitleEdit(current: String) {
        titleDraft = current
        isEditingTitle = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleDraft = title
            isEditingTitle = false
            return
        }
        onCommitTitle(trimmed)
        isEditingTitle = false
    }

    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if isEditingTitle {
                            TextField("Scale name", text: $titleDraft)
                                .font(.largeTitle.weight(.semibold))
                                .textFieldStyle(.plain)
                                .focused($titleFocused)
                                .submitLabel(.done)
                                .onSubmit { commitTitle() }
                        } else {
                            Text(title)
                                .font(.largeTitle.weight(.semibold))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { beginTitleEdit(current: title) } // tap title = rename
                        }

                        Button {
                            if isEditingTitle { commitTitle() }
                            else { beginTitleEdit(current: title) }
                        } label: {
                            Image(systemName: isEditingTitle ? "checkmark" : "pencil")
                                .font(.system(size: 15, weight: .semibold))
                                .padding(8)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onAppear {
                        if titleDraft.isEmpty { titleDraft = title }
                    }
                    .onChange(of: title) { newValue in
                        if !isEditingTitle { titleDraft = newValue }
                    }
                    .onChange(of: titleFocused) { focused in
                        if !focused && isEditingTitle { commitTitle() } // tap-away commits
                    }

                    Text(headerSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(referenceSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()

                    if !tags.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            ForEach(tags, id: \TagRef.id) { (tag: TagRef) in
                                TagChip(tag: tag, size: .regular)
                            }
                        }
                    } else {
                        Text("No tags yet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Actions")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        Button(action: onOpen) {
                            ActionTile(
                                title: "Open",
                                systemImage: "square.stack.3d.up.fill",
                                style: .standard(.accentColor)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onAdd) {
                            ActionTile(
                                title: "Add to Current Set",
                                systemImage: "arrow.turn.down.right",
                                style: .standard(.blue)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onExport) {
                            ActionTile(
                                title: "Export…",
                                systemImage: "square.and.arrow.up",
                                style: .standard(.accentColor)
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                onCopyRatios()
                            } label: {
                                Label("Copy ratios", systemImage: "list.number")
                            }
                            Button {
                                onCopyJSON()
                            } label: {
                                Label("Copy as JSON", systemImage: "curlybraces")
                            }
                            Button {
                                onCopySCL()
                            } label: {
                                Label("Copy .scl text", systemImage: "doc.plaintext")
                            }
                        } label: {
                            ActionTile(
                                title: "Copy…",
                                systemImage: "doc.on.doc",
                                style: .standard(.secondary)
                            )
                        }

                        Button {
                            beginTitleEdit(current: title)
                        } label: {
                            ActionTile(
                                title: "Rename",
                                systemImage: "pencil",
                                style: .standard(.secondary)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onTags) {
                            ActionTile(
                                title: "Tags…",
                                systemImage: "tag",
                                style: .standard(.secondary)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onDelete) {
                        ActionTile(
                            title: destructiveTitle,
                            systemImage: "trash",
                            style: .destructive
                        )
                    }
                    .buttonStyle(.plain)

                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }

}

private struct HearPage: View {
    let lissaE3: Color
    let lissaE5: Color
    let lissaSamples: Int
    let lissaGridDivs: Int
    let lissaShowGrid: Bool
    let lissaShowAxes: Bool
    let lissaRibbonWidth: Double
    let lissaDotMode: Bool
    let lissaDotSize: Double
    let lissaGlobalAlpha: Double

    @Binding var playbackMode: ScalePlaybackMode
    let focusedDegreeID: String?
    let focusedDegreeLabel: String?
    let degrees: [RatioRef]
    let rootHz: Double
    let onSelectDegree: (String) -> Void
    let isDronePlaying: Bool
    let onPlay: () -> Void
    let onToggleDrone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Hear", systemImage: "speaker.wave.2.fill")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    PlaybackModePills(selection: $playbackMode)


                    if playbackMode == .drone {
                        if let focusedDegreeLabel {
                            Text("Drone focus: \(focusedDegreeLabel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let xy = droneXYRatios {
                            LissajousPreviewFrame(contentPadding: 0, showsFill: false) {
                                LissajousCanvasPreview(
                                    e3: lissaE3,
                                    e5: lissaE5,
                                    samples: lissaSamples,
                                    gridDivs: lissaGridDivs,
                                    showGrid: lissaShowGrid,
                                    showAxes: lissaShowAxes,
                                    strokeWidth: lissaRibbonWidth,
                                    dotMode: lissaDotMode,
                                    dotSize: lissaDotSize,
                                    globalAlpha: lissaGlobalAlpha,
                                    idleMode: .empty,
                                    xRatio: xy.x,
                                    yRatio: xy.y
                                )
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .accessibilityIdentifier("LissajousCard")
                        }

                        Button(action: onToggleDrone) {
                            Label(isDronePlaying ? "Stop" : "Play",
                                  systemImage: isDronePlaying ? "stop.fill" : "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: onPlay) {
                            Label("Play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                }
                .padding(14)
                .background(hearBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Degrees")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ForEach(degrees, id: \.id) { ratio in
                            DegreeRow(
                                ratio: ratio,
                                rootHz: rootHz,
                                isSelected: focusedDegreeID == ratio.id
                            )
                            .onTapGesture {
                                onSelectDegree(ratio.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }
    
    private var droneXYRatios: (x: (n: Int, d: Int), y: (n: Int, d: Int))? {
        guard playbackMode == .drone,
              let id = focusedDegreeID,
              let yRatioRef = degrees.first(where: { $0.id == id }),
              let xRatioRef = degrees.first(where: { $0.p == 1 && $0.q == 1 && $0.octave == 0 }) ?? degrees.first
        else { return nil }

        return (x: ndTuple(for: xRatioRef), y: ndTuple(for: yRatioRef))
    }

    private func ndTuple(for r: RatioRef) -> (n: Int, d: Int) {
        // Keep it stable + avoid huge integers: clamp octave contribution.
        let (p, q) = RatioMath.canonicalPQUnit(r.p, r.q)
        let oct = max(-12, min(12, r.octave))

        if oct >= 0 {
            return (n: p * (1 << oct), d: q)
        } else {
            return (n: p, d: q * (1 << (-oct)))
        }
    }

    
    private var droneFocusHz: Double? {
        guard playbackMode == .drone,
              let id = focusedDegreeID,
              let ratio = degrees.first(where: { $0.id == id }) else { return nil }
        return RatioMath.hz(rootHz: rootHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: true)
    }


    @ViewBuilder
    private var hearBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

private struct LibrarySortPills: View {
    @Binding var selection: ScaleLibraryStore.SortKey

    var body: some View {
        HStack(spacing: 8) {
            pill(.recent, title: "Recent", icon: "clock")
            pill(.alpha,  title: "A–Z",    icon: "textformat")
            pill(.size,   title: "Size",   icon: "number")
            pill(.limit,  title: "Limit",  icon: "dial.min")
        }
        .padding(4)
        .background {
            let shape = Capsule()
            if #available(iOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) }
            else { shape.fill(.thinMaterial) }
        }
        .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }

    private func pill(_ mode: ScaleLibraryStore.SortKey, title: String, icon: String) -> some View {
        let isSelected = (selection == mode)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                selection = mode
            }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                if isSelected {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, isSelected ? 14 : 10)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .frame(maxWidth: isSelected ? .infinity : nil)
            .layoutPriority(isSelected ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Capsule().fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            Capsule().stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

}


private struct PlaybackModePills: View {
    @Binding var selection: ScalePlaybackMode

    var body: some View {
        HStack(spacing: 8) {
            pill(.arp,   title: "Arp",   icon: "metronome")
            pill(.chord, title: "Chord", icon: "pianokeys")
            pill(.drone, title: "Drone", icon: "dot.radiowaves.left.and.right")
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }

    private func pill(_ mode: ScalePlaybackMode, title: String, icon: String) -> some View {
        let isSelected = (selection == mode)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                selection = mode
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                if isSelected {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, isSelected ? 14 : 10)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .frame(maxWidth: isSelected ? .infinity : nil)
            .layoutPriority(isSelected ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1)
        )
    }
}

private struct DroneScopeView: View {
    let rootHz: Double   // x = 1/1 (root)
    let focusHz: Double  // y = focused degree

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let midX = size.width * 0.5
                let midY = size.height * 0.5
                let ampX = size.width  * 0.42
                let ampY = size.height * 0.38

                // Fold to keep the drawing stable + visually readable
                let fx = fold(rootHz)
                let fy = fold(focusHz)

                var path = Path()
                let steps = 220
                for i in 0...steps {
                    let u = Double(i) / Double(steps)
                    let tt = t + u * 0.55

                    let x = sin(2.0 * .pi * fx * tt)
                    let y = sin(2.0 * .pi * fy * tt)

                    let px = midX + CGFloat(x) * ampX
                    let py = midY - CGFloat(y) * ampY

                    if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                    else      { path.addLine(to: CGPoint(x: px, y: py)) }
                }

                ctx.stroke(path, with: .color(Color.primary.opacity(0.75)), lineWidth: 1.2)
            }
        }
    }

    private func fold(_ f: Double) -> Double {
        guard f.isFinite && f > 0 else { return 1 }
        var x = f
        while x < 55  { x *= 2 }
        while x > 880 { x *= 0.5 }
        return x
    }
}

private struct ActionTile: View {
    enum Style {
        case standard(Color)
        case destructive
    }

    let title: String
    let systemImage: String
    let subtitle: String?
    let style: Style

    private var isDestructive: Bool {
        if case .destructive = style { return true }
        return false
    }

    private var tint: Color {
        switch style {
        case .standard(let accent):
            return accent
        case .destructive:
            return .white
        }
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        let shape = tileShape
        let resolved: (isDestructive: Bool, tint: Color) = {
            switch style {
            case .standard(let accent):
                return (false, accent)
            case .destructive:
                return (true, .white)
            }
        }()

        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(resolved.tint)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(resolved.isDestructive ? .white : .primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(resolved.isDestructive ? .white.opacity(0.85) : .secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(12)
        .background {
                ZStack {
                    if resolved.isDestructive {
                        shape.fill(.red)
                    }
                    glassLayer
                }
            }
        .overlay(
            shape.stroke(
                resolved.isDestructive ? Color.white.opacity(0.35) : Color.secondary.opacity(0.15),
                lineWidth: 1
            )
        )
    }

    init(title: String, systemImage: String, subtitle: String? = nil, style: Style) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.style = style
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: tileShape)
                .opacity(isDestructive ? 0.35 : 1.0)
        } else if isDestructive {
            tileShape.fill(Color.white.opacity(0.12))
        } else {
            tileShape.fill(.ultraThinMaterial)
        }
    }
}

private struct RatioChip: View {
    let ratio: RatioRef
    let isSelected: Bool

    var body: some View {
        let display = RatioMath.unitLabel(ratio.p, ratio.q)
        HStack(spacing: 6) {
            Text(display)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if ratio.octave != 0 {
                Text(ratio.octave > 0 ? "+\(ratio.octave)" : "\(ratio.octave)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? .thinMaterial : .ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct DegreeRow: View {
    let ratio: RatioRef
    let rootHz: Double
    let isSelected: Bool

    var body: some View {
        let (p, q) = RatioMath.canonicalPQUnit(ratio.p, ratio.q)
        let hz = RatioMath.hz(rootHz: rootHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: true)
        let cents = NotationFormatter.centsFromNearestET(freqHz: hz)
        let note = NotationFormatter.spelledETNote(freqHz: hz)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(p)/\(q)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    if ratio.octave != 0 {
                        Text(ratio.octave > 0 ? "+\(ratio.octave) oct" : "\(ratio.octave) oct")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                Text("\(note.letter)\(note.accidental)\(note.octave)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.2f Hz", hz))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if abs(cents) >= 1 {
                    let rounded = Int(cents.rounded())
                    let sign = rounded >= 0 ? "+" : "−"
                    Text("\(sign)\(abs(rounded))¢")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(isSelected ? .thinMaterial : .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct RemovableChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}
