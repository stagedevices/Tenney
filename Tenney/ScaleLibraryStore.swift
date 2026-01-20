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
            scale.provenance?.packID == packID ? scale.id : nil
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
}
