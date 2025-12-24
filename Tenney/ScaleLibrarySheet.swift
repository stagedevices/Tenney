//
//  ScaleLibrarySheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//

import Foundation
import SwiftUI

struct ScaleLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = ScaleLibraryStore.shared
    @State private var showOnlyFavorites = false
    @Environment(\.colorScheme) private var scheme
    @State private var actionTarget: TenneyScale? = nil   // ← selected row for the action sheet

    // simple sort/local filter
    private var filteredScales: [TenneyScale] {
        var items = Array(library.scales.values)
        if showOnlyFavorites { items = items.filter { $0.favorite } }
        let q = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                (!$0.descriptionText.isEmpty && $0.descriptionText.localizedCaseInsensitiveContains(q))
            }
        }
        switch library.sortKey {
        case .recent:
            items.sort { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .alpha:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            items.sort { $0.size > $1.size }
        case .limit:
            items.sort { $0.detectedLimit < $1.detectedLimit }
        }
        return items
    }

    private let limits = [3,5,7,11,13,17,19]
    private func count(for limit: Int) -> Int {
        Array(library.scales.values).filter { $0.detectedLimit <= limit }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if library.scales.isEmpty {
                    Section {
                        ContentUnavailableView("No saved scales yet",
                                               systemImage: "music.quarternote.3",
                                               description: Text("Save a scale from the Builder, or start by browsing limits."))
                    }
                } else {
                    // Quick controls
                    Section {
                        HStack(spacing: 10) {
                            Picker("", selection: $library.sortKey) {
                                Text("Recent").tag(ScaleLibraryStore.SortKey.recent)
                                Text("A–Z").tag(ScaleLibraryStore.SortKey.alpha)
                                Text("Size").tag(ScaleLibraryStore.SortKey.size)
                                Text("Limit").tag(ScaleLibraryStore.SortKey.limit)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)

                            Toggle(isOn: $showOnlyFavorites) {
                                Image(systemName: showOnlyFavorites ? "star.fill" : "star")
                            }
                            .toggleStyle(.button)
                            .tint(.yellow)
                            .accessibilityLabel("Show only favorites")
                        }
                    }

                    // Browse by limit
                    Section("Collections by Limit") {
                        ForEach(limits, id:\.self) { p in
                            NavigationLink {
                                ScaleLimitBrowserView(limit: p) { chosen in
                                        addToBuilder(chosen)
                                    }
                            } label: {
                                HStack {
                                    Text("\(p)-limit")
                                    Spacer()
                                    if count(for: p) > 0 {
                                        Text("\(count(for: p))")
                                            .font(.caption2.monospacedDigit())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                
                                }
                            }
                        }
                    }

                    // All scales (filtered/sorted)
                    Section("My Scales (\(filteredScales.count))") {
                        ForEach(filteredScales) { s in
                                                    // Primary tap: open the Library action sheet for this scale
                                                    Button {
                                                        actionTarget = s
                                                    } label: {
                                                        ScaleRow(scale: s, disclosure: true) // show chevron on the right
                                                    }
                                                    .buttonStyle(.plain)
                                                    // Trailing swipe: Open / Add / Play (plus Delete)
                                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                        Button("Open") { openInBuilder(s) }.tint(.accentColor)
                                                        Button("Add")  { addToBuilder(s) }.tint(.blue)
                                                        Button("Play") { playScalePreview(s) }.tint(.gray)
                                                        Button(role: .destructive) {
                                                            library.deleteScale(id: s.id)
                                                        } label: { Label("Delete", systemImage: "trash") }
                                                    }
                                                    // Leading swipe: Favorite toggle
                                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                                        Button {
                                                            var t = s; t.favorite.toggle(); library.updateScale(t)
                                                        } label: {
                                                            Label(s.favorite ? "Unfavorite" : "Favorite",
                                                                  systemImage: s.favorite ? "star.slash" : "star")
                                                        }.tint(.yellow)
                                                    }
                                                    // Context menu: ensure three actions, with Open first
                                                    .contextMenu {
                                                        Button("Open in Builder") { openInBuilder(s) }
                                                        Button("Add to Builder") { addToBuilder(s) }
                                                        Button("Play Scale") { playScalePreview(s) }
                                                    }
                                                }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .searchable(text: $library.searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Per-scale actions presented as a medium detent sheet
                        .sheet(item: $actionTarget) { s in
                            ScaleActionsSheet(
                                scale: s,
                                onOpen: { openInBuilder(s) },
                                onAdd:  { addToBuilder(s) },
                                onPlay: { playScalePreview(s) }
                            )
                            .presentationDetents([.medium])
                            .presentationDragIndicator(.visible)
                        }
        }
    }
}

