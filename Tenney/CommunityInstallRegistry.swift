import Foundation
import Combine

struct CommunityInstallRecord: Codable, Hashable {
    var installedScaleIDs: [UUID]
    var installedRemoteScaleIDs: [String]?
    var installedAt: Date
    var installedVersion: String
    var installedContentHash: String
    var installedContentSignature: String?
}

@MainActor
final class CommunityInstallRegistryStore: ObservableObject {
    static let shared = CommunityInstallRegistryStore()

    @Published private(set) var records: [String: CommunityInstallRecord] = [:]

    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Tenney", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = dir.appendingPathComponent("community_install_registry_v1.json")
        load()
    }

    func record(for packID: String) -> CommunityInstallRecord? {
        records[packID]
    }

    func isInstalled(_ packID: String) -> Bool {
        records[packID] != nil
    }

    func setInstalled(packID: String, record: CommunityInstallRecord) {
        records[packID] = record
        save()
    }

    func removeInstalled(packID: String) {
        records.removeValue(forKey: packID)
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([String: CommunityInstallRecord].self, from: data)
        } catch {
            records = [:]
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("CommunityInstallRegistry save error:", error)
            #endif
        }
    }
}
