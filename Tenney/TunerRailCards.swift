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

private struct TunerRailListeningOverlay: View {
    let isActive: Bool

    var body: some View {
        Group {
            if isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.20))
                    .overlay(alignment: .topTrailing) {
                        Text("Listening…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    .allowsHitTesting(false)
            }
        }
    }
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
            let listening = snapshot.isListening
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
            .opacity(listening ? 0.65 : 1.0)
            .overlay { TunerRailListeningOverlay(isActive: listening) }
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
            let listening = snapshot.isListening
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
            .opacity(listening ? 0.65 : 1.0)
            .overlay { TunerRailListeningOverlay(isActive: listening) }
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

struct TunerRailMiniLatticeFocusCard: View {
    let snapshot: TunerRailSnapshot
    let lockedTarget: RatioResult?
    let globalPrimeLimit: Int
    let globalAxisShift: [Int:Int]
    let globalRootHz: Double
    let tunerRootOverride: RatioRef?
    let onSetOverride: (RatioRef) -> Void
    let onClearOverride: () -> Void
    let onLock: (RatioRef) -> Void
    let onPreview: ((RatioRef?) -> Void)?

    @Binding var collapsed: Bool

    @AppStorage(SettingsKeys.railMiniLatticePrimeLimit) private var primeLimit: Int = 11
    @AppStorage(SettingsKeys.railMiniLatticeAxisShift) private var axisShiftRaw: String = "{}"

