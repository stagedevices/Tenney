import SwiftUI
import UIKit
#if canImport(AppKit)
import AppKit
#endif
import Combine

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
    // Preserve INDEX.json scale titles as the source of truth, even after install.
    let scaleTitle = scale.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let payloadTitle = scale.payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedName: String
       if !scaleTitle.isEmpty {
           resolvedName = scaleTitle
       } else if !payloadTitle.isEmpty {
           resolvedName = payloadTitle
       } else {
           resolvedName = "Untitled Scale"
       }
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

private func firstSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let terminators: Set<Character> = [".", "!", "?"]
    var index = trimmed.startIndex
    while index < trimmed.endIndex {
        let character = trimmed[index]
        if terminators.contains(character) {
            let next = trimmed.index(after: index)
            if next == trimmed.endIndex || trimmed[next].isWhitespace {
                let sentence = String(trimmed[...index])
                return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        index = trimmed.index(after: index)
    }
    if let firstLine = trimmed.split(whereSeparator: \.isNewline).first {
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
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

struct CommunityPacksLoadingView: View {
    var isFeaturedStyle: Bool = false
    var symbolName: String = "shippingbox"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 16) {
            SpotlitPackSigil(
                symbolName: symbolName,
                isFeaturedStyle: isFeaturedStyle
            )
            VStack(spacing: 6) {
                Text("Loading Community Packs")
                    .font(.headline.weight(.semibold))
                LoadingMicrocopy()
            }
            .foregroundStyle(.secondary)
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            guard !isVisible else { return }
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.easeIn(duration: 0.22)) {
                    isVisible = true
                }
            }
        }
    }
}

private struct SpotlitPackSigil: View {
    let symbolName: String
    let isFeaturedStyle: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var haloScale: CGFloat = 0.96
    @State private var haloOpacity: Double = 0.28
    @State private var ringRotation: Angle = .degrees(0)
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        ZStack {
            halo
            tickRing
            disc
            glyph
        }
        .frame(width: 92, height: 92)
        .onAppear {
            let haloDuration = reduceMotion ? 1.4 : 2.1
            withAnimation(.easeInOut(duration: haloDuration).repeatForever(autoreverses: true)) {
                haloScale = 1.05
                haloOpacity = 0.42
            }
            if !reduceMotion {
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                    ringRotation = .degrees(360)
                }
            }
            let shimmerDuration = reduceMotion ? 1.6 : 2.2
            withAnimation(.linear(duration: shimmerDuration).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
    }

    private var disc: some View {
        ZStack {
            if #available(iOS 26.0, macOS 15.0, *) {
                Color.clear.glassEffect(.regular, in: Circle())
            } else {
                Circle().fill(.ultraThinMaterial)
            }
            shimmer
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
        )
        .clipShape(Circle())
    }

    private var halo: some View {
        Circle()
            .strokeBorder(Color.white.opacity(haloOpacity), lineWidth: isFeaturedStyle ? 2.4 : 2.0)
            .blur(radius: 6)
            .scaleEffect(haloScale)
    }

    private var tickRing: some View {
        TickRing(count: 72)
            .rotationEffect(reduceMotion ? .degrees(0) : ringRotation)
    }

    private var shimmer: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let offset = (shimmerPhase * (width * 1.6)) - (width * 0.8)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(-20))
                .offset(x: offset)
                .blendMode(.screen)
                .opacity(0.7)
        }
        .allowsHitTesting(false)
        .mask(Circle())
    }

    private var glyph: some View {
        Image(systemName: symbolName)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.9 : 0.75))
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            .blur(radius: 0.2)
    }
}

