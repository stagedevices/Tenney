//
//  TunerRailCards.swift
//  Tenney
//
//  Created by OpenAI on 2024-05-07.
//

import SwiftUI
import Combine
import CoreGraphics
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

/// Build a RatioRef from "p/q" (unit-octave) + computed monzo for primes up to 11.
/// If you already have a project helper, you can swap this impl to that.
private func ratioRefFrom(_ ratioText: String) -> RatioRef? {
    guard let pq = parsePQ(ratioText) else { return nil }
    return RatioRef(p: pq.p, q: pq.q, octave: 0)
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
        Button(action: onToggleCollapse) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .imageScale(.small)
                    .padding(6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            let placeholder = snapshot.isListeningPlaceholder
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(placeholder ? "—" : snapshot.ratioText)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(placeholder ? "— Hz" : String(format: "%.1f Hz", snapshot.hz))
                        .monospacedDigit()
                }
                HStack {
                    Text(placeholder ? "— ¢" : String(format: "%+.1f ¢", snapshot.cents))
                        .monospacedDigit()
                    Spacer()
                    Text(
                        placeholder
                        ? "—"
                        : String(format: "Conf %.2f", snapshot.confidence)
                    )
                    .font(.footnote)
                }
                if placeholder {
                    Text("Listening…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if !snapshot.lowerText.isEmpty || !snapshot.higherText.isEmpty {
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
            let listening = snapshot.isListeningPlaceholder
            VStack(alignment: .leading, spacing: 6) {
                if listening {
                    Text("Listening…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if entries.isEmpty {
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
        guard !snapshot.isListeningPlaceholder else {
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

struct TunerRailMiniLatticeFocusCard: View {
    let centerRatioText: String
    let globalPrimeLimit: Int
    let globalAxisShift: [Int:Int]
    let globalRootHz: Double
    let tunerRootOverride: RatioRef?
    let onSetOverride: (RatioRef) -> Void
    let onClearOverride: () -> Void

    @Binding var collapsed: Bool

    @AppStorage(SettingsKeys.railMiniLatticePrimeLimit) private var primeLimit: Int = 11
    @AppStorage(SettingsKeys.railMiniLatticeAxisShift) private var axisShiftRaw: String = "{}"

    @State private var pan: CGPoint = .zero
    @State private var zoom: CGFloat = 1.0

    private var axisShift: [Int:Int] {
        get {
            guard let data = axisShiftRaw.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([Int:Int].self, from: data) else { return [:] }
            return dict
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
               axisShiftRaw = s
            }
        }
    }

    private var overrideHz: Double? {
        guard let ref = tunerRootOverride else { return nil }
        return frequencyHz(rootHz: globalRootHz, ratio: ref, foldToAudible: false)
    }

    @ViewBuilder
    private var tunerRootStatus: some View {
        HStack(spacing: 8) {
            if let ref = tunerRootOverride, let hz = overrideHz {
                Text("Tuner Root: \(ratioDisplayString(ref)) · \(String(format: "%.1f Hz", hz)) (Override)")
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: "Tuner Root: Global (%.1f Hz)", globalRootHz))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if tunerRootOverride != nil {
                Button("Clear Override") { onClearOverride() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
        .font(.footnote)
    }


    var body: some View {
        TunerRailCardShell(
            title: "Mini Lattice Focus",
            systemImage: "hexagon",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Prime \(primeLimit)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset View") { resetView() }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }

                tunerRootStatus

                ZStack {
                    miniLattice
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // pan + scroll-wheel zoom (Catalyst)
                    #if targetEnvironment(macCatalyst)
                    CatalystMouseTrackingView(
                        onMove: { _ in },
                        onScroll: { dy, _ in
                            // dy: positive/negative wheel delta
                            let next = zoom * (dy < 0 ? 1.08 : 0.92)
                            zoom = min(4.0, max(0.5, next))
                        }
                    )
                    .allowsHitTesting(true)
                    #endif
                }
            }
            .contextMenu {
                Button("Reset View") { resetView() }
                Button("Sync to Global Settings") {
                    primeLimit = globalPrimeLimit
                    axisShift = globalAxisShift
                }
                Button("Clear Root Override") { onClearOverride() }
                    .disabled(tunerRootOverride == nil)
            }
        }
    }

    private var miniLattice: some View {
        GeometryReader { geo in
            let nodes = makeNodes(center: centerRatioText, primeLimit: primeLimit, axisShift: axisShift)
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let cx = w * 0.5 + pan.x
                let cy = h * 0.5 + pan.y
                let spacing: CGFloat = 28 * zoom

                for n in nodes {
                    let x = cx + CGFloat(n.dx - 2) * spacing
                    let y = cy + CGFloat(n.dy - 3) * spacing
                    let r = CGRect(x: x - 11*zoom, y: y - 11*zoom, width: 22*zoom, height: 22*zoom)

                    ctx.fill(Path(ellipseIn: r), with: .color(.secondary.opacity(0.20)))
                    ctx.stroke(Path(ellipseIn: r), with: .color(.secondary.opacity(0.35)), lineWidth: 1)

                    let text = Text(n.ratio)
                        .font(.system(size: 9*zoom, weight: .regular, design: .monospaced))
                    ctx.draw(text, at: CGPoint(x: x, y: y))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        pan = CGPoint(x: pan.x + v.translation.width * 0.25,
                                      y: pan.y + v.translation.height * 0.25)
                    }
            )
            .overlay(alignment: .topLeading) {
                // hit targets: invisible buttons per node
                let w = geo.size.width
                let h = geo.size.height
                let cx = w * 0.5 + pan.x
                let cy = h * 0.5 + pan.y
                let spacing: CGFloat = 28 * zoom
                let nodes = makeNodes(center: centerRatioText, primeLimit: primeLimit, axisShift: axisShift)

                ZStack {
                    ForEach(nodes, id: \.id) { n in
                        let x = cx + CGFloat(n.dx - 2) * spacing
                        let y = cy + CGFloat(n.dy - 3) * spacing
                        Button {
                            if let ref = ratioRefFrom(n.ratio) {
                                onSetOverride(ref)
                            }
                        } label: {
                            Color.clear
                        }
                        .frame(width: 26*zoom, height: 26*zoom)
                        .position(x: x, y: y)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func resetView() {
        pan = .zero
        zoom = 1.0
    }

    private struct MiniNode: Identifiable {
        let id = UUID()
        let dx: Int
        let dy: Int
        let ratio: String
    }

    /// 5×7 grid: dx ∈ [-2…2], dy ∈ [-3…3]
    /// We implement a simple 3/5 lattice step (multiply by 3^dx * 5^dy, then fold into [1,2)).
    private func makeNodes(center: String, primeLimit: Int, axisShift: [Int:Int]) -> [MiniNode] {
        guard let base = parsePQ(center) else {
            return (0..<35).map { i in
                MiniNode(dx: i % 5, dy: i / 5, ratio: "—")
            }
        }

        func applyPrimeShift(_ p: inout Int, _ q: inout Int) {
            for (prime, exp) in axisShift {
                guard exp != 0 else { continue }
                let powv = Int(pow(Double(prime), Double(abs(exp))))
                if exp > 0 { p *= powv } else { q *= powv }
            }
        }

        func foldUnit(_ pIn: Int, _ qIn: Int) -> (p: Int, q: Int) {
            var p = pIn
            var q = qIn
            let g = gcd(p, q)
            p /= g; q /= g
            // fold into [1,2)
            while p < q { p *= 2 }
            while p >= 2*q { q *= 2 }
            let g2 = gcd(p, q)
            return (p / g2, q / g2)
        }

        var out: [MiniNode] = []
        out.reserveCapacity(35)

        for dy in -3...3 {
            for dx in -2...2 {
                var p = base.p
                var q = base.q

                // axis shift (independent state)
                applyPrimeShift(&p, &q)

                // 3/5 steps
                if dx != 0 {
                    let pow3 = Int(pow(3.0, Double(abs(dx))))
                    if dx > 0 { p *= pow3 } else { q *= pow3 }
                }
                if dy != 0 {
                    let pow5 = Int(pow(5.0, Double(abs(dy))))
                    if dy > 0 { p *= pow5 } else { q *= pow5 }
                }

                // prime-limit clamp (simple): if any factor exceeds primeLimit, show placeholder
                if maxPrimeFactor(p) > primeLimit || maxPrimeFactor(q) > primeLimit {
                    out.append(.init(dx: dx + 2, dy: dy + 3, ratio: "×"))
                } else {
                    let f = foldUnit(p, q)
                    out.append(.init(dx: dx + 2, dy: dy + 3, ratio: "\(f.p)/\(f.q)"))
                }
            }
        }
        return out
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { let t = x % y; x = y; y = t }
        return abs(x)
    }

    private func maxPrimeFactor(_ n: Int) -> Int {
        var x = abs(n)
        var maxp = 1
        var p = 2
        while p*p <= x {
            while x % p == 0 { maxp = max(maxp, p); x /= p }
            p += (p == 2 ? 1 : 2)
        }
        if x > 1 { maxp = max(maxp, x) }
        return maxp
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
                Toggle("Sort by Complexity", isOn: $sortByComplexity)
                    .toggleStyle(.switch)
                    .font(.footnote)
                    .onChange(of: sortByComplexity) { _ in refresh() }

                if snapshot.isListeningPlaceholder {
                    Text("Listening…")
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
        guard snapshot.hasLivePitch else {
            candidates = []
            return
        }
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
            let hasLivePitch = snapshot.hasLivePitch
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Capture") { captureCurrent() }
                        .disabled(!hasLivePitch)
                    Button("Export as Scale") { exportAsScale() }
                }
                .buttonStyle(.borderedProminent)

                if !hasLivePitch {
                    Text("Listening…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

                    Button("Clear All") { session.clear() }
                        .font(.footnote)
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

#if targetEnvironment(macCatalyst)
struct TunerContextRailHost: View {
    let app: AppModel
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
        showSettings: Binding<Bool>,
        globalPrimeLimit: Int,
        globalAxisShift: [Int:Int],
        onLockTarget: @escaping (RatioRef) -> Void,
        onExportScale: @escaping (ScaleBuilderPayload) -> Void,
        onCustomize: (() -> Void)? = nil
    ) {
        self.store = store
        self.app = app
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

        case .miniLatticeFocus:
            TunerRailMiniLatticeFocusCard(
                centerRatioText: "1/1",
                globalPrimeLimit: globalPrimeLimit,
                globalAxisShift: globalAxisShift,
                globalRootHz: app.rootHz,
                tunerRootOverride: app.tunerRootOverride,
                onSetOverride: { ref in app.setTunerRootOverride(ref) },
                onClearOverride: { app.clearTunerRootOverride() },
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

        Binding(
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
#endif
