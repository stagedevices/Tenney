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

private enum OrganizeRoute: Identifiable, Hashable {
    case pickPack(scaleID: UUID)

    var id: String {
        switch self {
        case .pickPack(let scaleID):
            return "pick-pack-\(scaleID)"
        }
    }
}

private enum ScaleSheetRoute: Identifiable, Hashable {
    case actions(scaleID: UUID)
    case organize(OrganizeRoute)

    var id: String {
        switch self {
        case .actions(let scaleID):
            return "actions-\(scaleID)"
        case .organize(let route):
            return "organize-\(route.id)"
        }
    }
}

struct ScaleLibrarySheet: View {
    @State private var libraryPage: Int = 0
    @State private var didApplyLaunchMode = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @ObservedObject private var communityPacks = CommunityPacksStore.shared
    @AppStorage(SettingsKeys.libraryFiltersJSON) private var libraryFiltersJSON: String = ""
    @AppStorage(SettingsKeys.librarySearchText) private var librarySearchText: String = ""
    @AppStorage(SettingsKeys.libraryFavoritesOnly) private var libraryFavoritesOnly: Bool = false
    @AppStorage(SettingsKeys.librarySortKey) private var librarySortKeyRaw: String = ScaleLibraryStore.SortKey.recent.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSearchPresented = false
    @State private var filters: LibraryFilters = .defaultValue
    @State private var showFilterSheet = false
    @State private var didLoadFilters = false
    @State private var scaleSheetRoute: ScaleSheetRoute? = nil
    @State private var selectedPack: PackSummary? = nil
    @State private var selectedCommunityPack: CommunityPackViewModel? = nil
    @State private var newPackName: String = ""
    @State private var showNewPackPrompt: Bool = false
    @State private var packCreationContext: PackCreationContext? = nil
    @State private var renamePackTarget: PackRef? = nil
    @State private var renamePackTitle: String = ""
    @State private var deletePackTarget: PackRef? = nil
    @State private var infoPackTarget: PackSummary? = nil
    @Namespace private var communityPackNamespace
    @State private var moveToast: MoveToast? = nil
    @State private var moveToastTask: Task<Void, Never>? = nil

    private var isSearching: Bool {
        isSearchPresented || !librarySearchText.isEmpty
    }
    
