import Foundation
import SwiftUI
import Combine

@MainActor
final class ScaleBuilderStore: ObservableObject {

    // Editable UI fields
    @Published var name: String
    @Published var descriptionText: String
    @Published var warningText: String? = nil

    // Canonical builder payload (used heavily by ScaleBuilderScreen)
    @Published var payload: ScaleBuilderPayload

    init(payload: ScaleBuilderPayload) {
        self.payload = payload
        self.name = payload.existing?.name ?? "Untitled Scale"
        self.descriptionText = payload.existing?.descriptionText ?? ""
        rebuild()
    }

    // Convenience if some call site still passes “Any”
    convenience init(payload: Any) {
        if let p = payload as? ScaleBuilderPayload {
            self.init(payload: p)
        } else {
            self.init(payload: ScaleBuilderPayload(rootHz: 440.0, primeLimit: 5, items: []))
        }
    }

    // UI expects this
    var degrees: [RatioRef] { payload.items }

    // UI expects this
    var detectedPrimeLimit: Int {
        TenneyScale.detectedLimit(for: payload.items)
    }

    func rebuild() {
        // sanitize root
        if !payload.rootHz.isFinite || payload.rootHz <= 0 { payload.rootHz = 440.0 }

        // dedupe while preserving order (p/q@octave + monzo)
        var seen = Set<RatioRef>()
        var out: [RatioRef] = []
        out.reserveCapacity(payload.items.count)
        for r in payload.items where seen.insert(r).inserted {
            out.append(r)
        }
        payload.items = out

        // keep payload’s limit in sync with what’s actually in the degrees
        payload.primeLimit = detectedPrimeLimit

        // (optional) warning surface; keep nil unless you want to enforce rules here
        warningText = nil
    }

    func add(_ ref: RatioRef) {
        payload.items.append(ref)
        rebuild()
    }

    func remove(at offsets: IndexSet) {
        payload.items.remove(atOffsets: offsets)
        rebuild()
    }

    func makeScaleSnapshot() -> TenneyScale {
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Scale" : name
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = payload.existing {
            return TenneyScale(
                id: existing.id,
                name: resolvedName,
                descriptionText: desc,
                degrees: payload.items,
                tags: existing.tags,
                favorite: existing.favorite,
                lastPlayed: existing.lastPlayed,
                referenceHz: payload.rootHz,
                rootLabel: existing.rootLabel,
                detectedLimit: TenneyScale.detectedLimit(for: payload.items),
                periodRatio: existing.periodRatio,
                maxTenneyHeight: TenneyScale.maxTenneyHeight(for: payload.items),
                author: existing.author
            )
        }

        return TenneyScale(
            name: resolvedName,
            descriptionText: desc,
            degrees: payload.items,
            tags: [],
            favorite: false,
            lastPlayed: nil,
            referenceHz: payload.rootHz,
            rootLabel: nil,
            detectedLimit: TenneyScale.detectedLimit(for: payload.items),
            periodRatio: 2.0,
            maxTenneyHeight: TenneyScale.maxTenneyHeight(for: payload.items),
            author: nil,
        )
    }

    // UI expects these string exports
    var sclText: String {
        ScalaExporter.sclText(
            scaleName: name,
            description: descriptionText,
            degrees: payload.items
        )
    }

    var kbmText: String {
        ScalaExporter.kbmText(
            referenceHz: payload.rootHz,
            scaleSize: max(1, payload.items.count)
        )
    }
}
