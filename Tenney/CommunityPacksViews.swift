import SwiftUI
import UIKit

struct CommunityPackPreviewRequest {
    let packID: String
    let scaleID: String
    let scale: TenneyScale
}

private func communityScaleForFiltering(pack: CommunityPackViewModel, scale: CommunityPackScaleViewModel) -> TenneyScale {
    let provenance = TenneyScale.Provenance(
        kind: .communityPack,
        packID: pack.packID,
        packName: pack.title,
        authorName: pack.authorName,
        installedVersion: pack.version
    )
    let title = scale.payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedName = title.isEmpty ? scale.title : title
    return TenneyScale(
        id: communityScaleUUID(packID: pack.packID, scaleID: scale.id),
        name: resolvedName,
        descriptionText: scale.payload.notes,
        degrees: scale.payload.refs,
        tagIDs: [],
        favorite: false,
        lastPlayed: nil,
        referenceHz: scale.payload.rootHz,
        rootLabel: nil,
        detectedLimit: TenneyScale.detectedLimit(for: scale.payload.refs),
        periodRatio: 2.0,
        maxTenneyHeight: TenneyScale.maxTenneyHeight(for: scale.payload.refs),
        author: pack.authorName,
        provenance: provenance
    )
}

struct CommunityPackBadge: View {
    let packName: String

    var body: some View {
        HStack(spacing: 6) {
            Text("Community")
                .font(.caption2.weight(.semibold))
            Text(packName)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.secondary.opacity(0.12))
        )
    }
}

struct CommunityPacksPageList: View {
    let sortKey: ScaleLibraryStore.SortKey
    let filters: LibraryFilters
    let favoritesOnly: Bool
    let searchText: String
    let onClearFilters: () -> Void
    let onPreviewRequested: (CommunityPackPreviewRequest) -> Void
    @ObservedObject private var store = CommunityPacksStore.shared
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @State private var didTriggerRefresh = false
    @State private var selectedPack: CommunityPackViewModel?
    @Namespace private var packNamespace

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if store.showingCachedBanner {
                        OfflineBanner()
                    }

                    CommunityPacksHeader(
                        installedCount: installedCount,
                        availableCount: availableCount,
                        updatesCount: updatesCount
                    )

                    if case .schemaMismatch = store.state {
                        ContentUnavailableView(
                            "This pack format is newer than your app",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Update Tenney to browse Community Packs.")
                        )
                        .padding(.top, 12)
                    } else if case .failed(let message) = store.state, store.packs.isEmpty {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                "Community Packs unavailable",
                                systemImage: "wifi.slash",
                                description: Text(message)
                            )
                            Button("Retry") {
                                Task {
                                    await store.refresh(force: true)
                                }
                            }
                        }
                        .padding(.top, 12)
                    } else if store.packs.isEmpty, case .loading = store.state {
                        ProgressView("Loading Community Packs…")
                            .padding(.top, 20)
                    } else {
                        let filteredPacks = filteredPacks()
                        if filteredPacks.isEmpty {
                            FullPageEmptyState(
                                onClearFilters: onClearFilters
                            )
                            .frame(minHeight: proxy.size.height * 0.6)
                        } else {
                            CommunityPacksSections(
                                filteredPacks: filteredPacks,
                                selectedPack: $selectedPack,
                                namespace: packNamespace
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .refreshable {
                await store.refresh(force: true)
            }
        }
        .fullScreenCover(item: $selectedPack) { pack in
            CommunityPackDetailView(
                pack: pack,
                namespace: packNamespace,
                onPreviewRequested: onPreviewRequested
            )
        }
        .task {
            guard !didTriggerRefresh else { return }
            guard store.packs.isEmpty || (store.state == .idle) else { return }
            didTriggerRefresh = true
            await store.refresh(force: false)
        }
    }

    private var installedCount: Int {
        filteredPacks().filter { isInstalled($0) && !isDeleted($0) }.count
    }

    private var availableCount: Int {
        max(filteredPacks().count - installedCount, 0)
    }

    private var updatesCount: Int {
        filteredPacks().filter { updateAvailable($0) && !isDeleted($0) }.count
    }

    private func filteredPacks() -> [CommunityPackViewModel] {
        var output = store.packs.filter { packMatchesGlobalFilters($0) }
        switch sortKey {
        case .recent:
            output.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .alpha:
            output.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .size:
            output.sort { $0.scaleCount > $1.scaleCount }
        case .limit:
            output.sort { $0.primeLimitMin < $1.primeLimitMin }
        }
        return output
    }

    private func packMatchesGlobalFilters(_ pack: CommunityPackViewModel) -> Bool {
        let scaleMatch = pack.scales.contains { scale in
            let tenneyScale = communityScaleForFiltering(pack: pack, scale: scale)
            return filters.matches(
                scale: tenneyScale,
                tagStore: tagStore,
                favoritesOnly: favoritesOnly,
                searchText: searchText,
                favoriteIDs: library.favoriteIDs
            )
        }
        let metadataMatch = packMatchesMetadata(pack)
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return scaleMatch
        }
        return scaleMatch || metadataMatch
    }

    private func packMatchesMetadata(_ pack: CommunityPackViewModel) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        if pack.title.localizedCaseInsensitiveContains(query) { return true }
        if pack.authorName.localizedCaseInsensitiveContains(query) { return true }
        if pack.description.localizedCaseInsensitiveContains(query) { return true }
        if pack.summary.localizedCaseInsensitiveContains(query) { return true }
        if pack.packID.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    private func isInstalled(_ pack: CommunityPackViewModel) -> Bool {
        store.isInstalled(pack.packID)
    }

    private func updateAvailable(_ pack: CommunityPackViewModel) -> Bool {
        guard !isDeleted(pack) else { return false }
        return store.isUpdateAvailable(pack.packID)
    }

    private func isDeleted(_ pack: CommunityPackViewModel) -> Bool {
        store.isDeleted(pack.packID)
    }
}

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline • Showing cached packs")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

