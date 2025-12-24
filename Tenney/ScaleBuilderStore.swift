//
//  ScaleBuilderStore.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  ScaleBuilderStore.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class ScaleBuilderStore: ObservableObject {

    // MARK: - Editable state

    @Published var name: String = "Untitled Scale"
    @Published var notes: String = ""
    @Published var rootHz: Double = 440.0
    @Published var rootLabel: String? = nil
    @Published var tones: [TenneyScaleTone] = []

    // UI helpers
    @Published var ratioInput: String = ""
    @Published var showOnlyEnabled: Bool = false

    // MARK: - Init

    /// Accepts *any* payload type (so ContentView can pass whatever your AppModel uses)
    init(payload: Any) {
        hydrateBestEffort(from: payload)
        // Ensure we always have at least unison present for usability
        if tones.isEmpty {
            tones = [
                TenneyScaleTone(ref: RatioRef(p: 1, q: 1, octave: 0, monzo: [:]), name: "Unison", isEnabled: true)
            ]
        }
    }

    // MARK: - Build / Save

    func buildScale(existingID: UUID? = nil, favorite: Bool = false, lastPlayed: Date? = nil) -> TenneyScale {
        TenneyScale(
            id: existingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Scale" : name,
            rootHz: rootHz,
            rootLabel: rootLabel,
            tones: tones,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            favorite: favorite,
            lastPlayed: lastPlayed,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func saveToLibrary(_ library: ScaleLibraryStore) {
        let scale = buildScale()
        library.updateScale(scale)
    }

    // MARK: - Tone ops

    func addToneFromInput() {
        let trimmed = ratioInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = parseRatioRef(trimmed) else { return }
        tones.append(TenneyScaleTone(ref: parsed, name: nil, isEnabled: true))
        dedupeAndSort()
        ratioInput = ""
    }

    func add(scale: TenneyScale, includeDisabled: Bool = true) {
        let incoming = includeDisabled ? scale.tones : scale.tones.filter { $0.isEnabled }
        tones.append(contentsOf: incoming)
        dedupeAndSort()
    }

    func replace(with scale: TenneyScale, includeDisabled: Bool = true) {
        name = scale.name
        notes = scale.notes ?? ""
        rootHz = scale.rootHz
        rootLabel = scale.rootLabel
        tones = includeDisabled ? scale.tones : scale.tones.filter { $0.isEnabled }
        dedupeAndSort()
    }

    func toggleEnabled(_ toneID: UUID) {
        guard let i = tones.firstIndex(where: { $0.id == toneID }) else { return }
        tones[i].isEnabled.toggle()
    }

    func delete(at offsets: IndexSet, using filtered: [TenneyScaleTone]? = nil) {
        // If called from a filtered list, map back to the real indices.
        if let filtered {
            for o in offsets {
                guard filtered.indices.contains(o) else { continue }
                let tone = filtered[o]
                tones.removeAll { $0.id == tone.id }
            }
        } else {
            tones.remove(atOffsets: offsets)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        tones.move(fromOffsets: source, toOffset: destination)
    }

    func dedupeAndSort() {
        // Dedupe by p/q@octave
        var seen = Set<String>()
        tones = tones.filter { t in
            let k = "\(t.ref.p)/\(t.ref.q)@\(t.ref.octave)"
            return seen.insert(k).inserted
        }
        // Keep unison first if present, then ascending frequency ratio (ignoring root)
        tones.sort { a, b in
            let ra = (Double(a.ref.p) / Double(a.ref.q)) * pow(2.0, Double(a.ref.octave))
            let rb = (Double(b.ref.p) / Double(b.ref.q)) * pow(2.0, Double(b.ref.octave))
            return ra < rb
        }
    }

    // MARK: - Filtering

    var visibleTones: [TenneyScaleTone] {
        showOnlyEnabled ? tones.filter { $0.isEnabled } : tones
    }

    // MARK: - Best-effort payload hydration

    private func hydrateBestEffort(from payload: Any) {
        // If the payload contains a TenneyScale anywhere, use it.
        if let s = extractFirst(of: TenneyScale.self, from: payload) {
            replace(with: s, includeDisabled: true)
            return
        }

        // If it contains [RatioRef], convert to tones.
        if let refs = extractFirst(of: [RatioRef].self, from: payload) {
            tones = refs.map { TenneyScaleTone(ref: $0, name: nil, isEnabled: true) }
            dedupeAndSort()
        }

        // Try to find rootHz / label by name (Mirror)
        let m = Mirror(reflecting: payload)
        for child in m.children {
            guard let key = child.label else { continue }
            switch key {
            case "rootHz", "root", "a4", "hz":
                if let v = child.value as? Double { rootHz = v }
            case "rootLabel", "label", "rootName":
                if let v = child.value as? String { rootLabel = v }
            case "name", "scaleName", "title":
                if let v = child.value as? String, !v.isEmpty { name = v }
            default:
                break
            }
        }
    }

    private func extractFirst<T>(of type: T.Type, from payload: Any) -> T? {
        if let v = payload as? T { return v }
        let m = Mirror(reflecting: payload)
        for child in m.children {
            if let v = child.value as? T { return v }
            // one level deep
            let m2 = Mirror(reflecting: child.value)
            for c2 in m2.children {
                if let v = c2.value as? T { return v }
            }
        }
        return nil
    }

    // MARK: - Ratio parsing

    /// Accepts: "3/2", "3/2@1", "3/2^1", "3/2@-1"
    private func parseRatioRef(_ s: String) -> RatioRef? {
        let t = s.replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty else { return nil }

        var core = t
        var octave = 0

        if let at = core.firstIndex(of: "@") {
            let left = String(core[..<at])
            let right = String(core[core.index(after: at)...])
            core = left
            octave = Int(right) ?? 0
        } else if let car = core.firstIndex(of: "^") {
            let left = String(core[..<car])
            let right = String(core[core.index(after: car)...])
            core = left
            octave = Int(right) ?? 0
        }

        let parts = core.split(separator: "/")
        guard parts.count == 2, let p = Int(parts[0]), let q = Int(parts[1]), q != 0 else { return nil }

        let pp = max(1, abs(p))
        let qq = max(1, abs(q))
        return RatioRef(p: pp, q: qq, octave: octave, monzo: [:])
    }
}
