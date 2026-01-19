import Foundation

/// Current (UI-facing) scale model.
/// Back-compat: can decode legacy `{rootHz, tones, notes}` blobs.
struct TenneyScale: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var descriptionText: String
    var degrees: [RatioRef]

    // Library metadata
    var tagIDs: [TagID]
    var favorite: Bool
    var lastPlayed: Date?

    // Tuning metadata
    var referenceHz: Double
    var rootLabel: String?
    var periodRatio: Double

    // Cached/derived (kept as stored fields because the UI expects them)
    var detectedLimit: Int
    var maxTenneyHeight: Int

    // Optional authorship
    var author: String?

    // MARK: - Convenience / compatibility

    var size: Int { degrees.count }

    // Older code sometimes still wants these:
    var rootHz: Double { referenceHz }
    var notes: String? { descriptionText.isEmpty ? nil : descriptionText }

    init(
        id: UUID = UUID(),
        name: String,
        descriptionText: String = "",
        degrees: [RatioRef],
        tagIDs: [TagID] = [],
        favorite: Bool = false,
        lastPlayed: Date? = nil,
        referenceHz: Double = 440.0,
        rootLabel: String? = nil,
        detectedLimit: Int? = nil,
        periodRatio: Double = 2.0,
        maxTenneyHeight: Int? = nil,
        author: String? = nil
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.degrees = degrees
        self.tagIDs = tagIDs
        self.favorite = favorite
        self.lastPlayed = lastPlayed
        self.referenceHz = referenceHz
        self.rootLabel = rootLabel
        self.periodRatio = periodRatio
        self.author = author

        self.detectedLimit = detectedLimit ?? TenneyScale.detectedLimit(for: degrees)
        self.maxTenneyHeight = maxTenneyHeight ?? TenneyScale.maxTenneyHeight(for: degrees)
    }

    // MARK: - Static helpers expected by Builder/Library

    static func detectedLimit(for degrees: [RatioRef]) -> Int {
        var maxPrime = 2
        for r in degrees {
            if !r.monzo.isEmpty {
                let m = r.monzo.keys.filter { $0 != 2 }.max() ?? 2
                maxPrime = max(maxPrime, m)
            } else {
                maxPrime = max(maxPrime, maxOddPrimeFactor(of: r.p))
                maxPrime = max(maxPrime, maxOddPrimeFactor(of: r.q))
            }
        }
        return maxPrime
    }

    static func maxTenneyHeight(for degrees: [RatioRef]) -> Int {
        degrees
            .map { RatioMath.tenneyHeight(p: $0.p, q: $0.q) }
            .max() ?? 1
    }

    private static func maxOddPrimeFactor(of n: Int) -> Int {
        var x = abs(n)
        if x <= 1 { return 2 }
        while x % 2 == 0 { x /= 2 }
        if x <= 1 { return 2 }
        var maxP = 2
        var f = 3
        while f * f <= x {
            while x % f == 0 {
                maxP = f
                x /= f
            }
            f += 2
        }
        if x > 1 { maxP = max(maxP, x) }
        return maxP
    }

    // MARK: - Codable back-compat

    enum CodingKeys: String, CodingKey {
        // current
        case id, name, descriptionText, degrees, tagIDs, favorite, lastPlayed, referenceHz, rootLabel, periodRatio, detectedLimit, maxTenneyHeight, author

        // legacy
        case rootHz, tones, notes, rootLabelLegacy, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Scale"

        // Description (new or old)
        if let d = try c.decodeIfPresent(String.self, forKey: .descriptionText) {
            descriptionText = d
        } else {
            descriptionText = (try c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        }

        // Degrees (new or old)
        if let deg = try c.decodeIfPresent([RatioRef].self, forKey: .degrees) {
            degrees = deg
        } else if let legacyTones = try c.decodeIfPresent([TenneyScaleTone].self, forKey: .tones) {
            degrees = legacyTones.map { $0.ref }
        } else {
            degrees = []
        }

        if let ids = try c.decodeIfPresent([TagID].self, forKey: .tagIDs) {
            tagIDs = ids
        } else {
            let legacy = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
            tagIDs = TagStore.shared.migrateLegacyTags(legacy)
        }
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)

        // Reference Hz (new or old)
        if let hz = try c.decodeIfPresent(Double.self, forKey: .referenceHz) {
            referenceHz = hz
        } else {
            referenceHz = try c.decodeIfPresent(Double.self, forKey: .rootHz) ?? 440.0
        }

        // Root label (keep whichever exists)
        rootLabel = try c.decodeIfPresent(String.self, forKey: .rootLabel)

        periodRatio = try c.decodeIfPresent(Double.self, forKey: .periodRatio) ?? 2.0
        author = try c.decodeIfPresent(String.self, forKey: .author)

        detectedLimit = try c.decodeIfPresent(Int.self, forKey: .detectedLimit) ?? TenneyScale.detectedLimit(for: degrees)
        maxTenneyHeight = try c.decodeIfPresent(Int.self, forKey: .maxTenneyHeight) ?? TenneyScale.maxTenneyHeight(for: degrees)
    }
    func encode(to encoder: Encoder) throws {
          var c = encoder.container(keyedBy: CodingKeys.self)
          try c.encode(id, forKey: .id)
          try c.encode(name, forKey: .name)
          try c.encode(descriptionText, forKey: .descriptionText)
          try c.encode(degrees, forKey: .degrees)
          try c.encode(tagIDs, forKey: .tagIDs)
          try c.encode(favorite, forKey: .favorite)
          try c.encodeIfPresent(lastPlayed, forKey: .lastPlayed)
          try c.encode(referenceHz, forKey: .referenceHz)
          try c.encodeIfPresent(rootLabel, forKey: .rootLabel)
          try c.encode(periodRatio, forKey: .periodRatio)
          try c.encode(detectedLimit, forKey: .detectedLimit)
          try c.encode(maxTenneyHeight, forKey: .maxTenneyHeight)
          try c.encodeIfPresent(author, forKey: .author)
      }
}

/// Legacy tone (kept so old saved libraries decode cleanly).
struct TenneyScaleTone: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var ref: RatioRef
    var name: String?
    var isEnabled: Bool

    init(id: UUID = UUID(), ref: RatioRef, name: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.ref = ref
        self.name = name
        self.isEnabled = isEnabled
    }
}

// MARK: - Legacy initializer used by preset browsers (ScaleLimitBrowserView)

extension TenneyScale {
    init(
        name: String,
        rootHz: Double,
        rootLabel: String? = nil,
        ratioRefs: [RatioRef],
        sort: Bool = true,
        dedupe: Bool = true,
        notes: String? = nil
    ) {
        var refs = ratioRefs

        if dedupe {
            var seen = Set<String>()
            refs = refs.filter { r in
                let key = "\(r.p)/\(r.q)@\(r.octave)"
                return seen.insert(key).inserted
            }
        }

        if sort {
            refs.sort { a, b in
                let ra = (Double(a.p) / Double(a.q)) * pow(2.0, Double(a.octave))
                let rb = (Double(b.p) / Double(b.q)) * pow(2.0, Double(b.octave))
                return ra < rb
            }
        }

        self.init(
            name: name,
            descriptionText: (notes ?? ""),
            degrees: refs,
            tagIDs: [],
            favorite: false,
            lastPlayed: nil,
            referenceHz: rootHz,
            rootLabel: rootLabel,
            detectedLimit: TenneyScale.detectedLimit(for: refs),
            periodRatio: 2.0,
            maxTenneyHeight: TenneyScale.maxTenneyHeight(for: refs),
            author: nil
        )
    }
}
