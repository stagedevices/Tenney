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

    private init() {}

    func refresh(force: Bool) async {
        guard state != .loading else { return }
        setState(.loading)
        showingCachedBanner = false

        do {
            let result = try await fetchRemote()
            packs = result
            setState(.loaded)
            showingCachedBanner = false
            return
        } catch CommunityPacksError.schemaMismatch {
            setState(.schemaMismatch)
            return
        } catch {
            let remoteError = error
            do {
                let cached = try loadCached()
                packs = cached
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

    private func fetchRemote() async throws -> [CommunityPackViewModel] {
        let indexPath = CommunityPacksEndpoints.indexPath
        let (indexData, _, _) = try await fetchData(
            primary: CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.rawBase, path: indexPath),
            fallback: CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.cdnBase, path: indexPath),
            label: indexPath
        )
        let index = try decodeSchema(CommunityIndex.self, data: indexData, label: indexPath)

        let existingPacks = (try? CommunityPacksCache.load().packs) ?? []
        try? CommunityPacksCache.save(indexData: indexData, packs: existingPacks)

        var cachedPacks: [CommunityCachedPack] = []
        var viewModels: [CommunityPackViewModel] = []
        var sawSchemaMismatch = false
        for (offset, entry) in index.packs.enumerated() {
            do {
                let packPath = "\(entry.path)/pack.json"
                let packURL = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.rawBase, path: packPath)
                let packCDN = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.cdnBase, path: packPath)
                let (packData, _, _) = try await fetchData(primary: packURL, fallback: packCDN, label: packPath)
                let pack = try decodeSchema(CommunityPack.self, data: packData, label: packPath)

                var scaleDataByPath: [String: Data] = [:]
                for scale in pack.scales {
                    let scalePath = "\(entry.path)/\(scale.path)"
                    let scaleURL = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.rawBase, path: scalePath)
                    let scaleCDN = CommunityPacksEndpoints.url(base: CommunityPacksEndpoints.cdnBase, path: scalePath)
                    let (data, _, _) = try await fetchData(primary: scaleURL, fallback: scaleCDN, label: scalePath)
                    _ = try decodeSchema(CommunityScaleBuilderEnvelope.self, data: data, label: scalePath)
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
                try? CommunityPacksCache.save(indexData: indexData, packs: cachedPacks)
            } catch CommunityPacksError.schemaMismatch {
                sawSchemaMismatch = true
                logFetch("CommunityPacks pack \(entry.packID) schema mismatch; skipping pack.")
            } catch {
                logFetch("CommunityPacks pack \(entry.packID) failed: \(error.localizedDescription)")
            }
        }

        guard !viewModels.isEmpty else {
            if sawSchemaMismatch {
                throw CommunityPacksError.schemaMismatch
            }
            throw CommunityPacksError.decoding("All community packs failed to load.")
        }
        return viewModels
    }

    private func loadCached() throws -> [CommunityPackViewModel] {
        let cached = try CommunityPacksCache.load()
        let index = try decodeSchema(CommunityIndex.self, data: cached.indexData, label: "cached INDEX.json")

        var viewModels: [CommunityPackViewModel] = []
        var sawSchemaMismatch = false
        for (offset, entry) in index.packs.enumerated() {
            guard let cachedPack = cached.packs.first(where: { pack in
                pack.packID == CommunityPacksCache.safePathComponent(entry.packID) || pack.packID == entry.packID
            }) else {
                continue
            }

            do {
                let packData = cachedPack.packData
                let pack = try decodeSchema(CommunityPack.self, data: packData, label: "cached \(entry.path)/pack.json")
                var scaleDataByPath: [String: Data] = [:]
                for scale in pack.scales {
                    let key = CommunityPacksCache.safePathComponent(scale.path)
                    guard let data = cachedPack.scaleDataByPath[key] ?? cachedPack.scaleDataByPath[scale.path] else {
                        throw CommunityPacksError.cacheUnavailable
                    }
                    _ = try decodeSchema(CommunityScaleBuilderEnvelope.self, data: data, label: "cached \(entry.path)/\(scale.path)")
                    scaleDataByPath[scale.path] = data
                }

                let viewModel = try buildViewModel(
                    indexEntry: entry,
                    indexOrder: offset,
                    packData: packData,
                    scaleDataByPath: scaleDataByPath
                )
                viewModels.append(viewModel)
            } catch CommunityPacksError.schemaMismatch {
                sawSchemaMismatch = true
                logFetch("CommunityPacks cached pack \(entry.packID) schema mismatch; skipping pack.")
            } catch {
                logFetch("CommunityPacks cached pack \(entry.packID) failed: \(error.localizedDescription)")
            }
        }

        guard !viewModels.isEmpty else {
            if sawSchemaMismatch {
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
        scaleDataByPath: [String: Data]
    ) throws -> CommunityPackViewModel {
        let pack = try decodeSchema(CommunityPack.self, data: packData, label: "pack.json")
        var scales: [CommunityPackScaleViewModel] = []
        var minLimit = Int.max
        var maxLimit = 0

        for scale in pack.scales {
            guard let data = scaleDataByPath[scale.path] else {
                throw CommunityPacksError.cacheUnavailable
            }
            let envelope = try decodeSchema(CommunityScaleBuilderEnvelope.self, data: data, label: "scale-builder.json")
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

    private func decodeSchema<T: Decodable>(_ type: T.Type, data: Data, label: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
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

    private func sha256Hex(for packData: Data, scaleData: [Data]) -> String {
        var combined = Data()
        combined.append(packData)
        for data in scaleData {
            combined.append(data)
        }
        let hash = SHA256.hash(data: combined)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
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
        let path = error.codingPath.map(\.stringValue).joined(separator: ".")
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
