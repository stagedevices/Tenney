import Foundation
import CryptoKit

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

    private init() {}

    func refresh(force: Bool) async {
        guard state != .loading else { return }
        state = .loading
        showingCachedBanner = false

        do {
            let result = try await fetchRemote()
            packs = result
            state = .loaded
            showingCachedBanner = false
        } catch CommunityPacksError.schemaMismatch {
            state = .schemaMismatch
        } catch {
            do {
                let cached = try loadCached()
                packs = cached
                state = .loaded
                showingCachedBanner = true
            } catch CommunityPacksError.schemaMismatch {
                state = .schemaMismatch
            } catch {
                state = .failed(error.localizedDescription)
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

    private func fetchRemote() async throws -> [CommunityPackViewModel] {
        let indexData = try await fetchData(
            primary: CommunityPacksEndpoints.rawBase.appendingPathComponent(CommunityPacksEndpoints.indexPath),
            fallback: CommunityPacksEndpoints.cdnBase.appendingPathComponent(CommunityPacksEndpoints.indexPath)
        )
        let index = try decodeSchema(CommunityIndex.self, data: indexData)

        var cachedPacks: [CommunityCachedPack] = []
        var viewModels: [CommunityPackViewModel] = []
        for (offset, entry) in index.packs.enumerated() {
            let packURL = CommunityPacksEndpoints.rawBase.appendingPathComponent(entry.path).appendingPathComponent("pack.json")
            let packCDN = CommunityPacksEndpoints.cdnBase.appendingPathComponent(entry.path).appendingPathComponent("pack.json")
            let packData = try await fetchData(primary: packURL, fallback: packCDN)
            let pack = try decodeSchema(CommunityPack.self, data: packData)

            var scaleDataByPath: [String: Data] = [:]
            for scale in pack.scales {
                let scaleURL = CommunityPacksEndpoints.rawBase.appendingPathComponent(entry.path).appendingPathComponent(scale.path)
                let scaleCDN = CommunityPacksEndpoints.cdnBase.appendingPathComponent(entry.path).appendingPathComponent(scale.path)
                let data = try await fetchData(primary: scaleURL, fallback: scaleCDN)
                _ = try decodeSchema(CommunityScaleBuilderEnvelope.self, data: data)
                scaleDataByPath[scale.path] = data
            }

            let viewModel = try buildViewModel(
                indexEntry: entry,
                indexOrder: offset,
                packData: packData,
                scaleDataByPath: scaleDataByPath
            )
            viewModels.append(viewModel)
            cachedPacks.append(CommunityCachedPack(packID: pack.packID.isEmpty ? entry.packID : pack.packID, packData: packData, scaleDataByPath: scaleDataByPath))
        }

        try? CommunityPacksCache.save(indexData: indexData, packs: cachedPacks)
        return viewModels
    }

    private func loadCached() throws -> [CommunityPackViewModel] {
        let cached = try CommunityPacksCache.load()
        let index = try decodeSchema(CommunityIndex.self, data: cached.indexData)

        var viewModels: [CommunityPackViewModel] = []
        for (offset, entry) in index.packs.enumerated() {
            guard let cachedPack = cached.packs.first(where: { pack in
                pack.packID == CommunityPacksCache.safePathComponent(entry.packID) || pack.packID == entry.packID
            }) else {
                throw CommunityPacksError.cacheUnavailable
            }

            let packData = cachedPack.packData
            let pack = try decodeSchema(CommunityPack.self, data: packData)
            var scaleDataByPath: [String: Data] = [:]
            for scale in pack.scales {
                let key = CommunityPacksCache.safePathComponent(scale.path)
                guard let data = cachedPack.scaleDataByPath[key] ?? cachedPack.scaleDataByPath[scale.path] else {
                    throw CommunityPacksError.cacheUnavailable
                }
                _ = try decodeSchema(CommunityScaleBuilderEnvelope.self, data: data)
                scaleDataByPath[scale.path] = data
            }

            let viewModel = try buildViewModel(
                indexEntry: entry,
                indexOrder: offset,
                packData: packData,
                scaleDataByPath: scaleDataByPath
            )
            viewModels.append(viewModel)
        }

        return viewModels
    }

    private func buildViewModel(
        indexEntry: CommunityIndexEntry,
        indexOrder: Int,
        packData: Data,
        scaleDataByPath: [String: Data]
    ) throws -> CommunityPackViewModel {
        let pack = try decodeSchema(CommunityPack.self, data: packData)
        var scales: [CommunityPackScaleViewModel] = []
        var minLimit = Int.max
        var maxLimit = 0

        for scale in pack.scales {
            guard let data = scaleDataByPath[scale.path] else {
                throw CommunityPacksError.cacheUnavailable
            }
            let envelope = try decodeSchema(CommunityScaleBuilderEnvelope.self, data: data)
            let limit = TenneyScale.detectedLimit(for: envelope.payload.refs)
            minLimit = min(minLimit, limit)
            maxLimit = max(maxLimit, limit)
            scales.append(
                CommunityPackScaleViewModel(
                    id: scale.id,
                    title: scale.title.isEmpty ? "Untitled Scale" : scale.title,
                    payload: envelope.payload,
                    primeLimit: limit,
                    size: envelope.payload.refs.count
                )
            )
        }

        let hash = sha256Hex(for: packData, scaleData: pack.scales.map { scaleDataByPath[$0.path] ?? Data() })
        let sanitizedDescription = sanitizeCommunityDescription(pack.description)
        let dateString = pack.date

        return CommunityPackViewModel(
            id: indexEntry.packID,
            packID: pack.packID.isEmpty ? indexEntry.packID : pack.packID,
            title: pack.title,
            authorName: pack.author.name,
            authorURL: pack.author.url.flatMap(URL.init(string:)),
            license: pack.license,
            dateString: dateString,
            date: communityDate(from: dateString),
            description: sanitizedDescription,
            version: pack.version,
            scaleCount: scales.count,
            primeLimitMin: minLimit == Int.max ? 0 : minLimit,
            primeLimitMax: maxLimit,
            scales: scales,
            indexOrder: indexOrder,
            contentHash: hash
        )
    }

    private func fetchData(primary: URL, fallback: URL) async throws -> Data {
        do {
            return try await fetchData(url: primary)
        } catch {
            return try await fetchData(url: fallback)
        }
    }

    private func fetchData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CommunityPacksError.network("Unable to load community packs.")
        }
        return data
    }

    private func decodeSchema<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as CommunityPacksError {
            throw error
        } catch {
            throw CommunityPacksError.decoding("Unable to decode community packs.")
        }
    }

    private func sha256Hex(for packData: Data, scaleData: [Data]) -> String {
        var combined = Data()
        combined.append(packData)
        for data in scaleData {
            combined.append(data)
        }
        let hash = SHA256.hash(data: combined)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