private struct TickRing: View {
    let count: Int

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let tickLength = radius * 0.12
            let tickBaseRadius = radius * 0.72
            let circle = Double.pi * 2
            for index in 0..<count {
                let progress = Double(index) / Double(count)
                let angle = progress * circle
                let cosAngle = cos(angle)
                let sinAngle = sin(angle)
                let startRadius = tickBaseRadius
                let endRadius = tickBaseRadius + tickLength
                let start = CGPoint(
                    x: center.x + cosAngle * startRadius,
                    y: center.y + sinAngle * startRadius
                )
                let end = CGPoint(
                    x: center.x + cosAngle * endRadius,
                    y: center.y + sinAngle * endRadius
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                let phase = progress * circle
                let intensity = 0.24 + 0.26 * (0.5 + 0.5 * sin(phase))
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(intensity)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }
        }
        .frame(width: 86, height: 86)
    }
}

private struct LoadingMicrocopy: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    private let messages = [
        "Fetching index…",
        "Resolving pack metadata…",
        "Preparing previews…"
    ]
    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(messages[index])
            .font(.footnote.monospacedDigit())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: index)
            .onReceive(timer) { _ in
                let next = (index + 1) % messages.count
                if reduceMotion {
                    index = next
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        index = next
                    }
                }
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
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
                            CommunityPacksLoadingView()
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: proxy.size.height * 0.65)
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

                if store.state == .loading, !store.packs.isEmpty {
                    RefreshingPill()
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.state)
        }
        .sheet(item: $selectedPack) { pack in
            NavigationStack {
                    CommunityPackDetailView(
                        pack: pack,
                        namespace: packNamespace,
                        onPreviewRequested: onPreviewRequested
                    )
                }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(PremiumModalSurface.background)
            .tenneySheetSizing()
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
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filters.isFiltering(searchText: trimmedQuery, favoritesOnly: favoritesOnly) {
            return true
        }
        let metadataMatch = packMatchesMetadata(pack)
        if !trimmedQuery.isEmpty, metadataMatch {
            return true
        }
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
        if trimmedQuery.isEmpty {
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

private struct RefreshingPill: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
                .scaleEffect(1.05)
            Text("Refreshing…")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.2))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)
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
                            let isSelected = selectedPack?.packID == pack.packID
                            VStack(spacing: 0) {
                                FeaturedPackCard(
                                    pack: pack,
                                    isInstalling: store.installingPackIDs.contains(pack.packID),
                                    updateAvailable: updateAvailable(pack),
                                    isInstalled: store.isInstalled(pack.packID),
                                    isMatchedSource: isSelected,
                                    onOpen: { selectedPack = pack },
                                    onInstall: { store.enqueueInstall(pack: pack, action: action(for: pack)) },
                                    namespace: namespace
                                )
                                .frame(width: 280)
                                .modifier(FeaturedScrollTransition())
                            }
                            .opacity(isSelected ? 0 : 1)
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
                        let isSelected = selectedPack?.packID == pack.packID
                        VStack(spacing: 0) {
                            CompactPackCard(
                                pack: pack,
                                style: .installed,
                                isInstalling: store.installingPackIDs.contains(pack.packID),
                                updateAvailable: updateAvailable(pack),
                                isMatchedSource: isSelected,
                                onOpen: { selectedPack = pack },
                                onInstall: { store.enqueueInstall(pack: pack, action: .update) },
                                namespace: namespace
                            )
                        }
                        .opacity(isSelected ? 0 : 1)
                    }
                }
            }

            SectionHeader(title: "Browse all")
            LazyVStack(spacing: 10) {
                ForEach(browseAll) { pack in
                    let isSelected = selectedPack?.packID == pack.packID
                    VStack(spacing: 0) {
                        CompactPackCard(
                            pack: pack,
                            style: .browse,
                            isInstalling: store.installingPackIDs.contains(pack.packID),
                            updateAvailable: updateAvailable(pack),
                            isMatchedSource: isSelected,
                            onOpen: { selectedPack = pack },
                            onInstall: { store.enqueueInstall(pack: pack, action: .install) },
                            namespace: namespace
                        )
                    }
                    .opacity(isSelected ? 0 : 1)
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
    let isMatchedSource: Bool
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

            PackCardPrimaryActionButton(
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
                .matchedGeometryEffect(id: "pack-card-\(pack.packID)", in: namespace, isSource: isMatchedSource)
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
            // list buttons are always “open pack”
            "arrow.up.forward.app"
        }

    private var buttonAction: () -> Void {
            // list buttons never trigger install/update; they open the pack sheet
            onOpen
        }
}

private struct CompactPackCard: View {
    let pack: CommunityPackViewModel
    let style: CompactPackCardStyle
    let isInstalling: Bool
    let updateAvailable: Bool
    let isMatchedSource: Bool
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

            PackCardPrimaryActionButton(
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
                .matchedGeometryEffect(id: "pack-card-\(pack.packID)", in: namespace, isSource: isMatchedSource)
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
            // list buttons are always “open pack”
            "arrow.up.forward.app"
        }

    private var buttonAction: () -> Void {
            // list buttons never trigger install/update; they open the pack sheet
            onOpen
        }
}

private struct PackCardPrimaryActionButton: View {
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
                        .controlSize(.regular)
                } else {
                    symbolImage
                }
                Text(isInstalling ? "Installing…" : title)
                    .font(.caption.weight(.semibold))
            }
            .frame(minWidth: 96)
        }
        .modifier(PackButtonStyleModifier(isProminent: isProminent))
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
    @State private var scrollBaselineY: CGFloat? = nil
    @State private var actionBarHeight: CGFloat = 0
    @State private var previewPlayer = ScalePreviewPlayer()

    private var corner: CGFloat { 12 }

    @State private var topBarHeight: CGFloat = 64

    private struct TopBarHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private var primaryButtonMode: PackPrimaryActionMode {
        if updateAvailable || selectionMode == .updateSelecting {
            return .update(tint: primaryActionTint)
        }
        return .install(tint: primaryActionTint)
    }

    private var primaryIsBusy: Bool {
        store.installingPackIDs.contains(pack.packID)
    }


    
    private enum SelectionMode {
        case none
        case installSelecting
        case updateSelecting
    }

    private enum ActionBarState: Equatable {
        case primary
        case uninstall
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
        return "Installed" // not shown; uninstall button is shown instead
    }

    private var isSelecting: Bool {
        selectionMode != .none
    }

    private var actionBarState: ActionBarState {
        if selectionMode != .none || !isInstalled || updateAvailable {
            return .primary
        }
        return .uninstall
    }

    private var actionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.35)
    }

    private var actionTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    var body: some View {
        detailContent
    }

    private var detailContent: some View {
        ZStack {
            PremiumModalSurface.background
                    .ignoresSafeArea()
            
            PremiumModalSurface.baseFill
                .ignoresSafeArea()

           

            ScrollView {
                
                VStack(alignment: .leading, spacing: 20) {
                    // NEW: scrolls away; lets content slide under the bar as you scroll
                    Color.clear.frame(height: topBarHeight)
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
                .padding(.bottom, max(actionBarHeight + 16, 16))
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { detailActionBar }
            .onPreferenceChange(ActionBarHeightKey.self) { actionBarHeight = $0 }
            .overlay(alignment: .top) { detailTopBar }
            .onPreferenceChange(TopBarHeightKey.self) { topBarHeight = $0 }
        }
        .onAppear(perform: startReveal)
        .onDisappear {
            previewPlayer.stop()
        }
#if os(iOS)
.toolbar(.hidden, for: .navigationBar)
#endif

        .interactiveDismissDisabled(isSelecting)
        .presentationBackground(.clear)
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
    
    private var detailTopBar: some View {
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

            GlassWhiteCircleIconButton(
                systemName: isSelecting ? "chevron.backward" : "checkmark",
                accessibilityLabel: isSelecting ? "Back" : "Close",
                action: handleCloseTap
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        // IMPORTANT: give it a real hit-testable surface so taps don’t “fall through”
        .background(PremiumModalSurface.barGlass(in: Rectangle()))
        .contentShape(Rectangle())
        // measure height
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TopBarHeightKey.self, value: proxy.size.height)
            }
        )
        .zIndex(1000)
    }



    private var headerCard: some View {
        let identity = PackVisualIdentity.identity(for: pack.packID, accent: .accentColor)
        let parallax: CGFloat = 0

        let posterDescription = firstSentence(pack.description)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pack.title)
                        .font(.largeTitle.weight(.semibold))
                    Text("by \(pack.authorName)")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    if !posterDescription.isEmpty {
                        Text(posterDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                heroSymbolTile(packID: pack.packID, symbol: identity.symbolName, parallax: parallax)
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
        return "checkmark.seal.fill"
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
        if isInstalled {
            return
        }
    }

    private var detailActionBar: some View {
        HStack(spacing: 12) {
            if selectionMode == .none && isInstalled {
                previewControl
                    .transition(actionTransition)
            }

            ZStack {
                if actionBarState == .primary {
                            PackPrimaryActionButton(
                                mode: primaryButtonMode,
                                title: primaryActionTitle,
                                systemImage: actionIcon,
                                isBusy: primaryIsBusy,
                                isEnabled: !isPrimaryDisabled,
                                animateSymbol: updateAvailable,
                                action: handlePrimaryAction,
                                corner: corner
                            )
                            .transition(actionTransition)
                } else {
                    Button(action: { showUninstallConfirm = true }) {
                        Label("Uninstall", systemImage: "trash")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 14)
                            .foregroundStyle(.white)
                            .modifier(GlassTintedCapsule(tint: .red, isEnabled: true))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(GlassPressFeedback())
                    .transition(actionTransition)
                }
            }
            .frame(minWidth: 150)
            .animation(actionAnimation, value: actionBarState)
            .animation(actionAnimation, value: primaryButtonMode)
            .animation(actionAnimation, value: primaryIsBusy)
            
                        Menu {
                            Button("Contribute a Pack") { openURL(CommunityPacksEndpoints.submitURL) }
                            Button("How to submit")     { openURL(CommunityPacksEndpoints.issuesURL) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .modifier(GlassWhiteCircle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ActionBarHeightKey.self, value: proxy.size.height)
            }
        )
        .opacity(contentVisible ? 1 : 0)
        .animation(actionAnimation, value: isInstalled)
        .animation(actionAnimation, value: selectionMode)
    }

    @ViewBuilder
    private var previewControl: some View {
        if isInstalled {
            Menu {
                ForEach(pack.scales) { scale in
                    Button(action: { handleScalePreview(scale) }) {
                        Text(scaleMenuTitle(scale))
                    }
                }
            } label: {
                previewLabel(showsChevron: true)
            }
            .buttonStyle(GlassPressFeedback())
        }
    }

    private func previewLabel(showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.forward.app")
            Text("Preview")
                .font(.callout.weight(.semibold))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 14)
        .foregroundStyle(.primary)
        .modifier(GlassRoundedRect(corner: corner))
    }

    private var trimmedChangelog: String {
        pack.changelog.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsPreviewActions: Bool {
        isInstalled && !updateAvailable
    }

    private func scaleMenuTitle(_ scale: CommunityPackScaleViewModel) -> String {
        "\(scale.title) • \(scale.primeLimit)-limit"
    }

    private func handleDefaultPreview(allowLastPreviewed: Bool) {
        guard let target = defaultPreviewScale(allowLastPreviewed: allowLastPreviewed) else { return }
        handleScalePreview(target)
    }

    private func defaultPreviewScale(allowLastPreviewed: Bool) -> CommunityPackScaleViewModel? {
        guard !pack.scales.isEmpty else { return nil }
        if pack.scales.count == 1 {
            return pack.scales.first
        }
        if allowLastPreviewed,
           let lastScaleID = lastPreviewedScaleID(for: pack.packID),
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
    private func heroSymbolTile(packID: String, symbol: String, parallax: CGFloat) -> some View {
        PackHeroSymbolView(
            packID: packID,
            symbolName: symbol,
            parallax: parallax
        )
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

private struct PackHeroSymbolView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var meshStartRef: TimeInterval = Date().timeIntervalSinceReferenceDate
    private let meshW = 6
    private let meshH = 6
    let packID: String
    let symbolName: String
    let parallax: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            heroFill
               .clipShape(shape)
               .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 1))


            iconLayer
                .offset(y: parallax)
                .zIndex(10)

        }
        .frame(width: 84, height: 84)
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        
        .onAppear {
            meshStartRef = Date().timeIntervalSinceReferenceDate
        }

    }
    @ViewBuilder
        private var heroFill: some View {
            if #available(iOS 18.0, macOS 15.0, *) {
                if reduceMotion {
                    MeshGradient(
                        width: meshW,
                        height: meshH,
                        points: meshPoints(t: 0),
                        colors: meshColors
                    )
                    .drawingGroup(opaque: false, colorMode: .linear)
                    .opacity(0.92)
                } else {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate - meshStartRef
                        MeshGradient(
                            width: meshW,
                            height: meshH,
                            points: meshPoints(t: t),
                            colors: meshColors
                        )
                        .drawingGroup(opaque: false, colorMode: .linear)
                        .opacity(0.92)
                    }
                }
            } else {
                LinearGradient(colors: [baseColor, darkColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.9)
            }
        }

        @available(iOS 18.0, macOS 15.0, *)
        private var meshColors: [Color] {
            let seed = Self.fnv1a64(packID)

            // 12 curated anchor hues (degrees): teal, cyan, azure, indigo, violet, magenta,
            // rose, orange, amber, chartreuse, green, mint
            let anchorsDeg: [Double] = [184, 196, 210, 238, 268, 292, 328, 20, 44, 92, 132, 160]
            let anchor = anchorsDeg[Int(seed % UInt64(anchorsDeg.count))]
            let jitter = (Self.rand01(seed ^ 0xD1B54A32D192ED03) - 0.5) * 16.0 // ±8°

            let hueDeg = anchor + jitter
            let hue = Self.mod1(hueDeg / 360.0)

            var sat = Self.lerp(0.55, 0.78, Self.rand01(seed ^ 0xA5A5A5A5A5A5A5A5))
            var bri = Self.lerp(0.62, 0.88, Self.rand01(seed ^ 0x5A5A5A5A5A5A5A5A))
            if sat > 0.72 { bri = min(bri, 0.82) } // avoid neon

            let darkB = max(0.12, bri * 0.38)
            _ = sat * 0.92 // darkS (implicit via per-cell saturation)

            let focusU = 0.35 + 0.30 * Self.rand01(seed ^ 0x9E3779B97F4A7C15)
            let focusV = 0.30 + 0.35 * Self.rand01((seed >> 1) ^ 0xBF58476D1CE4E5B9)

            var out: [Color] = []
            out.reserveCapacity(meshW * meshH)

            let w1 = Double(max(1, meshW - 1))
            let h1 = Double(max(1, meshH - 1))

            for y in 0..<meshH {
                for x in 0..<meshW {
                    let u = Double(x) / w1
                    let v = Double(y) / h1

                    let du = u - focusU
                    let dv = v - focusV
                    let d = min(1.0, sqrt(du * du + dv * dv))

                    let m = pow(1.0 - d, 1.6)
                    let j = (Self.rand01(seed ^ (UInt64(x) << 16) ^ (UInt64(y) << 8)) - 0.5) * 0.06

                    let t = Self.clamp01(m + j)
                    let cellB = Self.lerp(darkB, bri, t)
                    let cellS = sat * (0.98 - 0.10 * d)

                    out.append(Color(hue: hue, saturation: cellS, brightness: cellB))
                }
            }
            return out
        }

        @available(iOS 18.0, macOS 15.0, *)
        private func meshPoints(t: TimeInterval) -> [SIMD2<Float>] {
            let tt = Float(t) // t is now small (anchored), so Float has enough precision
            var pts: [SIMD2<Float>] = []
            pts.reserveCapacity(meshW * meshH)

            func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

            let wMinus1 = Float(meshW - 1)
            let hMinus1 = Float(meshH - 1)

            for yi in 0..<meshH {
                for xi in 0..<meshW {
                    let bx = Float(xi) / wMinus1
                    let by = Float(yi) / hMinus1
                    let i = Float(yi * meshW + xi)

                    let isCorner = (xi == 0 || xi == meshW - 1) && (yi == 0 || yi == meshH - 1)
                    let isEdge = (xi == 0 || xi == meshW - 1 || yi == 0 || yi == meshH - 1)

                    // slightly smaller amplitudes than 4x4 (denser mesh reads smoother)
                    let amp: Float = isCorner ? 0.0 : (isEdge ? 0.045 : 0.085)

                    // “blobby” motion: per-point slow freqs + multi-harmonics (no global rotation cue)
                    let seed = i * 0.73
                    let fx = 0.22 + 0.06 * sin(seed)
                    let fy = 0.18 + 0.06 * cos(seed * 1.3)

                    let dx = amp * (0.65 * sin(tt * fx + seed) + 0.35 * sin(tt * (fx * 1.9) + seed * 0.4))
                    let dy = amp * (0.65 * cos(tt * fy + seed * 1.2) + 0.35 * sin(tt * (fy * 1.7) + seed * 0.9))

                    var px = bx + dx
                    var py = by + dy

                    // Pin boundary points to the unit square so the mesh always fully covers the tile.
                    // Still allows tangential motion: top/bottom edges can slide in X; left/right edges can slide in Y.
                    if xi == 0 { px = 0 }
                    else if xi == meshW - 1 { px = 1 }
                    else { px = clamp01(px) }

                    if yi == 0 { py = 0 }
                    else if yi == meshH - 1 { py = 1 }
                    else { py = clamp01(py) }

                    pts.append(SIMD2<Float>(px, py))

                }
            }
            return pts
        }

