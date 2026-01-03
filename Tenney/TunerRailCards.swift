//
//  TunerRailCards.swift
//  Tenney
//
//  Created by OpenAI on 2024-05-07.
//

import SwiftUI
import Combine
import UIKit

// MARK: - Shared rail models / helpers

struct TapeEntry: Identifiable, Codable, Hashable {
    let id = UUID()
    let ratio: String
    let hz: Double
    let cents: Double
    let timestamp: Date
}

@MainActor
final class TunerRailSessionCaptureModel: ObservableObject {
    @Published var entries: [TapeEntry] = []

    func capture(_ e: TapeEntry) {
        entries.append(e)
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func clear() {
        entries.removeAll()
    }
}

private enum RailPasteboard {
    static func copy(_ s: String) {
        #if targetEnvironment(macCatalyst) || os(iOS) || os(visionOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}

private enum RailCodec {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}

/// Minimal ratio string → (p,q). Accepts "p/q" and trims whitespace.
/// (We only need this for lock/capture/export; RatioSolver-candidates already provide RatioRef.)
private func parsePQ(_ s: String) -> (p: Int, q: Int)? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = t.split(separator: "/")
    guard parts.count == 2,
          let p = Int(parts[0].trimmingCharacters(in: .whitespaces)),
          let q = Int(parts[1].trimmingCharacters(in: .whitespaces)),
          p > 0, q > 0 else { return nil }
    return (p, q)
}

private func primesUpTo(_ max: Int) -> [Int] {
    guard max >= 2 else { return [] }
    var isPrime = [Bool](repeating: true, count: max + 1)
    isPrime[0] = false
    isPrime[1] = false
    let r = Int(Double(max).squareRoot())
    if r >= 2 {
        for p in 2...r where isPrime[p] {
            var m = p * p
            while m <= max {
                isPrime[m] = false
                m += p
            }
        }
    }
    return (2...max).filter { isPrime[$0] }
}

private func monzoFromPQ(p: Int, q: Int, primeLimit: Int = 13) -> [Int:Int]? {
    guard p > 0, q > 0 else { return nil }
    var num = p
    var den = q
    var exps: [Int:Int] = [:]

    for prime in primesUpTo(max(2, primeLimit)) {
        var cNum = 0
        while num % prime == 0 { num /= prime; cNum += 1 }
        var cDen = 0
        while den % prime == 0 { den /= prime; cDen += 1 }
        let exp = cNum - cDen
        if exp != 0 { exps[prime] = exp }
    }

    if num != 1 || den != 1 { return nil }
    return exps
}

/// Build a RatioRef from "p/q" (unit-octave) + computed monzo for primes up to 11.
/// If you already have a project helper, you can swap this impl to that.
private func ratioRefFrom(_ ratioText: String) -> RatioRef? {
    guard let pq = parsePQ(ratioText) else { return nil }
    let monzo = monzoFromPQ(p: pq.p, q: pq.q) ?? [:]
    return RatioRef(p: pq.p, q: pq.q, octave: 0, monzo: monzo)
}

struct TunerRailCardShell<Content: View>: View {
    let title: String
    let systemImage: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                header
                if !isCollapsed {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            GlassChip(title: isCollapsed ? "Expand" : "Collapse", active: true, action: onToggleCollapse)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Cards (minimal MVP scaffolding)

struct TunerRailNowTuningCard: View {
    let snapshot: TunerRailSnapshot
    @Binding var collapsed: Bool

    var body: some View {
        TunerRailCardShell(
            title: "Now Tuning",
            systemImage: "tuningfork",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snapshot.ratioText)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.1f Hz", snapshot.hz))
                        .monospacedDigit()
                }
                HStack {
                    Text(String(format: "%+.1f ¢", snapshot.cents))
                        .monospacedDigit()
                    Spacer()
                    Text(String(format: "Conf %.2f", snapshot.confidence))
                    .font(.footnote)
                }
                if !snapshot.lowerText.isEmpty || !snapshot.higherText.isEmpty {
                    Text("Lower: \(snapshot.lowerText) · Higher: \(snapshot.higherText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TunerRailIntervalTapeCard: View {
    let snapshot: TunerRailSnapshot
    @ObservedObject var session: TunerRailSessionCaptureModel
    let onLock: (RatioRef) -> Void

    @Binding var collapsed: Bool

    @SceneStorage("tunerRail.intervalTape.data") private var storedData: Data?
    @State private var entries: [TapeEntry] = []

    @State private var stableKey: String = ""
    @State private var stableStart: Date?

    private let stableSeconds: TimeInterval = 0.45
    private let minConfidence: Double = 0.6
    private let maxEntries: Int = 200

    var body: some View {
        TunerRailCardShell(
            title: "Interval Tape",
            systemImage: "timeline.selection",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if entries.isEmpty {
                    Text("Waiting for stable targets…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries.reversed()) { e in
                        row(e)
                            .contextMenu { rowMenu(e) }
                    }
                }
            }
            .onAppear { load() }
            .onChange(of: snapshot.targetKey) { _ in handleSnapshot() }
            .onChange(of: snapshot.confidence) { _ in handleSnapshot() }
        }
    }

    private func row(_ e: TapeEntry) -> some View {
        HStack(spacing: 10) {
            Text(e.ratio).font(.footnote)
            Spacer()
            Text(String(format: "%+.1f¢", e.cents)).monospacedDigit()
            Text(String(format: "%.1f Hz", e.hz)).monospacedDigit()
        }
    }

    @ViewBuilder
    private func rowMenu(_ e: TapeEntry) -> some View {
        if let ref = ratioRefFrom(e.ratio) {
            Button("Lock") { onLock(ref) }
        }
        Button("Copy Ratio") { RailPasteboard.copy(e.ratio) }
        Button("Copy Hz")    { RailPasteboard.copy(String(format: "%.2f", e.hz)) }
        Button("Copy ¢")     { RailPasteboard.copy(String(format: "%.2f", e.cents)) }
        Divider()
        Button("Add to Session Capture") { session.capture(e) }
        Button("Remove") { remove(e.id) }
        Divider()
        Button("Clear All") { clearAll() }
    }

    private func handleSnapshot() {
        guard !snapshot.isListening else {
            stableStart = nil
            stableKey = ""
            return
        }
        // stability gate: same targetKey for ≥450ms + confidence ≥0.6
        guard snapshot.confidence >= minConfidence else {
            stableStart = nil
            stableKey = ""
            return
        }

        let key = snapshot.targetKey
        guard !key.isEmpty else {
            stableStart = nil
            stableKey = ""
            return
        }

        if stableKey != key {
            stableKey = key
            stableStart = Date()
            return
        }

        guard let s = stableStart else {
            stableStart = Date()
            return
        }

        if Date().timeIntervalSince(s) >= stableSeconds {
            appendCurrent()
            stableStart = nil // require re-stabilize before next append
        }
    }

    private func appendCurrent() {
        guard snapshot.hasLivePitch else { return }
        let e = TapeEntry(
            ratio: snapshot.ratioText,
            hz: snapshot.hz,
            cents: snapshot.cents,
            timestamp: Date()
        )
        entries.append(e)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        persist()
    }

    private func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func clearAll() {
        entries.removeAll()
        persist()
    }

    private func load() {
        if let decoded: [TapeEntry] = RailCodec.decode([TapeEntry].self, from: storedData) {
            entries = decoded
        }
    }

    private func persist() {
        storedData = RailCodec.encode(entries)
    }
}

struct TunerRailNearestTargetsCard: View {
    let snapshot: TunerRailSnapshot
    let rootHz: Double
    let primeLimit: Int
    let axisShift: [Int:Int]
    
    @ObservedObject var session: TunerRailSessionCaptureModel
    let onLock: (RatioRef) -> Void
    let onExportSingleToScale: (RatioRef) -> Void
    
    @Binding var collapsed: Bool
    @State private var sortByComplexity = false
    @State private var candidates: [RatioCandidate] = []
    private let solver = RatioSolver()
    
    var body: some View {
        TunerRailCardShell(
            title: "Nearest Targets",
            systemImage: "list.bullet.rectangle",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                GlassChip(title: "Sort by Complexity", active: sortByComplexity) {
                    withAnimation(.snappy) {
                        sortByComplexity.toggle()
                    }
                    refresh()
                }

                if candidates.isEmpty {
                    Text("Waiting for pitch…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates.prefix(12)) { cand in
                        HStack(spacing: 10) {
                            Text(cand.ratioText).font(.footnote.monospaced())
                            Spacer()
                            Text(String(format: "%+.1f¢", cand.cents)).monospacedDigit()
                            Text(String(format: "%.1f Hz", cand.hz)).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onLock(cand.ref) }
                        .contextMenu { rowMenu(cand) }
                    }
                }
            }
            // refresh via the throttled rail clock (10–20 Hz)
            .onChange(of: snapshot.hz) { _ in refresh() }
            .onChange(of: rootHz) { _ in refresh() }
            .onChange(of: primeLimit) { _ in refresh() }
            .onChange(of: axisShift) { _ in refresh() }
            .onChange(of: snapshot.isListening) { listening in
                if !listening { refresh() }
            }
            .onAppear { refresh() }
        }
    }
    
    
    @ViewBuilder
    private func rowMenu(_ cand: RatioCandidate) -> some View {
        Button("Copy Ratio") { RailPasteboard.copy(cand.ratioText) }
        Button("Copy Hz")    { RailPasteboard.copy(String(format: "%.2f", cand.hz)) }
        Button("Copy ¢")     { RailPasteboard.copy(String(format: "%.2f", cand.cents)) }
        Divider()
        Button("Lock Target") { onLock(cand.ref) }
        Button("Add to Session Capture") {
            session.capture(.init(ratio: cand.ratioText, hz: cand.hz, cents: cand.cents, timestamp: Date()))
        }
        Button("Add to Scale") { onExportSingleToScale(cand.ref) }
    }
    
    private func refresh() {
        guard snapshot.hasLivePitch else { return }
        candidates = solver.candidates(
            aroundHz: snapshot.hz,
            rootHz: rootHz,
            primeLimit: primeLimit,
            axisShift: axisShift,
            count: 12
        )
        
        if sortByComplexity {
            candidates.sort { $0.tenneyHeight < $1.tenneyHeight }
        }
    }
}

struct TunerRailSessionCaptureCard: View {
    let snapshot: TunerRailSnapshot
    @ObservedObject var session: TunerRailSessionCaptureModel

    let rootHz: Double
    let primeLimit: Int

    let onExportScale: (ScaleBuilderPayload) -> Void
    let onLock: (RatioRef) -> Void

    @Binding var collapsed: Bool

    var body: some View {
        TunerRailCardShell(
            title: "Session Capture",
            systemImage: "tray.and.arrow.down",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    GlassChip(title: "Capture", active: snapshot.hasLivePitch, action: captureCurrent)
                        .disabled(!snapshot.hasLivePitch)
                    GlassChip(title: "Export as Scale", active: true, action: exportAsScale)
                }

                if session.entries.isEmpty {
                    Text("Captured items will appear here for export.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.entries) { e in
                        HStack(spacing: 10) {
                            Text(e.ratio).font(.footnote)
                            Spacer()
                            Text(String(format: "%+.1f¢", e.cents)).monospacedDigit()
                            Text(String(format: "%.1f Hz", e.hz)).monospacedDigit()
                        }
                        .contextMenu { rowMenu(e) }
                    }

                    GlassChip(title: "Clear All", active: !session.entries.isEmpty, color: .red) {
                        session.clear()
                    }
                    .disabled(session.entries.isEmpty)
                }
            }
        }
    }

