//
//  ScaleLibraryStore.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  ScaleLibraryStore.swift
//  Tenney
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ScaleLibraryStore: ObservableObject {

    static let shared = ScaleLibraryStore()

    // MARK: - Sorting

    enum SortKey: String, CaseIterable, Identifiable, Codable {
        case recent
        case alpha
        case size
        case limit
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent: return "Recent"
            case .alpha:  return "A–Z"
            case .size:   return "Size"
            case .limit:  return "Prime Limit"
            }
        }

    }

    // MARK: - Published state

    /// Canonical library store (ScaleLibrarySheet reads `Array(scales.values)`).
    @Published var scales: [UUID: TenneyScale] = [:]

    /// UI-only (not persisted)
    @Published var searchText: String = ""

    /// Persisted in the blob so the sheet remembers sort across launches.
    @Published var sortKey: SortKey = .recent {
        didSet { scheduleSave() }
    }

    @Published private(set) var favoriteIDs: Set<UUID> = []

    // MARK: - Persistence

    private struct LibraryBlob: Codable {
        var version: Int = 1
        var sortKey: SortKey = .recent
        var scales: [UUID: TenneyScale] = [:]
    }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Tenney", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = dir.appendingPathComponent("scale_library_v1.json")

        load()
    }

    // MARK: - CRUD

    func updateScale(_ scale: TenneyScale) {
        scales[scale.id] = scale
        updateFavorite(id: scale.id, isFavorite: scale.favorite)
        scheduleSave()
    }

    func deleteScale(id: UUID) {
        let removed = scales.removeValue(forKey: id)
        if removed?.provenance?.kind != .communityPack {
            updateFavorite(id: id, isFavorite: false)
        }
        scheduleSave()
    }

    func removeScales(forPackID packID: String) {
        let idsToRemove = scales.values.compactMap { scale in
            if scale.provenance?.packID == packID {
                return scale.id
            }
            if scale.pack?.source == .community, scale.pack?.slug == packID {
                return scale.id
            }
            return nil
        }
        guard !idsToRemove.isEmpty else { return }
        for id in idsToRemove {
            deleteScale(id: id)
        }
    }

    func upsert(_ scale: TenneyScale) { updateScale(scale) }
    // Newer UI calls this name.
    func addScale(_ scale: TenneyScale) { updateScale(scale) }

    func isFavorite(id: UUID) -> Bool {
        favoriteIDs.contains(id)
    }

    @discardableResult
    func toggleFavorite(id: UUID) -> Bool {
        let isFavorite = !favoriteIDs.contains(id)
        setFavorite(isFavorite, for: id)
        return isFavorite
    }

    func setFavorite(_ isFavorite: Bool, for id: UUID) {
        updateFavorite(id: id, isFavorite: isFavorite)
        if var scale = scales[id] {
            scale.favorite = isFavorite
            scales[id] = scale
            scheduleSave()
        }
    }

    enum MoveScaleOutcome: Equatable {
        case moved(previous: PackRef?, current: PackRef?)
        case blockedCommunity
        case unchanged
    }

    @discardableResult
    func moveScale(id scaleID: UUID, to pack: PackRef?) -> MoveScaleOutcome {
        guard var scale = scales[scaleID] else { return .unchanged }
        if scale.provenance?.kind == .communityPack {
            return .blockedCommunity
        }
        if scale.pack?.id == pack?.id,
           scale.pack?.title == pack?.title,
           scale.pack?.source == pack?.source {
            return .unchanged
        }
        let previous = scale.pack
        scale.pack = pack
        scales[scaleID] = scale
        scheduleSave()
        return .moved(previous: previous, current: pack)
    }

    func duplicateScaleToUser(id scaleID: UUID) -> UUID? {
        guard let scale = scales[scaleID] else { return nil }
        let newID = UUID()
        let newName = uniqueDuplicateName(for: scale.name)
        var duplicated = scale
        duplicated.id = newID
        duplicated.name = newName
        duplicated.pack = nil
        duplicated.provenance = nil
        addScale(duplicated)
        return newID
    }

    func assignPack(_ pack: PackRef?, to scaleID: UUID) {
        assignPack(pack, to: [scaleID])
    }

    func assignPack(_ pack: PackRef?, to scaleIDs: [UUID]) {
        guard !scaleIDs.isEmpty else { return }
        var updated = scales
        var didChange = false
        for id in scaleIDs {
            guard var scale = updated[id] else { continue }
            if scale.provenance?.kind == .communityPack { continue }
            if scale.pack?.id == pack?.id && scale.pack?.title == pack?.title && scale.pack?.source == pack?.source {
                continue
            }
            scale.pack = pack
            updated[id] = scale
            didChange = true
        }
        guard didChange else { return }
        scales = updated
        scheduleSave()
    }

    func allPackSummaries() -> [PackSummary] {
        let grouped = Dictionary(grouping: scales.values.compactMap { scale in
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

    func renamePack(id packID: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = scales
        var didChange = false
        for (id, scale) in scales {
            guard var pack = scale.pack, pack.id == packID else { continue }
            if pack.title == trimmed { continue }
            pack.title = trimmed
            var revised = scale
            revised.pack = pack
            updated[id] = revised
            didChange = true
        }
        guard didChange else { return }
        scales = updated
        scheduleSave()
    }

    func deletePack(id packID: String) {
        var updated = scales
        var didChange = false
        for (id, scale) in scales {
            guard scale.pack?.id == packID else { continue }
            var revised = scale
            revised.pack = nil
            updated[id] = revised
            didChange = true
        }
        guard didChange else { return }
        scales = updated
        scheduleSave()
    }

    func repairCommunityPackMetadata(using packs: [CommunityPackViewModel]) {
        guard !packs.isEmpty else { return }
        let mapped: [UUID: (PackRef, String)] = Dictionary(uniqueKeysWithValues: packs.flatMap { pack in
            let packRef = PackRef(
                source: .community,
                id: "community:\(pack.packID)",
                title: pack.title,
                slug: pack.packID
            )
            return pack.scales.map { scale in
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
                let stableID = communityScaleUUID(packID: pack.packID, scaleID: scale.id)
                return (stableID, (packRef, resolvedName))
            }
        })

        var updated = scales
        var didChange = false
        for (id, scale) in scales {
            guard let (packRef, resolvedName) = mapped[id] else { continue }
            var revised = scale
            if revised.pack?.id != packRef.id || revised.pack?.title != packRef.title {
                revised.pack = packRef
                didChange = true
            }
            let trimmedName = revised.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName == packRef.title.trimmingCharacters(in: .whitespacesAndNewlines) {
                revised.name = resolvedName
                didChange = true
            }
            if var provenance = revised.provenance, provenance.kind == .communityPack, provenance.packName != packRef.title {
                provenance.packName = packRef.title
                revised.provenance = provenance
                didChange = true
            }
            updated[id] = revised
            #if DEBUG
            if revised.pack?.source == .community {
                assert(revised.name.trimmingCharacters(in: .whitespacesAndNewlines) != packRef.title.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            #endif
        }
        guard didChange else { return }
        scales = updated
        scheduleSave()
    }

    // MARK: - Load / Save

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let blob = try JSONDecoder().decode(LibraryBlob.self, from: data)
            self.scales = blob.scales
            self.sortKey = blob.sortKey
        } catch {
            // first launch or corrupt file → start empty
            self.scales = [:]
            self.sortKey = .recent
        }
        loadFavorites()
        syncFavoritesToScales()
    }

    func saveNow() {
        let blob = LibraryBlob(sortKey: sortKey, scales: scales)
        do {
            let data = try JSONEncoder().encode(blob)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // non-fatal; keep running
            #if DEBUG
            print("ScaleLibraryStore save error:", error)
            #endif
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000) // debounce
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.libraryFavoriteIDsJSON) else {
            favoriteIDs = Set(scales.values.filter(\.favorite).map(\.id))
            return
        }
        do {
            let decoded = try JSONDecoder().decode([UUID].self, from: data)
            favoriteIDs = Set(decoded)
        } catch {
            favoriteIDs = Set(scales.values.filter(\.favorite).map(\.id))
        }
    }

    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(Array(favoriteIDs))
            UserDefaults.standard.set(data, forKey: SettingsKeys.libraryFavoriteIDsJSON)
        } catch {
            #if DEBUG
            print("ScaleLibraryStore favorites save error:", error)
            #endif
        }
    }

    private func updateFavorite(id: UUID, isFavorite: Bool) {
        if isFavorite {
            favoriteIDs.insert(id)
        } else {
            favoriteIDs.remove(id)
        }
        saveFavorites()
    }

    private func syncFavoritesToScales() {
        guard !scales.isEmpty else { return }
        var updated = scales
        var changed = false
        for (id, scale) in scales {
            let shouldFavorite = favoriteIDs.contains(id) || scale.favorite
            if scale.favorite != shouldFavorite {
                var updatedScale = scale
                updatedScale.favorite = shouldFavorite
                updated[id] = updatedScale
                changed = true
            }
            if shouldFavorite && !favoriteIDs.contains(id) {
                favoriteIDs.insert(id)
                changed = true
            }
        }
        if changed {
            scales = updated
            saveFavorites()
            scheduleSave()
        }
    }

    private func uniqueDuplicateName(for baseName: String) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = trimmed.isEmpty ? "Untitled Scale" : trimmed
        let existingNames = Set(scales.values.map { $0.name.lowercased() })
        var suffixIndex = 1
        var candidate = "\(resolvedBase) (Copy)"
        while existingNames.contains(candidate.lowercased()) {
            suffixIndex += 1
            candidate = "\(resolvedBase) (Copy \(suffixIndex))"
        }
        return candidate
    }
}
