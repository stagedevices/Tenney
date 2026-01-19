import SwiftUI
import CryptoKit

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

struct CommunityControlsCard: View {
    @Binding var sortKey: CommunityPackSortKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommunitySortPills(selection: $sortKey)
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
}

private struct CommunitySortPills: View {
    @Binding var selection: CommunityPackSortKey

    var body: some View {
        HStack(spacing: 8) {
            pill(.featured, icon: "sparkles")
            pill(.newest, icon: "clock")
            pill(.alpha, icon: "textformat")
            pill(.primeLimit, icon: "dial.min")
        }
        .padding(4)
        .background {
            let shape = Capsule()
            if #available(iOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) }
            else { shape.fill(.thinMaterial) }
        }
        .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }

    private func pill(_ key: CommunityPackSortKey, icon: String) -> some View {
        let isSelected = (selection == key)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                selection = key
            }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                if isSelected {
                    Text(key.label)
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
    }
}

struct CommunityPacksPageList: View {
    @Binding var sortKey: CommunityPackSortKey
    @ObservedObject private var store = CommunityPacksStore.shared
    @ObservedObject private var library = ScaleLibraryStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if store.showingCachedBanner {
                    OfflineBanner()
                }

                if case .schemaMismatch = store.state {
                    ContentUnavailableView(
                        "This pack format is newer than your app",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Update Tenney to browse Community Packs.")
                    )
                } else if case .failed(let message) = store.state, store.packs.isEmpty {
                    ContentUnavailableView(
                        "Community Packs unavailable",
                        systemImage: "wifi.slash",
                        description: Text(message)
                    )
                } else if store.packs.isEmpty, case .loading = store.state {
                    ProgressView("Loading Community Packs…")
                        .padding(.top, 20)
                } else {
                    let packs = store.filteredPacks(searchText: library.searchText, sortKey: sortKey)
                    if packs.isEmpty {
                        ContentUnavailableView(
                            "No matching packs",
                            systemImage: "magnifyingglass",
                            description: Text("Try clearing your search.")
                        )
                    } else {
                        ForEach(packs) { pack in
                            NavigationLink {
                                CommunityPackDetailView(pack: pack)
                            } label: {
                                CommunityPackCard(pack: pack)
                            }
                            .buttonStyle(.plain)
                        }
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

private struct CommunityPackCard: View {
    let pack: CommunityPackViewModel
    @ObservedObject private var registry = CommunityInstallRegistryStore.shared

    private var installedRecord: CommunityInstallRecord? {
        registry.record(for: pack.packID)
    }

    private var updateAvailable: Bool {
        guard let record = installedRecord else { return false }
        return record.installedContentHash != pack.contentHash
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pack.title)
                        .font(.title3.weight(.semibold))
                    Text("by \(pack.authorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if installedRecord != nil {
                    Label("Installed", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 8) {
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

            if !pack.description.isEmpty {
                Text(pack.description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }

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
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var primeLimitLabel: String {
        if pack.primeLimitMin == pack.primeLimitMax {
            return "\(pack.primeLimitMin)-limit"
        }
        return "\(pack.primeLimitMin)–\(pack.primeLimitMax)-limit"
    }

    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

private struct CommunityPackDetailView: View {
    let pack: CommunityPackViewModel
    @ObservedObject private var library = ScaleLibraryStore.shared
    @ObservedObject private var registry = CommunityInstallRegistryStore.shared
    @Environment(\.openURL) private var openURL

    @State private var showConflictDialog = false
    @State private var pendingAction: InstallAction = .install
    @State private var showUninstallConfirm = false

    private enum InstallAction {
        case install
        case update
    }

    private enum ConflictResolution {
        case overwrite
        case keepExisting
        case duplicate
    }

    private var installedRecord: CommunityInstallRecord? {
        registry.record(for: pack.packID)
    }

    private var updateAvailable: Bool {
        guard let record = installedRecord else { return false }
        return record.installedContentHash != pack.contentHash
    }

    private var primaryActionTitle: String {
        if installedRecord == nil { return "Install" }
        if updateAvailable { return "Update" }
        return "Uninstall"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                VStack(alignment: .leading, spacing: 10) {
                    Text("Scales")
                        .font(.headline)
                    ForEach(pack.scales) { scale in
                        CommunityScaleRow(scale: scale)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Button(primaryActionTitle) {
                        if installedRecord == nil || updateAvailable {
                            startInstall(action: updateAvailable ? .update : .install)
                        } else {
                            showUninstallConfirm = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(installedRecord == nil || updateAvailable ? .accentColor : .red)

                    Button("Submit a Pack") {
                        openURL(CommunityPacksEndpoints.submitURL)
                    }
                    .buttonStyle(.bordered)

                    Button("How to submit (GitHub Issues)") {
                        openURL(CommunityPacksEndpoints.issuesURL)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Some scales already exist in your Library.",
            isPresented: $showConflictDialog,
            titleVisibility: .visible
        ) {
            Button("Overwrite All", role: .destructive) { performInstall(resolution: .overwrite) }
            Button("Keep Existing") { performInstall(resolution: .keepExisting) }
            Button("Duplicate as Local Copy") { performInstall(resolution: .duplicate) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how you’d like to handle these collisions.")
        }
        .confirmationDialog(
            "Uninstall this pack?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) { uninstallPack() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes scales installed from this pack but keeps any local copies you created.")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pack.title)
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Text("by \(pack.authorName)")
                if let url = pack.authorURL {
                    Button("Open Author") {
                        openURL(url)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(pack.description)
                .font(.body)

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
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var primeLimitLabel: String {
        if pack.primeLimitMin == pack.primeLimitMax {
            return "\(pack.primeLimitMin)-limit"
        }
        return "\(pack.primeLimitMin)–\(pack.primeLimitMax)-limit"
    }

    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private func startInstall(action: InstallAction) {
        pendingAction = action
        let collisions = findCollisions()
        if collisions.isEmpty {
            performInstall(resolution: .overwrite)
        } else {
            showConflictDialog = true
        }
    }

    private func findCollisions() -> [UUID] {
        pack.scales.compactMap { scale in
            let id = stableScaleUUID(for: scale.id)
            return library.scales[id] != nil ? id : nil
        }
    }

    private func performInstall(resolution: ConflictResolution) {
        let existingIDs = Set(library.scales.keys)
        var imported: [TenneyScale] = []
        let newIDs = Set(pack.scales.map { stableScaleUUID(for: $0.id) })

        if pendingAction == .update, resolution == .overwrite {
            for scale in library.scales.values where scale.provenance?.packID == pack.packID && !newIDs.contains(scale.id) {
                library.deleteScale(id: scale.id)
            }
        }

        for scale in pack.scales {
            let stableID = stableScaleUUID(for: scale.id)
            let collision = existingIDs.contains(stableID)
            switch resolution {
            case .overwrite:
                imported.append(makeScale(from: scale, id: stableID, provenance: communityProvenance()))
            case .keepExisting:
                if !collision {
                    imported.append(makeScale(from: scale, id: stableID, provenance: communityProvenance()))
                }
            case .duplicate:
                if collision {
                    imported.append(makeScale(from: scale, id: UUID(), provenance: nil))
                } else {
                    imported.append(makeScale(from: scale, id: stableID, provenance: communityProvenance()))
                }
            }
        }

        for scale in imported {
            library.updateScale(scale)
        }

        let installedIDs = library.scales.values.compactMap { scale in
            guard scale.provenance?.packID == pack.packID else { return nil }
            return scale.id
        }
        let record = CommunityInstallRecord(
            installedScaleIDs: installedIDs,
            installedAt: Date(),
            installedVersion: pack.version,
            installedContentHash: pack.contentHash
        )
        registry.setInstalled(packID: pack.packID, record: record)
    }

    private func uninstallPack() {
        let installedIDs = registry.record(for: pack.packID)?.installedScaleIDs ?? []
        for id in installedIDs {
            if let scale = library.scales[id], scale.provenance?.packID == pack.packID {
                library.deleteScale(id: id)
            }
        }
        registry.removeInstalled(packID: pack.packID)
    }

    private func makeScale(from scale: CommunityPackScaleViewModel, id: UUID, provenance: TenneyScale.Provenance?) -> TenneyScale {
        let title = scale.payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = title.isEmpty ? scale.title : title
        return TenneyScale(
            id: id,
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

    private func communityProvenance() -> TenneyScale.Provenance {
        TenneyScale.Provenance(
            kind: .communityPack,
            packID: pack.packID,
            packName: pack.title,
            authorName: pack.authorName,
            installedVersion: pack.version
        )
    }

    private func stableScaleUUID(for scaleID: String) -> UUID {
        if let uuid = UUID(uuidString: scaleID) {
            return uuid
        }
        let data = Data((pack.packID + ":" + scaleID).utf8)
        let hash = SHA256.hash(data: data)
        var bytes = Array(hash)
        let tuple = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}

private struct CommunityScaleRow: View {
    let scale: CommunityPackScaleViewModel

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
                Text(scale.title)
                    .font(.headline.weight(.semibold))
                HStack(spacing: 8) {
                    Text("\(scale.primeLimit)-limit").font(.caption).foregroundStyle(.secondary)
                    Text("\(scale.size) notes").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