    private var overlayTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92))
    }

    private var overlayAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2)
    }

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
        NavigationStack {
            mainContent
                .overlay(alignment: .bottom) {
                    if let moveToast {
                        MoveToastView(
                            title: "Moved to \(moveToast.destinationTitle)",
                            onUndo: { undoMove(toast: moveToast) }
                        )
                        .transition(.opacity)
                        .padding(.bottom, 12)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Library")
                .searchable(
                    text: $librarySearchText,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .automatic)
                )
                .modifier(SearchPresentationToolbarHidden())
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showNewPackPrompt = true
                        } label: {
                            Label("New Pack", systemImage: "folder.badge.plus")
                        }
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: moveToast?.id)
            
            // Per-scale actions and organize sheet
            .sheet(item: $scaleSheetRoute) { route in
                switch route {
                case .actions(let scaleID):
                    if let scale = library.scales[scaleID] {
                        ScaleActionsSheet(
                            scale: scale,
                            onOpen: { openInBuilder(scale) },
                            onAdd:  { addToBuilder(scale) },
                            onMoveToPack: { beginMoveToPack(scaleID: scale.id) },
                            onDuplicateToUserPack: { duplicateScaleToUser(scaleID: scale.id) }
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
                case .organize(.pickPack(let scaleID)):
                    if let scale = library.scales[scaleID] {
                        PackPickerSheet(
                            scale: scale,
                            packSummaries: library.allPackSummaries(),
                            onMove: { pack in
                                handleMove(scaleID: scale.id, to: pack)
                                scaleSheetRoute = nil
                            },
                            onCreatePack: { title in
                                let packRef = makeUserPack(title: title)
                                return packRef
                            },
                            onClose: { scaleSheetRoute = nil }
                        )
                        .presentationDetents([.medium, .large])
                    }
                }
            }
            .fullScreenCover(item: $selectedPack) { pack in
                PackDetailSheet(
                    pack: pack,
                    scales: scalesForPack(pack),
                    onPickScale: { openScaleActions($0) },
                    onMoveToPack: { beginMoveToPack(scaleID: $0.id) },
                    openInBuilder: openInBuilder,
                    addToBuilder: addToBuilder,
                    playScalePreview: playScalePreview
                )
            }
            .fullScreenCover(item: $selectedCommunityPack) { pack in
                NavigationStack {
                    CommunityPackDetailView(
                        pack: pack,
                        namespace: communityPackNamespace,
                        onPreviewRequested: handleCommunityPackPreviewRequest
                    )
                }
                .presentationBackground(PremiumModalSurface.background)
            }
            .sheet(item: $packCreationContext) { context in
                PackCreationSheet(
                    title: context.title,
                    scales: filteredScales,
                    onCancel: { packCreationContext = nil },
                    onCreate: { selected in
                        guard !selected.isEmpty else {
                            packCreationContext = nil
                            return
                        }
                        let packRef = makeUserPack(title: context.title)
                        library.assignPack(packRef, to: selected)
                        packCreationContext = nil
                    }
                )
            }
            .sheet(item: $infoPackTarget) { info in
                PackInfoSheet(pack: info)
                    .presentationDetents([.medium])
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
            .alert("New Pack", isPresented: $showNewPackPrompt) {
                TextField("Pack name", text: $newPackName)
                Button("Create") {
                    let trimmed = newPackName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    packCreationContext = PackCreationContext(title: trimmed)
                    newPackName = ""
                }
                Button("Cancel", role: .cancel) {
                    newPackName = ""
                }
            } message: {
                Text("Create a new pack and pick scales to include.")
            }
            .alert("Rename Pack", isPresented: Binding(
                get: { renamePackTarget != nil },
                set: { if !$0 { renamePackTarget = nil } }
            )) {
                TextField("Pack name", text: $renamePackTitle)
                Button("Rename") {
                    guard let target = renamePackTarget else { return }
                    library.renamePack(id: target.id, newTitle: renamePackTitle)
                    renamePackTarget = nil
                    renamePackTitle = ""
                }
                Button("Cancel", role: .cancel) {
                    renamePackTarget = nil
                    renamePackTitle = ""
                }
            } message: {
                Text("Rename this pack across its scales.")
            }
            .alert("Delete Pack?", isPresented: Binding(
                get: { deletePackTarget != nil },
                set: { if !$0 { deletePackTarget = nil } }
            )) {
                Button("Delete Pack", role: .destructive) {
                    guard let target = deletePackTarget else { return }
                    library.deletePack(id: target.id)
                    deletePackTarget = nil
                }
                Button("Cancel", role: .cancel) { deletePackTarget = nil }
            } message: {
                Text("Scales in this pack will move to Loose Scales.")
            }
        }
        .overlay(alignment: .topTrailing) {
            // Overlay keeps dismissal off the nav bar and anchored to the sheet's top edge.
            Group {
                if isSearching {
                    Button(action: cancelSearch) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .modifier(GlassWhiteCircle())
                    }
                    .buttonStyle(.plain)
                    .transition(overlayTransition)
                } else {
                    GlassDismissCircleButton { dismiss() }
                        .transition(overlayTransition)
                }
            }
            .padding(.top, 20)
            .padding(.trailing, 20)
        }
        .animation(overlayAnimation, value: isSearching)
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
            library.repairCommunityPackMetadata(using: communityPacks.packs)
        }
        .onReceive(communityPacks.$packs) { packs in
            library.repairCommunityPackMetadata(using: packs)
        }
        .onChange(of: filters) { _ in
            persistFilters()
        }
        .onChange(of: library.sortKey) { newValue in
            librarySortKeyRaw = newValue.rawValue
        }
    }

    private var mainContent: some View {
        ZStack {
            libraryGlassBackground
                .ignoresSafeArea()
            VStack(spacing: 0) {
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
                    libraryPages
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }

                PagePips(page: $libraryPage, labels: ["Packs", "Collections by Limit", "Community Packs"])
                    .padding(.bottom, 10)
            }
        }
    }

    private var libraryPages: some View {
        TabView(selection: $libraryPage) {
            PackBrowserPageList(
                filteredScales: filteredScales,
                searchText: librarySearchText,
                onPickScale: { openScaleActions($0) },
                onMoveToPack: { beginMoveToPack(scaleID: $0.id) },
                onOpenPack: { selectedPack = $0 },
                onOpenPackInfo: { infoPackTarget = $0 },
                onRenamePack: beginRenamePack,
                onDeletePack: { deletePackTarget = $0 },
                onOpenCommunityPack: { selectedCommunityPack = $0 },
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
            openScaleActions(request.scale)
        }
    }

}

