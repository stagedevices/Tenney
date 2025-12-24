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
        scheduleSave()
    }

    func deleteScale(id: UUID) {
        scales.removeValue(forKey: id)
        scheduleSave()
    }

    func upsert(_ scale: TenneyScale) { updateScale(scale) }
    // Newer UI calls this name.
    func addScale(_ scale: TenneyScale) { updateScale(scale) }
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
}