private struct CommunityPacksHeader: View {
    let installedCount: Int
    let availableCount: Int
    let updatesCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Community Packs")
                .font(.title2.weight(.semibold))
            Text("Hand-picked scales from the community, ready to install.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("\(installedCount)", systemImage: "checkmark.seal")
                Label("\(availableCount)", systemImage: "shippingbox")
                Label("\(updatesCount)", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PackCardSurface(cornerRadius: 20))
    }
}

private struct CommunityPacksSections: View {
    let filteredPacks: [CommunityPackViewModel]
    @Binding var selectedPack: CommunityPackViewModel?
    let namespace: Namespace.ID
    @ObservedObject private var store = CommunityPacksStore.shared

    var body: some View {
        let deleted = filteredPacks.filter { store.isDeleted($0.packID) }
        let featured = filteredPacks.filter { $0.isFeatured && !store.isDeleted($0.packID) }
        let featuredIDs = Set(featured.map { $0.packID })
        let installed = filteredPacks.filter {
            store.isInstalled($0.packID) && !featuredIDs.contains($0.packID) && !store.isDeleted($0.packID)
        }
        let availablePacks = filteredPacks.filter {
            !store.isInstalled($0.packID) && !featuredIDs.contains($0.packID) && !store.isDeleted($0.packID)
        }
        let browseAll = availablePacks + deleted.filter { !featuredIDs.contains($0.packID) }

        VStack(alignment: .leading, spacing: 18) {
            if !featured.isEmpty {
                SectionHeader(title: "Featured", systemImage: "seal.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(featured) { pack in
                            FeaturedPackCard(
                                pack: pack,
                                isInstalling: store.installingPackIDs.contains(pack.packID),
                                updateAvailable: updateAvailable(pack),
                                isInstalled: store.isInstalled(pack.packID),
                                onOpen: { selectedPack = pack },
                                onInstall: { store.enqueueInstall(pack: pack, action: action(for: pack)) },
                                namespace: namespace
                            )
                            .frame(width: 280)
                            .modifier(FeaturedScrollTransition())
                            .opacity(selectedPack?.packID == pack.packID ? 0 : 1)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            }

            SectionHeader(title: "Installed")
            if installed.isEmpty {
                Text("No community packs installed yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(installed) { pack in
                        CompactPackCard(
                            pack: pack,
                            style: .installed,
                            isInstalling: store.installingPackIDs.contains(pack.packID),
                            updateAvailable: updateAvailable(pack),
                            onOpen: { selectedPack = pack },
                            onInstall: { store.enqueueInstall(pack: pack, action: .update) },
                            namespace: namespace
                        )
                        .opacity(selectedPack?.packID == pack.packID ? 0 : 1)
                    }
                }
            }

            SectionHeader(title: "Browse all")
            LazyVStack(spacing: 10) {
                ForEach(browseAll) { pack in
                    CompactPackCard(
                        pack: pack,
                        style: .browse,
                        isInstalling: store.installingPackIDs.contains(pack.packID),
                        updateAvailable: updateAvailable(pack),
                        onOpen: { selectedPack = pack },
                        onInstall: { store.enqueueInstall(pack: pack, action: .install) },
                        namespace: namespace
                    )
                    .opacity(selectedPack?.packID == pack.packID ? 0 : 1)
                }
            }
        }
    }