// MARK: - Seeded “nice single-color” gradient helpers

    private var baseColor: Color {
        let seed = Self.fnv1a64(packID)
        let hsb = Self.seededBaseHSB(seed: seed)
        return Color(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
    }

    private var darkColor: Color {
        let seed = Self.fnv1a64(packID)
        let hsb = Self.seededBaseHSB(seed: seed)
        let darkB = max(0.12, hsb.b * 0.38)
        let darkS = hsb.s * 0.92
        return Color(hue: hsb.h, saturation: darkS, brightness: darkB)
    }

    private static func seededBaseHSB(seed: UInt64) -> (h: Double, s: Double, b: Double) {
        let anchorsDeg: [Double] = [184, 196, 210, 238, 268, 292, 328, 20, 44, 92, 132, 160]
        let anchor = anchorsDeg[Int(seed % UInt64(anchorsDeg.count))]
        let jitter = (rand01(seed ^ 0xD1B54A32D192ED03) - 0.5) * 16.0 // ±8°

        let hue = mod1((anchor + jitter) / 360.0)
        var sat = lerp(0.55, 0.78, rand01(seed ^ 0xA5A5A5A5A5A5A5A5))
        var bri = lerp(0.62, 0.88, rand01(seed ^ 0x5A5A5A5A5A5A5A5A))
        if sat > 0.72 { bri = min(bri, 0.82) }
        // tiny stabilization against “samey” packs
        sat = min(0.80, max(0.50, sat))
        bri = min(0.90, max(0.55, bri))
        return (hue, sat, bri)
    }

    // FNV-1a 64-bit
    private static func fnv1a64(_ s: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        for b in s.utf8 {
            hash ^= UInt64(b)
            hash = hash &* prime
        }
        return hash
    }

    // SplitMix64-style hash → [0, 1]
    private static func rand01(_ x: UInt64) -> Double {
        var z = x &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z) / Double(UInt64.max)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func clamp01(_ v: Double) -> Double { min(1.0, max(0.0, v)) }
    private static func mod1(_ v: Double) -> Double {
        let m = v.truncatingRemainder(dividingBy: 1.0)
        return m < 0 ? (m + 1.0) : m
    }

    private var iconLayer: some View {
        let resolvedSymbolName = VerifiedSFSymbol.resolvedSymbolName(for: symbolName)
        return ZStack {
            Image(systemName: resolvedSymbolName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white.opacity(0.18))
                .font(.system(size: 56, weight: .semibold, design: .default))
                .blur(radius: 0.6)

            Image(systemName: resolvedSymbolName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .font(.system(size: 56, weight: .semibold, design: .default))
                .opacity(0.94)
                .blendMode(.overlay)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .compositingGroup()
        .zIndex(20)
    }
}

private struct VerifiedSFSymbol: View {
    private static let fallbackSymbolName = "music.note"
    private let fallbackSymbolName = VerifiedSFSymbol.fallbackSymbolName
    let symbolName: String
    let palette: [Color]
    let pointSize: CGFloat

    var body: some View {
        #if canImport(UIKit)
        if let image = configuredUIImage {
            Image(uiImage: image)
                .renderingMode(.original)
                .opacity(1)
                .blendMode(.normal)
                .compositingGroup()
        }
        #elseif canImport(AppKit)
        if let image = configuredNSImage {
            Image(nsImage: image)
                .renderingMode(.original)
                .opacity(1)
                .blendMode(.normal)
                .compositingGroup()
        }
        #else
        EmptyView()
        #endif
    }

    private var resolvedSymbolName: String {
        Self.resolvedSymbolName(for: symbolName)
    }

    static func resolvedSymbolName(for symbolName: String) -> String {
        #if canImport(UIKit)
        if UIImage(systemName: symbolName) != nil {
            return symbolName
        }
        #elseif canImport(AppKit)
        if NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil {
            return symbolName
        }
        #endif
        return fallbackSymbolName
    }

    #if canImport(UIKit)
    private var configuredUIImage: UIImage? {
        let uiPalette = palette.map { UIColor($0) }
        let base = UIImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .semibold,
            scale: .large
        )
        let paletteConfig = UIImage.SymbolConfiguration(paletteColors: uiPalette)
        let configuration = base.applying(paletteConfig)
        return UIImage(systemName: resolvedSymbolName, withConfiguration: configuration)
    }
    #endif

    #if canImport(AppKit)
    private var configuredNSImage: NSImage? {
        let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: resolvedSymbolName, accessibilityDescription: nil) else {
            return nil
        }
        let nsPalette = palette.map { NSColor($0) }
        let paletteConfig = NSImage.SymbolConfiguration(paletteColors: nsPalette)
        if let configured = symbol.withSymbolConfiguration(base.applying(paletteConfig)) {
            return configured
        }
        let fallbackColor = NSColor(palette.first ?? Color(.labelColor))
        let hierarchicalConfig = NSImage.SymbolConfiguration(hierarchicalColor: fallbackColor)
        return symbol.withSymbolConfiguration(base.applying(hierarchicalConfig))
    }
    #endif
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
        // prefer the smallest minY (most “scrolled up” / most negative)
        value = min(value, nextValue())
    }
}

private struct ActionBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#if canImport(UIKit)
private struct ScrollOffsetObserver: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(from: v) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator {
        let onChange: (CGFloat) -> Void
        private var observation: NSKeyValueObservation?
        private var attachAttempts = 0

        init(onChange: @escaping (CGFloat) -> Void) { self.onChange = onChange }

        func attach(from view: UIView) {
            var node: UIView? = view
            var scrollView: UIScrollView? = nil
            while let n = node, scrollView == nil {
                scrollView = n as? UIScrollView
                node = n.superview
            }

            guard let sv = scrollView else {
                attachAttempts += 1
                guard attachAttempts < 8 else { return }
                DispatchQueue.main.async { [weak self] in self?.attach(from: view) }
                return
            }

            observation = sv.observe(\.contentOffset, options: [.initial, .new]) { [weak self] sv, _ in
                self?.onChange(max(0, sv.contentOffset.y)) // 0 at top; increases as you scroll down
            }
        }
    }
}
#endif