// MARK: - Row
private struct ScaleRow: View {
    let scale: TenneyScale
    var disclosure: Bool = false
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                VStack(spacing: 2) {
                    Text("\(scale.size)")
                        .font(.headline.monospacedDigit())
                    Text("notes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                // Bolded name aligns with “Open in Builder” as the primary action
                        Text(scale.name).font(.headline.weight(.semibold))
                HStack(spacing: 8) {
                    Text("\(scale.detectedLimit)-limit").font(.caption).foregroundStyle(.secondary)
                    Text("Root \(Int(scale.referenceHz)) Hz").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if scale.favorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            if disclosure {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
        }
        .contentShape(Rectangle())
    }
}
// MARK: - Actions & Helpers
private extension ScaleLibrarySheet {
    func openInBuilder(_ s: TenneyScale) {
        // Open THIS file (not a new buffer)
        model.builderPayload = ScaleBuilderPayload(
            rootHz: s.referenceHz,
            primeLimit: s.detectedLimit,
            axisShift: [:],
            items: s.degrees,
            autoplayAll: model.latticeAuditionOn,
            startInLibrary: false,
            existing: s
        )
        // Close the medium detent; Builder sheet will present
        model.showScaleLibraryDetent = false
    }
    func addToBuilder(_ s: TenneyScale) {
        // Create a working buffer seeded with this scale (does NOT bind to file)
        model.builderPayload = ScaleBuilderPayload(
            rootHz: s.referenceHz,
            primeLimit: s.detectedLimit,
            axisShift: [:],
            items: s.degrees,
            autoplayAll: model.latticeAuditionOn,
            startInLibrary: false,
            existing: nil
        )
        model.showScaleLibraryDetent = false
    }
    func playScalePreview(_ s: TenneyScale) {
        let root = s.referenceHz
        for (i, r) in s.degrees.enumerated() {
            let when = DispatchTime.now() + .milliseconds(180 * i)
            DispatchQueue.main.asyncAfter(deadline: when) {
                let (cn, cd) = canonicalPQUnit(r.p, r.q)
                let f = foldToAudible(root * (Double(cn) / Double(cd)))
                _ = LatticeTone.shared.sustain(freq: f, amp: 0.16, attackMs: 8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { LatticeTone.shared.stopAll() }
            }
        }
    }
    // Keep 1 ≤ p/q < 2 so 3/2 never shows/plays as 3/1
    func canonicalPQUnit(_ p: Int, _ q: Int) -> (Int, Int) {
        guard p > 0 && q > 0 else { return (p, q) }
        var n = p, d = q
        while Double(n)/Double(d) >= 2 { d &*= 2 }
        while Double(n)/Double(d) <  1 { n &*= 2 }
        var a = n, b = d
        while b != 0 { let t = a % b; a = b; b = t }
        let g = max(1, a)
        return (n/g, d/g)
    }
    func foldToAudible(_ f: Double, minHz: Double = 20, maxHz: Double = 5000) -> Double {
        guard f.isFinite && f > 0 else { return f }
        var x = f; while x < minHz { x *= 2 }; while x > maxHz { x *= 0.5 }; return x
    }
}
// MARK: - Per-scale Action Sheet (Open • Add • Play)
private struct ScaleActionsSheet: View {
    let scale: TenneyScale
    let onOpen: () -> Void
    let onAdd:  () -> Void
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scale.name).font(.headline)
                    Text("\(scale.size) notes · \(scale.detectedLimit)-limit · Root \(Int(scale.referenceHz)) Hz")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 2)

            // Primary: Open in Builder (bold)
            Button {
                onOpen(); dismiss()
            } label: {
                Text("Open in Builder").font(.headline.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            // Secondary: Add to Builder
            Button {
                onAdd(); dismiss()
            } label: {
                Text("Add to Builder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // Tertiary: Play Scale
            Button {
                onPlay()
            } label: {
                Text("Play Scale").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button("Cancel") { dismiss() }
                .padding(.top, 6)
        }
        .padding(16)
    }
}
