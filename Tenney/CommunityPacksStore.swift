import Foundation
import CryptoKit
import Combine

@MainActor
final class CommunityPacksStore: ObservableObject {
    static let shared = CommunityPacksStore()

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
        case schemaMismatch
    }

    @Published private(set) var packs: [CommunityPackViewModel] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var showingCachedBanner: Bool = false
    @Published private(set) var installingPackIDs: Set<String> = []
    @Published private(set) var installedPackIDs: Set<String> = []
    @Published private(set) var updateAvailablePackIDs: Set<String> = []
    @Published private(set) var deletedPackIDs: Set<String> = []

    private var installQueue: [InstallRequest] = []
    private var activeInstallID: String? = nil
    private var cancellables: Set<AnyCancellable> = []

    private struct CanonicalPackSignature: Codable {
        let packID: String
        let scales: [CanonicalScaleSignature]
    }

    private struct CanonicalScaleSignature: Codable {
        let id: String
        let title: String
        let rootHz: Double
        let refs: [CanonicalRatioRef]
    }

    private struct CanonicalRatioRef: Codable {
        let p: Int
        let q: Int
        let octave: Int
        let monzo: [CanonicalMonzoEntry]
    }

    private struct CanonicalMonzoEntry: Codable {
        let prime: Int
        let exponent: Int
    }

    enum InstallAction {
        case install
        case update
    }

    enum InstallResolution {
        case overwrite
        case keepExisting
        case duplicate
    }

    private struct InstallRequest: Equatable {
        let pack: CommunityPackViewModel
        let action: InstallAction
        let resolution: InstallResolution

        static func == (lhs: InstallRequest, rhs: InstallRequest) -> Bool {
            lhs.pack.packID == rhs.pack.packID
        }
    }

    private init() {
        let registry = CommunityInstallRegistryStore.shared
        registry.$records
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateInstallState()
            }
            .store(in: &cancellables)
    }

    func refresh(force: Bool) async {
        guard state != .loading else { return }
        setState(.loading)
        showingCachedBanner = false

        do {
            let result = try await fetchRemote()
            setPacks(result)
            setState(.loaded)
            showingCachedBanner = false
            return
        } catch is CancellationError {
            setState(.idle)
            return
        } catch let error as URLError where error.code == .cancelled {
            setState(.idle)
            return
        } catch CommunityPacksError.schemaMismatch {
            setState(.schemaMismatch)
            return
        } catch {
            let remoteError = error
            do {
                let cached = try loadCached()
                setPacks(cached)
                setState(.loaded)
                showingCachedBanner = true
                return
            } catch CommunityPacksError.schemaMismatch {
                setState(.schemaMismatch)
                return
            } catch {
                let message = (remoteError as? LocalizedError)?.errorDescription ?? remoteError.localizedDescription
                setState(.failed(message))
                return
            }
        }
    }

    func filteredPacks(searchText: String, sortKey: CommunityPackSortKey) -> [CommunityPackViewModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = packs
        if !query.isEmpty {
            output = output.filter { pack in
                if pack.title.localizedCaseInsensitiveContains(query) { return true }
                if pack.authorName.localizedCaseInsensitiveContains(query) { return true }
                if pack.description.localizedCaseInsensitiveContains(query) { return true }
                return pack.scales.contains { $0.title.localizedCaseInsensitiveContains(query) }
            }
        }
        switch sortKey {
        case .featured:
            output.sort { $0.indexOrder < $1.indexOrder }
        case .newest:
            output.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .alpha:
            output.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .primeLimit:
            output.sort { $0.primeLimitMin < $1.primeLimitMin }
        }
        return output
    }

    func collisions(for pack: CommunityPackViewModel) -> [UUID] {
        let library = ScaleLibraryStore.shared
        return pack.scales.compactMap { scale in
            let id = communityScaleUUID(packID: pack.packID, scaleID: scale.id)
            return library.scales[id] != nil ? id : nil
        }
    }

    func enqueueInstall(
        pack: CommunityPackViewModel,
        action: InstallAction = .install,
        resolution: InstallResolution = .overwrite
    ) {
        if deletedPackIDs.remove(pack.packID) != nil {
            updateInstallState()
        }
        guard installingPackIDs.contains(pack.packID) == false else { return }
        guard installQueue.contains(where: { $0.pack.packID == pack.packID }) == false else { return }
        installQueue.append(InstallRequest(pack: pack, action: action, resolution: resolution))
        startNextInstallIfNeeded()
    }

    func isDeleted(_ packID: String) -> Bool {
        deletedPackIDs.contains(packID)
    }

    func isInstalled(_ packID: String) -> Bool {
        installedPackIDs.contains(packID)
    }

    func isUpdateAvailable(_ packID: String) -> Bool {
        updateAvailablePackIDs.contains(packID) && installedPackIDs.contains(packID)
    }

    func uninstall(pack: CommunityPackViewModel) {
        Task {
            await uninstallPack(packID: pack.packID)
        }
    }

    func uninstallPack(packID: String) async {
        let library = ScaleLibraryStore.shared
        let registry = CommunityInstallRegistryStore.shared

        do {
            try CommunityPacksCache.removePack(packID: packID)
        } catch {
            logFetch("CommunityPacks uninstall failed to remove cache for \(packID): \(error.localizedDescription)")
        }

        library.removeScales(forPackID: packID)
        registry.removeInstalled(packID: packID)
        deletedPackIDs.insert(packID)
        removeFromInstallQueue(packID: packID)
        installedPackIDs.remove(packID)
        updateAvailablePackIDs.remove(packID)
        updateInstallState()
        #if DEBUG
        assert(!installedPackIDs.contains(packID))
        assert(!updateAvailablePackIDs.contains(packID))
        #endif
    }

    private func startNextInstallIfNeeded() {
        guard activeInstallID == nil else { return }
        guard !installQueue.isEmpty else { return }
        let request = installQueue.removeFirst()
        activeInstallID = request.pack.packID
        installingPackIDs.insert(request.pack.packID)
        Task {
            await performInstall(request: request)
            await MainActor.run {
                self.installingPackIDs.remove(request.pack.packID)
                self.activeInstallID = nil
                self.startNextInstallIfNeeded()
            }
        }
    }

    private func performInstall(request: InstallRequest) async {
        let pack = request.pack
        let library = ScaleLibraryStore.shared
        let registry = CommunityInstallRegistryStore.shared
        let existingIDs = Set(library.scales.keys)
        var imported: [TenneyScale] = []
        let newIDs = Set(pack.scales.map { communityScaleUUID(packID: pack.packID, scaleID: $0.id) })

        if request.action == .update, request.resolution == .overwrite {
            for scale in library.scales.values where scale.provenance?.packID == pack.packID && !newIDs.contains(scale.id) {
                library.deleteScale(id: scale.id)
            }
        }

        for scale in pack.scales {
            let stableID = communityScaleUUID(packID: pack.packID, scaleID: scale.id)
            let collision = existingIDs.contains(stableID)
            switch request.resolution {
            case .overwrite:
                imported.append(makeScale(from: scale, pack: pack, id: stableID, provenance: communityProvenance(for: pack)))
            case .keepExisting:
                if !collision {
                    imported.append(makeScale(from: scale, pack: pack, id: stableID, provenance: communityProvenance(for: pack)))
                }
            case .duplicate:
                if collision {
                    imported.append(makeScale(from: scale, pack: pack, id: UUID(), provenance: nil))
                } else {
                    imported.append(makeScale(from: scale, pack: pack, id: stableID, provenance: communityProvenance(for: pack)))
                }
            }
        }

        for scale in imported {
            library.updateScale(scale)
        }

        let installedIDs: [UUID] = library.scales.values.compactMap { scale in
            guard scale.provenance?.packID == pack.packID else { return nil }
            return scale.id
        }
        let record = CommunityInstallRecord(
            installedScaleIDs: installedIDs,
            installedAt: Date(),
            installedVersion: pack.version,
            installedContentHash: pack.contentHash,
            installedContentSignature: pack.contentHash
        )
        registry.setInstalled(packID: pack.packID, record: record)
    }

    private func makeScale(
        from scale: CommunityPackScaleViewModel,
        pack: CommunityPackViewModel,
        id: UUID,
        provenance: TenneyScale.Provenance?
    ) -> TenneyScale {
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

    private func communityProvenance(for pack: CommunityPackViewModel) -> TenneyScale.Provenance {
        TenneyScale.Provenance(
            kind: .communityPack,
            packID: pack.packID,
            packName: pack.title,
            authorName: pack.authorName,
            installedVersion: pack.version
        )
    }

    private func removeFromInstallQueue(packID: String) {
        installQueue.removeAll { $0.pack.packID == packID }
        installingPackIDs.remove(packID)
        if activeInstallID == packID {
            activeInstallID = nil
        }
    }

    private func setPacks(_ packs: [CommunityPackViewModel]) {
        self.packs = packs
        updateInstallState()
    }

    private func updateInstallState() {
        let registry = CommunityInstallRegistryStore.shared
        let installedIDs = Set(registry.records.keys).subtracting(deletedPackIDs)
        installedPackIDs = installedIDs
        var updates: Set<String> = []
        for pack in packs {
            guard installedIDs.contains(pack.packID),
                  let record = registry.records[pack.packID] else { continue }
            guard let installedSignature = record.installedContentSignature else {
                #if DEBUG
                logFetch("CommunityPacks update check \(pack.packID): missing installed signature (installedVersion=\(record.installedVersion) remoteVersion=\(pack.version))")
                #endif
                continue
            }
            if installedSignature != pack.contentHash {
                updates.insert(pack.packID)
                #if DEBUG
                logFetch("CommunityPacks update check \(pack.packID): installedVersion=\(record.installedVersion) remoteVersion=\(pack.version) installedSig=\(installedSignature.prefix(8)) remoteSig=\(pack.contentHash.prefix(8))")
                #endif
            } else if record.installedVersion != pack.version {
                #if DEBUG
                logFetch("CommunityPacks update check \(pack.packID): version differs but signature matches (installedVersion=\(record.installedVersion) remoteVersion=\(pack.version))")
                #endif
            }
        }
        updateAvailablePackIDs = updates
    }

    private func fetchRemote() async throws -> [CommunityPackViewModel] {
        let indexPath = CommunityPacksEndpoints.indexPath
        let (indexData, _, _) = try await fetchData(
            primary: CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.rawBase, path: indexPath),
            fallback: CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.cdnBase, path: indexPath),
            label: indexPath
        )
        let index = try decodeSchema(CommunityIndex.self, data: indexData, label: indexPath)

        let existingPacks = (try? CommunityPacksCache.load().packs) ?? []
        var cachedPacks: [CommunityCachedPack] = existingPacks
        var viewModels: [CommunityPackViewModel] = []
        var sawSchemaMismatch = false
        var failedPacks = 0
        var schemaMismatchPacks = 0
        let assumedSchemaVersion = assumedSchemaVersion(from: index.schemaVersion)
        for (offset, entry) in index.packs.enumerated() {
            do {
                if entry.usesFilesContract {
                    let (viewModel, cachedPack) = try await fetchFilesContractPack(
                        entry: entry,
                        indexOrder: offset,
                        assumedSchemaVersion: assumedSchemaVersion,
                        indexSchemaVersion: index.schemaVersion
                    )
                    viewModels.append(viewModel)
                    cachedPacks = upsertCachedPack(cachedPacks, with: cachedPack)
                    try? CommunityPacksCache.save(indexData: indexData, packs: cachedPacks)
                    continue
                }
                guard !entry.path.isEmpty else {
                    logFetch("CommunityPacks index entry missing path (packID=\(entry.packID)); skipping.")
                    continue
                }
                let packPath = "\(entry.path)/pack.json"
                let packURL = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.rawBase, path: packPath)
                let packCDN = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.cdnBase, path: packPath)
                let (packData, _, _) = try await fetchData(primary: packURL, fallback: packCDN, label: packPath)
                let pack = try decodeSchema(
                    CommunityPack.self,
                    data: packData,
                    label: packPath,
                    assumedSchemaVersion: assumedSchemaVersion,
                    indexSchemaVersion: index.schemaVersion
                )

                var scaleDataByPath: [String: Data] = [:]
                for scale in pack.scales {
                    let scalePath = "\(entry.path)/\(scale.path)"
                    let scaleURL = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.rawBase, path: scalePath)
                    let scaleCDN = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.cdnBase, path: scalePath)
                    let (data, _, _) = try await fetchData(primary: scaleURL, fallback: scaleCDN, label: scalePath)
                    _ = try decodeScalePayload(
                        data: data,
                        label: scalePath,
                        assumedSchemaVersion: assumedSchemaVersion,
                        indexSchemaVersion: index.schemaVersion
                    )
                    scaleDataByPath[scale.path] = data
                }

                let viewModel = try buildViewModel(
                    indexEntry: entry,
                    indexOrder: offset,
                    packData: packData,
                    scaleDataByPath: scaleDataByPath,
                    assumedSchemaVersion: assumedSchemaVersion,
                    indexSchemaVersion: index.schemaVersion
                )
                viewModels.append(viewModel)
                let resolvedPackID = entry.packID.isEmpty ? entry.path : entry.packID
                let cacheID = pack.packID.isEmpty ? resolvedPackID : pack.packID
                let cachedPack = CommunityCachedPack(packID: cacheID, packData: packData, scaleDataByPath: scaleDataByPath)
                cachedPacks = upsertCachedPack(cachedPacks, with: cachedPack)
                try? CommunityPacksCache.save(indexData: indexData, packs: cachedPacks)
            } catch CommunityPacksError.schemaMismatch {
                sawSchemaMismatch = true
                schemaMismatchPacks += 1
                logFetch("CommunityPacks pack \(entry.packID.isEmpty ? entry.path : entry.packID) schema mismatch; skipping pack.")
            } catch {
                failedPacks += 1
                logFetch("CommunityPacks pack \(entry.packID.isEmpty ? entry.path : entry.packID) failed: \(error.localizedDescription)")
            }
        }

        logFetch("CommunityPacks summary: decoded packs=\(viewModels.count) failed packs=\(failedPacks) schemaMismatch packs=\(schemaMismatchPacks)")
        guard !viewModels.isEmpty else {
            if sawSchemaMismatch && failedPacks == 0 {
                throw CommunityPacksError.schemaMismatch
            }
            throw CommunityPacksError.decoding("All community packs failed to load. Pack format mismatch or invalid data.")
        }
        return viewModels
    }

    private func loadCached() throws -> [CommunityPackViewModel] {
        let cached = try CommunityPacksCache.load()
        let index = try decodeSchema(CommunityIndex.self, data: cached.indexData, label: "cached INDEX.json")

        var viewModels: [CommunityPackViewModel] = []
        var sawSchemaMismatch = false
        var failedPacks = 0
        var schemaMismatchPacks = 0
        let assumedSchemaVersion = assumedSchemaVersion(from: index.schemaVersion)
        for (offset, entry) in index.packs.enumerated() {
            guard !entry.path.isEmpty else {
                logFetch("CommunityPacks cached entry missing path (packID=\(entry.packID)); skipping.")
                continue
            }
            guard let cachedPack = cached.packs.first(where: { pack in
                let candidateIDs = [
                    entry.packID,
                    entry.path,
                    CommunityPacksCache.safePathComponent(entry.packID),
                    CommunityPacksCache.safePathComponent(entry.path)
                ].filter { !$0.isEmpty }
                return candidateIDs.contains(pack.packID)
            }) else {
                continue
            }

            do {
                let packData = cachedPack.packData
                let pack = try decodeSchema(
                    CommunityPack.self,
                    data: packData,
                    label: "cached \(entry.path)/pack.json",
                    assumedSchemaVersion: assumedSchemaVersion,
                    indexSchemaVersion: index.schemaVersion
                )
                var scaleDataByPath: [String: Data] = [:]
                for scale in pack.scales {
                    let key = CommunityPacksCache.safePathComponent(scale.path)
                    guard let data = cachedPack.scaleDataByPath[key] ?? cachedPack.scaleDataByPath[scale.path] else {
                        throw CommunityPacksError.cacheUnavailable
                    }
                    _ = try decodeScalePayload(
                        data: data,
                        label: "cached \(entry.path)/\(scale.path)",
                        assumedSchemaVersion: assumedSchemaVersion,
                        indexSchemaVersion: index.schemaVersion
                    )
                    scaleDataByPath[scale.path] = data
                }

                let viewModel = try buildViewModel(
                    indexEntry: entry,
                    indexOrder: offset,
                    packData: packData,
                    scaleDataByPath: scaleDataByPath,
                    assumedSchemaVersion: assumedSchemaVersion,
                    indexSchemaVersion: index.schemaVersion
                )
                viewModels.append(viewModel)
            } catch CommunityPacksError.schemaMismatch {
                sawSchemaMismatch = true
                schemaMismatchPacks += 1
                logFetch("CommunityPacks cached pack \(entry.packID.isEmpty ? entry.path : entry.packID) schema mismatch; skipping pack.")
            } catch {
                failedPacks += 1
                logFetch("CommunityPacks cached pack \(entry.packID.isEmpty ? entry.path : entry.packID) failed: \(error.localizedDescription)")
            }
        }

        logFetch("CommunityPacks cached summary: decoded packs=\(viewModels.count) failed packs=\(failedPacks) schemaMismatch packs=\(schemaMismatchPacks)")
        guard !viewModels.isEmpty else {
            if sawSchemaMismatch && failedPacks == 0 {
                throw CommunityPacksError.schemaMismatch
            }
            throw CommunityPacksError.cacheUnavailable
        }
        return viewModels
    }

    private func buildViewModel(
        indexEntry: CommunityIndexEntry,
        indexOrder: Int,
        packData: Data,
        scaleDataByPath: [String: Data],
        assumedSchemaVersion: Int?,
        indexSchemaVersion: Int
    ) throws -> CommunityPackViewModel {
        let pack = try decodeSchema(
            CommunityPack.self,
            data: packData,
            label: "pack.json",
            assumedSchemaVersion: assumedSchemaVersion,
            indexSchemaVersion: indexSchemaVersion
        )
        var scales: [CommunityPackScaleViewModel] = []
        var minLimit = Int.max
        var maxLimit = 0

        for scale in pack.scales {
            guard let data = scaleDataByPath[scale.path] else {
                throw CommunityPacksError.cacheUnavailable
            }
            let payload = try decodeScalePayload(
                data: data,
                label: "scale-builder.json",
                assumedSchemaVersion: assumedSchemaVersion,
                indexSchemaVersion: indexSchemaVersion
            )
            let limit = TenneyScale.detectedLimit(for: payload.refs)
            minLimit = min(minLimit, limit)
            maxLimit = max(maxLimit, limit)
            scales.append(
                CommunityPackScaleViewModel(
                    id: scale.id,
                    title: scale.title.isEmpty ? "Untitled Scale" : scale.title,
                    payload: payload,
                    primeLimit: limit,
                    size: payload.refs.count
                )
            )
        }

        let resolvedPackID = indexEntry.packID.isEmpty ? indexEntry.path : indexEntry.packID
        let hash = contentSignatureHash(packID: pack.packID.isEmpty ? resolvedPackID : pack.packID, scales: scales)
        let sanitizedDescription = sanitizeCommunityDescription(pack.description)
        let sanitizedSummary = sanitizeCommunityDescription(pack.summary ?? pack.description)
        let sanitizedChangelog = sanitizeCommunityDescription(pack.changelog ?? "")
        let dateString = pack.date

        let lastUpdated = communityDate(from: dateString)
        return CommunityPackViewModel(
            id: resolvedPackID,
            packID: pack.packID.isEmpty ? resolvedPackID : pack.packID,
            title: pack.title,
            authorName: pack.author.name,
            authorURL: pack.author.url.flatMap(URL.init(string:)),
            license: pack.license,
            dateString: dateString,
            date: lastUpdated,
            lastUpdated: lastUpdated,
            description: sanitizedDescription,
            summary: sanitizedSummary,
            changelog: sanitizedChangelog,
            version: pack.version,
            scaleCount: scales.count,
            primeLimitMin: minLimit == Int.max ? 0 : minLimit,
            primeLimitMax: maxLimit,
            scales: scales,
            indexOrder: indexOrder,
            contentHash: hash,
            isFeatured: indexEntry.isFeatured
        )
    }

    private func fetchFilesContractPack(
        entry: CommunityIndexEntry,
        indexOrder: Int,
        assumedSchemaVersion: Int?,
        indexSchemaVersion: Int
    ) async throws -> (CommunityPackViewModel, CommunityCachedPack) {
        guard let tenneyPath = entry.tenneyPath, !tenneyPath.isEmpty else {
            throw CommunityPacksError.decoding("INDEX.json is missing a tenney file path.")
        }
        let scalePathComponent = (tenneyPath as NSString).lastPathComponent
        let scaleURL = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.rawBase, path: tenneyPath)
        let scaleCDN = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.cdnBase, path: tenneyPath)
        let (scaleData, _, _) = try await fetchData(primary: scaleURL, fallback: scaleCDN, label: tenneyPath)
        _ = try decodeScalePayload(
            data: scaleData,
            label: tenneyPath,
            assumedSchemaVersion: assumedSchemaVersion,
            indexSchemaVersion: indexSchemaVersion
        )

        let packData = try synthesizePackData(entry: entry, scalePathComponent: scalePathComponent)
        let viewModel = try buildViewModel(
            indexEntry: entry,
            indexOrder: indexOrder,
            packData: packData,
            scaleDataByPath: [scalePathComponent: scaleData],
            assumedSchemaVersion: assumedSchemaVersion,
            indexSchemaVersion: indexSchemaVersion
        )
        let resolvedPackID = entry.packID.isEmpty ? entry.path : entry.packID
        let cachedPack = CommunityCachedPack(
            packID: resolvedPackID,
            packData: packData,
            scaleDataByPath: [scalePathComponent: scaleData]
        )
        return (viewModel, cachedPack)
    }

    private func synthesizePackData(entry: CommunityIndexEntry, scalePathComponent: String) throws -> Data {
        let resolvedPackID = entry.packID.isEmpty ? entry.path : entry.packID
        let title = entry.title ?? "Untitled Pack"
        let authorName = entry.authorName ?? "Unknown"
        let description = entry.description ?? ""
        let license = entry.license ?? ""
        var author: [String: Any] = ["name": authorName]
        if let url = entry.authorURLString, !url.isEmpty {
            author["url"] = url
        }
        let payload: [String: Any] = [
            "schemaVersion": CommunityPack.supportedSchemaVersion,
            "packID": resolvedPackID,
            "title": title,
            "version": "1",
            "date": "",
            "license": license,
            "author": author,
            "description": description,
            "scales": [
                [
                    "id": resolvedPackID,
                    "title": title,
                    "path": scalePathComponent
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func fetchData(primary: URL, fallback: URL, label: String) async throws -> (Data, HTTPURLResponse, URL) {
        do {
            let (data, response) = try await fetchData(url: primary, source: .raw, label: label)
            return (data, response, primary)
        } catch {
            let (data, response) = try await fetchData(url: fallback, source: .cdn, label: label)
            return (data, response, fallback)
        }
    }

    private func fetchData(url: URL, source: CommunityPacksSource, label: String) async throws -> (Data, HTTPURLResponse) {
        if url.path.hasSuffix("/") {
            logFetch("CommunityPacks \(label) [\(source.rawValue)] invalid URL (directory): \(url.absoluteString)")
            throw CommunityPacksError.network("\(label) URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logFetch("CommunityPacks \(label) [\(source.rawValue)] \(url.absoluteString) invalid response")
                throw CommunityPacksError.network("\(label) returned an invalid response.")
            }
            let status = httpResponse.statusCode
            let mimeType = httpResponse.mimeType ?? "unknown"
            let preview = payloadPreview(data)
            let firstByte = firstNonWhitespaceByte(in: data)
            let isJSON = isJSONPayload(firstByte: firstByte)
            let firstChar = firstByte.map { nonWhitespaceDescription(for: $0) } ?? "none"
            let jsonNote = isJSON ? "" : " non-JSON payload firstChar=\(firstChar)"
            logFetch("CommunityPacks \(label) [\(source.rawValue)] \(url.absoluteString) status=\(status) mimeType=\(mimeType) bytes=\(data.count) preview=\"\(preview)\"\(jsonNote)")
            guard (200...299).contains(status) else {
                throw CommunityPacksError.network("\(label) returned HTTP \(status).")
            }
            guard isJSON else {
                throw CommunityPacksError.decoding("\(label) returned non-JSON payload.")
            }
            return (data, httpResponse)
        } catch {
            logFetch("CommunityPacks \(label) [\(source.rawValue)] \(url.absoluteString) error: \(error.localizedDescription)")
            throw error
        }
    }

    #if DEBUG
    private func logFetch(_ message: String) { print(message) }
    #else
    private func logFetch(_ message: String) { }
    #endif

    private func decodeSchema<T: Decodable>(
        _ type: T.Type,
        data: Data,
        label: String,
        assumedSchemaVersion: Int? = nil,
        indexSchemaVersion: Int? = nil
    ) throws -> T {
        let workingData = injectSchemaVersionIfNeeded(
            data: data,
            label: label,
            assumedSchemaVersion: assumedSchemaVersion,
            indexSchemaVersion: indexSchemaVersion
        )
        let decoder = communityPacksDecoder()
        do {
            let decoded = try decoder.decode(T.self, from: workingData)
            logFetch("CommunityPacks \(label) decoded successfully.")
            return decoded
        } catch CommunityPacksError.schemaMismatch {
            logSchemaMismatch(label: label, data: data)
            throw CommunityPacksError.schemaMismatch
        } catch let error as CommunityPacksError {
            throw error
        } catch let error as DecodingError {
            logDecodingError(label: label, error: error, data: data)
            throw CommunityPacksError.decoding("\(label) failed to decode.")
        } catch {
            logFetch("CommunityPacks \(label) decode error: \(error.localizedDescription)")
            throw CommunityPacksError.decoding("\(label) failed to decode.")
        }
    }

    private func decodeScalePayload(
        data: Data,
        label: String,
        assumedSchemaVersion: Int?,
        indexSchemaVersion: Int
    ) throws -> ScaleBuilderPayload {
        do {
            let envelope = try decodeSchema(
                CommunityScaleBuilderEnvelope.self,
                data: data,
                label: label,
                assumedSchemaVersion: assumedSchemaVersion,
                indexSchemaVersion: indexSchemaVersion
            )
            return envelope.payload
        }
    }

    private func contentSignatureHash(packID: String, scales: [CommunityPackScaleViewModel]) -> String {
        let signature = CanonicalPackSignature(
            packID: packID,
            scales: canonicalScales(from: scales)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(signature) else {
            #if DEBUG
            logFetch("CommunityPacks signature encode failed for packID=\(packID)")
            #endif
            return ""
        }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func canonicalScales(from scales: [CommunityPackScaleViewModel]) -> [CanonicalScaleSignature] {
        let sortedScales = scales.sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            return $0.title < $1.title
        }
        return sortedScales.map { scale in
            CanonicalScaleSignature(
                id: scale.id,
                title: canonicalTitle(payloadTitle: scale.payload.title, fallback: scale.title),
                rootHz: canonicalDouble(scale.payload.rootHz),
                refs: canonicalRefs(scale.payload.refs)
            )
        }
    }

    private func canonicalTitle(payloadTitle: String, fallback: String) -> String {
        let trimmedPayload = payloadTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPayload.isEmpty {
            return trimmedPayload
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canonicalRefs(_ refs: [RatioRef]) -> [CanonicalRatioRef] {
        refs.map { ref in
            let sortedMonzo = ref.monzo.keys.sorted().map { key in
                CanonicalMonzoEntry(prime: key, exponent: ref.monzo[key] ?? 0)
            }
            return CanonicalRatioRef(
                p: ref.p,
                q: ref.q,
                octave: ref.octave,
                monzo: sortedMonzo
            )
        }
    }

    private func canonicalDouble(_ value: Double, precision: Double = 1_000_000_000) -> Double {
        (value * precision).rounded() / precision
    }

    private func setState(_ newState: LoadState) {
        logFetch("CommunityPacks state → \(describeState(newState))")
        state = newState
    }

    private func describeState(_ state: LoadState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .failed(let message):
            return "failed(\(message))"
        case .schemaMismatch:
            return "schemaMismatch"
        }
    }

    private func payloadPreview(_ data: Data, limit: Int = 160) -> String {
        let preview = String(decoding: data.prefix(limit), as: UTF8.self)
        return preview.replacingOccurrences(of: "\n", with: "\\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstNonWhitespaceByte(in data: Data) -> UInt8? {
        for byte in data {
            if !byte.isWhitespaceASCII {
                return byte
            }
        }
        return nil
    }

    private func isJSONPayload(firstByte: UInt8?) -> Bool {
        guard let firstByte else { return false }
        return firstByte == 0x7b || firstByte == 0x5b
    }

    private func nonWhitespaceDescription(for byte: UInt8) -> String {
        if byte >= 0x20 && byte <= 0x7e {
            return "'\(Character(UnicodeScalar(byte)))'"
        }
        return String(format: "0x%02x", byte)
    }

    private func logSchemaMismatch(label: String, data: Data) {
        var versionDescription = "missing"
        if let object = try? JSONSerialization.jsonObject(with: data),
           let dict = object as? [String: Any] {
            if let version = dict["schemaVersion"] as? Int {
                versionDescription = "\(version)"
            }
        }
        logFetch("CommunityPacks \(label) schema mismatch (schemaVersion: \(versionDescription)).")
    }

    private func logDecodingError(label: String, error: DecodingError, data: Data) {
        let path = decodingPath(from: error)
        logFetch("CommunityPacks \(label) decode error at \(path.isEmpty ? "<root>" : path): \(error.localizedDescription)")
        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dict = object as? [String: Any] {
                let keys = dict.keys.sorted().joined(separator: ", ")
                logFetch("CommunityPacks \(label) top-level keys: [\(keys)]")
            } else if object is [Any] {
                logFetch("CommunityPacks \(label) top-level JSON is an array.")
            }
        }
    }

    private func decodingPath(from error: DecodingError) -> String {
        let path: [CodingKey]
        switch error {
        case .typeMismatch(_, let context):
            path = context.codingPath
        case .valueNotFound(_, let context):
            path = context.codingPath
        case .keyNotFound(_, let context):
            path = context.codingPath
        case .dataCorrupted(let context):
            path = context.codingPath
        @unknown default:
            path = []
        }
        return path.map(\.stringValue).joined(separator: ".")
    }

    private func injectSchemaVersionIfNeeded(
        data: Data,
        label: String,
        assumedSchemaVersion: Int?,
        indexSchemaVersion: Int?
    ) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              var dict = object as? [String: Any] else {
            return data
        }
        if let version = dict["schemaVersion"] as? Int {
            logFetch("CommunityPacks \(label) schemaVersion=\(version)")
            return data
        }
        guard let assumedSchemaVersion, let indexSchemaVersion else { return data }
        dict["schemaVersion"] = assumedSchemaVersion
        logFetch("CommunityPacks \(label) schemaVersion missing; assuming v\(assumedSchemaVersion) (index schemaVersion=\(indexSchemaVersion))")
        return (try? JSONSerialization.data(withJSONObject: dict)) ?? data
    }

    private func assumedSchemaVersion(from indexSchemaVersion: Int) -> Int? {
        guard indexSchemaVersion == CommunityIndex.supportedSchemaVersion else { return nil }
        return CommunityIndex.supportedSchemaVersion
    }

    private func communityPacksDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                if let date = Self.iso8601FractionalFormatter.date(from: stringValue)
                    ?? Self.iso8601Formatter.date(from: stringValue) {
                    return date
                }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date string: \(stringValue)"
                )
            }
            if let doubleValue = try? container.decode(Double.self) {
                let seconds = doubleValue > 1_000_000_000_000 ? doubleValue / 1000.0 : doubleValue
                return Date(timeIntervalSince1970: seconds)
            }
            if let intValue = try? container.decode(Int.self) {
                let seconds = intValue > 1_000_000_000_000 ? Double(intValue) / 1000.0 : Double(intValue)
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format")
        }
        return decoder
    }

    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func upsertCachedPack(_ cachedPacks: [CommunityCachedPack], with pack: CommunityCachedPack) -> [CommunityCachedPack] {
        var output = cachedPacks.filter { $0.packID != pack.packID }
        output.append(pack)
        return output
    }
}

private enum CommunityPacksSource: String {
    case raw
    case cdn
}

private extension UInt8 {
    var isWhitespaceASCII: Bool {
        self == 0x20 || self == 0x09 || self == 0x0a || self == 0x0d
    }
}
