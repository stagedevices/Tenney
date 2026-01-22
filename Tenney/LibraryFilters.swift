import Foundation

struct LibraryFilters: Codable, Equatable {
    enum SourceFilter: String, Codable, CaseIterable, Identifiable {
        case all
        case localOnly
        case communityOnly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "Any"
            case .localOnly: return "Local"
            case .communityOnly: return "Community"
            }
        }
    }

    enum MaxLimit: Int, Codable, CaseIterable, Identifiable {
        case none = 0
        case limit3 = 3
        case limit5 = 5
        case limit7 = 7
        case limit11 = 11
        case limit13 = 13
        case limit17 = 17
        case limit19 = 19

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .none: return "Any"
            default: return "≤ \(rawValue)"
            }
        }

        var limitValue: Int? {
            self == .none ? nil : rawValue
        }
    }

    enum SizeRange: String, Codable, CaseIterable, Identifiable {
        case any
        case small
        case medium
        case large
        case huge

        var id: String { rawValue }

        var label: String {
            switch self {
            case .any: return "Any"
            case .small: return "≤ 7 notes"
            case .medium: return "8–12 notes"
            case .large: return "13–24 notes"
            case .huge: return "25+ notes"
            }
        }

        func contains(size: Int) -> Bool {
            switch self {
            case .any: return true
            case .small: return size <= 7
            case .medium: return (8...12).contains(size)
            case .large: return (13...24).contains(size)
            case .huge: return size >= 25
            }
        }
    }

    enum RootHzRange: String, Codable, CaseIterable, Identifiable {
        case any
        case upTo110
        case hz110to220
        case hz220to440
        case hz440to880
        case hz880Plus

        var id: String { rawValue }

        var label: String {
            switch self {
            case .any: return "Any"
            case .upTo110: return "0–110 Hz"
            case .hz110to220: return "110–220 Hz"
            case .hz220to440: return "220–440 Hz"
            case .hz440to880: return "440–880 Hz"
            case .hz880Plus: return "880+ Hz"
            }
        }

        func contains(hz: Double) -> Bool {
            switch self {
            case .any:
                return true
            case .upTo110:
                return hz < 110
            case .hz110to220:
                return hz >= 110 && hz < 220
            case .hz220to440:
                return hz >= 220 && hz < 440
            case .hz440to880:
                return hz >= 440 && hz < 880
            case .hz880Plus:
                return hz >= 880
            }
        }
    }

    enum NotesFilter: String, Codable, CaseIterable, Identifiable {
        case any
        case hasNotes

        var id: String { rawValue }

        var label: String {
            switch self {
            case .any: return "Any"
            case .hasNotes: return "Has notes"
            }
        }
    }

    enum RecentlyPlayed: String, Codable, CaseIterable, Identifiable {
        case any
        case days7
        case days30
        case days90

        var id: String { rawValue }

        var label: String {
            switch self {
            case .any: return "Any"
            case .days7: return "Last 7 days"
            case .days30: return "Last 30 days"
            case .days90: return "Last 90 days"
            }
        }

        var dayWindow: Int? {
            switch self {
            case .any: return nil
            case .days7: return 7
            case .days30: return 30
            case .days90: return 90
            }
        }
    }

    var selectedTagIDs: Set<TagID> = []
    var source: SourceFilter = .all
    var maxLimit: MaxLimit = .none
    var sizeRange: SizeRange = .any
    var rootHzRange: RootHzRange = .any
    var notesFilter: NotesFilter = .any
    var recentlyPlayed: RecentlyPlayed = .any

    static let defaultValue = LibraryFilters()

    var isDefault: Bool {
        self == LibraryFilters.defaultValue
    }
}

extension LibraryFilters {
    func matches(
        scale: TenneyScale,
        tagStore: TagStore,
        favoritesOnly: Bool,
        searchText: String,
        favoriteIDs: Set<UUID>
    ) -> Bool {
        if favoritesOnly, !favoriteIDs.contains(scale.id) {
            return false
        }

        if source != .all {
            let isCommunity = scale.provenance?.kind == .communityPack
            if source == .localOnly, isCommunity { return false }
            if source == .communityOnly, !isCommunity { return false }
        }

        if let maxLimitValue = maxLimit.limitValue, scale.detectedLimit > maxLimitValue {
            return false
        }

        if !sizeRange.contains(size: scale.size) {
            return false
        }

        if !rootHzRange.contains(hz: scale.referenceHz) {
            return false
        }

        if notesFilter == .hasNotes {
            if scale.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }

        if let days = recentlyPlayed.dayWindow {
            guard let lastPlayed = scale.lastPlayed else { return false }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
            if lastPlayed < cutoff { return false }
        }

        if !selectedTagIDs.isEmpty {
            let scaleTagIDs = Set(scale.tagIDs)
            if !selectedTagIDs.allSatisfy({ scaleTagIDs.contains($0) }) {
                return false
            }
        }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return true
        }
        let query = trimmedQuery.lowercased()
        let blob = searchTextBlob(for: scale, tagStore: tagStore)
        return blob.localizedCaseInsensitiveContains(query)
    }

    func isFiltering(searchText: String, favoritesOnly: Bool) -> Bool {
        !isDefault || favoritesOnly || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func searchTextBlob(for scale: TenneyScale, tagStore: TagStore) -> String {
        var parts: [String] = [scale.name, scale.descriptionText]

        let tags = tagStore.tags(for: scale.tagIDs).map { $0.name }
        parts.append(contentsOf: tags)

        if let provenance = scale.provenance {
            parts.append(provenance.packName)
            parts.append(provenance.packID)
            if let author = provenance.authorName {
                parts.append(author)
            }
        }
        if let pack = scale.pack {
            parts.append(pack.title)
            parts.append(pack.id)
            if let slug = pack.slug {
                parts.append(slug)
            }
        }

        if let author = scale.author {
            parts.append(author)
        }

        return parts
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