    private func captureCurrent() {
        guard snapshot.hasLivePitch else { return }
        session.capture(.init(ratio: snapshot.ratioText, hz: snapshot.hz, cents: snapshot.cents, timestamp: Date()))
    }

    private func exportAsScale() {
        let refs: [RatioRef] = session.entries.compactMap { ratioRefFrom($0.ratio) }
        guard !refs.isEmpty else { return }

        let payload = ScaleBuilderPayload(
            rootHz: rootHz,
            primeLimit: primeLimit,
            items: refs
        )
        onExportScale(payload)
    }

    @ViewBuilder
    private func rowMenu(_ e: TapeEntry) -> some View {
        if let ref = ratioRefFrom(e.ratio) {
            Button("Lock") { onLock(ref) }
        }
        Button("Copy as text") {
            RailPasteboard.copy("\(e.ratio)  \(String(format: "%.2f", e.hz)) Hz  \(String(format: "%+.2f", e.cents))¢")
        }
        Button("Delete Entry") { session.remove(id: e.id) }
        Divider()
        Button("Clear") { session.clear() }
        Button("Export as Scale") { exportAsScale() }
    }
}

// MARK: - Host

struct TunerContextRailHost: View {
    let app: AppModel
    @ObservedObject var tunerStore: TunerStore
    let onLockTarget: (RatioRef) -> Void
    let onExportScale: (ScaleBuilderPayload) -> Void
    let globalAxisShift: [Int:Int]
    let globalPrimeLimit: Int

