import Foundation
import SwiftUI
import Combine

final class TagStore: ObservableObject {
    static let shared = TagStore()

    @Published private(set) var tags: [TagID: TagRef] = [:]

    private struct TagBlob: Codable {
        var version: Int = 1
        var tags: [TagRef] = []
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
        self.fileURL = dir.appendingPathComponent("scale_tags_v1.json")

        load()
    }

    // MARK: - Public API

    var allTags: [TagRef] {
        tags.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func tag(for id: TagID) -> TagRef? {
        tags[id]
    }

    func tags(for ids: [TagID]) -> [TagRef] {
        ids.compactMap { tags[$0] }
    }

    func lookupByName(_ name: String) -> TagRef? {
        let normalized = TagNameNormalizer.normalize(name)
        return tags.values.first { $0.name == normalized }
    }

    @discardableResult
    func createTag(name: String) -> TagRef {
        let normalized = TagNameNormalizer.normalize(name)
        guard !normalized.isEmpty else {
            let fallback = TagRef(id: TagID(), name: "UNTITLED", sfSymbolName: nil, color: .default, customHex: nil)
            tags[fallback.id] = fallback
            scheduleSave()
            return fallback
        }
        if let existing = lookupByName(normalized) {
            return existing
        }
        let tag = TagRef(id: TagID(), name: normalized, sfSymbolName: nil, color: .default, customHex: nil)
        tags[tag.id] = tag
        scheduleSave()
        return tag
    }

    func updateTag(_ tag: TagRef) {
        let normalized = TagNameNormalizer.normalize(tag.name)
        tags[tag.id] = TagRef(id: tag.id, name: normalized, sfSymbolName: tag.sfSymbolName, color: tag.color, customHex: tag.customHex)
        scheduleSave()
    }

    func renameTag(id: TagID, newName: String) {
        let normalized = TagNameNormalizer.normalize(newName)
        guard !normalized.isEmpty else { return }
        if let existing = lookupByName(normalized), existing.id != id {
            mergeTag(from: id, into: existing.id)
            return
        }
        guard var tag = tags[id] else { return }
        tag.name = normalized
        tags[id] = tag
        scheduleSave()
    }

    func setTagIcon(id: TagID, sfSymbolName: String?) {
        guard var tag = tags[id] else { return }
        tag.sfSymbolName = sfSymbolName
        tags[id] = tag
        scheduleSave()
    }

    func setTagColor(id: TagID, color: TagColor) {
        guard var tag = tags[id] else { return }
        tag.color = color
        tag.customHex = nil
        tags[id] = tag
        scheduleSave()
    }

    func setTagCustomHex(id: TagID, hex: String) {
        guard var tag = tags[id] else { return }
        tag.customHex = hex
        tags[id] = tag
        scheduleSave()
    }

    func migrateLegacyTags(_ legacyTags: [String]) -> [TagID] {
        var resolved: [TagID] = []
        for legacy in legacyTags {
            let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parsed = parseLegacyTag(trimmed)
            let normalized = TagNameNormalizer.normalize(parsed.name)
            guard !normalized.isEmpty else { continue }

            if let existing = lookupByName(normalized) {
                resolved.append(existing.id)
                continue
            }

            let tag = TagRef(
                id: TagID(),
                name: normalized,
                sfSymbolName: parsed.symbol ?? "tag.fill",
                color: .default,
                customHex: nil
            )
            tags[tag.id] = tag
            resolved.append(tag.id)
        }
        if !resolved.isEmpty {
            scheduleSave()
        }
        return sortedTagIDs(Set(resolved))
    }

    func sortedTagIDs(_ ids: Set<TagID>) -> [TagID] {
        let resolved = ids.compactMap { tags[$0] }
                let sorted = resolved.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return sorted.map { $0.id }
    }

    // MARK: - Persistence

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let blob = try JSONDecoder().decode(TagBlob.self, from: data)
            let dict = Dictionary(uniqueKeysWithValues: blob.tags.map { ($0.id, $0) })
            self.tags = dict
        } catch {
            self.tags = [:]
        }
    }

    private func saveNow() {
        let blob = TagBlob(tags: allTags)
        do {
            let data = try JSONEncoder().encode(blob)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("TagStore save error:", error)
            #endif
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func mergeTag(from sourceID: TagID, into targetID: TagID) {
        guard sourceID != targetID else { return }
        let library = ScaleLibraryStore.shared
        for scale in library.scales.values {
            guard scale.tagIDs.contains(sourceID) else { continue }
            var updated = scale
            var ids = Set(scale.tagIDs)
            ids.remove(sourceID)
            ids.insert(targetID)
            updated.tagIDs = sortedTagIDs(ids)
            library.updateScale(updated)
        }
        tags.removeValue(forKey: sourceID)
        scheduleSave()
    }

    private func parseLegacyTag(_ raw: String) -> (name: String, symbol: String?) {
        let folderPrefix = "folder:"
        let cleaned = raw.lowercased().hasPrefix(folderPrefix) ? String(raw.dropFirst(folderPrefix.count)) : raw
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let separators: [Character] = ["|", ":", "·", "•"]
        for separator in separators {
            let parts = trimmed.split(separator: separator).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { continue }
            let first = parts[0]
            let second = parts[1]
            if second.contains(".") {
                return (name: first, symbol: second)
            }
            if first.contains(".") {
                return (name: second, symbol: first)
            }
        }

        return (name: trimmed, symbol: nil)
    }
}
