//
//  TunerContextRail.swift
//  Tenney
//
//  Lightweight, modular right-rail for the mac tuner surface.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum TunerRailCard: String, CaseIterable, Identifiable {
    case miniLattice
    case nearestTargets
    case stabilityTrace
    case sessionCapture

    var id: String { rawValue }

    static let defaultCards: [TunerRailCard] = [.miniLattice, .nearestTargets, .stabilityTrace]
    static let defaultRaw: String = defaultCards.map(\.rawValue).joined(separator: ",")
}

struct TunerContextRail: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var store: TunerStore
    var availableHeight: CGFloat? = nil

    @AppStorage(SettingsKeys.tunerRailEnabledCards)
    private var enabledRaw: String = TunerRailCard.defaultRaw

    private var enabledCards: [TunerRailCard] {
        let raw = enabledRaw
            .split(separator: ",")
            .compactMap { TunerRailCard(rawValue: String($0)) }
        let set = Set(raw)
        let ordered = TunerRailCard.allCases.filter { set.contains($0) }
        return ordered.isEmpty ? TunerRailCard.defaultCards : ordered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(enabledCards) { card in
                switch card {
                case .miniLattice:
                    MiniLatticeCard(
                        target: store.lockedTarget ?? parseRatio(app.display.ratioText),
                        primeLimit: store.primeLimit
                    ) { store.lockedTarget = $0 }

                case .nearestTargets:
                    NearestTargetsCard(
                        hz: app.display.hz,
                        rootHz: app.rootHz,
                        primeLimit: store.primeLimit
                    ) { store.lockedTarget = $0 }

                case .stabilityTrace:
                    StabilityTraceCard(
                        cents: app.display.cents,
                        confidence: app.display.confidence,
                        held: store.lockedTarget != nil
                    )

                case .sessionCapture:
                    SessionCaptureCard(
                        hz: app.display.hz,
                        cents: app.display.cents,
                        confidence: app.display.confidence,
                        ratioText: app.display.ratioText
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: availableHeight ?? .infinity,
            alignment: .topLeading
        )
    }
}

// MARK: - Mini lattice
private struct MiniNode: Identifiable {
    let id = UUID()
    let coord: LatticeCoord
    let point: CGPoint
    let ratio: RatioResult
}

private struct MiniLatticeCard: View {
    let target: RatioResult?
    let primeLimit: Int
    let onLock: (RatioResult) -> Void

    var body: some View {
        RailCardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Label("Mini Lattice", systemImage: "hexagon")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if let t = target {
                        Text("\(t.num)/\(t.den)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if target != nil {
                    MiniLatticeView(target: target, primeLimit: primeLimit, onLock: onLock)
                        .frame(height: 190)
                } else {
                    Text("Waiting for a target…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                }
            }
        }
    }
}

private struct MiniLatticeView: View {
    let target: RatioResult?
    let primeLimit: Int
    let onLock: (RatioResult) -> Void

    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @State private var hovered: LatticeCoord? = nil

    private let layout = LatticeLayout()

    var body: some View {
        GeometryReader { geo in
            let nodes = buildNodes(size: geo.size)

            Canvas { ctx, size in
                guard !nodes.isEmpty else { return }

                // links
                var lines = Path()
                for a in nodes {
                    for b in neighbors(of: a.coord, within: nodes) {
                        lines.move(to: a.point)
                        lines.addLine(to: b.point)
                    }
                }
                ctx.stroke(lines, with: .color(Color.secondary.opacity(0.16)), lineWidth: 1)

                for node in nodes {
                    let isCenter = node.coord == centerCoord(for: target)
                    let isHover = node.coord == hovered
                    let r: CGFloat = isCenter ? 8 : 6
                    var circle = Path(ellipseIn: CGRect(x: node.point.x - r, y: node.point.y - r, width: r * 2, height: r * 2))

                    let dominantPrime = abs(node.coord.e3) >= abs(node.coord.e5) ? 3 : 5
                    let tint = theme.primeTint(dominantPrime).opacity(0.85)
                    ctx.fill(circle, with: .color(tint))
                    ctx.stroke(circle, with: .color(Color.white.opacity(0.22)), lineWidth: 1)

                    if isHover || isCenter {
                        let label = Text(node.ratio.ratioString)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        ctx.draw(label, at: CGPoint(x: node.point.x, y: node.point.y - r - 10), anchor: .center)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hovered = nearest(to: value.location, in: nodes)?.coord
                    }
                    .onEnded { value in
                        if let hit = nearest(to: value.location, in: nodes) {
                            onLock(hit.ratio)
                        }
                        hovered = nil
                    }
            )
            .onDisappear { hovered = nil }
        }
    }

    private func neighbors(of coord: LatticeCoord, within nodes: [MiniNode]) -> [MiniNode] {
        nodes.filter { abs($0.coord.e3 - coord.e3) + abs($0.coord.e5 - coord.e5) == 1 }
    }

    private func buildNodes(size: CGSize) -> [MiniNode] {
        guard let centerRatio = target else { return [] }
        let baseMonzo = monzo(for: centerRatio, limit: primeLimit)
        let baseCoord = centerCoord(for: target)
        let basePos = layout.position(for: baseCoord)

        var raw: [MiniNode] = []
        for de3 in -2...2 {
            for de5 in -2...2 {
                let coord = LatticeCoord(e3: baseCoord.e3 + de3, e5: baseCoord.e5 + de5)
                let pos = layout.position(for: coord)
                let rel = CGPoint(x: pos.x - basePos.x, y: pos.y - basePos.y)
                var monzo = baseMonzo
                monzo[3, default: 0] += de3
                monzo[5, default: 0] += de5
                let ratio = ratioResult(fromMonzo: monzo)
                raw.append(MiniNode(coord: coord, point: rel, ratio: ratio))
            }
        }

        let bounds = raw.reduce(into: CGRect.null) { rect, node in
            rect = rect.union(CGRect(origin: node.point, size: .zero))
        }
        guard bounds.width.isFinite, bounds.height.isFinite else { return [] }

        let pad: CGFloat = 12
        let sx = (size.width  - pad * 2) / max(bounds.width, 1)
        let sy = (size.height - pad * 2) / max(bounds.height, 1)
        let scale = max(4, min(sx, sy))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        return raw.map { node in
            let p = CGPoint(
                x: center.x + (node.point.x - bounds.midX) * scale,
                y: center.y + (node.point.y - bounds.midY) * scale
            )
            return MiniNode(coord: node.coord, point: p, ratio: node.ratio)
        }
    }

    private func nearest(to point: CGPoint, in nodes: [MiniNode]) -> MiniNode? {
        nodes.min { a, b in
            let da = hypot(a.point.x - point.x, a.point.y - point.y)
            let db = hypot(b.point.x - point.x, b.point.y - point.y)
            return da < db
        }
    }

    private func centerCoord(for ratio: RatioResult?) -> LatticeCoord {
        guard let ratio else { return .zero }
        let monzo = monzo(for: ratio, limit: primeLimit)
        return LatticeCoord(e3: monzo[3] ?? 0, e5: monzo[5] ?? 0)
    }
}

// MARK: - Nearest targets
private struct NearestTargetsCard: View {
    let hz: Double
    let rootHz: Double
    let primeLimit: Int
    let onLock: (RatioResult) -> Void

    @State private var rows: [RatioCandidate] = []
    private let solver = RatioSolver()
    @State private var lastUpdate = Date.distantPast

    var body: some View {
        RailCardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Nearest targets", systemImage: "target")
                        .font(.callout.weight(.semibold))
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.prefix(8), id: \.result) { cand in
                        HStack {
                            Text(cand.result.ratioString)
                                .font(.headline.monospacedDigit())
                            Spacer()
                            Text(String(format: "%+.1f¢", cand.cents))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f Hz", cand.hz))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                onLock(cand.result)
                            } label: {
                                Image(systemName: "lock")
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                        }
                    }
                }
            }
        }
        .onChange(of: hz) { _ in recompute() }
        .onChange(of: rootHz) { _ in recompute() }
        .onChange(of: primeLimit) { _ in recompute() }
        .onAppear { recompute() }
    }

    private func recompute() {
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) > 0.08 else { return }
        lastUpdate = now
        let newRows = solver.nearestCandidates(for: hz, rootHz: rootHz, primeLimit: primeLimit, maxCount: 10)
        rows = newRows
    }
}