    @ObservedObject var store: TunerRailStore
    @Binding var showSettings: Bool
    var onCustomize: (() -> Void)?

    @StateObject private var clock: TunerRailClock
    @SceneStorage("tunerRail.width") private var railWidth: Double = 340
    @SceneStorage("tunerRail.collapsed.raw") private var collapsedRaw: String = "[]"
        @State private var dividerHover = false
        @State private var isDraggingDivider = false
        @State private var dragStartWidth: Double = 340
    
    private let minWidth: Double = 260
    private let maxWidth: Double = 520

    init(
        store: TunerRailStore,
        app: AppModel,
        tunerStore: TunerStore,
        showSettings: Binding<Bool>,
        globalPrimeLimit: Int,
        globalAxisShift: [Int:Int],
        onLockTarget: @escaping (RatioRef) -> Void,
        onExportScale: @escaping (ScaleBuilderPayload) -> Void,
        onCustomize: (() -> Void)? = nil
    ) {
        self.store = store
        self.app = app
        self.tunerStore = tunerStore
        self._showSettings = showSettings
        self.globalPrimeLimit = globalPrimeLimit
        self.globalAxisShift = globalAxisShift
        self.onLockTarget = onLockTarget
        self.onExportScale = onExportScale
        self.onCustomize = onCustomize
        _clock = StateObject(wrappedValue: TunerRailClock(app: app))
    }