    private func action(for pack: CommunityPackViewModel) -> CommunityPacksStore.InstallAction {
        updateAvailable(pack) ? .update : .install
    }

    private func updateAvailable(_ pack: CommunityPackViewModel) -> Bool {
        guard !store.isDeleted(pack.packID) else { return false }
        return store.isUpdateAvailable(pack.packID)
    }
}

private struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private enum CompactPackCardStyle {
    case installed
    case browse
}

private struct FeaturedPackCard: View {
    let pack: CommunityPackViewModel
    let isInstalling: Bool
    let updateAvailable: Bool
    let isInstalled: Bool
    let onOpen: () -> Void
    let onInstall: () -> Void
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pack.title)
                        .font(.title3.weight(.semibold))
                    Text("by \(pack.authorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                featuredBadge
            }

            if !pack.summary.isEmpty {
                Text(pack.summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label("\(pack.scaleCount)", systemImage: "music.note.list")
                Label(primeLimitLabel, systemImage: "dial.min")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            PackPrimaryActionButton(
                title: buttonTitle,
                systemImage: buttonIcon,
                isInstalling: isInstalling,
                animateSymbol: updateAvailable,
                isProminent: true,
                onPress: buttonAction
            )
        }
        .padding(16)
        .background(
            PackCardSurface(cornerRadius: 24)
                .matchedGeometryEffect(id: "pack-card-\(pack.packID)", in: namespace, isSource: true)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private var featuredBadge: some View {
        Label("FEATURED", systemImage: "seal.fill")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(.primary)
    }

    private var primeLimitLabel: String {
        if pack.primeLimitMin == pack.primeLimitMax {
            return "\(pack.primeLimitMin)-limit"
        }
        return "\(pack.primeLimitMin)–\(pack.primeLimitMax)-limit"
    }

    private var buttonTitle: String {
        if isInstalled {
            return updateAvailable ? "Update" : "Open"
        }
        return "Install"
    }

    private var buttonIcon: String {
        if isInstalled {
            return updateAvailable ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.up.forward.app"
        }
        return "arrow.down.circle.fill"
    }

    private var buttonAction: () -> Void {
        if isInstalled && !updateAvailable {
            return onOpen
        }
        return onInstall
    }
}

private struct CompactPackCard: View {
    let pack: CommunityPackViewModel
    let style: CompactPackCardStyle
    let isInstalling: Bool
    let updateAvailable: Bool
    let onOpen: () -> Void
    let onInstall: () -> Void
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            if style == .installed {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pack.title)
                    .font(.headline.weight(.semibold))
                Text(pack.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if updateAvailable && style == .installed {
                Text("Update")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            }

            PackPrimaryActionButton(
                title: buttonTitle,
                systemImage: buttonIcon,
                isInstalling: isInstalling,
                animateSymbol: updateAvailable,
                isProminent: style == .browse,
                onPress: buttonAction
            )
        }
        .padding(12)
        .background(
            PackCardSurface(cornerRadius: 16)
                .matchedGeometryEffect(id: "pack-card-\(pack.packID)", in: namespace, isSource: true)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private var buttonTitle: String {
        if style == .installed {
            return updateAvailable ? "Update" : "Open"
        }
        return "Install"
    }

    private var buttonIcon: String {
        if style == .installed {
            return updateAvailable ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.up.forward.app"
        }
        return "arrow.down.circle.fill"
    }

    private var buttonAction: () -> Void {
        if style == .installed && !updateAvailable {
            return onOpen
        }
        return onInstall
    }
}

private struct PackPrimaryActionButton: View {
    let title: String
    let systemImage: String
    let isInstalling: Bool
    let animateSymbol: Bool
    let isProminent: Bool
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 8) {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    symbolImage
                }
                Text(isInstalling ? "Installing…" : title)
                    .font(.caption.weight(.semibold))
            }
        }
        .modifier(PackButtonStyleModifier(isProminent: isProminent))
        .disabled(isInstalling)
    }

    @ViewBuilder
    private var symbolImage: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: systemImage)
                .symbolEffect(.bounce, value: animateSymbol)
        } else {
            Image(systemName: systemImage)
        }
    }
}

