import Foundation

struct CommunityCachedPack {
    let packID: String
    let packData: Data
    let scaleDataByPath: [String: Data]
}

struct CommunityCachedPayload {
    let indexData: Data
    let packs: [CommunityCachedPack]
}

enum CommunityPacksCache {
    private static let cacheFolderName = "CommunityPacks"

    private static var cacheDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Tenney", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let cacheDir = dir.appendingPathComponent(cacheFolderName, isDirectory: true)
        if !fm.fileExists(atPath: cacheDir.path) {
            try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        return cacheDir
    }

    static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(filtered)
    }

    static func save(indexData: Data, packs: [CommunityCachedPack]) throws {
        let fm = FileManager.default
        let dir = cacheDirectory
        let indexURL = dir.appendingPathComponent("index.json")
        try indexData.write(to: indexURL, options: [.atomic])

        for pack in packs {
            let packDir = dir.appendingPathComponent(safePathComponent(pack.packID), isDirectory: true)
            if !fm.fileExists(atPath: packDir.path) {
                try fm.createDirectory(at: packDir, withIntermediateDirectories: true)
            }
            let packURL = packDir.appendingPathComponent("pack.json")
            try pack.packData.write(to: packURL, options: [.atomic])

            let scalesDir = packDir.appendingPathComponent("scales", isDirectory: true)
            if !fm.fileExists(atPath: scalesDir.path) {
                try fm.createDirectory(at: scalesDir, withIntermediateDirectories: true)
            }
            for (path, data) in pack.scaleDataByPath {
                let name = safePathComponent(path)
                let fileURL = scalesDir.appendingPathComponent(name).appendingPathExtension("json")
                try data.write(to: fileURL, options: [.atomic])
            }
        }
    }

    static func load() throws -> CommunityCachedPayload {
        let fm = FileManager.default
        let dir = cacheDirectory
        let indexURL = dir.appendingPathComponent("index.json")
        guard fm.fileExists(atPath: indexURL.path) else {
            throw CommunityPacksError.cacheUnavailable
        }
        let indexData = try Data(contentsOf: indexURL)

        let packDirs = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var packs: [CommunityCachedPack] = []
        for packDir in packDirs where packDir.hasDirectoryPath {
            let packURL = packDir.appendingPathComponent("pack.json")
            guard fm.fileExists(atPath: packURL.path) else { continue }
            let packData = try Data(contentsOf: packURL)
            let scalesDir = packDir.appendingPathComponent("scales", isDirectory: true)
            var scaleDataByPath: [String: Data] = [:]
            if fm.fileExists(atPath: scalesDir.path) {
                let scaleFiles = (try? fm.contentsOfDirectory(at: scalesDir, includingPropertiesForKeys: nil)) ?? []
                for file in scaleFiles {
                    let data = try Data(contentsOf: file)
                    let name = file.deletingPathExtension().lastPathComponent
                    scaleDataByPath[name] = data
                }
            }
            let packID = packDir.lastPathComponent
            packs.append(CommunityCachedPack(packID: packID, packData: packData, scaleDataByPath: scaleDataByPath))
        }

        guard !packs.isEmpty else {
            throw CommunityPacksError.cacheUnavailable
        }

        return CommunityCachedPayload(indexData: indexData, packs: packs)
    }

    static func removePack(packID: String) throws {
        let fm = FileManager.default
        let dir = cacheDirectory
        let packDir = dir.appendingPathComponent(safePathComponent(packID), isDirectory: true)
        guard fm.fileExists(atPath: packDir.path) else { return }
        try fm.removeItem(at: packDir)
    }
}