    var body: some View {
        Group {
            if store.showRail {
                HStack(spacing: 0) {
                    divider
                    content
                }
                .frame(width: railWidth)
                .onAppear { railWidth = min(maxWidth, max(minWidth, railWidth)) }
                .onAppear { store.updateSnapshot(clock.snapshot) }
                .onChange(of: clock.snapshot) { snap in
                    store.updateSnapshot(snap)
                }
                .contextMenu {
                    Toggle(isOn: Binding(get: { store.showRail }, set: store.setShowRail)) {
                        Label("Show Rail", systemImage: "sidebar.trailing")
                    }
                    Button {
                        app.openSettingsToTunerRail = true
                        onCustomize?()
                        showSettings = true
                    } label: {
                        Label("Customize…", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
                    .fill(Color.secondary.opacity(dividerHover ? 0.32 : 0.15))
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { dividerHover = $0 }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDraggingDivider {
                                    isDraggingDivider = true
                                    dragStartWidth = railWidth
                                }
                                // Dragging divider to the RIGHT should SHRINK the rail.
                                let proposed = dragStartWidth - value.translation.width
                                railWidth = min(maxWidth, max(minWidth, proposed))
                            }
                            .onEnded { _ in
                                isDraggingDivider = false
                            }
                    )
    }

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    if store.enabledCards.isEmpty {
                        emptyPlaceholder
                    } else {
                        ForEach(store.enabledCards) { card in
                            cardView(for: card)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
        }
                .background(.ultraThinMaterial)
                .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func cardView(for id: TunerRailCardID) -> some View {
        switch id {
        case .nowTuning:
            TunerRailNowTuningCard(snapshot: clock.snapshot, collapsed: binding(for: id))

        case .intervalTape:
            TunerRailIntervalTapeCard(
                snapshot: clock.snapshot,
                session: store.session,
                onLock: onLockTarget,
                collapsed: binding(for: id)
            )

        case .nearestTargets:
            TunerRailNearestTargetsCard(
                snapshot: clock.snapshot,
                rootHz: app.effectiveRootHz,
                primeLimit: globalPrimeLimit,
                axisShift: globalAxisShift,
                session: store.session,
                onLock: onLockTarget,
                onExportSingleToScale: { ref in
                    let payload = ScaleBuilderPayload(rootHz: app.effectiveRootHz, primeLimit: globalPrimeLimit, items: [ref])
                    onExportScale(payload)
                },
                collapsed: binding(for: id)
            )

        case .sessionCapture:
            TunerRailSessionCaptureCard(
                snapshot: clock.snapshot,
                session: store.session,
                rootHz: app.effectiveRootHz,
                primeLimit: globalPrimeLimit,
                onExportScale: onExportScale,
                onLock: onLockTarget,
                collapsed: binding(for: id)
            )
        }

    }

    private func binding(for id: TunerRailCardID) -> Binding<Bool> {
        func decodeCollapsed() -> Set<TunerRailCardID> {
            guard let data = collapsedRaw.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return Set(ids.compactMap { TunerRailCardID(rawValue: $0) })
        }

        func encodeCollapsed(_ set: Set<TunerRailCardID>) {
            let ids = set.map(\.rawValue)
            if let data = try? JSONEncoder().encode(ids),
               let json = String(data: data, encoding: .utf8) {
                collapsedRaw = json
            }
        }

        return Binding(
            get: { decodeCollapsed().contains(id) },
            set: { newValue in
                var set = decodeCollapsed()
                if newValue { set.insert(id) } else { set.remove(id) }
                encodeCollapsed(set)
            }
        )
    }

    private var emptyPlaceholder: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No cards enabled").font(.headline)
                Text("Use Settings → Tuner Context Rail to add cards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
