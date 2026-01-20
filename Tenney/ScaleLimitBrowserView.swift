//
//  ScaleLimitBrowserView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


import SwiftUI

/// A lightweight “catalog” of preset JI collections by prime limit, plus any user-saved scales
/// whose detected limit is <= the chosen limit.
///
/// Intended flow:
/// ScaleLibrarySheet -> NavigationLink(limit) -> ScaleLimitBrowserView(limit) -> onSelect(scale)
struct ScaleLimitBrowserView: View {
    let limit: Int
    let filteredSavedScales: [TenneyScale]
    let onSelect: (TenneyScale) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    @State private var search = ""
    @State private var includeSaved = true

    var body: some View {
        List {
            Section {
                Toggle("Include saved scales", isOn: $includeSaved)
            }

            if !search.isEmpty {
                Section {
                    Text("Searching presets + saved scales for “\(search)”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Featured presets") {
                ForEach(filteredPresets) { scale in
                    Button {
                        onSelect(scale)
                        dismiss()
                    } label: {
                        PresetRow(scale: scale, subtitle: presetSubtitle(for: scale))
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Odd-limit diamond") {
                let diamond = makeOddLimitDiamondScale(limit: limit, rootHz: model.rootHz)
                Button {
                    onSelect(diamond)
                    dismiss()
                } label: {
                    PresetRow(
                        scale: diamond,
                        subtitle: "All reduced odd ratios a/b, 1 ≤ a,b ≤ \(limit), folded to one octave"
                    )
                }
                .buttonStyle(.plain)
            }

            Section("Harmonic series") {
                ForEach(harmonicSeriesPresets) { scale in
                    Button {
                        onSelect(scale)
                        dismiss()
                    } label: {
                        PresetRow(scale: scale, subtitle: presetSubtitle(for: scale))
                    }
                    .buttonStyle(.plain)
                }
            }

            if includeSaved {
                Section("Your saved scales (≤ \(limit)-limit)") {
                    if filteredSaved.isEmpty {
                        ContentUnavailableView(
                            "No saved scales at this limit",
                            systemImage: "tray",
                            description: Text("Save or import a scale, then it’ll show up here automatically.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredSaved) { scale in
                            Button {
                                onSelect(scale)
                                dismiss()
                            } label: {
                                PresetRow(
                                    scale: scale,
                                    subtitle: "\(scale.size) degrees • \(scale.detectedLimit)-limit"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(limit)-limit")
        .searchable(text: $search, prompt: "Search presets & saved")
    }

    // MARK: - Filtering

    private var filteredPresets: [TenneyScale] {
        let all = featuredPresets
        guard !search.isEmpty else { return all }
        let q = search.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q)
            || $0.descriptionText.lowercased().contains(q)
        }
    }

    private var filteredSaved: [TenneyScale] {
        var items = filteredSavedScales
            .filter { $0.detectedLimit <= limit }

        if !search.isEmpty {
            let q = search.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(q)
                || $0.descriptionText.lowercased().contains(q)
            }
        }

        // Stable-ish, human-friendly ordering.
        items.sort { (a, b) in
            if a.favorite != b.favorite { return a.favorite && !b.favorite }
            if a.detectedLimit != b.detectedLimit { return a.detectedLimit < b.detectedLimit }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return items
    }

    // MARK: - Preset catalog

    private var featuredPresets: [TenneyScale] {
        let root = model.rootHz

        // “Prime steps” (one representative for each prime up to the limit, folded)
        let primes = primesUpTo(limit)
        let primeStepRefs: [RatioRef] = primes
            .filter { $0 > 2 }
            .map { p in
                // p/2 folded into [1,2) gives common “step” like 3/2, 5/4, 7/4 -> 7/4 folds to 7/4 (still <2)
                makeFoldedRatioRef(p: p, q: 2, limit: limit)
            }

        let primeSteps = TenneyScale(
            name: "Prime steps (≤ \(limit))",
            rootHz: root,
            rootLabel: "1/1",
            ratioRefs: ([RatioRef(p: 1, q: 1, octave: 0, monzo: [2: 0])] + primeStepRefs),
            sort: true,
            dedupe: true,
            notes: "One folded representative per prime (p/2), plus unison."
        )

        // “Odd diamond (compact)” — sample a/b where a,b are odd <= limit but keep it smaller for quick browsing.
        let compact = TenneyScale(
            name: "Odd diamond (compact, ≤ \(limit))",
            rootHz: root,
            rootLabel: "1/1",
            ratioRefs: makeOddDiamondCompactRefs(limit: limit),
            sort: true,
            dedupe: true,
            notes: "A smaller subset of the odd-limit diamond (favoring simpler ratios)."
        )

        return [primeSteps, compact]
    }

    private var harmonicSeriesPresets: [TenneyScale] {
        let root = model.rootHz
        let n1 = min(limit, 16)
        let n2 = min(limit, 32)

        let s1 = makeHarmonicSeriesScale(n: n1, rootHz: root)
        let s2 = makeHarmonicSeriesScale(n: n2, rootHz: root)

        return Array([s1, s2].prefix(s1.size == s2.size ? 1 : 2))
    }

    private func presetSubtitle(for scale: TenneyScale) -> String {
        if !scale.descriptionText.isEmpty { return scale.descriptionText }
        return "\(scale.size) degrees • \(scale.detectedLimit)-limit"
    }

    // MARK: - Generators

    private func makeHarmonicSeriesScale(n: Int, rootHz: Double) -> TenneyScale {
        let refs: [RatioRef] = (1...max(1, n)).map { k in
            makeFoldedRatioRef(p: k, q: 1, limit: limit)
        }
        return TenneyScale(
            name: "Harmonic series 1–\(max(1, n))",
            rootHz: rootHz,
            rootLabel: "1/1",
            ratioRefs: refs,
            sort: true,
            dedupe: true,
            notes: "Ratios k/1 (k = 1…\(max(1, n))) folded to one octave."
        )
    }

    private func makeOddLimitDiamondScale(limit: Int, rootHz: Double) -> TenneyScale {
        TenneyScale(
            name: "\(limit)-limit odd diamond",
            rootHz: rootHz,
            rootLabel: "1/1",
            ratioRefs: makeOddDiamondRefs(limit: limit),
            sort: true,
            dedupe: true,
            notes: "All reduced ratios a/b where a,b are odd and ≤ \(limit), folded into one octave."
        )
    }

    private func makeOddDiamondRefs(limit: Int) -> [RatioRef] {
        var seen = Set<String>()
        var out: [RatioRef] = []

        let odds = (1...max(1, limit)).filter { $0 % 2 == 1 }

        for a in odds {
            for b in odds {
                let g = gcd(a, b)
                let p = a / g
                let q = b / g

                // Fold into [1,2)
                let ref = makeFoldedRatioRef(p: p, q: q, limit: limit)

                let key = "\(ref.p)/\(ref.q)@\(ref.octave)"
                if seen.insert(key).inserted {
                    out.append(ref)
                }
            }
        }

        // Ensure 1/1 present.
        if !out.contains(where: { $0.p == 1 && $0.q == 1 }) {
            out.append(RatioRef(p: 1, q: 1, octave: 0, monzo: [2: 0]))
        }
        return out
    }

    /// A smaller diamond subset: only include ratios with modest numerator+denominator (keeps browsing snappy).
    private func makeOddDiamondCompactRefs(limit: Int) -> [RatioRef] {
        let full = makeOddDiamondRefs(limit: limit)
        var trimmed = full.filter { ($0.p + $0.q) <= max(12, limit) }
        // Always keep unison + a few anchors if present.
        trimmed.append(RatioRef(p: 1, q: 1, octave: 0, monzo: [2: 0]))
        trimmed.append(makeFoldedRatioRef(p: 3, q: 2, limit: limit))
        trimmed.append(makeFoldedRatioRef(p: 5, q: 4, limit: limit))
        trimmed.append(makeFoldedRatioRef(p: 7, q: 4, limit: limit))
        return trimmed
    }

    private func makeFoldedRatioRef(p: Int, q: Int, limit: Int) -> RatioRef {
        let pp = max(1, p)
        let qq = max(1, q)
        let g = gcd(pp, qq)
        let rp = pp / g
        let rq = qq / g

        var octave = 0
        var r = Double(rp) / Double(rq)
        while r >= 2.0 {
            r *= 0.5
            octave -= 1
        }
        while r < 1.0 {
            r *= 2.0
            octave += 1
        }

        let monzo = makeMonzo(p: rp, q: rq, octave: octave)
        return RatioRef(p: rp, q: rq, octave: octave, monzo: monzo)
    }

    // MARK: - Number theory helpers

    private func primesUpTo(_ n: Int) -> [Int] {
        guard n >= 2 else { return [] }
        var sieve = Array(repeating: true, count: n + 1)
        sieve[0] = false
        sieve[1] = false
        var p = 2
        while p * p <= n {
            if sieve[p] {
                var k = p * p
                while k <= n {
                    sieve[k] = false
                    k += p
                }
            }
            p += 1
        }
        return (2...n).filter { sieve[$0] }
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let t = x % y
            x = y
            y = t
        }
        return max(1, x)
    }

    private func makeMonzo(p: Int, q: Int, octave: Int) -> [Int: Int] {
        // Best-effort: build prime-exponent map for p/q, then include 2^octave.
        var num = max(1, abs(p))
        var den = max(1, abs(q))

        var exps: [Int: Int] = [:]
        exps[2] = octave

        func factor(_ x: inout Int, sign: Int) {
            var n = x
            var f = 2
            while f * f <= n {
                while n % f == 0 {
                    exps[f, default: 0] += sign
                    n /= f
                }
                f += (f == 2 ? 1 : 2) // 2 then odds
            }
            if n > 1 {
                exps[n, default: 0] += sign
            }
            x = 1
        }

        factor(&num, sign: +1)
        factor(&den, sign: -1)
        return exps
    }
}

private struct PresetRow: View {
    let scale: TenneyScale
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(scale.name)
                        .font(.headline)
                        .lineLimit(1)

                    if scale.favorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Text("\(scale.size)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