private struct SearchPresentationToolbarHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.searchPresentationToolbar(.hidden)
        } else {
            content
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


private struct PackCreationContext: Identifiable {
    let id = UUID()
    let title: String
}

private struct PackBrowserPageList: View {
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared

    let filteredScales: [TenneyScale]
    let searchText: String
    let onPickScale: (TenneyScale) -> Void
    let onMoveToPack: (TenneyScale) -> Void
    let onOpenPack: (PackSummary) -> Void
    let onOpenPackInfo: (PackSummary) -> Void
    let onRenamePack: (PackRef) -> Void
    let onDeletePack: (PackRef) -> Void
    let onOpenCommunityPack: (CommunityPackViewModel) -> Void
    let openInBuilder: (TenneyScale) -> Void
    let addToBuilder: (TenneyScale) -> Void
    let playScalePreview: (TenneyScale) -> Void
    let onClearFilters: () -> Void

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearch.isEmpty
    }

    private var favorites: [TenneyScale] {
        filteredScales.filter { library.favoriteIDs.contains($0.id) }
    }

    private var recents: [TenneyScale] {
        filteredScales
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    private var looseScales: [TenneyScale] {
        filteredScales.filter { $0.pack == nil }
    }

    private var packGroups: [PackSummary] {
        let grouped = Dictionary(grouping: filteredScales.compactMap { scale in
            scale.pack.map { ($0, scale) }
        }, by: { $0.0.id })
        return grouped.compactMap { _, values in
            guard let packRef = values.first?.0 else { return nil }
            let count = values.count
            let subtitle = "\(count) scale\(count == 1 ? "" : "s")"
            return PackSummary(
                id: packRef.id,
                title: packRef.title,
                subtitle: subtitle,
                count: count,
                source: packRef.source,
                packRef: packRef,
                kind: .realPack(packRef)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var communityPacksSummaries: [PackSummary] {
        packGroups.filter { $0.source == .community }
    }

    private var builtInSummaries: [PackSummary] {
        packGroups.filter { $0.source == .builtIn }
    }

    private var userSummaries: [PackSummary] {
        packGroups.filter { $0.source == .user }
    }

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
            } else if isSearching {
                Section("Results (\(filteredScales.count))") {
                    ForEach(filteredScales) { s in
                        Button { onPickScale(s) } label: {
                            ScaleRow(
                                scale: s,
                                tagRefs: tagStore.tags(for: s.tagIDs),
                                disclosure: true,
                                packBadge: packBadgeInfo(for: s)
                            )
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
                            Button("Move to Pack…") { onMoveToPack(s) }
                                .disabled(s.provenance?.kind == .communityPack)
                        }
                    }
                }
            } else {
                Section {
                    Button { onOpenPack(favoritesSummary) } label: {
                        PackRow(pack: favoritesSummary, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)

                    Button { onOpenPack(recentsSummary) } label: {
                        PackRow(pack: recentsSummary, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Library")
                }

                Section {
                    NavigationLink {
                        CommunityPackFolderList(
                            packs: communityPacksSummaries,
                            onOpenCommunityPack: onOpenCommunityPack,
                            onPickScale: onPickScale
                        )
                    } label: {
                        PackRow(pack: communitySuperFolderSummary, showsDisclosure: true)
                    }
                }

                if !builtInSummaries.isEmpty {
                    Section("Built-in Packs") {
                        ForEach(builtInSummaries) { pack in
                            Button { onOpenPack(pack) } label: {
                                PackRow(pack: pack, showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Info") { onOpenPackInfo(pack) }
                            }
                        }
                    }
                }

                if !userSummaries.isEmpty {
                    Section("Your Packs") {
                        ForEach(userSummaries) { pack in
                            Button { onOpenPack(pack) } label: {
                                PackRow(pack: pack, showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename") {
                                    guard let packRef = pack.packRef else { return }
                                    onRenamePack(packRef)
                                }
                                Button("Info") { onOpenPackInfo(pack) }
                                Button("Delete", role: .destructive) {
                                    guard let packRef = pack.packRef else { return }
                                    onDeletePack(packRef)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { onOpenPack(looseSummary) } label: {
                        PackRow(pack: looseSummary, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listStyle(.insetGrouped)
    }

    private var favoritesSummary: PackSummary {
        let count = favorites.count
        return PackSummary(
            id: "favorites",
            title: "Favorites",
            subtitle: "\(count) scale\(count == 1 ? "" : "s")",
            count: count,
            source: nil,
            packRef: nil,
            kind: .favorites
        )
    }

    private var recentsSummary: PackSummary {
        let count = recents.count
        return PackSummary(
            id: "recents",
            title: "Recents",
            subtitle: "\(count) scale\(count == 1 ? "" : "s")",
            count: count,
            source: nil,
            packRef: nil,
            kind: .recents
        )
    }

    private var communitySuperFolderSummary: PackSummary {
        let count = communityPacksSummaries.count
        return PackSummary(
            id: "community",
            title: "Community Packs",
            subtitle: "\(count) pack\(count == 1 ? "" : "s")",
            count: count,
            source: .community,
            packRef: nil,
            kind: .communitySuperFolder
        )
    }

    private var looseSummary: PackSummary {
        let count = looseScales.count
        return PackSummary(
            id: "loose",
            title: "Loose Scales",
            subtitle: "\(count) scale\(count == 1 ? "" : "s")",
            count: count,
            source: nil,
            packRef: nil,
            kind: .loose
        )
    }

    private func packBadgeInfo(for scale: TenneyScale) -> PackBadgeInfo? {
        if let pack = scale.pack {
            return PackBadgeInfo(title: pack.title, source: pack.source)
        }
        if let provenance = scale.provenance, provenance.kind == .communityPack {
            return PackBadgeInfo(title: provenance.packName, source: .community)
        }
        return PackBadgeInfo(title: "Loose", source: nil)
    }
}

private struct CommunityPackFolderList: View {
    let packs: [PackSummary]
    let onOpenCommunityPack: (CommunityPackViewModel) -> Void
    let onPickScale: (TenneyScale) -> Void
    @ObservedObject private var communityPacks = CommunityPacksStore.shared
    @ObservedObject private var library = ScaleLibraryStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedPackIDs: Set<String> = []
    @State private var didLoadExpandedPackIDs = false
    private let expandedStorageKey = "communityPacks.expandedPackIDs"

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if packs.isEmpty {
                    ContentUnavailableView(
                        "No installed community packs",
                        systemImage: "shippingbox",
                        description: Text("Install a pack to see it here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else {
                    Text("Installed Packs")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    ForEach(packs) { pack in
                        let packViewModel = communityPackViewModel(for: pack)
                        let packKey = stablePackKey(for: pack, packViewModel: packViewModel)
                        let isExpanded = expandedPackIDs.contains(packKey)
                        let installedScales = installedScales(for: packViewModel?.packID)
                        CommunityPackDisclosureCard(
                            title: pack.title,
                            subtitle: packSubtitle(for: pack, scaleCount: installedScales.count),
                            updateAvailable: packViewModel.map { communityPacks.isUpdateAvailable($0.packID) } ?? false,
                            isExpanded: isExpanded,
                            reduceMotion: reduceMotion,
                            onToggle: { toggleExpanded(packKey) },
                            scales: installedScales,
                            onPickScale: onPickScale
                        ) {
                            if let packViewModel {
                                if communityPacks.isUpdateAvailable(packViewModel.packID) {
                                    Button("Update") {
                                        communityPacks.enqueueInstall(pack: packViewModel, action: .update)
                                    }
                                }
                                Button("Info") { onOpenCommunityPack(packViewModel) }
                                Button("Uninstall", role: .destructive) {
                                    handleUninstall(packID: packViewModel.packID, packKey: packKey)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .navigationTitle("Community Packs")
        .onAppear {
            loadExpandedPackIDsIfNeeded()
        }
        .onChange(of: packs.map(\.id)) { _ in
            sanitizeExpandedPackIDs()
        }
        .onChange(of: communityPacks.packs.map(\.packID)) { _ in
            sanitizeExpandedPackIDs()
        }
    }

    private func communityPackViewModel(for pack: PackSummary) -> CommunityPackViewModel? {
        let slug = pack.packRef?.slug ?? pack.packRef?.id.replacingOccurrences(of: "community:", with: "")
        guard let slug else { return nil }
        return communityPacks.packs.first(where: { $0.packID == slug })
    }

    private func stablePackKey(for pack: PackSummary, packViewModel: CommunityPackViewModel?) -> String {
        if let id = pack.packRef?.id, id.hasPrefix("community:") {
            return id
        }
        if let slug = pack.packRef?.slug ?? packViewModel?.packID {
            return "community:\(slug)"
        }
        return "community:\(pack.id)"
    }

    private func packSubtitle(for pack: PackSummary, scaleCount: Int) -> String {
        let count = max(scaleCount, pack.count)
        return "\(count) scale\(count == 1 ? "" : "s") • Installed"
    }

    private func installedScales(for packID: String?) -> [TenneyScale] {
        guard let packID else { return [] }
        let scales = library.scales.values.filter { scale in
            if scale.provenance?.packID == packID {
                return true
            }
            if scale.pack?.source == .community, scale.pack?.slug == packID {
                return true
            }
            return false
        }
        return scales.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func toggleExpanded(_ key: String) {
        let animation = reduceMotion ? Animation.easeOut(duration: 0.15) : .snappy(duration: 0.35)
        withAnimation(animation) {
            if expandedPackIDs.contains(key) {
                expandedPackIDs.remove(key)
            } else {
                expandedPackIDs.insert(key)
            }
        }
        persistExpandedPackIDs()
    }

    private func handleUninstall(packID: String, packKey: String) {
        expandedPackIDs.remove(packKey)
        persistExpandedPackIDs()
        Task {
            await communityPacks.uninstallPack(packID: packID)
        }
    }

    private func loadExpandedPackIDsIfNeeded() {
        guard !didLoadExpandedPackIDs else { return }
        didLoadExpandedPackIDs = true
        if let stored = UserDefaults.standard.stringArray(forKey: expandedStorageKey) {
            expandedPackIDs = Set(stored)
        }
        sanitizeExpandedPackIDs()
    }

    private func sanitizeExpandedPackIDs() {
        let validPackKeys = Set(packs.map { stablePackKey(for: $0, packViewModel: communityPackViewModel(for: $0)) })
        let sanitized = expandedPackIDs.intersection(validPackKeys)
        guard sanitized != expandedPackIDs else { return }
        expandedPackIDs = sanitized
        persistExpandedPackIDs()
    }

    private func persistExpandedPackIDs() {
        UserDefaults.standard.set(Array(expandedPackIDs), forKey: expandedStorageKey)
    }
}

private struct CommunityPackDisclosureCard<MenuContent: View>: View {
    let title: String
    let subtitle: String
    let updateAvailable: Bool
    let isExpanded: Bool
    let reduceMotion: Bool
    let onToggle: () -> Void
    let scales: [TenneyScale]
    let onPickScale: (TenneyScale) -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    HStack(spacing: 12) {
                        communityBadge
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline.weight(.semibold))
                            HStack(spacing: 8) {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if updateAvailable {
                                    Text("Update available")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(isExpanded ? .degrees(90) : .degrees(0))
                            .foregroundStyle(.secondary)
                            .animation(
                                reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.35),
                                value: isExpanded
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Menu(content: menuContent) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
            }

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(scales) { scale in
                        Button {
                            onPickScale(scale)
                        } label: {
                            CommunityPackScaleInlineRow(scale: scale)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(PremiumModalSurface.cardSurface(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var communityBadge: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
            Image(systemName: "person.3.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 36, height: 36)
    }
}

private struct CommunityPackScaleInlineRow: View {
    let scale: TenneyScale

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scale.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(scale.detectedLimit)-limit • \(scale.size) notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .contentShape(Rectangle())
    }
}

private struct PackRow: View {
    let pack: PackSummary
    let showsDisclosure: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(pack.title)
                    .font(.headline.weight(.semibold))
                HStack(spacing: 8) {
                    if let subtitle = pack.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let source = pack.source {
                        PackSourceBadge(source: source)
                    }
                }
            }
            Spacer()
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct PackBadgeInfo {
    let title: String
    let source: PackRef.Source?
}

private struct PackSourceBadge: View {
    let source: PackRef.Source

    var body: some View {
        Text(source.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

private struct PackDetailSheet: View {
    let pack: PackSummary
    let scales: [TenneyScale]
    let onPickScale: (TenneyScale) -> Void
    let onMoveToPack: (TenneyScale) -> Void
    let openInBuilder: (TenneyScale) -> Void
    let addToBuilder: (TenneyScale) -> Void
    let playScalePreview: (TenneyScale) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared

    var body: some View {
        NavigationStack {
            List {
                if scales.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No scales in this pack",
                            systemImage: "tray",
                            description: Text("Move a scale into this pack to get started.")
                        )
                    }
                } else {
                    Section {
                        ForEach(scales) { s in
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
                                Button("Move to Pack…") { onMoveToPack(s) }
                                    .disabled(s.provenance?.kind == .communityPack)
                            }
                        }
                    } header: {
                        Text("\(pack.title) (\(scales.count))")
                    }
                }
            }
            .navigationTitle(pack.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum PackDestination: Hashable, Identifiable {
    case loose
    case pack(PackRef)

    var id: String {
        switch self {
        case .loose:
            return "loose"
        case .pack(let pack):
            return pack.id
        }
    }

    var packRef: PackRef? {
        switch self {
        case .loose:
            return nil
        case .pack(let pack):
            return pack
        }
    }

    static func from(pack: PackRef?) -> PackDestination {
        guard let pack else { return .loose }
        return .pack(pack)
    }
}

private struct PackPickerSheet: View {
    let scale: TenneyScale
    let packSummaries: [PackSummary]
    let onMove: (PackRef?) -> Void
    let onCreatePack: (String) -> PackRef
    let onClose: () -> Void

    @State private var searchText: String = ""
    @State private var newPackName: String = ""
    @State private var selectedDestination: PackDestination
    @State private var extraUserPacks: [PackRef] = []
    private let initialDestination: PackDestination

    init(
        scale: TenneyScale,
        packSummaries: [PackSummary],
        onMove: @escaping (PackRef?) -> Void,
        onCreatePack: @escaping (String) -> PackRef,
        onClose: @escaping () -> Void
    ) {
        self.scale = scale
        self.packSummaries = packSummaries
        self.onMove = onMove
        self.onCreatePack = onCreatePack
        self.onClose = onClose
        let initial = PackDestination.from(pack: scale.pack)
        _selectedDestination = State(initialValue: initial)
        initialDestination = initial
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentPackSummaries: [PackSummary] {
        let recentIDs = PackRecentsStore.load()
        let mapped = Dictionary(uniqueKeysWithValues: packSummaries.compactMap { summary in
            summary.packRef.map { (summary.id, summary) }
        })
        let ordered = recentIDs.compactMap { mapped[$0] }
        if trimmedSearch.isEmpty {
            return Array(ordered.prefix(5))
        }
        return ordered.filter { $0.title.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private var userPackSummaries: [PackSummary] {
        let extras = extraUserPacks.map { pack in
            PackSummary(
                id: pack.id,
                title: pack.title,
                subtitle: "Empty",
                count: 0,
                source: pack.source,
                packRef: pack,
                kind: .realPack(pack)
            )
        }
        let combined = packSummaries.filter { $0.source == .user } + extras
        let deduped = Dictionary(grouping: combined, by: \.id).compactMap { $0.value.first }
        return filterPacks(deduped)
    }

    private var builtInPackSummaries: [PackSummary] {
        filterPacks(packSummaries.filter { $0.source == .builtIn })
    }

    private var communityPackSummaries: [PackSummary] {
        filterPacks(packSummaries.filter { $0.source == .community })
    }

    private var canMove: Bool {
        selectedDestination != initialDestination
    }

    var body: some View {
        NavigationStack {
            List {
                if !recentPackSummaries.isEmpty {
                    Section("Recents") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentPackSummaries) { summary in
                                    if let packRef = summary.packRef {
                                        Button {
                                            selectedDestination = .pack(packRef)
                                        } label: {
                                            FilterChip(label: summary.title, systemImage: "clock")
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(summary.title)
                                        .accessibilityValue(selectedDestination.id == packRef.id ? "Selected" : "")
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("New Pack") {
                    HStack(spacing: 12) {
                        TextField("New pack name", text: $newPackName)
                            .textFieldStyle(.plain)
                            .submitLabel(.done)
                            .onSubmit { createPack() }
                        Button("Create") {
                            createPack()
                        }
                        .disabled(newPackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Destination") {
                    packRow(title: "Loose Scales", subtitle: "No pack", destination: .loose)
                }

                if !userPackSummaries.isEmpty {
                    Section("User Packs") {
                        ForEach(userPackSummaries) { pack in
                            if let packRef = pack.packRef {
                                packRow(
                                    title: pack.title,
                                    subtitle: pack.subtitle,
                                    destination: .pack(packRef)
                                )
                            }
                        }
                    }
                }

                if !builtInPackSummaries.isEmpty {
                    Section("Built-in Packs") {
                        ForEach(builtInPackSummaries) { pack in
                            if let packRef = pack.packRef {
                                packRow(
                                    title: pack.title,
                                    subtitle: pack.subtitle,
                                    destination: .pack(packRef)
                                )
                            }
                        }
                    }
                }

                if !communityPackSummaries.isEmpty {
                    Section("Community Packs") {
                        ForEach(communityPackSummaries) { pack in
                            if let packRef = pack.packRef {
                                packRow(
                                    title: pack.title,
                                    subtitle: pack.subtitle,
                                    destination: .pack(packRef)
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to Pack")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onClose() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Move") {
                        onMove(selectedDestination.packRef)
                    }
                    .disabled(!canMove)
                }
            }
        }
    }

    private func createPack() {
        let trimmed = newPackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pack = onCreatePack(trimmed)
        extraUserPacks.append(pack)
        selectedDestination = .pack(pack)
        newPackName = ""
    }

    private func filterPacks(_ packs: [PackSummary]) -> [PackSummary] {
        guard !trimmedSearch.isEmpty else {
            return packs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return packs
            .filter { $0.title.localizedCaseInsensitiveContains(trimmedSearch) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @ViewBuilder
    private func packRow(title: String, subtitle: String?, destination: PackDestination) -> some View {
        Button {
            selectedDestination = destination
        } label: {
            HStack(alignment: subtitle == nil ? .center : .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectedDestination == destination {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selectedDestination == destination ? "Selected" : "")
    }
}

private struct PackCreationSheet: View {
    let title: String
    let scales: [TenneyScale]
    let onCancel: () -> Void
    let onCreate: ([UUID]) -> Void

    @ObservedObject private var tagStore = TagStore.shared
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section("Select scales") {
                    ForEach(scales) { scale in
                        Button {
                            toggle(scale.id)
                        } label: {
                            HStack {
                                ScaleRow(scale: scale, tagRefs: tagStore.tags(for: scale.tagIDs))
                                Spacer()
                                if selectedIDs.contains(scale.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { onCreate(Array(selectedIDs)) }
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

private struct PackInfoSheet: View {
    let pack: PackSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pack.title)
                .font(.title2.weight(.semibold))
            if let subtitle = pack.subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let source = pack.source {
                Text("Source: \(source.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

private struct PackRecentsStore {
    static let maxCount = 5

    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.libraryRecentPackIDsJSON) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func record(packID: String) {
        var ids = load()
        ids.removeAll { $0 == packID }
        ids.insert(packID, at: 0)
        if ids.count > maxCount {
            ids = Array(ids.prefix(maxCount))
        }
        save(ids)
    }

    private static func save(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: SettingsKeys.libraryRecentPackIDsJSON)
        }
    }
}

private struct MoveToast: Identifiable {
    let id = UUID()
    let scaleID: UUID
    let previousPack: PackRef?
    let destinationTitle: String
}

private struct MoveToastView: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo") {
                onUndo()
            }
            .font(.callout.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(toastBackground)
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var toastBackground: some View {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

private extension PackRef.Source {
    var label: String {
        switch self {
        case .builtIn:
            return "Built-in"
        case .user:
            return "User"
        case .community:
            return "Community"
        }
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
    var packBadge: PackBadgeInfo? = nil
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
                if let packBadge {
                    PackBadge(info: packBadge)
                } else if let provenance = scale.provenance, provenance.kind == .communityPack {
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

private struct PackBadge: View {
    let info: PackBadgeInfo

    var body: some View {
        HStack(spacing: 6) {
            if let source = info.source {
                Text(source.label)
            }
            Text(info.title)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
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

    // Acceptance checklist:
    // - tap search → chevron appears, no extra X visible
    // - tap chevron → search cancels, keyboard dismisses, checkmark returns
    // - type search text → results filter; chevron remains until canceled
    // - tap checkmark when not searching → sheet dismisses
    private func cancelSearch() {
        librarySearchText = ""
        isSearchPresented = false
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
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

    func makeUserPack(title: String) -> PackRef {
        PackRef(
            source: .user,
            id: "user:\(UUID().uuidString)",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            slug: nil
        )
    }

    func beginRenamePack(_ pack: PackRef) {
        renamePackTarget = pack
        renamePackTitle = pack.title
    }

    func scalesForPack(_ pack: PackSummary) -> [TenneyScale] {
        switch pack.kind {
        case .favorites:
            return filteredScales.filter { library.favoriteIDs.contains($0.id) }
        case .recents:
            return filteredScales
                .filter { $0.lastPlayed != nil }
                .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .loose:
            return filteredScales.filter { $0.pack == nil }
        case .realPack(let packRef):
            return filteredScales.filter { $0.pack?.id == packRef.id }
        case .communitySuperFolder:
            return []
        }
    }

    func openScaleActions(_ scale: TenneyScale) {
        scaleSheetRoute = .actions(scaleID: scale.id)
    }

    func beginMoveToPack(scaleID: UUID) {
        if library.scales[scaleID]?.provenance?.kind == .communityPack {
            return
        }
        scaleSheetRoute = .organize(.pickPack(scaleID: scaleID))
    }

    func duplicateScaleToUser(scaleID: UUID) {
        guard let newID = library.duplicateScaleToUser(id: scaleID) else { return }
        scaleSheetRoute = .organize(.pickPack(scaleID: newID))
    }

    func handleMove(scaleID: UUID, to pack: PackRef?) {
        let outcome = library.moveScale(id: scaleID, to: pack)
        guard case let .moved(previous, current) = outcome else { return }
        if let packID = current?.id {
            PackRecentsStore.record(packID: packID)
        }
        let destinationTitle = current?.title ?? "Loose Scales"
        showMoveToast(scaleID: scaleID, previousPack: previous, destinationTitle: destinationTitle)
    }

    func showMoveToast(scaleID: UUID, previousPack: PackRef?, destinationTitle: String) {
        moveToastTask?.cancel()
        moveToast = MoveToast(scaleID: scaleID, previousPack: previousPack, destinationTitle: destinationTitle)
        moveToastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                moveToast = nil
            }
        }
    }

    func undoMove(toast: MoveToast) {
        moveToastTask?.cancel()
        moveToast = nil
        _ = library.moveScale(id: toast.scaleID, to: toast.previousPack)
    }
}
// MARK: - Per-scale Action Sheet (Open • Add • Play)
struct ScaleActionsSheet: View {
    @State private var isDronePlaying: Bool = false

    let scale: TenneyScale
    let onOpen: () -> Void
    let onAdd:  () -> Void
    let onMoveToPack: () -> Void
    let onDuplicateToUserPack: () -> Void
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

    private func toggleFavorite() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        _ = library.toggleFavorite(id: currentScale.id)
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

    private var isCommunityScale: Bool {
        currentScale.provenance?.kind == .communityPack
    }

    private var currentPackTitle: String {
        currentScale.pack?.title ?? "Loose Scales"
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
                                isFavorite: library.isFavorite(id: currentScale.id),
                                currentPackTitle: currentPackTitle,
                                isCommunityScale: isCommunityScale,
                                onOpen: { onOpen(); dismiss() },
                                onAdd: { onAdd(); dismiss() },
                                onExport: { showExportSheet = true },
                                onCopyRatios: { copyRatios() },
                                onCopyJSON: { copyJSON() },
                                onCopySCL: { copySCL() },
                                onCommitTitle: { commitScaleRename($0) },
                                onTags: { showTagsSheet = true },
                                onToggleFavorite: { toggleFavorite() },
                                onMoveToPack: { onMoveToPack() },
                                onDuplicateToUserPack: { onDuplicateToUserPack() },
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
    let isFavorite: Bool
    let currentPackTitle: String
    let isCommunityScale: Bool
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onExport: () -> Void
    let onCopyRatios: () -> Void
    let onCopyJSON: () -> Void
    let onCopySCL: () -> Void
    let onCommitTitle: (String) -> Void
    let onTags: () -> Void
    let onToggleFavorite: () -> Void
    let onMoveToPack: () -> Void
    let onDuplicateToUserPack: () -> Void
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
                    Text("Organize")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Button(action: onToggleFavorite) {
                        OrganizeRow(
                            title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            subtitle: nil,
                            systemImage: isFavorite ? "star.fill" : "star",
                            showsChevron: false,
                            iconColor: .yellow
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: onMoveToPack) {
                        OrganizeRow(
                            title: "Move to Pack…",
                            subtitle: currentPackTitle,
                            systemImage: "folder",
                            showsChevron: true,
                            isEnabled: !isCommunityScale
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isCommunityScale)

                    if isCommunityScale {
                        Text("Community scales can’t be moved. Duplicate to a User Pack first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isCommunityScale {
                        Button(action: onDuplicateToUserPack) {
                            OrganizeRow(
                                title: "Duplicate to User Pack…",
                                subtitle: nil,
                                systemImage: "doc.on.doc",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
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

private struct OrganizeRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let showsChevron: Bool
    var isEnabled: Bool = true
    var iconColor: Color? = nil

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(isEnabled ? (iconColor ?? .primary) : .secondary)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
