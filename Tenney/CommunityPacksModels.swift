import Foundation
import CryptoKit

enum CommunityPacksError: Error, LocalizedError {
    case schemaMismatch
    case network(String)
    case decoding(String)
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .schemaMismatch:
            return "This pack format is newer than your app."
        case .network(let message):
            return message
        case .decoding(let message):
            return message
        case .cacheUnavailable:
            return "No cached community packs are available."
        }
    }
}

enum CommunityPackSortKey: String, CaseIterable, Identifiable {
    case featured
    case newest
    case alpha
    case primeLimit

    var id: String { rawValue }
    var label: String {
        switch self {
        case .featured: return "Featured"
        case .newest: return "Newest"
        case .alpha: return "A–Z"
        case .primeLimit: return "Prime (min)"
        }
    }
}

struct CommunityIndex: Decodable {
    static let supportedSchemaVersions = Set([1, 2])

    let schemaVersion: Int
    let packs: [CommunityIndexEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case packs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) else {
            throw CommunityPacksError.schemaMismatch
        }
        guard Self.supportedSchemaVersions.contains(version) else {
            throw CommunityPacksError.schemaMismatch
        }
        self.schemaVersion = version
        self.packs = try c.decodeIfPresent([CommunityIndexEntry].self, forKey: .packs) ?? []
    }
}

struct CommunityIndexEntry: Decodable {
    let packID: String
    let path: String
    let title: String?
    let description: String?
    let authorName: String?
    let authorURLString: String?
    let license: String?
    let tenneyPath: String?
    let usesFilesContract: Bool
    let isFeatured: Bool
    let indexScales: [CommunityIndexScale]?

    enum CodingKeys: String, CodingKey {
        case packID
        case path
        case slug
        case title
        case description
        case descr
        case author
        case authorUrl
        case license
        case files
        case featured
        case isFeatured
        case scales
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let files = try c.decodeIfPresent(CommunityIndexFiles.self, forKey: .files)
        let packID = try c.decodeIfPresent(String.self, forKey: .packID)
        let path = try c.decodeIfPresent(String.self, forKey: .path)
        let slug = try c.decodeIfPresent(String.self, forKey: .slug)
        let resolvedPath: String
        if let path, !path.isEmpty {
            resolvedPath = path
        } else if let slug, !slug.isEmpty {
            resolvedPath = "packs/\(slug)"
        } else if let packID, !packID.isEmpty {
            resolvedPath = packID
        } else {
            resolvedPath = ""
        }
        self.packID = packID ?? slug ?? path ?? ""
        self.path = resolvedPath
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
            ?? c.decodeIfPresent(String.self, forKey: .descr)
        self.authorName = try c.decodeIfPresent(String.self, forKey: .author)
        self.authorURLString = try c.decodeIfPresent(String.self, forKey: .authorUrl)
        self.license = try c.decodeIfPresent(String.self, forKey: .license)
        self.tenneyPath = files?.tenney
        self.usesFilesContract = (tenneyPath?.isEmpty == false)
        self.isFeatured = try c.decodeIfPresent(Bool.self, forKey: .featured)
            ?? c.decodeIfPresent(Bool.self, forKey: .isFeatured)
            ?? false
        self.indexScales = try c.decodeIfPresent([CommunityIndexScale].self, forKey: .scales)
    }
}

struct CommunityIndexFiles: Decodable {
    let tenney: String?
}

struct CommunityIndexScale: Decodable {
    let id: String?
    let title: String?
    let files: CommunityIndexScaleFiles?
}

struct CommunityIndexScaleFiles: Decodable {
    let tenney: String?
}

struct CommunityPack: Decodable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let packID: String
    let title: String
    let version: String
    let date: String
    let license: String
    let author: CommunityAuthor
    let description: String
    // Optional metadata reserved for future server wiring.
    let summary: String?
    let changelog: String?
    let scales: [CommunityPackScale]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case packID
        case title
        case version
        case date
        case license
        case author
        case description
        case summary
        case changelog
        case scales
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) else {
            throw CommunityPacksError.schemaMismatch
        }
        guard version == Self.supportedSchemaVersion else {
            throw CommunityPacksError.schemaMismatch
        }
        self.schemaVersion = version
        self.packID = try c.decodeIfPresent(String.self, forKey: .packID) ?? ""
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Pack"
        self.version = try c.decodeIfPresent(String.self, forKey: .version) ?? "0"
        self.date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        self.license = try c.decodeIfPresent(String.self, forKey: .license) ?? ""
        self.author = try c.decodeIfPresent(CommunityAuthor.self, forKey: .author) ?? CommunityAuthor(name: "Unknown", url: nil)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.changelog = try c.decodeIfPresent(String.self, forKey: .changelog)
        self.scales = try c.decodeIfPresent([CommunityPackScale].self, forKey: .scales) ?? []
    }
}

struct CommunityAuthor: Decodable {
    let name: String
    let url: String?
}

struct CommunityPackScale: Decodable, Hashable {
    let id: String
    let title: String
    let path: String
}

struct CommunityScaleBuilderEnvelope: Decodable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let payload: ScaleBuilderPayload

    enum CodingKeys: String, CodingKey {
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) else {
            throw CommunityPacksError.schemaMismatch
        }
        guard version == Self.supportedSchemaVersion else {
            throw CommunityPacksError.schemaMismatch
        }
        self.schemaVersion = version
        self.payload = try ScaleBuilderPayload(from: decoder)
    }
}

struct CommunityPackScaleViewModel: Identifiable {
    let id: String
    let title: String
    let payload: ScaleBuilderPayload
    let primeLimit: Int
    let size: Int
}

struct CommunityPackViewModel: Identifiable {
    let id: String
    let packID: String
    let title: String
    let authorName: String
    let authorURL: URL?
    let license: String
    let dateString: String
    let date: Date?
    let lastUpdated: Date?
    let description: String
    let summary: String
    let changelog: String
    let version: String
    let scaleCount: Int
    let primeLimitMin: Int
    let primeLimitMax: Int
    let scales: [CommunityPackScaleViewModel]
    let indexOrder: Int
    let contentHash: String
    let isFeatured: Bool
}

func sanitizeCommunityDescription(_ text: String) -> String {
    var output = text
    let patterns = [
        "\\[(.*?)\\]\\((https?:\\/\\/[^\\)]+)\\)",
        "https?:\\/\\/\\S+",
        "\\bwww\\.[^\\s]+"
    ]
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: output.utf16.count)
            if pattern.hasPrefix("\\[") {
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "$1")
            } else {
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
            }
        }
    }
    return output
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func communityScaleUUID(packID: String, scaleID: String) -> UUID {
    if let uuid = UUID(uuidString: scaleID) {
        return uuid
    }
    let data = Data((packID + ":" + scaleID).utf8)
    let hash = SHA256.hash(data: data)
    let bytes = Array(hash)
    let tuple = (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    )
    return UUID(uuid: tuple)
}

func communityDate(from string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: string)
}