private struct PackButtonStyleModifier: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            content.buttonStyle(isProminent ? .bordered : .bordered)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

private struct FeaturedScrollTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
                view
                    .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                    .opacity(phase.isIdentity ? 1.0 : 0.86)
                    .offset(y: phase.isIdentity ? 0 : 6)
            }
        } else {
            content
        }
    }
}

private struct PackCardSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

private struct FullPageEmptyState: View {
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "No matching packs",
                systemImage: "shippingbox",
                description: Text("Try clearing filters or adjusting your search.")
            )
            Button("Clear filters") {
                onClearFilters()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct CommunityPackDetailView: View {
    let pack: CommunityPackViewModel
    let namespace: Namespace.ID
    let onPreviewRequested: (CommunityPackPreviewRequest) -> Void
    @ObservedObject private var store = CommunityPacksStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.communityPackLastPreviewedScaleIDs) private var lastPreviewedScaleIDsJSON: String = ""
    @AppStorage("Tenney.SoundOn") private var soundOn: Bool = true
    @AppStorage(SettingsKeys.safeAmp) private var safeAmp: Double = 0.18

    @State private var showConflictDialog = false
    @State private var showUninstallConfirm = false
    @State private var showChangelog = false
    @State private var heroVisible = false
    @State private var contentVisible = false
    @State private var selectionMode: SelectionMode = .none
    @State private var selectedScaleIDs: Set<String> = []
    @State private var selectedNewScaleIDs: Set<String> = []
    @State private var pendingAction: CommunityPacksStore.InstallAction = .install
    @State private var pendingScaleIDs: Set<String> = []
    @State private var scrollOffset: CGFloat = 0
    @State private var symbolDrawn = false
    @State private var previewPlayer = ScalePreviewPlayer()

    private enum SelectionMode {
        case none
        case installSelecting
        case updateSelecting
    }

    private var isInstalled: Bool {
        store.isInstalled(pack.packID)
    }

    private var updateAvailable: Bool {
        guard !store.isDeleted(pack.packID) else { return false }
        return store.isUpdateAvailable(pack.packID)
    }

    private var primaryActionTitle: String {
        switch selectionMode {
        case .installSelecting:
            return selectedScaleIDs.isEmpty ? "Select scales" : "Install Selected"
        case .updateSelecting:
            return selectedNewScaleIDs.isEmpty ? "Update" : "Update + Add"
        case .none:
            break
        }
        if !isInstalled { return "Install" }
        if updateAvailable { return "Update" }
        return "Preview"
    }

    var body: some View {
        detailContent
    }

    private var detailContent: some View {
        ZStack {
            PremiumModalSurface.background
                .ignoresSafeArea()

            NoiseOverlay(seed: PackVisualIdentity.stableSeed(for: pack.packID), opacity: 0.04)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("packDetailScroll")).minY)
                    }
                    .frame(height: 0)

                    headerCard
                        .opacity(heroVisible ? 1 : 0)
                        .offset(y: heroVisible ? 0 : 18)

                    DetailSectionCard(title: "What you get") {
                        HStack(spacing: 16) {
                            DetailStatView(title: "Scales", value: "\(pack.scaleCount)")
                            DetailStatView(title: "Typical limit", value: "\(typicalLimit)-limit")
                        }
                        if !pack.summary.isEmpty {
                            Text(pack.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 16)
                    .blur(radius: contentVisible ? 0 : 6)

                    DetailSectionCard(title: "Sample scales") {
                        VStack(spacing: 10) {
                            ForEach(visibleScales) { scale in
                                CommunityScaleRow(
                                    scale: scale,
                                    packID: pack.packID,
                                    showsSelection: selectionMode != .none,
                                    isSelected: isScaleSelected(scale),
                                    isSelectable: isScaleSelectable(scale),
                                    isUpdating: isScaleUpdating(scale),
                                    isNew: newScaleIDs.contains(scale.id),
                                    canPreviewInLibrary: showsPreviewActions,
                                    onToggleSelection: { toggleSelection(for: scale) },
                                    onPlay: { playScalePreview(scale) },
                                    onPreviewInLibrary: { handleScalePreview(scale) }
                                )
                            }
                        }
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 16)
                    .blur(radius: contentVisible ? 0 : 6)

                    DetailSectionCard(title: "Version & updates") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Label(pack.version, systemImage: "tag")
                                if let updated = pack.lastUpdated {
                                    Label(updated.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if !trimmedChangelog.isEmpty {
                                DisclosureGroup(isExpanded: $showChangelog) {
                                    Text(trimmedChangelog)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                } label: {
                                    Text("Changelog")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 16)
                    .blur(radius: contentVisible ? 0 : 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .safeAreaInset(edge: .top) { detailToolbar }
            .safeAreaInset(edge: .bottom) { detailActionBar }
            .coordinateSpace(name: "packDetailScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                scrollOffset = offset
            }
        }
        .onAppear(perform: startReveal)
        .onAppear {
            symbolDrawn = true
        }
        .onDisappear {
            previewPlayer.stop()
        }
        .presentationBackground(PremiumModalSurface.background)
        .confirmationDialog(
            "Some scales already exist in your Library.",
            isPresented: $showConflictDialog,
            titleVisibility: .visible
        ) {
            Button("Overwrite All", role: .destructive) { resolveInstall(.overwrite) }
            Button("Keep Existing") { resolveInstall(.keepExisting) }
            Button("Duplicate as Local Copy") { resolveInstall(.duplicate) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how you’d like to handle these collisions.")
        }
        .confirmationDialog(
            "Uninstall this pack?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) { store.uninstall(pack: pack) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes scales installed from this pack but keeps any local copies you created.")
        }
    }

    private var headerCard: some View {
        let identity = PackVisualIdentity.identity(for: pack.packID, accent: .accentColor)
        let parallax = max(min(-scrollOffset / 10, 12), -12)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pack.title)
                        .font(.largeTitle.weight(.semibold))
                    Text("by \(pack.authorName)")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    if !pack.description.isEmpty {
                        Text(pack.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                heroSymbolTile(symbol: identity.symbol, colors: identity.colors, parallax: parallax)
            }

            HStack(spacing: 10) {
                if !pack.license.isEmpty {
                    Label(pack.license, systemImage: "doc.plaintext")
                }
                Label(pack.version, systemImage: "tag")
                if let updated = pack.lastUpdated {
                    Label(updated.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if pack.isFeatured {
                    premiumBadge(title: "FEATURED", systemImage: "seal.fill")
                }
                if updateAvailable {
                    premiumBadge(title: "UPDATE", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PremiumModalSurface.cardSurface(cornerRadius: 28)
                .matchedGeometryEffect(id: "pack-card-\(pack.packID)", in: namespace, isSource: false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 3)
        )
    }

    private var visibleScales: [CommunityPackScaleViewModel] {
        if selectionMode == .none {
            return Array(pack.scales.prefix(8))
        }
        return pack.scales
    }

    private var typicalLimit: Int {
        let limits = pack.scales.map { $0.primeLimit }.sorted()
        guard !limits.isEmpty else { return 0 }
        let mid = limits.count / 2
        if limits.count % 2 == 0 {
            return Int(round(Double(limits[mid - 1] + limits[mid]) / 2.0))
        }
        return limits[mid]
    }

    private var actionIcon: String {
        switch selectionMode {
        case .installSelecting:
            return "checkmark.circle.fill"
        case .updateSelecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .none:
            break
        }
        if !isInstalled {
            return "arrow.down.circle.fill"
        }
        if updateAvailable {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        return "arrow.up.forward.app"
    }

    private func handlePrimaryAction() {
        switch selectionMode {
        case .installSelecting:
            guard !selectedScaleIDs.isEmpty else { return }
            prepareInstall(action: .install, selectedScaleIDs: selectedScaleIDs)
            return
        case .updateSelecting:
            let selected = installedScaleIDs.union(selectedNewScaleIDs)
            prepareInstall(action: .update, selectedScaleIDs: selected)
            return
        case .none:
            break
        }

        if !isInstalled {
            if pack.scales.count > 1 {
                enterInstallSelection()
                return
            }
            prepareInstall(action: .install, selectedScaleIDs: Set(pack.scales.map(\.id)))
            return
        }

        if updateAvailable {
            if newScaleIDs.isEmpty {
                prepareInstall(action: .update, selectedScaleIDs: installedScaleIDs)
            } else {
                enterUpdateSelection()
            }
            return
        }

        handleDefaultPreview()
    }

    private var detailToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(toolbarSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: handleCloseTap) {
                Image(systemName: selectionMode == .none ? "xmark" : "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(PremiumModalSurface.background)
                            .overlay(PremiumModalSurface.glassOverlay(in: Circle()))
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                            )
                    )
                    .contentShape(Circle())
                    .accessibilityLabel(selectionMode == .none ? "Close" : "Back")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(barBackground(separatorEdge: .bottom))
        .opacity(heroVisible ? 1 : 0)
        .zIndex(1000)
    }

    private var detailActionBar: some View {
        HStack(spacing: 12) {
            if showsPreviewActions && pack.scales.count > 1 && selectionMode == .none {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button(action: handlePrimaryAction) {
                            HStack(spacing: 8) {
                                if store.installingPackIDs.contains(pack.packID) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    actionSymbol
                                }
                                Text(store.installingPackIDs.contains(pack.packID) ? "Installing…" : primaryActionTitle)
                                    .font(.callout.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(primaryActionTint)
                        .disabled(isPrimaryDisabled)

                        Menu {
                            ForEach(pack.scales) { scale in
                                Button(action: { handleScalePreview(scale) }) {
                                    Text(scaleMenuTitle(scale))
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel("Choose scale")
                    }

                    if let lastPreviewedScaleName {
                        Text("Last: \(lastPreviewedScaleName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button(action: handlePrimaryAction) {
                    HStack(spacing: 8) {
                        if store.installingPackIDs.contains(pack.packID) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            actionSymbol
                        }
                        Text(store.installingPackIDs.contains(pack.packID) ? "Installing…" : primaryActionTitle)
                            .font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(primaryActionTint)
                .disabled(isPrimaryDisabled)
            }

            if isInstalled && !updateAvailable && selectionMode == .none {
                Button("Uninstall") {
                    showUninstallConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }

            Menu {
                Button("Submit a Pack") {
                    openURL(CommunityPacksEndpoints.submitURL)
                }
                Button("How to submit (GitHub Issues)") {
                    openURL(CommunityPacksEndpoints.issuesURL)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(barBackground(separatorEdge: .top))
        .opacity(contentVisible ? 1 : 0)
    }

    private func barBackground(separatorEdge: VerticalEdge) -> some View {
        PremiumModalSurface.barBackground
            .overlay(PremiumModalSurface.glassOverlay(in: Rectangle()))
            .overlay(
                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 1),
                alignment: separatorEdge == .top ? .top : .bottom
            )
    }

    private var trimmedChangelog: String {
        pack.changelog.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsPreviewActions: Bool {
        isInstalled && !updateAvailable
    }

    @ViewBuilder
    private var actionSymbol: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: actionIcon)
                .symbolEffect(.bounce, value: updateAvailable)
        } else {
            Image(systemName: actionIcon)
        }
    }

    private var lastPreviewedScaleName: String? {
        guard let scaleID = lastPreviewedScaleID(for: pack.packID) else { return nil }
        return pack.scales.first(where: { $0.id == scaleID })?.title
    }

    private func scaleMenuTitle(_ scale: CommunityPackScaleViewModel) -> String {
        "\(scale.title) • \(scale.primeLimit)-limit"
    }

    private func handleDefaultPreview() {
        guard let target = defaultPreviewScale() else { return }
        handleScalePreview(target)
    }

    private func defaultPreviewScale() -> CommunityPackScaleViewModel? {
        guard !pack.scales.isEmpty else { return nil }
        if pack.scales.count == 1 {
            return pack.scales.first
        }
        if let lastScaleID = lastPreviewedScaleID(for: pack.packID),
           let lastScale = pack.scales.first(where: { $0.id == lastScaleID }) {
            return lastScale
        }
        return pack.scales.first
    }

    private func handleScalePreview(_ scale: CommunityPackScaleViewModel) {
        setLastPreviewedScaleID(packID: pack.packID, scaleID: scale.id)
        let tenneyScale = communityScaleForFiltering(pack: pack, scale: scale)
        let request = CommunityPackPreviewRequest(
            packID: pack.packID,
            scaleID: scale.id,
            scale: tenneyScale
        )
        dismiss()
        DispatchQueue.main.async {
            onPreviewRequested(request)
        }
    }

    private func lastPreviewedScaleID(for packID: String) -> String? {
        decodeLastPreviewedScaleIDs()[packID]
    }

    private func setLastPreviewedScaleID(packID: String, scaleID: String) {
        var map = decodeLastPreviewedScaleIDs()
        map[packID] = scaleID
        guard let data = try? JSONEncoder().encode(map),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        lastPreviewedScaleIDsJSON = encoded
    }

    private func decodeLastPreviewedScaleIDs() -> [String: String] {
        guard let data = lastPreviewedScaleIDsJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func startReveal() {
        guard !heroVisible else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                heroVisible = true
                contentVisible = true
            }
            return
        }
        withAnimation(.easeOut(duration: 0.8)) {
            heroVisible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 240_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.6)) {
                    contentVisible = true
                }
            }
        }
    }

    private var toolbarSubtitle: String {
        switch selectionMode {
        case .installSelecting:
            return "Selected: \(selectedScaleIDs.count)"
        case .updateSelecting:
            return "Selected: \(selectedNewScaleIDs.count)"
        case .none:
            return "Community Pack"
        }
    }

    private var installedScaleIDs: Set<String> {
        let installed = store.installedRemoteScaleIDs(for: pack.packID)
        if installed.isEmpty {
            return Set(pack.scales.map(\.id))
        }
        return installed
    }

    private var newScaleIDs: Set<String> {
        Set(pack.scales.map(\.id)).subtracting(installedScaleIDs)
    }

    private var primaryActionTint: Color? {
        switch selectionMode {
        case .installSelecting:
            return .green
        case .updateSelecting:
            return .orange
        case .none:
            return nil
        }
    }

    private var isPrimaryDisabled: Bool {
        if store.installingPackIDs.contains(pack.packID) {
            return true
        }
        if selectionMode == .installSelecting {
            return selectedScaleIDs.isEmpty
        }
        return false
    }

    private func handleCloseTap() {
        if selectionMode != .none {
            exitSelectionMode()
            return
        }
        dismiss()
    }

    private func enterInstallSelection() {
        selectionMode = .installSelecting
        selectedScaleIDs = Set(pack.scales.map(\.id))
    }

    private func enterUpdateSelection() {
        selectionMode = .updateSelecting
        selectedNewScaleIDs = []
        selectedScaleIDs = installedScaleIDs
    }

    private func exitSelectionMode() {
        selectionMode = .none
        selectedScaleIDs = []
        selectedNewScaleIDs = []
    }

    private func prepareInstall(action: CommunityPacksStore.InstallAction, selectedScaleIDs: Set<String>) {
        pendingAction = action
        pendingScaleIDs = selectedScaleIDs
        let collisions = store.collisions(for: pack, selectedScaleIDs: selectedScaleIDs)
        if collisions.isEmpty {
            resolveInstall(.overwrite)
        } else {
            showConflictDialog = true
        }
        exitSelectionMode()
    }

    private func resolveInstall(_ resolution: CommunityPacksStore.InstallResolution) {
        store.enqueueInstall(pack: pack, action: pendingAction, resolution: resolution, selectedScaleIDs: pendingScaleIDs)
    }

    private func isScaleSelectable(_ scale: CommunityPackScaleViewModel) -> Bool {
        switch selectionMode {
        case .installSelecting:
            return true
        case .updateSelecting:
            return newScaleIDs.contains(scale.id)
        case .none:
            return false
        }
    }

    private func isScaleSelected(_ scale: CommunityPackScaleViewModel) -> Bool {
        switch selectionMode {
        case .installSelecting:
            return selectedScaleIDs.contains(scale.id)
        case .updateSelecting:
            return selectedNewScaleIDs.contains(scale.id)
        case .none:
            return false
        }
    }

    private func isScaleUpdating(_ scale: CommunityPackScaleViewModel) -> Bool {
        selectionMode == .updateSelecting && installedScaleIDs.contains(scale.id)
    }

    private func toggleSelection(for scale: CommunityPackScaleViewModel) {
        guard isScaleSelectable(scale) else { return }
        switch selectionMode {
        case .installSelecting:
            if selectedScaleIDs.contains(scale.id) {
                selectedScaleIDs.remove(scale.id)
            } else {
                selectedScaleIDs.insert(scale.id)
            }
        case .updateSelecting:
            if selectedNewScaleIDs.contains(scale.id) {
                selectedNewScaleIDs.remove(scale.id)
            } else {
                selectedNewScaleIDs.insert(scale.id)
            }
        case .none:
            break
        }
    }

    private func playScalePreview(_ scale: CommunityPackScaleViewModel) {
        guard soundOn else { return }
        let tenneyScale = communityScaleForFiltering(pack: pack, scale: scale)
        let degrees = tenneyScale.degrees.sorted { lhs, rhs in
            let l = RatioMath.hz(rootHz: tenneyScale.referenceHz, p: lhs.p, q: lhs.q, octave: lhs.octave, fold: false)
            let r = RatioMath.hz(rootHz: tenneyScale.referenceHz, p: rhs.p, q: rhs.q, octave: rhs.octave, fold: false)
            if l == r { return lhs.id < rhs.id }
            return l < r
        }
        previewPlayer.play(mode: .arp, scale: tenneyScale, degrees: degrees, focus: nil, safeAmp: safeAmp)
    }

    @ViewBuilder
    private func heroSymbolTile(symbol: String, colors: [Color], parallax: CGFloat) -> some View {
        let gradient = LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(gradient.opacity(0.9))
                .overlay(PremiumModalSurface.glassOverlay(in: RoundedRectangle(cornerRadius: 18, style: .continuous)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0], colors[1], colors.count > 2 ? colors[2] : Color.white)
                .offset(y: parallax)
                .ifAvailableSymbolEffect(symbolDrawn)
        }
        .frame(width: 84, height: 84)
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
    }

    private func premiumBadge(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(.primary)
    }
}

private struct DetailStatView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .padding(12)
        .background(PremiumModalSurface.cardSurface(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct CommunityScaleRow: View {
    let scale: CommunityPackScaleViewModel
    let packID: String
    let showsSelection: Bool
    let isSelected: Bool
    let isSelectable: Bool
    let isUpdating: Bool
    let isNew: Bool
    let canPreviewInLibrary: Bool
    let onToggleSelection: () -> Void
    let onPlay: () -> Void
    let onPreviewInLibrary: () -> Void
    @ObservedObject private var library = ScaleLibraryStore.shared

    var body: some View {
        let isFavorite = library.isFavorite(id: communityScaleUUID(packID: packID, scaleID: scale.id))
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                VStack(spacing: 2) {
                    Text("\(scale.size)")
                        .font(.headline.monospacedDigit())
                    Text("notes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scale.title)
                        .font(.headline.weight(.semibold))
                    if isNew {
                        Text("New")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                }
                HStack(spacing: 8) {
                    Text("\(scale.primeLimit)-limit").font(.caption).foregroundStyle(.secondary)
                    Text("\(scale.size) notes").font(.caption).foregroundStyle(.secondary)
                }
                if isUpdating {
                    Text("Updating")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            if showsSelection {
                if isSelectable {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.green : Color.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Menu {
                    if canPreviewInLibrary {
                        Button("Preview in Library") {
                            onPreviewInLibrary()
                        }
                    }
                    Button("Copy scale name") {
                        UIPasteboard.general.string = scale.title
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .rotationEffect(.degrees(90))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            PremiumModalSurface.cardSurface(cornerRadius: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if showsSelection {
                onToggleSelection()
            }
        }
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .scrollTransition(.animated) { view, phase in
                    view.opacity(phase.isIdentity ? 1 : 0.6)
                        .scaleEffect(phase.isIdentity ? 1 : 0.96)
                }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PremiumModalSurface.cardSurface(cornerRadius: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    @ViewBuilder
    func ifAvailableSymbolEffect(_ isActive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.symbolEffect(.drawOn, value: isActive)
        } else {
            self
        }
    }
}
