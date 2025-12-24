//
//  ScaleBuilderPayload.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  ScaleBuilderPayload.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation

/// A portable payload representing the user’s in-progress scale/collection in the Builder.
/// This is intentionally “UI-agnostic”: it’s the data the Builder sheet needs,
/// plus enough metadata to serialize / restore later.
struct ScaleBuilderPayload: Identifiable, Codable, Equatable, Sendable {

    enum Source: String, Codable, CaseIterable, Sendable {
        case lattice
        case library
        case tuner
        case manual
    }

    var id: UUID = UUID()
    var source: Source = .manual

    /// User-facing title shown in Builder.
    var title: String

    /// Optional description/notes.
    var notes: String

    /// The reference root for interpreting ratios (does not force tuning system,
    /// but is required for frequency previews).
    var rootHz: Double

    /// Prime limit used when generating / validating candidate ratios.
    var primeLimit: Int

    /// Ordered list of ratio refs that constitute the scale/collection.
    var refs: [RatioRef]

    /// When adding from lattice, we often want to show “new additions since baseline”.
    /// This is a UI helper that can be persisted in the payload (optional).
    var stagingBaseCount: Int?

    /// Timestamp (useful for debugging / restore).
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        source: Source = .manual,
        title: String = "Untitled",
        notes: String = "",
        rootHz: Double,
        primeLimit: Int,
        refs: [RatioRef],
        stagingBaseCount: Int? = nil
    ) {
        self.source = source
        self.title = title
        self.notes = notes
        self.rootHz = rootHz
        self.primeLimit = primeLimit
        self.refs = refs
        self.stagingBaseCount = stagingBaseCount
    }

    // MARK: - Derived helpers

    var count: Int { refs.count }

    /// A stable “fingerprint” for comparing payloads without relying on UUID.
    var signature: String {
        var h = Hasher()
        h.combine(source.rawValue)
        h.combine(title)
        h.combine(Int(rootHz.rounded()))
        h.combine(primeLimit)
        for r in refs {
            h.combine(r.p); h.combine(r.q); h.combine(r.octave)
            // monzo is optional in some flows; normalize keys to stabilize.
            let keys = r.monzo.keys.sorted()
            for k in keys { h.combine(k); h.combine(r.monzo[k] ?? 0) }
        }
        return String(h.finalize())
    }

    mutating func touch() { updatedAt = Date() }

    /// Ensure refs are unique by (p,q,octave,monzo) while preserving first occurrence order.
    mutating func dedupePreservingOrder() {
        var seen = Set<RatioRef>()
        var out: [RatioRef] = []
        out.reserveCapacity(refs.count)
        for r in refs where !seen.contains(r) {
            seen.insert(r)
            out.append(r)
        }
        refs = out
        touch()
    }

    /// Sort refs by frequency ratio (p/q folded by octave).
    /// Note: this is optional; Builder can keep user order.
    mutating func sortAscendingByRatio() {
        refs.sort { a, b in
            let ra = (Double(a.p) / Double(a.q)) * pow(2.0, Double(a.octave))
            let rb = (Double(b.p) / Double(b.q)) * pow(2.0, Double(b.octave))
            return ra < rb
        }
        touch()
    }

    /// Convenience JSON export for debugging.
    func toJSON(pretty: Bool = true) -> String? {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSON(_ s: String) -> ScaleBuilderPayload? {
        guard let data = s.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(ScaleBuilderPayload.self, from: data)
    }
}