// MARK: - Stability trace
private final class TraceBuffer: ObservableObject {
    struct Sample: Identifiable { let id = UUID(); let cents: Double; let confidence: Double }
    @Published var samples: [Sample] = []
    private let maxCount = 240

    func push(cents: Double, confidence: Double) {
        let s = Sample(cents: cents, confidence: confidence)
        samples.append(s)
        if samples.count > maxCount {
            samples.removeFirst(samples.count - maxCount)
        }
    }
}

private struct StabilityTraceCard: View {
    let cents: Double
    let confidence: Double
    let held: Bool

    @StateObject private var buffer = TraceBuffer()
    @State private var lastSample = Date.distantPast

    var body: some View {
        RailCardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Stability", systemImage: "waveform.path.ecg")
                        .font(.callout.weight(.semibold))
                    if held {
                        Text("Held")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                    Spacer()
                }

                TraceSparkline(samples: buffer.samples)
                    .frame(height: 90)
            }
        }
        .onAppear { sample() }
        .onChange(of: cents) { _ in sample() }
        .onChange(of: confidence) { _ in sample() }
    }

    private func sample() {
        let now = Date()
        guard now.timeIntervalSince(lastSample) > 0.04 else { return }
        lastSample = now
        buffer.push(cents: cents, confidence: max(0, min(1, confidence)))
    }
}