    @State private var pan: CGPoint = .zero
    @State private var zoom: CGFloat = 1.0
    @State private var centerRef: RatioRef? = nil
    @State private var centerKey: String = ""

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
            .onAppear { refreshCenter() }
            .onChange(of: lockedTarget) { _ in refreshCenter() }
            .onChange(of: snapshot.targetKey) { _ in refreshCenter() }
        }
    }

    private var miniLattice: some View {
        GeometryReader { geo in
            let center = resolvedCenter
            let snapshot = center.flatMap { buildMiniSnapshot(center: $0, primeLimit: primeLimit, axisShift: axisShift) }
            let mapper = snapshot.map { MiniLatticeMapper(snapshot: $0, size: geo.size, pan: pan, zoom: zoom) }

            ZStack {
                Canvas { ctx, _ in
                    guard let snapshot, let mapper else { return }
                    for node in snapshot.nodes {
                        drawMiniNode(node, mapper: mapper, in: &ctx)
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
                    if let snapshot, let mapper {
                        ZStack {
                            ForEach(snapshot.nodes) { node in
                                let pos = mapper.screenPosition(for: node.worldOffset)
                                Button {
                                    onLock(node.ref)
                                    onPreview?(nil)
                                } label: {
                                    Color.clear
                                }
                                .frame(width: mapper.hitSize, height: mapper.hitSize)
                                .position(x: pos.x, y: pos.y)
                                .buttonStyle(.plain)
#if targetEnvironment(macCatalyst)
                                .onHover { hovering in
                                    onPreview?(hovering ? node.ref : nil)
                                }
#endif
                                .contextMenu {
                                    Button("Set as Tuner Root") { onSetOverride(node.ref) }
                                    Button("Copy Ratio") { RailPasteboard.copy(node.label) }
                                }
                            }
                        }
                    }
                }

                if snapshot == nil {
                    Text("Waiting for target…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resetView() {
        pan = .zero
        zoom = 1.0
        onPreview?(nil)
    }

    private var resolvedCenter: RatioRef? {
        if let locked = lockedTarget {
            return ratioRef(from: locked)
        }
        if let centerRef { return centerRef }
        return ratioRefFrom(snapshot.ratioText)
    }

    private func ratioRef(from result: RatioResult) -> RatioRef {
        RatioRef(
            p: result.num,
            q: result.den,
            octave: result.octave,
            monzo: monzoFromPQ(p: result.num, q: result.den) ?? [:]
        )
    }

    private func refreshCenter() {
        if let lockedTarget {
            applyCenter(
                ratioRef(from: lockedTarget),
                key: "lock:\(lockedTarget.num)/\(lockedTarget.den)@\(lockedTarget.octave)"
            )
            return
        }

        if let live = ratioRefFrom(snapshot.ratioText) {
            applyCenter(live, key: "live:\(snapshot.targetKey)")
        }
    }

    private func applyCenter(_ ref: RatioRef, key: String) {
        guard centerKey != key else { return }
        centerKey = key
        centerRef = ref
    }

    private struct MiniLatticeNode: Identifiable {
        let id = UUID()
        let worldOffset: CGPoint
        let label: String
        let ref: RatioRef
        let isOverlay: Bool
        let prime: Int?
    }

    private struct MiniLatticeSnapshot {
        let nodes: [MiniLatticeNode]
        let bounds: CGRect
    }

    private struct MiniLatticeMapper {
        let snapshot: MiniLatticeSnapshot
        let size: CGSize
        let pan: CGPoint
        let zoom: CGFloat

        var scale: CGFloat {
            let padding: CGFloat = 24
            let width = max(snapshot.bounds.width, 1)
            let height = max(snapshot.bounds.height, 1)
            let availW = max(1, size.width - padding * 2)
            let availH = max(1, size.height - padding * 2)
            let base = min(availW / width, availH / height) * 0.92
            return base * zoom
        }

        var center: CGPoint {
            CGPoint(x: size.width * 0.5 + pan.x, y: size.height * 0.5 + pan.y)
        }

        var hitSize: CGFloat { max(22, 26 * zoom) }

        func screenPosition(for offset: CGPoint) -> CGPoint {
            CGPoint(
                x: center.x + offset.x * scale,
                y: center.y + offset.y * scale
            )
        }
    }

    private func buildMiniSnapshot(center: RatioRef, primeLimit: Int, axisShift: [Int:Int]) -> MiniLatticeSnapshot? {
        let layout = LatticeLayout()
        let monzo = center.monzo.isEmpty ? (monzoFromPQ(p: center.p, q: center.q, primeLimit: primeLimit) ?? [:]) : center.monzo
        let shift3 = axisShift[3] ?? 0
        let shift5 = axisShift[5] ?? 0

        let pivot = LatticeCoord(
            e3: (monzo[3] ?? 0) - shift3,
            e5: (monzo[5] ?? 0) - shift5
        )
        let pivotWorld = layout.position(for: pivot)

        var nodes: [MiniLatticeNode] = []
        var bounds = CGRect.null

        func appendNode(offset: CGPoint, label: String, ref: RatioRef, isOverlay: Bool, prime: Int?) {
            nodes.append(.init(worldOffset: offset, label: label, ref: ref, isOverlay: isOverlay, prime: prime))
            let r: CGRect = .init(x: offset.x, y: offset.y, width: 0, height: 0)
            bounds = bounds.union(r)
        }

        for dy in -3...3 {
            for dx in -2...2 {
                let coord = LatticeCoord(e3: pivot.e3 + dx, e5: pivot.e5 + dy)
                guard let pq = planePQ(e3: coord.e3 + shift3, e5: coord.e5 + shift5) else { continue }
                let (cp, cq) = RatioMath.canonicalPQUnit(pq.p, pq.q)
                let label = RatioMath.unitLabel(cp, cq)
                let ref = RatioRef(p: cp, q: cq, octave: 0, monzo: [3: coord.e3 + shift3, 5: coord.e5 + shift5])
                let world = layout.position(for: coord)
                let offset = CGPoint(x: world.x - pivotWorld.x, y: world.y - pivotWorld.y)
                appendNode(offset: offset, label: label, ref: ref, isOverlay: false, prime: nil)
            }
        }

        let overlayPrimes = overlayPrimeSet(centerMonzo: monzo, axisShift: axisShift, primeLimit: primeLimit)
        let baseE3 = pivot.e3 + shift3
        let baseE5 = pivot.e5 + shift5
        let centerPrimeOffsets: [Int:Int] = {
            var out: [Int:Int] = [:]
            for p in overlayPrimes {
                let shiftP = axisShift[p] ?? 0
                out[p] = (monzo[p] ?? 0) - shiftP
            }
            return out
        }()

        for prime in overlayPrimes {
            let shiftP = axisShift[prime] ?? 0
            let centerEp = centerPrimeOffsets[prime] ?? 0
            for ep in (centerEp - 2)...(centerEp + 2) {
                let eP = ep + shiftP
                guard let pq = overlayPQ(e3: baseE3, e5: baseE5, prime: prime, eP: eP) else { continue }
                let (cp, cq) = RatioMath.canonicalPQUnit(pq.p, pq.q)
                let label = RatioMath.unitLabel(cp, cq)
                let refMonzo: [Int:Int] = [3: baseE3, 5: baseE5, prime: eP]
                let ref = RatioRef(p: cp, q: cq, octave: 0, monzo: refMonzo)
                let world = layout.position(monzo: refMonzo)
                let offset = CGPoint(x: world.x - pivotWorld.x, y: world.y - pivotWorld.y)
                appendNode(offset: offset, label: label, ref: ref, isOverlay: true, prime: prime)
            }
        }

        guard !nodes.isEmpty else { return nil }
        return MiniLatticeSnapshot(nodes: nodes, bounds: bounds)
    }

    private func drawMiniNode(_ node: MiniLatticeNode, mapper: MiniLatticeMapper, in ctx: inout GraphicsContext) {
        let pos = mapper.screenPosition(for: node.worldOffset)
        let tenney = max(1, RatioMath.tenneyHeight(p: node.ref.p, q: node.ref.q))
        let base: CGFloat = 12
        let lift = CGFloat(18.0 * (1.0 / sqrt(Double(tenney))))
        let sz = max(8, base + lift)
        let rect = CGRect(x: pos.x - sz * 0.5, y: pos.y - sz * 0.5, width: sz, height: sz)

        let fill = node.isOverlay ? Color.accentColor : Color.secondary
        ctx.fill(Path(ellipseIn: rect), with: .color(fill.opacity(0.22)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(fill.opacity(0.40)), lineWidth: 1)

        let text = Text(node.label)
            .font(.system(size: 9 * max(0.75, mapper.zoom), weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.9))
        ctx.draw(text, at: CGPoint(x: pos.x, y: pos.y - sz * 0.75), anchor: .center)
    }

    private func planePQ(e3: Int, e5: Int) -> (Int, Int)? {
        var num = 1
        var den = 1

        func mul(_ x: inout Int, _ factor: Int?) -> Bool {
            guard let f = factor, let r = safeMul(x, f) else { return false }
            x = r
            return true
        }

        if e3 >= 0 { if !mul(&num, safePowInt(3, exp: e3)) { return nil } }
        else       { if !mul(&den, safePowInt(3, exp: -e3)) { return nil } }

        if e5 >= 0 { if !mul(&num, safePowInt(5, exp: e5)) { return nil } }
        else       { if !mul(&den, safePowInt(5, exp: -e5)) { return nil } }

        let g = gcd(num, den)
        return (num / g, den / g)
    }

    private func overlayPQ(e3: Int, e5: Int, prime: Int, eP: Int) -> (Int, Int)? {
        var num = 1
        var den = 1

        func mul(_ x: inout Int, _ factor: Int?) -> Bool {
            guard let f = factor, let r = safeMul(x, f) else { return false }
            x = r
            return true
        }

        if e3 >= 0 { if !mul(&num, safePowInt(3, exp: e3)) { return nil } }
        else       { if !mul(&den, safePowInt(3, exp: -e3)) { return nil } }

        if e5 >= 0 { if !mul(&num, safePowInt(5, exp: e5)) { return nil } }
        else       { if !mul(&den, safePowInt(5, exp: -e5)) { return nil } }

        if eP >= 0 { if !mul(&num, safePowInt(prime, exp: eP)) { return nil } }
        else       { if !mul(&den, safePowInt(prime, exp: -eP)) { return nil } }

        let g = gcd(num, den)
        return (num / g, den / g)
    }

    private func overlayPrimeSet(centerMonzo: [Int:Int], axisShift: [Int:Int], primeLimit: Int) -> Set<Int> {
        var primes = Set([7, 11].filter { $0 <= primeLimit })
        for p in centerMonzo.keys where p > 5 && p <= primeLimit { primes.insert(p) }
        for (p, shift) in axisShift where p > 5 && shift != 0 && p <= primeLimit { primes.insert(p) }
        return primes
    }

    private func safeMul(_ a: Int, _ b: Int) -> Int? {
        let (r, o) = a.multipliedReportingOverflow(by: b)
        return o ? nil : r
    }

    private func safePowInt(_ base: Int, exp: Int) -> Int? {
        guard exp >= 0 else { return nil }
        if exp == 0 { return 1 }
        var r = 1
        for _ in 0..<exp {
            guard let next = safeMul(r, base) else { return nil }
            r = next
        }
        return r
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a), y = abs(b)
        while y != 0 { let t = x % y; x = y; y = t }
        return max(1, x)
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
            let listening = snapshot.isListening
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Sort by Complexity", isOn: $sortByComplexity)
                    .toggleStyle(.switch)
                    .font(.footnote)
                    .onChange(of: sortByComplexity) { _ in refresh() }

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
            .opacity(listening ? 0.65 : 1.0)
            .overlay { TunerRailListeningOverlay(isActive: listening) }
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
            let hasLivePitch = snapshot.hasLivePitch
            let listening = snapshot.isListening
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Capture") { captureCurrent() }
                        .disabled(!hasLivePitch)
                    Button("Export as Scale") { exportAsScale() }
                }
                .buttonStyle(.borderedProminent)

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
            .opacity(listening ? 0.65 : 1.0)
            .overlay { TunerRailListeningOverlay(isActive: listening) }
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

        case .miniLatticeFocus:
            TunerRailMiniLatticeFocusCard(
                snapshot: clock.snapshot,
                lockedTarget: tunerStore.lockedTarget,
                globalPrimeLimit: globalPrimeLimit,
                globalAxisShift: globalAxisShift,
                globalRootHz: app.rootHz,
                tunerRootOverride: app.tunerRootOverride,
                onSetOverride: { ref in app.setTunerRootOverride(ref) },
                onClearOverride: { app.clearTunerRootOverride() },
                onLock: onLockTarget,
                onPreview: nil,
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
#endif
