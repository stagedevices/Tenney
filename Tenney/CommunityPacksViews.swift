import SwiftUI

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
            CommunityPackDetailView(pack: pack, namespace: packNamespace)
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
    @ObservedObject private var store = CommunityPacksStore.shared
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showConflictDialog = false
    @State private var showUninstallConfirm = false
    @State private var showChangelog = false
    @State private var heroVisible = false
    @State private var contentVisible = false
    @State private var closeSymbolVisible = false
    @State private var actionScale: TenneyScale?

    private var isInstalled: Bool {
        store.isInstalled(pack.packID)
    }

    private var updateAvailable: Bool {
        guard !store.isDeleted(pack.packID) else { return false }
        return store.isUpdateAvailable(pack.packID)
    }

    private var primaryActionTitle: String {
        if !isInstalled { return "Install" }
        if updateAvailable { return "Update" }
        return "Open"
    }

    var body: some View {
        let content = detailContent
        if #available(iOS 16.0, *) {
            content
                .presentationBackground(detailBackdrop)
        } else {
            content
                .background(detailBackdrop.ignoresSafeArea())
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                    .opacity(heroVisible ? 1 : 0)
                    .offset(y: heroVisible ? 0 : 18)

                DetailSectionCard(title: "What you get") {
                    HStack(spacing: 16) {
                        DetailStatView(title: "Scales", value: "\(pack.scaleCount)")
                        DetailStatView(title: "Typical limit", value: "\(typicalLimit)-limit")
                    }
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 16)
                .blur(radius: contentVisible ? 0 : 6)

                DetailSectionCard(title: "Sample scales") {
                    VStack(spacing: 10) {
                        ForEach(sampleScales) { scale in
                            CommunityScaleRow(
                                scale: scale,
                                packID: pack.packID,
                                onActions: { actionScale = communityScaleForFiltering(pack: pack, scale: scale) }
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

                        DisclosureGroup(isExpanded: $showChangelog) {
                            Text(pack.changelog.isEmpty ? "No changelog provided." : pack.changelog)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text("Changelog")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 16)
                .blur(radius: contentVisible ? 0 : 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { detailToolbar }
        .safeAreaInset(edge: .bottom) { detailActionBar }
        .onAppear(perform: startReveal)
        .sheet(item: $actionScale) { scale in
            ScaleActionsSheet(
                scale: scale,
                onOpen: { model.openBuilder(with: scale) },
                onAdd: { model.addToBuilder(scale: scale) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pack.title)
                        .font(.title2.weight(.semibold))
                    Text("by \(pack.authorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if pack.isFeatured {
                    Label("FEATURED", systemImage: "seal.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                }
            }

            if !pack.description.isEmpty {
                Text(pack.description)
                    .font(.callout)
            }

            HStack(spacing: 10) {
                if !pack.license.isEmpty {
                    Text(pack.license)
                }
                if !pack.dateString.isEmpty {
                    Text(pack.dateString)
                }
                Text("\(pack.scaleCount) scales")
                Text(primeLimitLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if updateAvailable {
                Text("Update available")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PackCardSurface(cornerRadius: 24)
                .matchedGeometryEffect(id: "pack-card-\(pack.packID)", in: namespace, isSource: false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var sampleScales: [CommunityPackScaleViewModel] {
        Array(pack.scales.prefix(8))
    }

    private var primeLimitLabel: String {
        if pack.primeLimitMin == pack.primeLimitMax {
            return "\(pack.primeLimitMin)-limit"
        }
        return "\(pack.primeLimitMin)–\(pack.primeLimitMax)-limit"
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
        if !isInstalled {
            return "arrow.down.circle.fill"
        }
        if updateAvailable {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        return "arrow.up.forward.app"
    }

    private func handlePrimaryAction() {
        if !isInstalled || updateAvailable {
            let collisions = store.collisions(for: pack)
            if collisions.isEmpty {
                resolveInstall(.overwrite)
            } else {
                showConflictDialog = true
            }
        } else {
            dismiss()
        }
    }

    private func resolveInstall(_ resolution: CommunityPacksStore.InstallResolution) {
        let action: CommunityPacksStore.InstallAction = updateAvailable ? .update : .install
        store.enqueueInstall(pack: pack, action: action, resolution: resolution)
    }

    private var detailBackdrop: LinearGradient {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var detailToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title)
                    .font(.headline.weight(.semibold))
                Text("Community Pack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                ZStack {
                    DetailGlassCircle()
                    closeSymbol
                }
                .frame(width: 34, height: 34)
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .accessibilityLabel("Close")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            PackCardSurface(cornerRadius: 0)
                .overlay(
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
        .opacity(heroVisible ? 1 : 0)
    }

    @ViewBuilder
    private var closeSymbol: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .symbolEffect(.drawOn, value: closeSymbolVisible)
        } else {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
        }
    }

    private var detailActionBar: some View {
        HStack(spacing: 12) {
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
            .disabled(store.installingPackIDs.contains(pack.packID))

            if isInstalled && !updateAvailable {
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
        .background(
            PackCardSurface(cornerRadius: 0)
                .overlay(
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1),
                    alignment: .top
                )
        )
        .opacity(contentVisible ? 1 : 0)
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

    private func startReveal() {
        guard !heroVisible else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                heroVisible = true
                contentVisible = true
                closeSymbolVisible = true
            }
            return
        }
        withAnimation(.easeOut(duration: 0.45)) {
            heroVisible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    contentVisible = true
                    closeSymbolVisible = true
                }
            }
        }
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
        .background(PackCardSurface(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct CommunityScaleRow: View {
    let scale: CommunityPackScaleViewModel
    let packID: String
    let onActions: () -> Void
    @ObservedObject private var library = ScaleLibraryStore.shared

    var body: some View {
        let isFavorite = library.isFavorite(id: communityScaleUUID(packID: packID, scaleID: scale.id))
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
                Text(scale.title)
                    .font(.headline.weight(.semibold))
                HStack(spacing: 8) {
                    Text("\(scale.primeLimit)-limit").font(.caption).foregroundStyle(.secondary)
                    Text("\(scale.size) notes").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            Button(action: onActions) {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .rotationEffect(.degrees(90))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            PackCardSurface(cornerRadius: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PackCardSurface(cornerRadius: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct DetailGlassCircle: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.regular, in: Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }
}