private struct TraceSparkline: View {
    let samples: [TraceBuffer.Sample]

    var body: some View {
        GeometryReader { geo in
            let pts = pathPoints(in: geo.size)
            ZStack {
                if !pts.line.isEmpty {
                    Path { p in
                        p.addLines(pts.line)
                    }
                    .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }

                if !pts.conf.isEmpty {
                    Path { p in
                        p.addLines(pts.conf)
                    }
                    .stroke(Color.secondary.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
            }
        }
    }

    private func pathPoints(in size: CGSize) -> (line: [CGPoint], conf: [CGPoint]) {
        guard !samples.isEmpty else { return ([], []) }
        let values = samples.suffix(120)
        let span = max(50.0, values.map { abs($0.cents) }.max() ?? 20.0)
        let width = size.width
        let height = size.height
        let step = width / CGFloat(max(values.count - 1, 1))

        var line: [CGPoint] = []
        var conf: [CGPoint] = []

        for (i, s) in values.enumerated() {
            let x = CGFloat(i) * step
            let y = height * 0.5 - CGFloat(s.cents / span) * (height * 0.45)
            let c = height * (1 - CGFloat(s.confidence)) * 0.9
            line.append(CGPoint(x: x, y: y))
            conf.append(CGPoint(x: x, y: c))
        }
        return (line, conf)
    }
}

// MARK: - Session capture
private struct CapturedNote: Identifiable {
    let id = UUID()
    let ratio: String
    let hz: Double
    let cents: Double
    let date: Date
}

private struct SessionCaptureCard: View {
    let hz: Double
    let cents: Double
    let confidence: Double
    let ratioText: String

    @State private var captures: [CapturedNote] = []
    @State private var stableStart: Date? = nil

    var body: some View {
        RailCardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Captured notes", systemImage: "tray.full")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button {
                        appendCapture()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                if captures.isEmpty {
                    Text("Auto-captures when steady, or tap + to add.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(captures) { note in
                        HStack {
                            Text(note.ratio)
                                .font(.headline.monospacedDigit())
                            Spacer()
                            Text(String(format: "%.1f Hz", note.hz))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Copy") { copyRatios() }
                        Spacer()
                        Button("Clear") { captures.removeAll() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .onChange(of: hz) { _ in trackStability() }
        .onChange(of: confidence) { _ in trackStability() }
        .onChange(of: cents) { _ in trackStability() }
        .onAppear { trackStability() }
    }

    private func trackStability() {
        let steady = confidence >= 0.7 && abs(cents) < 4
        let now = Date()
        if steady {
            if stableStart == nil { stableStart = now }
            if let start = stableStart, now.timeIntervalSince(start) > 0.6 {
                appendCapture()
                stableStart = nil
            }
        } else {
            stableStart = nil
        }
    }

    private func appendCapture() {
        guard hz.isFinite, hz > 0, ratioText.contains("/") else { return }
        let note = CapturedNote(ratio: ratioText, hz: hz, cents: cents, date: Date())
        captures.append(note)
    }

    private func copyRatios() {
        let lines = captures.map { $0.ratio }.joined(separator: "\n")
#if canImport(UIKit)
        UIPasteboard.general.string = lines
#elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines, forType: .string)
#endif
    }
}

// MARK: - Shared helpers
private struct RailCardSurface<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(12)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var bg: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            Color.clear.background(.ultraThinMaterial)
        }
    }
}

private func monzo(for ratio: RatioResult, limit: Int) -> [Int:Int] {
    var out: [Int:Int] = [:]
    let primes = [2] + PrimeConfig.primes.filter { $0 <= limit }

    func factor(_ n: Int, sign: Int) {
        var x = n
        for p in primes {
            while x % p == 0 && x > 1 {
                out[p, default: 0] += sign
                x /= p
            }
        }
        if x > 1 {
            out[x, default: 0] += sign
        }
    }

    factor(ratio.num, sign: +1)
    factor(ratio.den, sign: -1)
    out[2, default: 0] += ratio.octave
    return out
}

private func ratioResult(fromMonzo monzo: [Int:Int]) -> RatioResult {
    let (p, q) = RatioMath.pq(fromMonzo: monzo)
    let unit = RatioMath.canonicalPQUnit(p, q)
    let raw = Double(p) / Double(q)
    let unitVal = Double(unit.p) / Double(unit.q)
    let octave = Int(round(log2(raw / unitVal)))
    return RatioResult(num: unit.p, den: unit.q, octave: octave)
}

private func parseRatio(_ s: String) -> RatioResult? {
    let parts = s.split(separator: "/")
    guard parts.count == 2, let p = Int(parts[0]), let q = Int(parts[1]) else { return nil }
    return RatioResult(num: p, den: q, octave: 0)
}
