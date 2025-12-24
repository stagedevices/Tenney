// /Users/seb/Tenney/Tenney/TenneyScale.swift

import Foundation

struct TenneyScale: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var rootHz: Double
    var rootLabel: String?
    var tones: [TenneyScaleTone]

    /// Legacy freeform notes. (ScaleLibrarySheet treats this as the “description”.)
    var notes: String?

    /// Library metadata
    var favorite: Bool
    var lastPlayed: Date?

    /// Optional timestamps (useful for future sorting / syncing).
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Derived fields used by the library UI

    var descriptionText: String {
        (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var size: Int { tones.count }

    /// Exposes the raw ratio refs (used by the detail sheet).
    var degrees: [RatioRef] { tones.map { $0.ref } }

    /// Best-effort “prime limit” detection from p/q + monzo.
    var detectedLimit: Int {
        TenneyScale.detectedPrimeLimit(from: tones)
    }

    // MARK: - Initializers

    init(
        id: UUID = UUID(),
        name: String,
        rootHz: Double = 440.0,
        rootLabel: String? = nil,
        tones: [TenneyScaleTone] = [],
        notes: String? = nil,
        favorite: Bool = false,
        lastPlayed: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootHz = rootHz
        self.rootLabel = rootLabel
        self.tones = tones
        self.notes = notes
        self.favorite = favorite
        self.lastPlayed = lastPlayed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Back-compat decode (so older stored scales still load cleanly).
    enum CodingKeys: String, CodingKey {
        case id, name, rootHz, rootLabel, tones
        case notes
        case favorite, lastPlayed
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        rootHz = try c.decodeIfPresent(Double.self, forKey: .rootHz) ?? 440.0
        rootLabel = try c.decodeIfPresent(String.self, forKey: .rootLabel)
        tones = try c.decodeIfPresent([TenneyScaleTone].self, forKey: .tones) ?? []

        notes = try c.decodeIfPresent(String.self, forKey: .notes)

        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)

        let now = Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? now
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(rootHz, forKey: .rootHz)
        try c.encodeIfPresent(rootLabel, forKey: .rootLabel)
        try c.encode(tones, forKey: .tones)

        try c.encodeIfPresent(notes, forKey: .notes)

        try c.encode(favorite, forKey: .favorite)
        try c.encodeIfPresent(lastPlayed, forKey: .lastPlayed)

        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Convenience init used by ScaleLimitBrowserView (and anywhere else you build from ratios)

    init(
        name: String,
        rootHz: Double,
        rootLabel: String? = nil,
        ratioRefs: [RatioRef],
        sort: Bool = true,
        dedupe: Bool = true,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.rootHz = rootHz
        self.rootLabel = rootLabel
        self.favorite = false
        self.lastPlayed = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.notes = notes

        var built = ratioRefs.map { TenneyScaleTone(ref: $0, name: nil) }

        if dedupe {
            var seen = Set<String>()
            built = built.filter { t in
                let key = "\(t.ref.p)/\(t.ref.q)@\(t.ref.octave)"
                return seen.insert(key).inserted
            }
        }

        if sort {
            built.sort { $0.frequency(in: rootHz) < $1.frequency(in: rootHz) }
        }

        self.tones = built
    }

    // MARK: - Limit detection

    private static func detectedPrimeLimit(from tones: [TenneyScaleTone]) -> Int {
        var maxPrime = 2

        for t in tones {
            let monzo = t.ref.monzo
            if !monzo.isEmpty {
                let m = monzo.keys.filter { $0 != 2 }.max() ?? 2
                maxPrime = max(maxPrime, m)
                continue
            }

            maxPrime = max(maxPrime, maxOddPrimeFactor(of: t.ref.p))
            maxPrime = max(maxPrime, maxOddPrimeFactor(of: t.ref.q))
        }

        return maxPrime
    }

    private static func maxOddPrimeFactor(of n: Int) -> Int {
        var x = abs(n)
        if x <= 1 { return 2 }

        // Strip 2s
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
}

struct TenneyScaleTone: Identifiable, Codable, Hashable {
    var id: UUID
    var ref: RatioRef
    var name: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        ref: RatioRef,
        name: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.ref = ref
        self.name = name
        self.isEnabled = isEnabled
    }

    func frequency(in rootHz: Double) -> Double {
        let r = Double(ref.p) / Double(ref.q) * pow(2.0, Double(ref.octave))
        return rootHz * r
    }

    func foldingToOneOctave() -> TenneyScaleTone {
        self
    }
}

// MARK: - Lightweight presets (optional)

enum TenneyScalePresets {
    static func unisonAndOctave(rootHz: Double, rootLabel: String? = nil) -> TenneyScale {
        TenneyScale(
            name: "Unison + Octave",
            rootHz: rootHz,
            rootLabel: rootLabel,
            ratioRefs: [
                RatioRef(p: 1, q: 1, octave: 0, monzo: [2: 0, 3: 0, 5: 0]),
                RatioRef(p: 1, q: 1, octave: 1, monzo: [2: 1, 3: 0, 5: 0])
            ],
            sort: true,
            dedupe: true,
            notes: "Utility preset for verifying output routing and latency."
        )
    }
}
