//
//  LatticeView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import SwiftUI
import UIKit
#if targetEnvironment(macCatalyst)
import AppKit
#endif

#if targetEnvironment(macCatalyst)
private let USE_STOP_GRADIENTS = false
#else
private let USE_STOP_GRADIENTS = true
#endif


extension LatticeCamera {
    mutating func center(in size: CGSize, scale: CGFloat? = nil) {
        translation = CGPoint(x: size.width/2, y: size.height/2)
        if let s = scale { self.scale = max(12, min(240, s)) }
    }
}

// MARK: - Hex Grid Mode (shared with Settings)
enum LatticeGridMode: String, CaseIterable, Identifiable {
    case outlines     // hex outlines
    case cells        // filled hex cells (subtle)
    case triMesh      // triangular mesh
    case off          // no grid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .outlines: return "Outlines"
        case .cells:    return "Cells"
        case .triMesh:  return "Tri Mesh"
        case .off:      return "Off"
        }
    }
}


struct LatticeView: View {
    @AppStorage(SettingsKeys.latticeSoundEnabled)
    private var latticeSoundEnabled: Bool = true
    @State private var infoSwitchSeq: UInt64 = 0
    @inline(__always)
    private var latticeAudioAllowed: Bool { latticeSoundEnabled }

    
    init(
        previewGridMode: LatticeGridMode? = nil,
        previewConnectionMode: LatticeConnectionMode? = nil
    ) {
        self.previewGridMode = previewGridMode
        self.previewConnectionMode = previewConnectionMode
    }

    
    // PREVIEW overrides (used by Settings/WhatsNew previews; nil = use AppStorage)
    let previewGridMode: LatticeGridMode?
    let previewConnectionMode: LatticeConnectionMode?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    
        private var infoCardMaxWidth: CGFloat {
            hSizeClass == .compact ? 260 : 320
        }
    
        // Keep the translucent card from overlapping the 13–31 row (and stealing taps).
        private var infoCardTopPad: CGFloat {
            app.primeLimit >= 13 ? 104 : 72
        }
    
    
    @AppStorage(SettingsKeys.latticeConnectionMode)
    private var latticeConnectionModeRaw: String = LatticeConnectionMode.chain.rawValue

    private var latticeConnectionMode: LatticeConnectionMode {
        previewConnectionMode
        ?? (LatticeConnectionMode(rawValue: latticeConnectionModeRaw) ?? .chain)
    }

    @AppStorage(SettingsKeys.latticeHexGridMode)
    private var gridModeRaw: String = LatticeGridMode.outlines.rawValue

    @AppStorage(SettingsKeys.latticeHexGridStrength)
    private var gridStrengthRaw: Double = 0.16

    @AppStorage(SettingsKeys.latticeHexGridMajorEnabled)
    private var gridMajorEnabled: Bool = true

    @AppStorage(SettingsKeys.latticeHexGridMajorEvery)
    private var gridMajorEvery: Int = 2

    private var gridMode: LatticeGridMode {
        previewGridMode
        ?? (LatticeGridMode(rawValue: gridModeRaw) ?? .outlines)
    }

    private var gridStrength: CGFloat {
        max(0, min(1, CGFloat(gridStrengthRaw)))
    }

    private var gridMajorEveryClamped: Int {
        max(2, min(24, gridMajorEvery))
    }

    // Hold-to-toggle-all for overlay prime chips (7+)
    @State private var overlayPrimeHoldConsumedTap = false

    private var overlayChipPrimes: [Int] {
        PrimeConfig.primes.filter { $0 != 2 && $0 != 3 && $0 != 5 }
    }

    private func stopAllLatticeVoices(hard: Bool = true) {
        releaseInfoVoice(hard: hard)
        store.stopAllLatticeVoices(hard: hard)
    }

    private func toggleAllOverlayChipPrimes() {
        let primes = overlayChipPrimes
        guard !primes.isEmpty else { return }

        let allOn = primes.allSatisfy { store.visiblePrimes.contains($0) }
        let target = !allOn

        // Important: DO NOT batch with `animated: false` (that’s what caused the snap).
        // Also only touch primes that actually change, so we don’t spawn “off” animations from nothing.
        for p in primes {
            let isOn = store.visiblePrimes.contains(p)
            if isOn != target {
                store.setPrimeVisible(p, target, animated: true)
            }
        }
        LearnEventBus.shared.send(.latticePrimeChipHiToggle(target))

    }

    @Environment(\.latticePreviewMode) private var latticePreviewMode
    @Environment(\.latticePreviewHideChips) private var latticePreviewHideChips
    
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: LatticeStore   // shared from LatticeScreen
    @Environment(\.colorScheme) private var systemScheme
    
    private var effectiveIsDark: Bool {
        (themeStyleRaw == "dark") || (themeStyleRaw == "system" && systemScheme == .dark)
    }
    
    private var activeTheme: LatticeTheme {
        // tenneyThemeID can be "custom:<uuid>" — LatticeTheme only supports builtins.
        let raw = themeIDRaw
        let builtinRaw = raw.hasPrefix("custom:") ? LatticeThemeID.classicBO.rawValue : raw
        let id = LatticeThemeID(rawValue: builtinRaw) ?? .classicBO
        return ThemeRegistry.theme(id, dark: effectiveIsDark)
    }

    
    private struct TenneyDistanceNode {
        let screen: CGPoint
        let exps: [Int:Int]   // prime -> exponent (absolute, includes axisShift where appropriate)
    }
#if targetEnvironment(macCatalyst)
    private struct ContextTarget {
        let label: String
        let hz: Double
        let cents: Double
        let coord: LatticeCoord?
        let num: Int
        let den: Int
        let monzo: [Int:Int]
    }
#endif

    private func tenneyDistanceNodes() -> [TenneyDistanceNode] {
        // Use the unified, chronological selection order (plane + ghosts).
        let ordered = orderedSelectionKeysForPath()

        // Deduplicate in order (SelectionKey is Equatable but not necessarily Hashable)
        var keys: [LatticeStore.SelectionKey] = []
        for k in ordered {
            if !keys.contains(k) { keys.append(k) }
        }

        guard !keys.isEmpty else { return [] }

        // Helper: produce exponents + screen point for a single selection key.
        func node(for key: LatticeStore.SelectionKey) -> TenneyDistanceNode? {
            switch key {
            case .plane(let c):
                let e3 = c.e3 + store.pivot.e3 + (store.axisShift[3] ?? 0)
                let e5 = c.e5 + store.pivot.e5 + (store.axisShift[5] ?? 0)
                let world = layout.position(for: LatticeCoord(e3: e3, e5: e5))
                let screen = store.camera.worldToScreen(world)
                return TenneyDistanceNode(screen: screen, exps: [3: e3, 5: e5])

            case .ghost(let g):
                // Ghosts already store absolute exponents in hitTest; include the higher prime.
                let exps: [Int:Int] = [3: g.e3, 5: g.e5, g.p: g.eP]
                let world = layout.position(monzo: exps)
                let screen = store.camera.worldToScreen(world)
                return TenneyDistanceNode(screen: screen, exps: exps)
            }
        }
        guard keys.count == 2 else { return [] }

        guard let n0 = node(for: keys[0]), let n1 = node(for: keys[1]) else { return [] }
        return [n0, n1]
    }


    // MARK: - Overlay-node labels (7+ primes)

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

    private func overlayLabelText(num: Int, den: Int) -> String? {
        let (cp, cq) = canonicalPQ(num, den)

        if store.labelMode == .ratio {
            return "\(cp)/\(cq)"
        } else {
            return hejiTextLabel(p: cp, q: cq, octave: 0, rootHz: app.rootHz)
        }
    }

    private func shouldDrawOverlayLabel(ep: Int) -> Bool {
        guard labelDensity > 0.01 else { return false }

        let zoom = store.camera.appliedScale
        let zoomT = clamp01((zoom - 52) / 80)
        guard zoomT >= 0.15 else { return false }

        // keep labels close to the prime-axis origin to prevent clutter
        let baseR  = max(3, min(14, Int(zoom / 16)))
        let labelR = Int(CGFloat(baseR) * CGFloat(labelDensity))
        return abs(ep) <= labelR
    }

    
    @AppStorage(SettingsKeys.tenneyThemeID) private var themeIDRaw: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.latticeThemeStyle) private var themeStyleRaw: String = ThemeStyleChoice.system.rawValue
    
    @AppStorage(SettingsKeys.latticeAlwaysRecenterOnQuit)
        private var latticeAlwaysRecenterOnQuit: Bool = false
    
        @AppStorage(SettingsKeys.latticeRecenterPending)
        private var latticeRecenterPending: Bool = false
    
    @State private var viewSize: CGSize = .zero
    
    
    private let layout = LatticeLayout()
    @State private var infoOctaveOffset: Int = 0
    // LatticeView.swift (near other state vars)
    @State private var infoVoiceID: Int? = nil
    @State private var pausedForInfoCoord: LatticeCoord? = nil
    
    // LatticeView.swift
    
    @State private var selectionHapticTick: Int = 0
    @State private var focusHapticTick: Int = 0
    @State private var autoSelectInFlight: Bool = false
#if os(macOS) || targetEnvironment(macCatalyst)
    @State private var pointerInLattice: CGPoint? = nil
    @State private var lastPointerLog: Date? = nil
    @State private var isHoveringLattice: Bool = false
#endif
#if targetEnvironment(macCatalyst)
    @State private var isMousePanning: Bool = false
    @State private var contextTarget: ContextTarget? = nil
#endif

    private struct SelectionRimMetrics {
        let pad: CGFloat
        let outerWidth: CGFloat
        let bevelWidth: CGFloat
        let innerInset: CGFloat
    }

    private func selectionRimMetrics(zoom: CGFloat, focused: Bool) -> SelectionRimMetrics {
        // below mid zoom: present but not dominant
        // high zoom: slightly thinner relative
        let t = smoothstep(clamp01((zoom - 60) / 120))
        let baseOuter = lerp(2.4, 1.8, t)
        let baseBevel = lerp(1.4, 1.1, t)
        let pad = lerp(4.0, 2.5, t)

        let bump: CGFloat = focused ? 1.18 : 1.0
        return .init(
            pad: pad,
            outerWidth: baseOuter * bump,
            bevelWidth: baseBevel * bump,
            innerInset: lerp(2.0, 1.4, t)
        )
    }

    private func breathScale(now: Double, seed: UInt64) -> CGFloat {
        // ~6s shared breath, tiny phase offset
        let period = 6.2
        let u = Double(seed % 10_000) / 10_000.0
        let phase = u * 0.65  // small offset only
        let s = sin((now / period + phase) * 2 * .pi)
        let amp: Double = 0.015 // 1.5%
        return CGFloat(1.0 + amp * s)
    }

    private func breathAlpha(now: Double, seed: UInt64) -> CGFloat {
        let period = 6.2
        let u = Double((seed >> 12) % 10_000) / 10_000.0
        let phase = u * 0.65
        let s = sin((now / period + phase) * 2 * .pi)
        let amp: Double = 0.05 // subtle opacity modulation
        return CGFloat(1.0 + amp * s)
    }

    private func selectionTint(for key: LatticeStore.SelectionKey, pivot: LatticeCoord, shift: [Int:Int]) -> Color {
        switch key {
        case .plane(let c):
            let e3 = c.e3 + pivot.e3 + (shift[3] ?? 0)
            let e5 = c.e5 + pivot.e5 + (shift[5] ?? 0)
            return activeTheme.nodeColor(e3: e3, e5: e5)
        case .ghost(let g):
            return overlayColor(forPrime: g.p)
        }
    }

    private func selectionScreenPoint(for key: LatticeStore.SelectionKey, pivot: LatticeCoord, shift: [Int:Int], camera: LatticeCamera) -> CGPoint {
        switch key {
        case .plane(let c):
            let e3 = c.e3 + pivot.e3 + (shift[3] ?? 0)
            let e5 = c.e5 + pivot.e5 + (shift[5] ?? 0)
            let wp = layout.position(for: LatticeCoord(e3: e3, e5: e5))
            return camera.worldToScreen(wp)
        case .ghost(let g):
            let wp = layout.position(monzo: [3: g.e3, 5: g.e5, g.p: g.eP])
            return camera.worldToScreen(wp)
        }
    }

    /// Matches your node sizing logic enough to make the rim hug the node.
    private func selectionNodeRadius(for key: LatticeStore.SelectionKey, pivot: LatticeCoord, shift: [Int:Int]) -> CGFloat {
        let base = nodeBaseSize()

        func lift(tenney: Int) -> CGFloat {
            let t = max(1, tenney)
            return CGFloat(18.0 * (1.0 / sqrt(Double(t))))
        }

        switch key {
        case .plane(let c):
            // meaning uses axisShift; geometry uses pivot+shift (as you already do elsewhere)
            let e3m = (c.e3 + (shift[3] ?? 0))
            let e5m = (c.e5 + (shift[5] ?? 0))
            let (p, q) = planePQ(e3: e3m, e5: e5m) ?? (1,1)
            let tenney = max(p, q)
            let sz = max(8, base + lift(tenney: tenney))
            return sz * 0.5
        case .ghost(let g):
            let (p, q) = overlayPQ(e3: g.e3, e5: g.e5, prime: g.p, eP: g.eP) ?? (1,1)
            let tenney = max(p, q)
            let sz = max(8, base + lift(tenney: tenney))
            return sz * 0.5
        }
    }

    private func primeExponentMap(num: Int, den: Int, primes: [Int]) -> [Int:Int] {
        func factor(_ n: Int, primes: [Int]) -> [Int:Int] {
            var x = abs(n)
            var out: [Int:Int] = [:]
            for p in primes where p >= 2 {
                if x < p*p { break }
                while x % p == 0 { out[p, default: 0] += 1; x /= p }
            }
            if x > 1 { out[x, default: 0] += 1 } // remainder prime
            return out
        }

        let ps = primes
        let fn = factor(num, primes: ps)
        let fd = factor(den, primes: ps)

        var out: [Int:Int] = [:]
        for p in Set(fn.keys).union(fd.keys) {
            let e = (fn[p] ?? 0) - (fd[p] ?? 0)
            if e != 0 { out[p] = e }
        }
        return out
    }

    private func drawSelectionRim(
        ctx: inout GraphicsContext,
        center: CGPoint,
        nodeR: CGFloat,
        tint: Color,
        focused: Bool,
        phase: (targetOn: Bool, t: CGFloat, duration: Double, seed: UInt64)?,
        now: Double,
        zoom: CGFloat,
        scheme: ColorScheme,
        primeTicks: [(prime: Int, exp: Int)] = []
    ) {
        let m = selectionRimMetrics(zoom: zoom, focused: focused)

        // OFF anims still draw while phase exists
        let targetOn = phase?.targetOn ?? true
        let t = phase?.t ?? 1.0
        let seed = phase?.seed ?? 0

        // tasteful “shock” on toggle
        let shockT: CGFloat = targetOn ? smoothstep(t) : smoothstep(1 - t)
            // ✅ kill “breathing” (this was the jitter)
            let bS: CGFloat = 1.0
            let bA: CGFloat = 1.0
        
            // ✅ uniform ring color (use scheme for contrast)
            let ringColor: Color = (scheme == .dark ? .white : .black)

        // rim radius
        let rimR = (nodeR + m.pad) * bS
        let rect = CGRect(x: center.x - rimR, y: center.y - rimR, width: rimR * 2, height: rimR * 2)
        let circle = Circle().path(in: rect)

        // shock wash (radial pressure wave), clipped inside rim
        if phase != nil {
            var g = ctx
            g.clip(to: circle)

            let washEnd = rimR * (0.25 + 0.85 * shockT)
            let wash = USE_STOP_GRADIENTS
            ? Gradient(stops: [
                .init(color: tint.opacity(0.00), location: 0.00),
                .init(color: tint.opacity(0.22 * bA), location: 0.18),
                .init(color: tint.opacity(0.00), location: 0.55),
            ])
            : Gradient(colors: [
                tint.opacity(0.00),
                tint.opacity(0.22 * bA),
                tint.opacity(0.00),
            ])

            g.fill(circle, with: .radialGradient(
                wash,
                center: center,
                startRadius: 0,
                endRadius: washEnd
            ))
        }

        // ✅ draw-on reveal (trim) when animating
            let reveal: CGFloat = {
                guard phase != nil else { return 1.0 }
                let tt = smoothstep(t)
                return targetOn ? tt : (1.0 - tt)
            }()

            // rotate so trim “starts” at 12 o’clock
            let rot: CGFloat = -.pi / 2
            var xf = CGAffineTransform(translationX: center.x, y: center.y)
            xf = xf.rotated(by: rot)
            xf = xf.translatedBy(x: -center.x, y: -center.y)

            let basePath = circle.applying(xf)
            let rimPath  = (phase != nil) ? basePath.trimmedPath(from: 0, to: reveal) : basePath

            // base rim (uniform color)
            ctx.stroke(rimPath, with: .color(ringColor.opacity(0.85 * bA)), lineWidth: m.outerWidth)

            // bevel (still neutral, not tint-colored)
            let bevelLight: Color = .white.opacity((scheme == .dark ? 0.16 : 0.12) * bA)
            let bevelDark:  Color = .black.opacity((scheme == .dark ? 0.10 : 0.18) * bA)

            let inner1 = Circle().path(in: rect.insetBy(dx: m.innerInset, dy: m.innerInset)).applying(xf)
            let inner2 = Circle().path(in: rect.insetBy(dx: m.innerInset + 0.8, dy: m.innerInset + 0.8)).applying(xf)
            let inner1Path = (phase != nil) ? inner1.trimmedPath(from: 0, to: reveal) : inner1
            let inner2Path = (phase != nil) ? inner2.trimmedPath(from: 0, to: reveal) : inner2

            ctx.stroke(inner1Path, with: .color(bevelLight), lineWidth: m.bevelWidth)
            ctx.stroke(inner2Path, with: .color(bevelDark),  lineWidth: max(0.8, m.bevelWidth * 0.75))

        // focused hierarchy: secondary inner reticle
        if focused {
            ctx.stroke(Circle().path(in: rect.insetBy(dx: m.innerInset + 3.2, dy: m.innerInset + 3.2)),
                       with: .color(tint.opacity(0.25 * bA)),
                       lineWidth: 1.0)
        }

        // focused prime ticks (subtle, capped)
        if focused, !primeTicks.isEmpty {
            let maxTicks = 6
            let chosen = Array(primeTicks.prefix(maxTicks))
            let n = max(1, chosen.count)

            for (i, item) in chosen.enumerated() {
                let p = item.prime
                let exp = item.exp
                let mag = min(3, max(1, abs(exp)))

                let angle = (Double(i) / Double(n)) * 2 * .pi - (.pi / 2)
                let ux = CGFloat(cos(angle))
                let uy = CGFloat(sin(angle))

                let inner = rimR - 2.2
                let lenBase: CGFloat = 4.0
                let len = lenBase + CGFloat(mag - 1) * 2.2

                let a = CGPoint(x: center.x + ux * inner, y: center.y + uy * inner)
                let b = CGPoint(x: center.x + ux * (inner + len), y: center.y + uy * (inner + len))

                var tick = Path()
                tick.move(to: a)
                tick.addLine(to: b)

                let c = activeTheme.primeTint(p).opacity(0.70)
                ctx.stroke(tick, with: .color(c), lineWidth: 1.2)

                // “double tick” for magnitude >= 2 (still subtle)
                if mag >= 2 {
                    let off: CGFloat = 2.0
                    let a2 = CGPoint(x: a.x + -uy * off, y: a.y + ux * off)
                    let b2 = CGPoint(x: b.x + -uy * off, y: b.y + ux * off)
                    var tick2 = Path()
                    tick2.move(to: a2)
                    tick2.addLine(to: b2)
                    ctx.stroke(tick2, with: .color(c.opacity(0.75)), lineWidth: 1.0)
                }
            }
        }
    }

    private func orderedSelectionKeysForPath() -> [LatticeStore.SelectionKey] {
        // ✅ single, global, chronological order (plane + ghosts)
        if !store.selectionOrderKeys.isEmpty { return store.selectionOrderKeys }

        // Fallback (only if you haven’t wired the store yet)
        var out: [LatticeStore.SelectionKey] = []
        out.reserveCapacity(store.selectionOrder.count + store.selectionOrderGhosts.count)
        out += store.selectionOrder.map { .plane($0) }
        out += store.selectionOrderGhosts.map { .ghost($0) }
        return out
    }

    private func gridNeighborDeltas(for gridMode: LatticeGridMode) -> [LatticeCoord] {
        switch gridMode {
        case .off:
            return []

        case .outlines, .triMesh:
            // Axial-hex neighbors in (e3,e5):
            // order is the deterministic tie-breaker for BFS.
            return [
                .init(e3: +1, e5:  0),
                .init(e3:  0, e5: +1),
                .init(e3: +1, e5: -1),
                .init(e3: -1, e5:  0),
                .init(e3:  0, e5: -1),
                .init(e3: -1, e5: +1),
            ]

        @unknown default:
            return [
                .init(e3: +1, e5:  0),
                .init(e3:  0, e5: +1),
                .init(e3: +1, e5: -1),
                .init(e3: -1, e5:  0),
                .init(e3:  0, e5: -1),
                .init(e3: -1, e5: +1),
            ]
        }
    }

    private func isDrawablePlaneCoord(_ c: LatticeCoord, radius: Int) -> Bool {
        // Deterministic, stable, and matches the lattice plane sampling domain.
        abs(c.e3) <= radius && abs(c.e5) <= radius
    }

    private func hexDistance(_ a: LatticeCoord, _ b: LatticeCoord) -> Int {
        // axial (q,r) => cube (x,z), y = -x-z
        let ax = a.e3, az = a.e5
        let bx = b.e3, bz = b.e5
        let dx = bx - ax
        let dz = bz - az
        let dy = (-bx - bz) - (-ax - az)
        return max(abs(dx), max(abs(dy), abs(dz)))
    }

    private func cubeRound(x: Double, y: Double, z: Double) -> (Int, Int, Int) {
        var rx = Int(x.rounded())
        var ry = Int(y.rounded())
        var rz = Int(z.rounded())

        let dx = abs(Double(rx) - x)
        let dy = abs(Double(ry) - y)
        let dz = abs(Double(rz) - z)

        if dx > dy && dx > dz {
            rx = -ry - rz
        } else if dy > dz {
            ry = -rx - rz
        } else {
            rz = -rx - ry
        }
        return (rx, ry, rz)
    }

    private func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func posMod(_ a: Int, _ m: Int) -> Int {
        let r = a % m
        return r < 0 ? r + m : r
    }

    /// “Major line” on any of the 3 axial families (e3, e5, s=-e3-e5).
    private func isOnMajorLine(_ c: LatticeCoord, every: Int) -> Bool {
        guard every >= 2 else { return false }
        let q = c.e3
        let r = c.e5
        let s = -q - r
        return posMod(q, every) == 0 || posMod(r, every) == 0 || posMod(s, every) == 0
    }

    /// A* over axial-hex neighbor edges, biased toward major lines.
    /// Falls back to your existing `shortestGridPath` if search bails out.
    private func routedGridPath(
        from start: LatticeCoord,
        to goal: LatticeCoord,
        gridMode: LatticeGridMode,
        majorEnabled: Bool,
        majorEvery: Int
    ) -> [LatticeCoord]? {
        guard gridMode != .off else { return nil }
        if start == goal { return [start] }

        let deltas = gridNeighborDeltas(for: gridMode)
        guard !deltas.isEmpty else { return nil }

        let n = hexDistance(start, goal)
        let maxSteps = 320
        guard n <= maxSteps else { return nil }

        // Keep the search local (prevents wandering).
        let pad = max(8, (majorEnabled ? (majorEvery * 5) : 10))
        let minE3 = min(start.e3, goal.e3) - pad
        let maxE3 = max(start.e3, goal.e3) + pad
        let minE5 = min(start.e5, goal.e5) - pad
        let maxE5 = max(start.e5, goal.e5) + pad

        @inline(__always)
        func inBounds(_ c: LatticeCoord) -> Bool {
            c.e3 >= minE3 && c.e3 <= maxE3 && c.e5 >= minE5 && c.e5 <= maxE5
        }

        @inline(__always)
        func stepCost(_ a: LatticeCoord, _ b: LatticeCoord) -> Double {
            // Base edge cost
            var cost = 1.0

            // Bias toward “major roads”
            if majorEnabled, majorEvery >= 2 {
                let aMaj = isOnMajorLine(a, every: majorEvery)
                let bMaj = isOnMajorLine(b, every: majorEvery)
                if aMaj && bMaj { cost *= 0.55 }      // strongly prefer staying on major lines
                else if aMaj || bMaj { cost *= 0.82 } // mild preference to enter/exit majors
            }
            return cost
        }

        // A* state
        var open: [LatticeCoord] = [start]
        var openSet: Set<LatticeCoord> = [start]
        var cameFrom: [LatticeCoord: LatticeCoord] = [:]
        var gScore: [LatticeCoord: Double] = [start: 0.0]
        var fScore: [LatticeCoord: Double] = [start: Double(n)]

        let maxExplored = 6500
        var explored = 0

        while !open.isEmpty {
            // Pop min-f (linear scan is fine at this scale)
            var bestIdx = 0
            var bestF = fScore[open[0]] ?? .infinity
            if open.count > 1 {
                for i in 1..<open.count {
                    let fi = fScore[open[i]] ?? .infinity
                    if fi < bestF {
                        bestF = fi
                        bestIdx = i
                    }
                }
            }

            let current = open.remove(at: bestIdx)
            openSet.remove(current)

            if current == goal {
                // Reconstruct
                var path: [LatticeCoord] = [goal]
                var cur = goal
                var guardN = 0
                while cur != start {
                    guard let prev = cameFrom[cur] else { break }
                    path.append(prev)
                    cur = prev
                    guardN += 1
                    if guardN > maxExplored { break }
                }
                return path.reversed()
            }

            explored += 1
            if explored > maxExplored { break }

            let gCur = gScore[current] ?? .infinity

            for d in deltas {
                let next = LatticeCoord(e3: current.e3 + d.e3, e5: current.e5 + d.e5)
                guard inBounds(next) else { continue }

                let tentative = gCur + stepCost(current, next)
                if tentative < (gScore[next] ?? .infinity) {
                    cameFrom[next] = current
                    gScore[next] = tentative

                    // heuristic = hex distance; tiny multiplier as tie-breaker
                    let h = Double(hexDistance(next, goal)) * 1.02
                    fScore[next] = tentative + h

                    if !openSet.contains(next) {
                        open.append(next)
                        openSet.insert(next)
                    }
                }
            }
        }

        // Fallback to your existing “hex line” if A* bails (keeps behavior robust).
        return shortestGridPath(from: start, to: goal, gridMode: gridMode, radius: 0)
    }

    private func shortestGridPath(
        from start: LatticeCoord,
        to goal: LatticeCoord,
        gridMode: LatticeGridMode,
        radius: Int // kept for call-site compatibility; no longer used
    ) -> [LatticeCoord]? {
        guard gridMode != .off else { return nil }
        if start == goal { return [start] }

        let n = hexDistance(start, goal)

        // Safety cap (prevents pathological “draw 5000 segments” when someone connects very distant nodes)
        let maxSteps = 320
        if n > maxSteps { return nil }

        let ax = Double(start.e3), az = Double(start.e5)
        let bx = Double(goal.e3),  bz = Double(goal.e5)

        // cube coords: (x, y, z) with y = -x-z
        let ay = -ax - az
        let by = -bx - bz

        var out: [LatticeCoord] = []
        out.reserveCapacity(n + 1)

        for i in 0...n {
            let t = Double(i) / Double(n)
            let x = lerpD(ax, bx, t)
            let y = lerpD(ay, by, t)
            let z = lerpD(az, bz, t)

            let (rx, _, rz) = cubeRound(x: x, y: y, z: z)
            out.append(.init(e3: rx, e5: rz))
        }

        // de-dupe consecutive duplicates (rounding can repeat)
        var dedup: [LatticeCoord] = []
        dedup.reserveCapacity(out.count)
        for c in out {
            if dedup.last != c { dedup.append(c) }
        }

        // guarantee endpoints
        if dedup.first != start { dedup.insert(start, at: 0) }
        if dedup.last  != goal  { dedup.append(goal) }

        return dedup
    }

    // MARK: - GridPath routing (map-like): snap to visible grid ink, prefer MINOR, avoid zig-zag

    private struct Corner3: Hashable { let i3: Int; let j3: Int }

    private struct CornerEdgeSnap {
        let a: Corner3
        let b: Corner3
        let t: CGFloat           // 0..1 along a->b (distance fraction of a->point)
        let pointWorld: CGPoint
    }

    private struct MeshEdgeSnap {
        let a: LatticeCoord
        let b: LatticeCoord
        let t: CGFloat           // 0..1 along a->b
        let pointWorld: CGPoint
    }

    @inline(__always) private func pAdd(_ a: CGPoint, _ b: CGPoint) -> CGPoint { .init(x: a.x + b.x, y: a.y + b.y) }
    @inline(__always) private func pSub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { .init(x: a.x - b.x, y: a.y - b.y) }
    @inline(__always) private func pMul(_ a: CGPoint, _ s: CGFloat) -> CGPoint { .init(x: a.x * s, y: a.y * s) }

    private func closestPointOnSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (t: CGFloat, q: CGPoint) {
        let ab = pSub(b, a)
        let ap = pSub(p, a)
        let ab2 = ab.x*ab.x + ab.y*ab.y
        if ab2 <= 1e-9 { return (0, a) }
        var t = (ap.x*ab.x + ap.y*ab.y) / ab2
        t = max(0, min(1, t))
        return (t, pAdd(a, pMul(ab, t)))
    }

    private func nearestSuperCenterRel(for c: LatticeCoord, step: Int) -> LatticeCoord {
        // cube round on (e3,e5) scaled by step
        let x = Double(c.e3) / Double(step)
        let z = Double(c.e5) / Double(step)
        let y = -x - z
        let (rx, _, rz) = cubeRound(x: x, y: y, z: z)
        return .init(e3: rx * step, e5: rz * step)
    }

    private func isMajorCorner(_ c: Corner3, step: Int, majorEvery: Int, majorEnabled: Bool) -> Bool {
        guard majorEnabled else { return false }
        let m = max(2, majorEvery) * max(1, step)
        return posMod(c.i3, m) == 0 && posMod(c.j3, m) == 0
    }

    private func isMajorMeshVertex(_ c: LatticeCoord, step: Int, majorEvery: Int, majorEnabled: Bool) -> Bool {
        guard majorEnabled else { return false }
        let m = max(2, majorEvery) * max(1, step)
        return posMod(c.e3, m) == 0 && posMod(c.e5, m) == 0
    }

    private func snapToVisibleHexEdge(
        pointWorld: CGPoint,
        nearRel: LatticeCoord,
        pivot: LatticeCoord,
        step: Int
    ) -> CornerEdgeSnap? {
        let (u0, v0) = gridBasisUV()
        let u = pMul(u0, CGFloat(step))
        let v = pMul(v0, CGFloat(step))

        // same corner offsets you use in hexPath(): a,b,c,-a,-b,-c
        let offs3: [(Int,Int)] = [(1,1),(2,-1),(1,-2),(-1,-1),(-2,1),(-1,2)]

        // local neighborhood of super-centers
        let base = nearestSuperCenterRel(for: nearRel, step: step)
        let nbr: [LatticeCoord] = [
            .init(e3: 0, e5: 0),
            .init(e3: +step, e5: 0),
            .init(e3: 0, e5: +step),
            .init(e3: +step, e5: -step),
            .init(e3: -step, e5: 0),
            .init(e3: 0, e5: -step),
            .init(e3: -step, e5: +step),
        ]

        var best: (d2: CGFloat, snap: CornerEdgeSnap)? = nil

        for d in nbr {
            let cRel = LatticeCoord(e3: base.e3 + d.e3, e5: base.e5 + d.e5)
            let cAbs = LatticeCoord(e3: pivot.e3 + cRel.e3, e5: pivot.e5 + cRel.e5)

            let centerW = layout.position(for: cAbs)

            // world corner vectors for this visible step
            let a = pMul(pAdd(u, v), 1.0/3.0)
            let b = pMul(pSub(pMul(u, 2), v), 1.0/3.0)
            let c = pMul(pSub(u, pMul(v, 2)), 1.0/3.0)

            let cornersW: [CGPoint] = [
                pAdd(centerW, a),
                pAdd(centerW, b),
                pAdd(centerW, c),
                pSub(centerW, a),
                pSub(centerW, b),
                pSub(centerW, c),
            ]

            // matching CORNER integer coords in “thirds” relative-to-pivot
            let baseI3 = 3 * cRel.e3
            let baseJ3 = 3 * cRel.e5
            let corners3: [Corner3] = offs3.map { (dx, dy) in
                .init(i3: baseI3 + step * dx, j3: baseJ3 + step * dy)
            }

            for i in 0..<6 {
                let j = (i + 1) % 6
                let A = cornersW[i]
                let B = cornersW[j]
                let (t, q) = closestPointOnSegment(pointWorld, A, B)
                let d2 = (q.x - pointWorld.x)*(q.x - pointWorld.x) + (q.y - pointWorld.y)*(q.y - pointWorld.y)

                if best == nil || d2 < best!.d2 {
                    best = (d2, .init(a: corners3[i], b: corners3[j], t: t, pointWorld: q))
                }
            }
        }

        return best?.snap
    }

    private func snapToVisibleTriMeshEdge(
        pointWorld: CGPoint,
        nearRel: LatticeCoord,
        pivot: LatticeCoord,
        step: Int
    ) -> MeshEdgeSnap? {
        let base = nearestSuperCenterRel(for: nearRel, step: step)

        // candidate mesh vertices around base
        let nbr: [LatticeCoord] = [
            .init(e3: 0, e5: 0),
            .init(e3: +step, e5: 0),
            .init(e3: 0, e5: +step),
            .init(e3: +step, e5: -step),
            .init(e3: -step, e5: 0),
            .init(e3: 0, e5: -step),
            .init(e3: -step, e5: +step),
        ]

        // the 3 “forward” edges that define triMesh (u, v, v-u), scaled by step
        let fwd: [LatticeCoord] = [
            .init(e3: +step, e5: 0),
            .init(e3: 0, e5: +step),
            .init(e3: -step, e5: +step),
        ]

        var best: (d2: CGFloat, snap: MeshEdgeSnap)? = nil

        for d in nbr {
            let aRel = LatticeCoord(e3: base.e3 + d.e3, e5: base.e5 + d.e5)
            let aAbs = LatticeCoord(e3: pivot.e3 + aRel.e3, e5: pivot.e5 + aRel.e5)
            let A = layout.position(for: aAbs)

            for e in fwd {
                let bRel = LatticeCoord(e3: aRel.e3 + e.e3, e5: aRel.e5 + e.e5)
                let bAbs = LatticeCoord(e3: pivot.e3 + bRel.e3, e5: pivot.e5 + bRel.e5)
                let B = layout.position(for: bAbs)

                let (t, q) = closestPointOnSegment(pointWorld, A, B)
                let d2 = (q.x - pointWorld.x)*(q.x - pointWorld.x) + (q.y - pointWorld.y)*(q.y - pointWorld.y)

                if best == nil || d2 < best!.d2 {
                    best = (d2, .init(a: aRel, b: bRel, t: t, pointWorld: q))
                }
            }
        }

        return best?.snap
    }

    private func aStarCorners(
        start: Corner3,
        goals: Set<Corner3>,
        step: Int,
        majorEnabled: Bool,
        majorEvery: Int,
        turnPenalty: Double
    ) -> (path: [Corner3], cost: Double, end: Corner3)? {
        if goals.contains(start) { return ([start], 0.0, start) }

        // 6 neighbor deltas around a hex-edge vertex (in “thirds”), scaled by step
        let base: [(Int,Int)] = [(1,-2),(-1,-1),(-2,1),(-1,2),(1,1),(2,-1)]
        let deltas: [Corner3] = base.map { .init(i3: $0.0 * step, j3: $0.1 * step) }

        let (u0, v0) = gridBasisUV()
        let edgeVec = pAdd(pMul(u0, CGFloat(deltas[0].i3) / 3.0), pMul(v0, CGFloat(deltas[0].j3) / 3.0))
        let edgeLen = Double(hypot(edgeVec.x, edgeVec.y))

        @inline(__always) func worldDist(_ a: Corner3, _ b: Corner3) -> Double {
            let di3 = CGFloat(b.i3 - a.i3) / 3.0
            let dj3 = CGFloat(b.j3 - a.j3) / 3.0
            let dW = pAdd(pMul(u0, di3), pMul(v0, dj3))
            return Double(hypot(dW.x, dW.y))
        }
        
        // bound search (distance-proportional pad; prevents wandering)
                let minGoalI = goals.map(\.i3).min() ?? start.i3
                let maxGoalI = goals.map(\.i3).max() ?? start.i3
                let minGoalJ = goals.map(\.j3).min() ?? start.j3
                let maxGoalJ = goals.map(\.j3).max() ?? start.j3
        
                let h0 = goals.map { worldDist(start, $0) / max(1e-6, edgeLen) }.min() ?? 0
                let padSteps = max(18, min(140, Int(ceil(h0 * 1.35)) + 18))
                let pad = step * padSteps
        
                let minI = min(start.i3, minGoalI) - pad
                let maxI = max(start.i3, maxGoalI) + pad
                let minJ = min(start.j3, minGoalJ) - pad
                let maxJ = max(start.j3, maxGoalJ) + pad
        
                @inline(__always) func inBounds(_ c: Corner3) -> Bool {
                    c.i3 >= minI && c.i3 <= maxI && c.j3 >= minJ && c.j3 <= maxJ
                }

        @inline(__always) func heuristic(_ c: Corner3) -> Double {
            var best = Double.infinity
            for g in goals {
                best = min(best, worldDist(c, g) / max(1e-6, edgeLen))
            }
            return best
        }

        struct State: Hashable { let c: Corner3; let dir: Int } // dir = last move index, -1 for start
        let startS = State(c: start, dir: -1)

        var open: [State] = [startS]
        var openSet: Set<State> = [startS]
        var cameFrom: [State: State] = [:]
        var gScore: [State: Double] = [startS: 0.0]
        var fScore: [State: Double] = [startS: heuristic(start)]

        let maxExplored = 9000
        var explored = 0

        while !open.isEmpty {
            var bestIdx = 0
            var bestF = fScore[open[0]] ?? .infinity
            if open.count > 1 {
                for i in 1..<open.count {
                    let fi = fScore[open[i]] ?? .infinity
                    if fi < bestF { bestF = fi; bestIdx = i }
                }
            }

            let cur = open.remove(at: bestIdx)
            openSet.remove(cur)

            if goals.contains(cur.c) {
                // reconstruct
                var states: [State] = [cur]
                var s = cur
                var guardN = 0
                while let prev = cameFrom[s] {
                    states.append(prev)
                    s = prev
                    guardN += 1
                    if guardN > maxExplored { break }
                }
                states.reverse()
                let path = states.map(\.c)
                let cost = gScore[cur] ?? .infinity
                return (path, cost, cur.c)
            }

            explored += 1
            if explored > maxExplored { break }

            let gCur = gScore[cur] ?? .infinity

            for (idx, d) in deltas.enumerated() {
                let nxtC = Corner3(i3: cur.c.i3 + d.i3, j3: cur.c.j3 + d.j3)
                if !inBounds(nxtC) { continue }

                let nxt = State(c: nxtC, dir: idx)

                var stepCost = 1.0

                // “map-like”: penalize turns to avoid zig-zag
                if cur.dir >= 0 && cur.dir != idx { stepCost += turnPenalty }

                let tentative = gCur + stepCost
                if tentative < (gScore[nxt] ?? .infinity) {
                    cameFrom[nxt] = cur
                    gScore[nxt] = tentative
                    fScore[nxt] = tentative + heuristic(nxtC)
                    if !openSet.contains(nxt) {
                        open.append(nxt)
                        openSet.insert(nxt)
                    }
                }
            }
        }

        return nil
    }

    private func aStarTriMesh(
        start: LatticeCoord,
        goals: Set<LatticeCoord>,
        step: Int,
        majorEnabled: Bool,
        majorEvery: Int,
        turnPenalty: Double
    ) -> (path: [LatticeCoord], cost: Double, end: LatticeCoord)? {
        if goals.contains(start) { return ([start], 0.0, start) }

        // 6 axial neighbor deltas scaled by visible grid step
        let base = gridNeighborDeltas(for: .outlines)
        let deltas: [LatticeCoord] = base.map { .init(e3: $0.e3 * step, e5: $0.e5 * step) }

        let minE3 = min(start.e3, goals.map(\.e3).min() ?? start.e3) - step * 60
        let maxE3 = max(start.e3, goals.map(\.e3).max() ?? start.e3) + step * 60
        let minE5 = min(start.e5, goals.map(\.e5).min() ?? start.e5) - step * 60
        let maxE5 = max(start.e5, goals.map(\.e5).max() ?? start.e5) + step * 60

        @inline(__always) func inBounds(_ c: LatticeCoord) -> Bool {
            c.e3 >= minE3 && c.e3 <= maxE3 && c.e5 >= minE5 && c.e5 <= maxE5
        }

        let (u0, v0) = gridBasisUV()
        let edgeVec = pAdd(pMul(u0, CGFloat(deltas[0].e3)), pMul(v0, CGFloat(deltas[0].e5)))
        let edgeLen = Double(hypot(edgeVec.x, edgeVec.y))

        @inline(__always) func worldDist(_ a: LatticeCoord, _ b: LatticeCoord) -> Double {
            let dW = pAdd(pMul(u0, CGFloat(b.e3 - a.e3)), pMul(v0, CGFloat(b.e5 - a.e5)))
            return Double(hypot(dW.x, dW.y))
        }

        @inline(__always) func heuristic(_ c: LatticeCoord) -> Double {
            var best = Double.infinity
            for g in goals { best = min(best, worldDist(c, g) / max(1e-6, edgeLen)) }
            return best
        }

        struct State: Hashable { let c: LatticeCoord; let dir: Int }
        let startS = State(c: start, dir: -1)

        var open: [State] = [startS]
        var openSet: Set<State> = [startS]
        var cameFrom: [State: State] = [:]
        var gScore: [State: Double] = [startS: 0.0]
        var fScore: [State: Double] = [startS: heuristic(start)]

        let maxExplored = 9000
        var explored = 0

        while !open.isEmpty {
            var bestIdx = 0
            var bestF = fScore[open[0]] ?? .infinity
            if open.count > 1 {
                for i in 1..<open.count {
                    let fi = fScore[open[i]] ?? .infinity
                    if fi < bestF { bestF = fi; bestIdx = i }
                }
            }

            let cur = open.remove(at: bestIdx)
            openSet.remove(cur)

            if goals.contains(cur.c) {
                var states: [State] = [cur]
                var s = cur
                var guardN = 0
                while let prev = cameFrom[s] {
                    states.append(prev)
                    s = prev
                    guardN += 1
                    if guardN > maxExplored { break }
                }
                states.reverse()
                let path = states.map(\.c)
                let cost = gScore[cur] ?? .infinity
                return (path, cost, cur.c)
            }

            explored += 1
            if explored > maxExplored { break }

            let gCur = gScore[cur] ?? .infinity

            for (idx, d) in deltas.enumerated() {
                let nxtC = LatticeCoord(e3: cur.c.e3 + d.e3, e5: cur.c.e5 + d.e5)
                if !inBounds(nxtC) { continue }

                let nxt = State(c: nxtC, dir: idx)

                var stepCost = 1.0
                if cur.dir >= 0 && cur.dir != idx { stepCost += turnPenalty }

                let tentative = gCur + stepCost
                if tentative < (gScore[nxt] ?? .infinity) {
                    cameFrom[nxt] = cur
                    gScore[nxt] = tentative
                    fScore[nxt] = tentative + heuristic(nxtC)
                    if !openSet.contains(nxt) {
                        open.append(nxt)
                        openSet.insert(nxt)
                    }
                }
            }
        }

        return nil
    }

    private func routedGridPolylineScreen(
        from aRel: LatticeCoord,
        to bRel: LatticeCoord,
        gridMode: LatticeGridMode,
        pivot: LatticeCoord,
        shift: [Int:Int],
        camera: LatticeCamera,
        zoom: CGFloat,
        majorEnabled: Bool,
        majorEvery: Int
    ) -> [CGPoint]? {
        guard gridMode != .off else { return nil }
        guard zoom >= gridMinZoom else { return nil } // no visible grid to follow

        let step = gridStride(for: zoom)
        let turnPenalty = 0.42

        // Node world positions (include axisShift like your node geometry does)
        let aAbs = LatticeCoord(
            e3: pivot.e3 + aRel.e3 + (shift[3] ?? 0),
            e5: pivot.e5 + aRel.e5 + (shift[5] ?? 0)
        )
        let bAbs = LatticeCoord(
            e3: pivot.e3 + bRel.e3 + (shift[3] ?? 0),
            e5: pivot.e5 + bRel.e5 + (shift[5] ?? 0)
        )

        let aWorld = layout.position(for: aAbs)
        let bWorld = layout.position(for: bAbs)
        let aScreen = camera.worldToScreen(aWorld)
        let bScreen = camera.worldToScreen(bWorld)

        switch gridMode {
        case .triMesh:
            guard
                let entry = snapToVisibleTriMeshEdge(pointWorld: aWorld, nearRel: aRel, pivot: pivot, step: step),
                let exit  = snapToVisibleTriMeshEdge(pointWorld: bWorld, nearRel: bRel, pivot: pivot, step: step)
            else { return nil }

            let entryG0_A = Double(entry.t)
            let entryG0_B = Double(1.0 - entry.t)

            let goals: Set<LatticeCoord> = [exit.a, exit.b]

            // try both possible start vertices on the entry edge
            var best: (pts: [CGPoint], cost: Double)? = nil

            for (sV, g0) in [(entry.a, entryG0_A), (entry.b, entryG0_B)] {
                guard let r = aStarTriMesh(
                    start: sV,
                    goals: goals,
                    step: step,
                    majorEnabled: majorEnabled,
                    majorEvery: majorEvery,
                    turnPenalty: turnPenalty
                ) else { continue }

                let end = r.end
                let exitCost: Double = (end == exit.a) ? Double(exit.t) : Double(1.0 - exit.t)
                let total = g0 + r.cost + exitCost

                // build screen polyline
                var pts: [CGPoint] = []
                pts.reserveCapacity(r.path.count + 4)

                pts.append(aScreen)
                pts.append(camera.worldToScreen(entry.pointWorld))

                for v in r.path {
                    let vAbs = LatticeCoord(e3: pivot.e3 + v.e3, e5: pivot.e5 + v.e5)
                    pts.append(camera.worldToScreen(layout.position(for: vAbs)))
                }

                pts.append(camera.worldToScreen(exit.pointWorld))
                pts.append(bScreen)

                if best == nil || total < best!.cost { best = (pts, total) }
            }

            return best?.pts

        case .outlines, .cells:
            guard
                let entry = snapToVisibleHexEdge(pointWorld: aWorld, nearRel: aRel, pivot: pivot, step: step),
                let exit  = snapToVisibleHexEdge(pointWorld: bWorld, nearRel: bRel, pivot: pivot, step: step)
            else { return nil }

            let entryG0_A = Double(entry.t)
            let entryG0_B = Double(1.0 - entry.t)

            let goals: Set<Corner3> = [exit.a, exit.b]

            var best: (pts: [CGPoint], cost: Double)? = nil

            for (sC, g0) in [(entry.a, entryG0_A), (entry.b, entryG0_B)] {
                guard let r = aStarCorners(
                    start: sC,
                    goals: goals,
                    step: step,
                    majorEnabled: majorEnabled,
                    majorEvery: majorEvery,
                    turnPenalty: turnPenalty
                ) else { continue }

                let end = r.end
                let exitCost: Double = (end == exit.a) ? Double(exit.t) : Double(1.0 - exit.t)
                let total = g0 + r.cost + exitCost

                // convert corner “thirds” -> world using (pivot + thirds/3) in basis
                let (u0, v0) = gridBasisUV()
                func cornerWorld(_ c: Corner3) -> CGPoint {
                    // absolute thirds = 3*pivot + relThirds
                    let i3Abs = 3 * pivot.e3 + c.i3
                    let j3Abs = 3 * pivot.e5 + c.j3
                    let di = CGFloat(i3Abs) / 3.0
                    let dj = CGFloat(j3Abs) / 3.0
                    let o = layout.position(for: .init(e3: 0, e5: 0))
                    return pAdd(o, pAdd(pMul(u0, di), pMul(v0, dj)))
                }

                var pts: [CGPoint] = []
                pts.reserveCapacity(r.path.count + 4)

                pts.append(aScreen)
                pts.append(camera.worldToScreen(entry.pointWorld))

                for c in r.path {
                    pts.append(camera.worldToScreen(cornerWorld(c)))
                }

                pts.append(camera.worldToScreen(exit.pointWorld))
                pts.append(bScreen)

                if best == nil || total < best!.cost { best = (pts, total) }
            }

            return best?.pts

        case .off:
            return nil

        @unknown default:
            return nil
        }
    }

    private func drawSelectionPath(
         ctx: inout GraphicsContext,
         keys: [LatticeStore.SelectionKey],
         now: Double,
         pivot: LatticeCoord,
         shift: [Int:Int],
         camera: LatticeCamera,
         zoom: CGFloat,
         gridStrokeWidth: CGFloat
     ) {
        guard keys.count > 1 else { return }

        // Keep whatever your current baseline width logic is.
        // (This line is illustrative; keep your existing baseWidth computation.)
         let baseWidth: CGFloat = max(1.5, gridStrokeWidth + 1.1)
        let radius: Int = Int(max(8, min(48, zoom / 5)))

        // Precompute endpoint screen points + endpoint tints (existing helpers).
        func pt(_ k: LatticeStore.SelectionKey) -> CGPoint {
            selectionScreenPoint(for: k, pivot: pivot, shift: shift, camera: camera)
        }
        func tint(_ k: LatticeStore.SelectionKey) -> Color {
            selectionTint(for: k, pivot: pivot, shift: shift)
        }

        // Build ordered pairs per mode (Chain / Loop).
        var pairs: [(LatticeStore.SelectionKey, LatticeStore.SelectionKey)] = []
        pairs.reserveCapacity(keys.count)

        for i in 0..<(keys.count - 1) {
            pairs.append((keys[i], keys[i + 1]))
        }

        if latticeConnectionMode == .loop, keys.count >= 3 {
            pairs.append((keys[keys.count - 1], keys[0]))
        }

        // Stroke helper: EXACT same styling passes as your current per-segment code.
        @inline(__always)
        func strokeSegment(a: CGPoint, b: CGPoint, shade: GraphicsContext.Shading) {
            var seg = Path()
            seg.move(to: a)
            seg.addLine(to: b)

            // Keep these three strokes identical to your current code.
            ctx.stroke(seg, with: .color(Color.black.opacity(0.28)), lineWidth: baseWidth + 1.30)
            ctx.stroke(seg, with: .color(Color.white.opacity(0.18)), lineWidth: baseWidth + 0.70)
            ctx.stroke(seg, with: shade, lineWidth: baseWidth)
        }

        // Render
        for (aKey, bKey) in pairs {
            let aPt = pt(aKey)
            let bPt = pt(bKey)
            let aTint = tint(aKey)
            let bTint = tint(bKey)

            // Default shading matches existing behavior (gradient between endpoints).
            let endpointShade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [aTint, bTint]),
                startPoint: aPt,
                endPoint: bPt
            )

            // GRID PATH MODE (ordinal only; never closes unless Loop already did)
            if latticeConnectionMode == .gridPath,
               gridMode != .off,
               case let .plane(aC) = aKey,
               case let .plane(bC) = bKey,
               let poly = routedGridPolylineScreen(
                   from: aC,
                   to: bC,
                   gridMode: gridMode,
                   pivot: pivot,
                   shift: shift,
                   camera: camera,
                   zoom: zoom,
                   majorEnabled: gridMajorEnabled,
                   majorEvery: gridMajorEveryClamped
               ),
               poly.count >= 2 {

                for i in 0..<(poly.count - 1) {
                    strokeSegment(a: poly[i], b: poly[i + 1], shade: endpointShade)
                }
                continue
            }

            // FALLBACK (Chain behavior for this pair):
            // - grid off
            // - ghosts involved
            // - route not found
            strokeSegment(a: aPt, b: bPt, shade: endpointShade)
        }
    }


    
    private func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }
    // MARK: - Plane-node labels (ratio / HEJI)

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

    private func planeLabelText(for coord: LatticeCoord) -> String? {
        // axis-shift affects meaning (labels), but NOT geometry
        let e3 = coord.e3 + (store.axisShift[3] ?? 0)
        let e5 = coord.e5 + (store.axisShift[5] ?? 0)

        guard let (p, q) = planePQ(e3: e3, e5: e5) else { return nil }
        let (cp, cq) = canonicalPQ(p, q)

        if store.labelMode == .ratio {
            return "\(cp)/\(cq)"
        } else {
            return hejiTextLabel(p: cp, q: cq, octave: 0, rootHz: app.rootHz)
        }
    }

    private func shouldDrawPlaneLabel(coord: LatticeCoord) -> Bool {
        guard labelDensity > 0.01 else { return false }

        let zoom = store.camera.appliedScale
        let zoomT = clamp01((zoom - 42) / 70)
        guard zoomT >= 0.15 else { return false }

        // keep labels near pivot to avoid clutter
        let dx = abs(coord.e3 - store.pivot.e3)
        let dy = abs(coord.e5 - store.pivot.e5)
        let d  = max(dx, dy)

        let baseR  = max(4, min(18, Int(zoom / 14)))
        let labelR = Int(CGFloat(baseR) * CGFloat(labelDensity))
        return d <= labelR
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = clamp01(x)
        return t * t * (3 - 2 * t)
    }
    
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    /// Small, deterministic per-node jitter in normalized “t-space” so the ink front isn’t perfectly uniform.
    private func inkJitterFrac(prime: Int, e3: Int, e5: Int, eP: Int, duration: Double) -> CGFloat {
        // deterministic hash -> 0...1
        var x: UInt64 = 0
        x &+= UInt64(truncatingIfNeeded: prime &* 0x9E3779B1)
        x &+= UInt64(truncatingIfNeeded: e3    &* 0x85EBCA6B)
        x &+= UInt64(truncatingIfNeeded: e5    &* 0xC2B2AE35)
        x &+= UInt64(truncatingIfNeeded: eP    &* 0x27D4EB2F)

        // xorshift64*
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        x &*= 0x2545F4914F6CDD1D

        let u = Double(x) / Double(UInt64.max)   // 0...1
        let centered = (u * 2.0 - 1.0)           // -1...1

        let baseAmp = 0.045                      // small fraction of maxR (in t-space)
        let durScale = max(0.65, min(1.25, duration / 0.65))
        return CGFloat(centered * baseAmp * durScale)
    }

    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        // small, tasteful overshoot
        let c1: CGFloat = 1.15
        let c3: CGFloat = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
    
    private func maxRadius(from center: CGPoint, in rect: CGRect) -> CGFloat {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        let m = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0
        return m + 120
    }
    
    
    private func silenceSelectionMomentarily(_ duration: TimeInterval = 0.06) {
        guard store.auditionEnabled else { return }
        // Briefly pause selection audition so only the info voice is heard
        store.pauseAuditionForInfoVoice(durationMS: Int(duration * 1000.0))
    }
    
    
    // Interaction state
    @State private var lastDrag: CGSize = .zero
    @State private var lastMag: CGFloat = 1
    @State private var magnify: CGFloat = 1
    @State private var focusedPoint: (pos: CGPoint, label: String, etCents: Double, hz: Double, coord: LatticeCoord?, num: Int, den: Int)? = nil
    @State private var lastTapPoint: CGPoint = .zero
    @State private var cometScreen: CGPoint? = nil
    @State private var cometVisible: Bool = false
    @State private var trayHeight: CGFloat = 0
    @State private var bottomHUDHeight: CGFloat = 0
    @State private var latticeViewSize: CGSize = .zero
    private let utilityBarHeight: CGFloat = 50 // matches your UtilityBar; tweak if needed
    
    
    @AppStorage(SettingsKeys.nodeSize)     private var nodeSize = "m"
    @AppStorage(SettingsKeys.labelDensity) private var labelDensity: Double = 0.65
    @AppStorage(SettingsKeys.accidentalPreference) private var accidentalPreferenceRaw: String = AccidentalPreference.auto.rawValue
    @AppStorage(SettingsKeys.staffA4Hz) private var staffA4Hz: Double = 440
    
    @Environment(\.latticePreviewHideDistance) private var latticePreviewHideDistance
    @Environment(\.displayScale) private var displayScale
    
    private func nodeBaseSize() -> CGFloat {
        switch nodeSize {
        case "s":     return 10
        case "m":     return 12
        case "mplus": return 14
        case "l":     return 16
        default:      return 12
        }
    }

    private func helmholtzPreference(from preference: AccidentalPreference) -> NotationFormatter.AccidentalPreference {
        switch preference {
        case .preferFlats: return .preferFlats
        case .preferSharps: return .preferSharps
        case .auto: return .auto
        }
    }
    
    // MARK: - Info-card octave helpers (no-fold; do NOT force ratio back to 1–2)
    private func ratioWithOctaveOffsetNoFold(num: Int, den: Int, offset: Int) -> (Int, Int) {
        guard offset != 0 else { return (num, den) }
        if offset > 0 {
            let mul = 1 << offset                 // 2^offset
            return reduceNoFold(num * mul, den)
        } else {
            let mul = 1 << (-offset)              // 2^(-offset)
            return reduceNoFold(num, den * mul)
        }
    }
    private func reduceNoFold(_ p: Int, _ q: Int) -> (Int, Int) {
        let g = gcd(abs(p), abs(q))
        return (p / g, q / g)
    }
    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
    
    private func canonicalPQ(_ p: Int, _ q: Int) -> (Int, Int) {
        guard p > 0 && q > 0 else { return (p, q) }
        var num = p, den = q
        // Move powers of 2 between numerator/denominator to bring ratio into [1,2)
        while Double(num) / Double(den) >= 2.0 { den &*= 2 }  // multiply den by 2
        while Double(num) / Double(den) <  1.0 { num &*= 2 }  // multiply num by 2
        // Reduce common factors (cheap gcd) so labels stay small when possible
        func gcd(_ a: Int, _ b: Int) -> Int {
            var x = a, y = b
            while y != 0 { let t = x % y; x = y; y = t }
            return max(1, x)
        }
        let g = gcd(num, den)
        return (num / g, den / g)
    }
    
    
    private struct SelectionTrayHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
    
    private struct BottomHUDHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
    
    // REPLACE tapper(viewRect:) with this (same body; just swap gesture type + location source)
    private func tapper(viewRect: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { v in
                let loc = v.location
                lastTapPoint = loc
                
                // capture BEFORE we mutate focus (used for haptic + focus tick)
                let prevFocusCoord = focusedPoint?.coord

                guard let cand = hitTestCandidate(at: loc, viewRect: viewRect) else {
                    endInfoPreviewAndResumeSelectionIfStillSelected()
                    focusedPoint = nil
                    return
                }
#if targetEnvironment(macCatalyst)
                contextTarget = makeContextTarget(from: cand)
#endif
                
                if cand.isPlane, let c = cand.coord, focusedPoint?.coord == c, store.selected.contains(c) {
                    releaseInfoVoice(hard: true)
                    autoSelectInFlight = true
                    store.toggleSelection(c)
                    selectionHapticTick &+= 1
                    autoSelectNextNode(
                        excluding: .plane(c),
                        referencePoint: cand.pos,
                        viewRect: viewRect
                    )
                    return
                }

                let (cn, cd) = canonicalPQ(cand.p, cand.q)
                let raw = app.rootHz * (Double(cn) / Double(cd))
                let freq = foldToAudible(raw, minHz: 20, maxHz: 5000)
                let willDeselectPausedPlane: Bool = {
                    guard cand.isPlane, let c = cand.coord else { return false }
                    return (pausedForInfoCoord == c) && store.selected.contains(c)
                }()

                if willDeselectPausedPlane {
                    releaseInfoVoice(hard: true)
                } else {
                    endInfoPreviewAndResumeSelectionIfStillSelected(hard: true)
                }

                focusedPoint = (
                    pos: cand.pos,
                    label: "\(cn)/\(cd)",
                    etCents: RatioMath.centsFromET(freqHz: freq, refHz: app.rootHz),
                    hz: freq,
                    coord: cand.coord,
                    num: cn,
                    den: cd
                )
                let newFocusCoord = focusedPoint?.coord
                if prevFocusCoord != newFocusCoord {
                    focusHapticTick &+= 1
                #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.35)
                #endif
                }

                if cand.isPlane, let c = cand.coord {
                    let wasSelected = store.selected.contains(c)
                    if wasSelected { autoSelectInFlight = true }
                    // if this tap will deselect the currently focused plane node, add a touch more punch
                    if let fp = focusedPoint?.coord, fp == c, store.selected.contains(c) {
                #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1.0)
                #endif
                    }
                    store.toggleSelection(c)
                    infoOctaveOffset = store.octaveOffset(for: c)
                    selectionHapticTick &+= 1
                    if wasSelected {
                        autoSelectNextNode(
                            excluding: .plane(c),
                            referencePoint: cand.pos,
                            viewRect: viewRect
                        )
                    }
                } else if let g = cand.ghost {
                    let ghostKey = LatticeStore.GhostMonzo(e3: g.e3, e5: g.e5, p: g.prime, eP: g.eP)
                    let wasSelected = store.selectedGhosts.contains(ghostKey)
                    if wasSelected { autoSelectInFlight = true }
                    store.toggleOverlay(prime: g.prime, e3: g.e3, e5: g.e5, eP: g.eP)
                    infoOctaveOffset = 0
                    selectionHapticTick &+= 1
                    if wasSelected {
                        autoSelectNextNode(
                            excluding: .ghost(ghostKey),
                            referencePoint: cand.pos,
                            viewRect: viewRect
                        )
                    }
                }

            }
    }
    
    
    private func foldToAudible(_ f: Double, minHz: Double, maxHz: Double) -> Double {
        guard f.isFinite && f > 0 else { return f }
        var x = f
        while x < minHz { x *= 2 }
        while x > maxHz { x *= 0.5 }
        return x
    }

    private func autoSelectNextNode(
        excluding excludedKey: LatticeStore.SelectionKey,
        referencePoint: CGPoint,
        viewRect: CGRect
    ) {
        defer { autoSelectInFlight = false }
        if store.selected.isEmpty && store.selectedGhosts.isEmpty {
            releaseInfoVoice()
            withAnimation(.easeOut(duration: 0.2)) { focusedPoint = nil }
            return
        }

        let candidates = selectedSelectionCandidates(in: viewRect)
        guard let nextKey = NextNodeSelection.pickNext(
            from: candidates,
            excluding: excludedKey,
            referencePoint: referencePoint,
            preferVisibleSubset: true,
            priorDirection: nil,
            displayScale: displayScale
        ) else {
            releaseInfoVoice()
            withAnimation(.easeOut(duration: 0.2)) { focusedPoint = nil }
            return
        }

        guard let nextCandidate = candidates.first(where: { $0.id == nextKey }) else { return }

        if let newFocus = focusedPoint(for: nextKey, at: nextCandidate.position) {
            focusedPoint = newFocus
        }
    }

    private func focusedPoint(
        for key: LatticeStore.SelectionKey,
        at screenPoint: CGPoint
    ) -> (pos: CGPoint, label: String, etCents: Double, hz: Double, coord: LatticeCoord?, num: Int, den: Int)? {
        switch key {
        case .plane(let c):
            let e3m = c.e3 + (store.axisShift[3] ?? 0)
            let e5m = c.e5 + (store.axisShift[5] ?? 0)
            guard let (p, q) = planePQ(e3: e3m, e5: e5m) else { return nil }
            let (cn, cd) = canonicalPQ(p, q)
            let raw = app.rootHz * (Double(cn) / Double(cd))
            let freq = foldToAudible(raw, minHz: 20, maxHz: 5000)
            infoOctaveOffset = store.octaveOffset(for: c)
            return (
                pos: screenPoint,
                label: "\(cn)/\(cd)",
                etCents: RatioMath.centsFromET(freqHz: freq, refHz: app.rootHz),
                hz: freq,
                coord: c,
                num: cn,
                den: cd
            )
        case .ghost(let g):
            guard let (p, q) = overlayPQ(e3: g.e3, e5: g.e5, prime: g.p, eP: g.eP) else { return nil }
            let (cn, cd) = canonicalPQ(p, q)
            let raw = app.rootHz * (Double(cn) / Double(cd))
            let freq = foldToAudible(raw, minHz: 20, maxHz: 5000)
            infoOctaveOffset = store.octaveOffset(for: g)
            return (
                pos: screenPoint,
                label: "\(cn)/\(cd)",
                etCents: RatioMath.centsFromET(freqHz: freq, refHz: app.rootHz),
                hz: freq,
                coord: nil,
                num: cn,
                den: cd
            )
        }
    }

    private func selectedSelectionCandidates(
        in viewRect: CGRect
    ) -> [NextNodeSelection.Candidate<LatticeStore.SelectionKey>] {
        var out: [NextNodeSelection.Candidate<LatticeStore.SelectionKey>] = []

        for coord in store.selected {
            let wp = layout.position(for: coord)
            let sp = store.camera.worldToScreen(wp)
            let e3m = coord.e3 + (store.axisShift[3] ?? 0)
            let e5m = coord.e5 + (store.axisShift[5] ?? 0)
            let complexity: Double = {
                guard let (p, q) = planePQ(e3: e3m, e5: e5m) else { return 1.0e12 }
                return complexityScore(num: p, den: q)
            }()

            out.append(
                .init(
                    id: .plane(coord),
                    stableID: "plane:\(coord.e3),\(coord.e5)",
                    position: sp,
                    isVisible: viewRect.contains(sp),
                    isGhost: false,
                    opacityOrPriority: nil,
                    complexity: complexity
                )
            )
        }

        for ghost in store.selectedGhosts {
            let wp = layout.position(monzo: [3: ghost.e3, 5: ghost.e5, ghost.p: ghost.eP])
            let sp = store.camera.worldToScreen(wp)
            let complexity: Double = {
                guard let (p, q) = overlayPQ(e3: ghost.e3, e5: ghost.e5, prime: ghost.p, eP: ghost.eP) else { return 1.0e12 }
                return complexityScore(num: p, den: q)
            }()

            out.append(
                .init(
                    id: .ghost(ghost),
                    stableID: "ghost:\(ghost.p):\(ghost.e3):\(ghost.e5):\(ghost.eP)",
                    position: sp,
                    isVisible: viewRect.contains(sp),
                    isGhost: true,
                    opacityOrPriority: nil,
                    complexity: complexity
                )
            )
        }

        return out
    }

    private func complexityScore(num: Int, den: Int) -> Double {
        let n = Double(max(1, num))
        let d = Double(max(1, den))
        let value = n * d
        guard value.isFinite else { return 1.0e12 }
        return log2(max(1.0, value))
    }
    
    
#if targetEnvironment(macCatalyst)
    private var currentCursor: CatalystCursorIntent {
        if isMousePanning { return .closedHand }
        if contextTarget != nil { return .pointingHand }
        return .openHand
    }

    private func updateContextTarget(at point: CGPoint, in size: CGSize) {
        let viewRect = CGRect(origin: .zero, size: size)
        guard let cand = hitTestCandidate(at: point, viewRect: viewRect) else {
            contextTarget = nil
            return
        }
        guard let target = makeContextTarget(from: cand) else {
            contextTarget = nil
            return
        }
        contextTarget = target
    }

    private func makeContextTarget(
        from cand: (pos: CGPoint, label: String, isPlane: Bool, coord: LatticeCoord?, p: Int, q: Int, ghost: (prime:Int, e3:Int, e5:Int, eP:Int)?)
    ) -> ContextTarget? {
        let (cn, cd) = canonicalPQ(cand.p, cand.q)
        let rawHz = app.rootHz * (Double(cn) / Double(cd))
        let freq = RatioMath.foldToAudible(rawHz)
        let cents = RatioMath.centsFromET(freqHz: freq, refHz: app.rootHz)

        var monzo: [Int:Int] = [:]
        if let c = cand.coord {
            monzo[3] = c.e3 + store.pivot.e3 + (store.axisShift[3] ?? 0)
            monzo[5] = c.e5 + store.pivot.e5 + (store.axisShift[5] ?? 0)
        }
        if let g = cand.ghost {
            monzo[g.prime] = g.eP
            monzo[3] = (monzo[3] ?? 0) + g.e3
            monzo[5] = (monzo[5] ?? 0) + g.e5
        }

        return ContextTarget(
            label: "\(cn)/\(cd)",
            hz: freq,
            cents: cents,
            coord: cand.coord,
            num: cn,
            den: cd,
            monzo: monzo
        )
    }

    @ViewBuilder
    private func latticeContextMenu() -> some View {
        if let target = contextTarget {
            Button("Copy Ratio") { copyToPasteboard(target.label) }
            Button("Copy Hz") {
                copyToPasteboard(String(format: "%.3f Hz", target.hz))
            }
            Button("Copy Cents") {
                copyToPasteboard(String(format: "%+.1f¢", target.cents))
            }
            Button("Add to Scale") { addTargetToBuilder(target) }
            Button("Set as Root") { app.rootHz = target.hz }
        }
    }

    private func addTargetToBuilder(_ target: ContextTarget) {
        let ref = RatioRef(
            p: target.num,
            q: target.den,
            octave: 0,
            monzo: target.monzo
        )
        let payload: ScaleBuilderPayload
        if app.builderSessionExists {
#if DEBUG
            let draftHash = AppModel.debugDegreeHash(app.builderSession.draftDegrees)
            let pendingCount = app.builderSession.pendingAddRefs?.count ?? 0
            print("[Builder+Context] loadedScaleID=\(app.builderSession.savedScaleID?.uuidString ?? "nil") draftCount=\(app.builderSession.draftDegrees.count) draftHash=\(draftHash) payloadRefs=1 pendingAddRefs=\(pendingCount)")
#endif
            app.appendBuilderDraftRefs([ref])
            if let sessionPayload = app.builderSessionPayload {
                payload = sessionPayload
            } else if let existing = app.builderLoadedScale {
                payload = ScaleBuilderPayload(
                    rootHz: existing.referenceHz,
                    primeLimit: existing.detectedLimit,
                    axisShift: [:],
                    items: existing.degrees,
                    autoplayAll: app.latticeAuditionOn,
                    startInLibrary: false,
                    existing: existing
                )
            } else {
                payload = ScaleBuilderPayload(
                    rootHz: app.rootHz,
                    primeLimit: app.primeLimit,
                    refs: [ref]
                )
            }
        } else {
            payload = ScaleBuilderPayload(
                rootHz: app.rootHz,
                primeLimit: app.primeLimit,
                refs: [ref]
            )
        }
        store.beginStaging()
        app.builderPayload = payload
    }

    private func copyToPasteboard(_ text: String) {
        UIPasteboard.general.string = text
    }
#endif
    
    //
    private func releaseInfoVoice(hard: Bool = true) {
        infoSwitchSeq &+= 1
        if let id = infoVoiceID {
            ToneOutputEngine.shared.release(id: id, seconds: hard ? 0.0 : 0.05)
            infoVoiceID = nil
        }
        if pausedForInfoCoord != nil {
            pausedForInfoCoord = nil
        }
    }

    private func endInfoPreviewAndResumeSelectionIfStillSelected(hard: Bool = true) {
        let coordToResume = pausedForInfoCoord
        releaseInfoVoice(hard: hard)
        guard let c = coordToResume else { return }
        DispatchQueue.main.async {
            if store.selected.contains(c) {
                store.resumeSelectionVoiceIfNeeded(for: c)
            }
        }
    }
    
    private func switchInfoTone(toHz hz: Double, newOffset: Int) {
        // Always update the UI state immediately.
            infoOctaveOffset = newOffset
        
            // If audio is disabled, never leave anything paused.
            guard latticeAudioAllowed else {
                releaseInfoVoice(hard: true)   // stops preview only
                return
            }

        // Pause ONLY the focused node’s selection sustain so we don’t hear both
        if let c = focusedPoint?.coord, pausedForInfoCoord == nil {
            store.pauseSelectionVoice(for: c, hard: true)
            pausedForInfoCoord = c
        }

        // Bump token to invalidate any queued start from a previous tap.
        infoSwitchSeq &+= 1
        let seq = infoSwitchSeq

        @inline(__always)
        func startPreviewIfCurrent() {
            guard seq == infoSwitchSeq else { return }   // stale start; ignore
            let key = "lattice:info:\(seq)"              // avoid ownerKey collisions during release windows
            let newID: ToneOutputEngine.VoiceID = ToneOutputEngine.shared.sustain(
                freq: hz,
                amp: 0.22,
                owner: .other,
                ownerKey: key,
                attackMs: nil,
                releaseMs: nil
            )
            infoVoiceID = newID
        }

        if let id = infoVoiceID {
            // Give the engine a breath to retire the old voice before re-arming.
            ToneOutputEngine.shared.release(id: id, seconds: 0.02)
            infoVoiceID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                startPreviewIfCurrent()
            }
        } else {
            startPreviewIfCurrent()
        }
    }

    
    // MARK: - Axis Shift contrast (white/black by tint luminance)
    private enum AxisShiftContrast {
        static func foreground(
            tint: Color,
            usesTintedSurface: Bool,
            isActive: Bool,
            isEnabled: Bool,
            scheme: ColorScheme
        ) -> Color {
            guard isEnabled else { return .secondary }
            guard isActive else { return .secondary }
            guard usesTintedSurface else { return .primary } // plane primes: neutral surface, keep “instrument label” semantics
            
#if canImport(UIKit)
            let (r, g, b, _) = rgba(tint, scheme: scheme)
            let L = relativeLuminance(r, g, b)
            
            // Contrast ratio vs white/black; pick the higher.
            let contrastWhite = (max(1.0, L) + 0.05) / (min(1.0, L) + 0.05)      // white luminance = 1
            let contrastBlack = (max(L, 0.0) + 0.05) / (min(L, 0.0) + 0.05)      // black luminance = 0
            return (contrastWhite >= contrastBlack) ? .white : .black
#else
            return .white
#endif
        }
        
#if canImport(UIKit)
        private static func rgba(_ color: Color, scheme: ColorScheme) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let ui = UIColor(color)
            let style: UIUserInterfaceStyle = (scheme == .dark) ? .dark : .light
            let resolved = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if resolved.getRed(&r, green: &g, blue: &b, alpha: &a) {
                return (r, g, b, a)
            }
            // Fallback: treat as mid-gray
            return (0.5, 0.5, 0.5, 1.0)
        }
        
        // WCAG-ish relative luminance in linear sRGB
        private static func relativeLuminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Double {
            func lin(_ c: CGFloat) -> Double {
                let x = Double(c)
                return (x <= 0.04045) ? (x / 12.92) : pow((x + 0.055) / 1.055, 2.4)
            }
            let R = lin(r), G = lin(g), B = lin(b)
            return 0.2126 * R + 0.7152 * G + 0.0722 * B
        }
#endif
    }
    
    
    // MARK: - Axis Shift HUD (v0.3)
    private struct AxisShiftHUD: View {
        @ObservedObject var store: LatticeStore
        @ObservedObject var app: AppModel
        
        /// theme tint per prime
        let tint: (Int) -> Color
        
        @Environment(\.colorScheme) private var scheme
        @State private var showPro = false
        @Namespace private var ns
        
        private let primes: [Int] = [3,5,7,11,13,17,19,23,29,31]
        
        var body: some View {
            Group {
                if #available(iOS 26.0, *) {
                    rail
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                } else {
                    rail
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .sheet(isPresented: $showPro) {
                AxisShiftProSheet(
                    store: store,
                    app: app,
                    tint: tint,
                    primes: primes,
                    scheme: scheme,
                    ns: ns
                )
                .presentationDetents([.height(300), .large])
                .presentationDragIndicator(.hidden) // we provide our own (matched-geometry) handle
                .presentationBackground(.ultraThinMaterial)
            }
        }
        
        private var rail: some View {
            VStack(spacing: 8) {
                AxisShiftHandle(isPresented: showPro, ns: ns)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { showPro = true } }
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onEnded { v in
                                if v.translation.height < -12 {
                                    withAnimation(.snappy) { showPro = true }
                                }
                            }
                    )
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(primes, id: \.self) { p in
                            AxisShiftChip(
                                prime: p,
                                value: store.axisShift[p, default: 0],
                                tint: tint(p),
                                scheme: scheme,
                                disabled: false,
                                size: .compact,
                                minus: { store.shift(prime: p, delta: -1) },
                                plus:  { store.shift(prime: p, delta: +1) },
                                reset: { store.resetShift(prime: p) }
                            )
                            .matchedGeometryEffect(id: "axischip.\(p)", in: ns)
                        }
                        
                        if store.axisShift.values.contains(where: { $0 != 0 }) {
                            Button("Reset All") { withAnimation(.snappy) { store.resetShift() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }
    
    private struct AxisShiftHandle: View {
        let isPresented: Bool
        let ns: Namespace.ID
        
        var body: some View {
            Capsule()
                .frame(width: 44, height: 5)
                .foregroundStyle(.secondary.opacity(0.65))
                .matchedGeometryEffect(id: "axishandle", in: ns, isSource: !isPresented)
                .padding(.top, 2)
        }
    }
    
    private struct AxisShiftProSheet: View {
        @ObservedObject var store: LatticeStore
        @ObservedObject var app: AppModel
        
        let tint: (Int) -> Color
        let primes: [Int]
        let scheme: ColorScheme
        let ns: Namespace.ID
        
        @Environment(\.dismiss) private var dismiss
        
        private var activePrimes: [Int] {
            primes.filter { store.axisShift[$0, default: 0] != 0 }
        }
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        // matched handle
                        Capsule()
                            .frame(width: 44, height: 5)
                            .foregroundStyle(.secondary.opacity(0.65))
                            .matchedGeometryEffect(id: "axishandle", in: ns, isSource: true)
                            .padding(.top, 10)
                        
                        // Active shifts summary (the “reason to exist”)
                        Group {
                            if #available(iOS 26.0, *) {
                                activeSummary
                                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            } else {
                                activeSummary
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        
                        // Full control surface
                        Group {
                            if #available(iOS 26.0, *) {
                                controlGrid
                                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            } else {
                                controlGrid
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        
                        if store.axisShift.values.contains(where: { $0 != 0 }) {
                            Button("Reset All") { withAnimation(.snappy) { store.resetShift() } }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
                }
                .navigationTitle("Axis Shift")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        
        private var activeSummary: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Active Shifts")
                        .font(.headline)
                    Spacer()
                    if !activePrimes.isEmpty {
                        Button("Reset") { withAnimation(.snappy) { store.resetShift() } }
                            .buttonStyle(.borderless)
                    }
                }
                
                if activePrimes.isEmpty {
                    Text("None")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    // show only non-zero primes as chips
                    FlowWrap(spacing: 8) {
                        ForEach(activePrimes, id: \.self) { p in
                            let v = store.axisShift[p, default: 0]
                            AxisShiftChip(
                                prime: p,
                                value: v,
                                tint: tint(p),
                                scheme: scheme,
                                disabled: false,
                                size: .summary,
                                minus: { store.shift(prime: p, delta: -1) },
                                plus:  { store.shift(prime: p, delta: +1) },
                                reset: { store.resetShift(prime: p) }
                            )
                            .matchedGeometryEffect(id: "axischip.\(p)", in: ns)
                        }
                    }
                }
            }
            .padding(12)
        }
        
        private var controlGrid: some View {
            let cols: [GridItem] = [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]
            return LazyVGrid(columns: cols, spacing: 10) {
                ForEach(primes, id: \.self) { p in
                    let v = store.axisShift[p, default: 0]
                    AxisShiftChip(
                        prime: p,
                        value: v,
                        tint: tint(p),
                        scheme: scheme,
                        disabled: false,
                        size: .pro,
                        minus: { store.shift(prime: p, delta: -1) },
                        plus:  { store.shift(prime: p, delta: +1) },
                        reset: { store.resetShift(prime: p) }
                    )
                    .matchedGeometryEffect(id: "axischip.\(p)", in: ns)
                }
            }
            .padding(12)
        }
    }
    
    // MARK: - Chip (compact + pro)
    private struct AxisShiftChip: View {
        enum Size { case compact, summary, pro }
        
        let prime: Int
        let value: Int
        let tint: Color
        let scheme: ColorScheme
        let disabled: Bool
        
        let size: Size
        let minus: () -> Void
        let plus:  () -> Void
        let reset: () -> Void
        
        private var labelColor: Color {
            disabled ? .secondary.opacity(0.7) : (value == 0 ? .secondary : tint)
        }

        private var controlColor: Color {
            disabled ? .secondary.opacity(0.7) : (value == 0 ? .secondary : .primary)
        }

        
        private var corner: CGFloat { 12 }
        
        private var padH: CGFloat {
            switch size {
            case .summary: return 8
            case .compact: return 8
            case .pro:     return 10
            }
        }
        
        private var padV: CGFloat {
            switch size {
            case .summary: return 6
            case .compact: return 7
            case .pro:     return 10
            }
        }
        
        private var iconSize: CGFloat {
            switch size {
            case .summary: return 11
            case .compact: return 12
            case .pro:     return 14
            }
        }
        
        private var labelFont: Font {
            // keep your existing “presence”: small label, stable number
            .system(size: size == .pro ? 12 : 11, weight: .semibold, design: .monospaced)
        }
        
        private var valueFont: Font {
            .system(size: size == .pro ? 13 : 12, weight: .semibold, design: .monospaced)
        }
        
        private var canMinus: Bool { !disabled && value > -5 }
        private var canPlus:  Bool { !disabled && value <  5 }
        
        var body: some View {
            HStack(spacing: 8) {
                Text("±\(prime)")
                    .font(labelFont)
                    .foregroundStyle(labelColor)
                
                Button(action: { withAnimation(.snappy) { minus() } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: iconSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controlColor)
                .opacity(canMinus ? 1.0 : 0.35)
                .disabled(!canMinus)
                
                Text(verbatim: "\(value)")
                    .font(valueFont)
                    .foregroundStyle(controlColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                // this is the “off vs on” semantics you already had
                    .background(value == 0 ? .clear : tint.opacity(0.16), in: Capsule())
                    .contentTransition(.numericText())
                    .sensoryFeedback(.selection, trigger: value)
                
                Button(action: { withAnimation(.snappy) { plus() } }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: iconSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controlColor)
                .opacity(canPlus ? 1.0 : 0.35)
                .disabled(!canPlus)
            }
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contextMenu {
                Button("Reset ±\(prime) axis", role: .destructive, action: reset)
            }
            .compositingGroup()
            .onTapGesture(count: 2, perform: reset)
            .modifier(AxisShiftChipSurface(
                tint: tint,
                isActive: value != 0,
                disabled: disabled,
                corner: corner
            ))

            .opacity(disabled ? 0.45 : 1.0)
            .disabled(disabled)
            .allowsHitTesting(!disabled)
        }
    }
    
    private struct AxisShiftChipSurface: ViewModifier {
        let tint: Color
        let isActive: Bool
        let disabled: Bool
        let corner: CGFloat

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

            if #available(iOS 26.0, *) {
                content
                    // neutral glass (NOT tinted fill)
                    .glassEffect(.regular, in: shape)
                    // tint as identity: stroke + tiny wash only when active
                    .overlay(
                        shape.strokeBorder(
                            tint.opacity(isActive ? 0.60 : 0.22),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                    )
                    .overlay(
                        Group {
                            if isActive {
                                shape.fill(tint.opacity(0.08))
                            }
                        }
                            .allowsHitTesting(false)
                    )
            } else {
                content
                    .background(.thinMaterial, in: shape)
                    .overlay(
                        shape.strokeBorder(
                            tint.opacity(isActive ? 0.55 : 0.25),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                    )
                    .overlay(
                        Group {
                            if isActive {
                                shape.fill(tint.opacity(0.07))
                            }
                        }
                            .allowsHitTesting(false)
                    )
            }
        }
    }

    
    // MARK: - Luminance-based foreground for legibility (fixes “pink on pink”)
    private static func foregroundOnTint(_ tint: Color, scheme: ColorScheme) -> Color {
#if canImport(UIKit)
        let ui = UIColor(tint)
        let resolved = ui.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        )
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.2126*r + 0.7152*g + 0.0722*b
        return (lum < 0.58) ? .white : .black
#else
        return .primary
#endif
    }
    
    // MARK: - Tiny flow layout for “Active Shifts”
    private struct FlowWrap<Content: View>: View {
        let spacing: CGFloat
        @ViewBuilder let content: () -> Content
        
        init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
            self.spacing = spacing
            self.content = content
        }
        
        var body: some View {
            _VariadicView.Tree(FlowLayout(spacing: spacing)) { content() }
        }
        
        private struct FlowLayout: _VariadicView_UnaryViewRoot {
            let spacing: CGFloat
            func body(children: _VariadicView.Children) -> some View {
                GeometryReader { geo in
                    var x: CGFloat = 0
                    var y: CGFloat = 0
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                            child
                                .alignmentGuide(.leading) { d in
                                    if x + d.width > geo.size.width {
                                        x = 0
                                        y -= (d.height + spacing)
                                    }
                                    let result = x
                                    x += d.width + spacing
                                    return result
                                }
                                .alignmentGuide(.top) { _ in
                                    let result = y
                                    return result
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(minHeight: 10)
            }
        }
    }
    
    
    
    
    // MARK: - Selection Tray (v0.3)
    private struct SelectionTray: View {
        @ObservedObject var store: LatticeStore
        @ObservedObject var app: AppModel
        let stopInfoPreview: (Bool) -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorScheme) private var colorScheme
        @Namespace private var addNS

        private var hasDelta: Bool { store.additionsSinceBaseline > 0 }
        private var hasBuilderSession: Bool { app.builderSessionExists }
        private var sessionLoaded: Bool { app.builderSessionExists }
        private var sessionDirty: Bool { app.builderSession.isEdited }
        private var stagingActive: Bool {
            store.selectedCount > 0
                || store.additionsSinceBaseline > 0
                || !(app.builderSession.pendingAddRefs?.isEmpty ?? true)
        }
        private var sessionDisplayName: String {
            let trimmed = app.builderSession.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Untitled Scale" : trimmed
        }
        private var sessionStateText: String { sessionDirty ? "Edited" : "Clean" }

        // Only show the word when (a) not compact by selectionCount, and (b) no delta flag
        private var addShowsWord: Bool { !addIsCompact && !hasDelta }

        private var addWord: String { hasBuilderSession ? "Add" : "New" }

        private var addIsCompact: Bool {
            store.selectedCount > 1
        }

        // MARK: - Sizing (keep tray height stable)
        private let ctl: CGFloat = 40          // uniform control size
        private let addCompactSide: CGFloat = 40   // square-ish compact width for "+"
        private let corner: CGFloat = 12       // rounded-rect corner radius
        private let trayPadV: CGFloat = 8      // reduce padding so net height stays ~same
        private let railSpacing: CGFloat = 4

        private struct BuilderSessionStatus: Equatable {
            let exists: Bool
            let displayName: String
            let isEdited: Bool
            let isLoaded: Bool

            var leftPrefix: String {
                if isEdited { return "Editing" }
                return isLoaded ? "Loaded" : "Draft"
            }

            var leftLabel: String {
                "\(leftPrefix) — \(displayName)"
            }

            var stateText: String {
                if isEdited { return "Edited" }
                return isLoaded ? "Clean" : "Unsaved"
            }

            var stateTextWithDelta: String {
                isEdited ? "Edited Δ" : stateText
            }

            var stateSymbol: String {
                if isEdited { return "pencil.circle" }
                return isLoaded ? "checkmark.circle" : "pencil.circle"
            }

            var helpText: String {
                "\(displayName) — \(stateTextWithDelta)"
            }

            var accessibilityLabel: String {
                let sessionLabel = isEdited ? "Editing scale" : (isLoaded ? "Loaded scale" : "Draft scale")
                return [sessionLabel, displayName, stateText].joined(separator: ", ")
            }
        }

        private var builderSessionStatus: BuilderSessionStatus {
            guard app.builderSessionExists else {
                return BuilderSessionStatus(exists: false, displayName: "", isEdited: false, isLoaded: false)
            }
            let rawName = app.builderSession.displayName
            let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = trimmedName.isEmpty ? "Untitled Scale" : trimmedName
            return BuilderSessionStatus(
                exists: true,
                displayName: displayName,
                isEdited: app.builderSession.isEdited,
                isLoaded: app.builderSession.savedScaleID != nil
            )
        }

        @ViewBuilder
        private var builderSessionStateIcon: some View {
            let symbol = builderSessionStatus.stateSymbol
            if #available(iOS 17.0, *) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
            } else {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
            }
        }

        private var builderSessionRail: some View {
            let status = builderSessionStatus
            return Button {
                app.resumeBuilderSessionFromRail()
            } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                            Circle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 3.5, height: 3.5)
                        }
                        .frame(width: 7, height: 7)

                        Text(status.leftLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        builderSessionStateIcon
                            .font(.caption.weight(.semibold))
                        Text(status.stateText)
                        if status.isEdited {
                            Text("Δ")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .padding(.top, 2)
            }
            .buttonStyle(RailButtonStyle(reduceTransparency: reduceTransparency, isHovered: railHovered))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.accessibilityLabel)
#if os(macOS) || targetEnvironment(macCatalyst)
            .help(status.helpText)
            .onHover { railHovered = $0 }
#endif
        }

        private enum EmptyMode: String, CaseIterable, Identifiable {
            case recents
            case favorites
            var id: String { rawValue }

            var symbol: String {
                switch self {
                case .recents:   return "clock.arrow.circlepath"
                case .favorites: return "star"
                }
            }

            var a11y: String {
                switch self {
                case .recents:   return "Recents"
                case .favorites: return "Favorites"
                }
            }
        }

        @State private var emptyMode: EmptyMode = .recents
        @State private var addDidCommit: Bool = false
        @State private var keepTrayOpenAfterClear: Bool = false
        @State private var railHovered: Bool = false

        private var isActive: Bool {
            stagingActive
                || sessionLoaded
                || keepTrayOpenAfterClear
        }

        @ViewBuilder
        private func glassCircleBG() -> some View {
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Circle())
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }

        @ViewBuilder
        private func glassRectBG(prominent: Bool = false) -> some View {
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            if #available(iOS 26.0, *) {
                // iOS 26 Glass only exposes variants like .regular here (no .prominent)
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            } else {
                shape.fill(prominent ? .thinMaterial : .ultraThinMaterial)
            }
        }

        private func glassStrokeRect() -> some View {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }

        private func glassStrokeCircle() -> some View {
            Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        
        private struct GlassClearRoundedRect: ViewModifier {
            let corner: CGFloat
            func body(content: Content) -> some View {
                let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)
                if #available(iOS 26.0, *) {
                    content.glassEffect(.regular, in: rr)
                } else {
                    content
                        .background(.ultraThinMaterial, in: rr)
                        .overlay(rr.stroke(Color.secondary.opacity(0.14), lineWidth: 1))
                }
            }
        }

        private struct GlassAmberRoundedRect: ViewModifier {
            let corner: CGFloat
            func body(content: Content) -> some View {
                let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)
                let amber = Color(red: 0.96, green: 0.58, blue: 0.12)
                if #available(iOS 26.0, *) {
                    content.glassEffect(.regular.tint(amber), in: rr)
                } else {
                    content
                        .background(.ultraThinMaterial, in: rr)
                        .background(rr.fill(amber.opacity(0.28)))
                        .overlay(rr.stroke(amber.opacity(0.45), lineWidth: 1))
                }
            }
        }



        private struct GlassWhiteRoundedRect: ViewModifier {
            let corner: CGFloat
            func body(content: Content) -> some View {
                let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)
                if #available(iOS 26.0, *) {
                    content.glassEffect(.regular.tint(.white), in: rr)
                } else {
                    content
                        .background(.ultraThinMaterial, in: rr)
                        .background(rr.fill(Color.white.opacity(0.62)))
                        .overlay(rr.stroke(Color.secondary.opacity(0.14), lineWidth: 1))
                }
            }
        }
        
        private struct GlassBlackRoundedRect: ViewModifier {
            let corner: CGFloat
            func body(content: Content) -> some View {
                let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)
                if #available(iOS 26.0, *) {
                    content.glassEffect(.regular.tint(.black), in: rr)
                } else {
                    content
                        .background(.ultraThinMaterial, in: rr)
                        .background(rr.fill(Color.black.opacity(0.28)))
                        .overlay(rr.stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
            }
        }

        private struct RailButtonStyle: ButtonStyle {
            let reduceTransparency: Bool
            let isHovered: Bool

            func makeBody(configuration: Configuration) -> some View {
                let pressed = configuration.isPressed
                let fillOpacity = reduceTransparency
                    ? (pressed ? 0.18 : 0.12)
                    : (pressed ? 0.08 : (isHovered ? 0.05 : 0.0))
                let strokeOpacity = reduceTransparency
                    ? (pressed ? 0.32 : (isHovered ? 0.26 : 0.18))
                    : (pressed ? 0.24 : (isHovered ? 0.18 : 0.12))

                return configuration.label
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(fillOpacity))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(strokeOpacity), lineWidth: 1)
                    )
            }
        }
        


        
        private enum ClearState {
            case neutral
            case amber
            case red
        }

        // Truth table (SelectionTray status):
        // 1) sessionLoaded=true,  stagingActive=false, sessionDirty=false -> red,   "Unload scale"
        // 2) sessionLoaded=true,  stagingActive=false, sessionDirty=true  -> red,   "Discard changes and unload scale"
        // 3) sessionLoaded=true,  stagingActive=true                     -> amber, "Clear selection and staging"
        // 4) sessionLoaded=false, stagingActive=true                     -> amber
        // 5) sessionLoaded=false, stagingActive=false                    -> neutral/disabled
        private var effectiveClearState: ClearState {
            if sessionLoaded { return stagingActive ? .amber : .red }
            return stagingActive ? .amber : .neutral
        }

        private var clearAccessibilityLabel: String {
            switch effectiveClearState {
            case .neutral:
                return "Clear selection"
            case .amber:
                return "Clear selection and staging"
            case .red:
                return sessionDirty ? "Discard changes and unload scale" : "Unload scale"
            }
        }

        private var clearHelpText: String {
            switch effectiveClearState {
            case .neutral:
                return "Clears selection."
            case .amber:
                if sessionLoaded {
                    return "\(sessionDisplayName) — \(sessionStateText)"
                }
                return "Staging — \(sessionStateText)"
            case .red:
                return "\(sessionDisplayName) — \(sessionStateText)"
            }
        }

        private var clearIconColor: Color {
            switch effectiveClearState {
            case .neutral:
                return colorScheme == .dark ? .white : .black
            case .amber:
                return colorScheme == .dark ? .white : .white
            case .red:
                return .white
            }
        }

        private func clearStagingNonDestructive() {
            stopInfoPreview(true)
            store.stopSelectionAudio(hard: true)
            store.resetStagingDelta()
            withAnimation(.snappy) { store.clearSelection() }
            keepTrayOpenAfterClear = true
        }

        private func unloadSessionDestructive() {
            stopInfoPreview(true)
            store.stopSelectionAudio(hard: true)
            store.stopAllLatticeVoices(hard: true)
            ToneOutputEngine.shared.builderDidDismiss()
            store.endStaging()
            withAnimation(.snappy) { store.clearSelection() }
            app.unloadBuilderScale()
            keepTrayOpenAfterClear = false
        }

        private func performClearAction(state: ClearState) {
            switch state {
            case .neutral:
                return
            case .amber:
                clearStagingNonDestructive()
            case .red:
                unloadSessionDestructive()
            }
        }

        @ViewBuilder
        private func clearButtonLabel(for state: ClearState) -> some View {
            let icon = Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(clearIconColor)
                .frame(width: ctl, height: ctl)

            switch state {
            case .neutral:
                icon.modifier(GlassClearRoundedRect(corner: corner))
            case .amber:
                icon.modifier(GlassAmberRoundedRect(corner: corner))
            case .red:
                icon.modifier(GlassRedRoundedRect(corner: corner))
            }
        }

        private var clearButton: some View {
            let state = effectiveClearState

            return Button {
                performClearAction(state: state)
            } label: {
                clearButtonLabel(for: state)
            }
            .buttonStyle(.plain)
            .disabled(state == .neutral)
            .accessibilityLabel(clearAccessibilityLabel)
#if os(macOS) || targetEnvironment(macCatalyst)
            .help(clearHelpText)
#endif
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }

        // MARK: - Row pieces

        private var statusCluster: some View {
            let hasDelta = store.additionsSinceBaseline > 0

            return HStack(spacing: 8) {
                Text("Selected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(store.selectedCount)")
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .contentTransition(.numericText())

                if hasDelta {
                    Text("Δ+\(store.additionsSinceBaseline)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                        )
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(height: ctl)
            .padding(.horizontal, 12)
        //    .frame(minWidth: 132, alignment: .center)
            .background(glassRectBG())
            .overlay(glassStrokeRect())
        }


        private var toolsCapsule: some View {
            HStack(spacing: 8) {
                toolCircle(
                    systemName: "arrow.uturn.left",
                    enabled: store.canUndo
                ) { store.undo() }

                toolCircle(
                    systemName: "arrow.uturn.right",
                    enabled: store.canRedo
                ) { store.redo() }

                clearButton

            }
            .frame(height: ctl)
            .padding(.horizontal, 8)
            .background(glassRectBG())
            .overlay(glassStrokeRect())
        }

        private func toolCircle(systemName: String, enabled: Bool, showStroke: Bool = true, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.footnote.weight(.semibold))
                    .frame(width: ctl, height: ctl)
                    .background(glassCircleBG())
                    .overlay {
                        if showStroke { glassStrokeCircle() }
                    }
                    .opacity(enabled ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .contentShape(Circle())
        }

        private var addIcon: some View {
            Group {
                if #available(iOS 17.0, *) {
                    Image(systemName: addDidCommit ? "checkmark" : "plus")
                        .symbolRenderingMode(addDidCommit ? .multicolor : .hierarchical)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                } else {
                    Image(systemName: addDidCommit ? "checkmark" : "plus")
                        .symbolRenderingMode(addDidCommit ? .multicolor : .hierarchical)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .matchedGeometryEffect(id: "add-icon", in: addNS)
        }

        private var addFullPill: some View {
            let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)

            return HStack(spacing: 8) {
                addIcon
                Text(addWord)
                    .fontWeight(.regular)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.9)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            .frame(height: ctl)
            .padding(.horizontal, 12)
            .background(
                Color.clear
                    .matchedGeometryEffect(id: "add-bg", in: addNS)
                    .modifier(GlassWhiteRoundedRect(corner: corner))
            )
            .contentShape(rr)
        }

        private var addCompactPill: some View {
            let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)

            return addIcon
                .frame(width: addCompactSide, height: ctl)
                .background(
                    Color.clear
                        .matchedGeometryEffect(id: "add-bg", in: addNS)
                        .modifier(GlassWhiteRoundedRect(corner: corner))
                )
                .contentShape(rr)
        }

        

        private var addButton: some View {
            Button {
                let refs = store.selectionRefs(pivot: store.pivot, axisShift: store.axisShift)
                let payload: ScaleBuilderPayload
#if DEBUG
                let draftHash = AppModel.debugDegreeHash(app.builderSession.draftDegrees)
                let pendingCount = app.builderSession.pendingAddRefs?.count ?? 0
                print("[Builder+Tray] loadedScaleID=\(app.builderSession.savedScaleID?.uuidString ?? "nil") draftCount=\(app.builderSession.draftDegrees.count) draftHash=\(draftHash) payloadRefs=\(refs.count) pendingAddRefs=\(pendingCount)")
#endif
                if hasBuilderSession {
                    app.appendBuilderDraftRefs(refs)
                    if let sessionPayload = app.builderSessionPayload {
                        payload = sessionPayload
                    } else if let existing = app.builderLoadedScale {
                        payload = ScaleBuilderPayload(
                            rootHz: existing.referenceHz,
                            primeLimit: existing.detectedLimit,
                            axisShift: [:],
                            items: existing.degrees,
                            autoplayAll: app.latticeAuditionOn,
                            startInLibrary: false,
                            existing: existing
                        )
                    } else {
                        payload = ScaleBuilderPayload(
                            rootHz: app.rootHz,
                            primeLimit: app.primeLimit,
                            refs: refs
                        )
                    }
                } else {
                    payload = ScaleBuilderPayload(
                        rootHz: app.rootHz,
                        primeLimit: app.primeLimit,
                        refs: refs
                    )
                }

                // Trigger feedback *first* so it has a chance to render even if Builder presents immediately.
                if !reduceMotion {
                    withAnimation(.snappy(duration: 0.25)) { addDidCommit = true }
                } else {
                    addDidCommit = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    if !reduceMotion {
                        withAnimation(.snappy(duration: 0.22)) { addDidCommit = false }
                    } else {
                        addDidCommit = false
                    }
                }

                store.beginStaging()
                app.builderPayload = payload
            } label: {
                Group {
                    if addShowsWord {
                        ViewThatFits(in: .horizontal) {
                            addFullPill
                            addCompactPill
                        }
                    } else {
                        addCompactPill
                    }
                }
                .animation(.snappy(duration: 0.28), value: addShowsWord)
            }
            .buttonStyle(.plain)
            .disabled(store.selectedCount == 0)
            .sensoryFeedback(.success, trigger: addDidCommit)
            .accessibilityLabel("Add selected ratios")
        }

        private var libraryButton: some View {
            Button {
                store.beginStaging()
                if !isActive {
                    app.scaleLibraryLaunchMode = (emptyMode == .favorites ? .favorites : .recents)
                }
                app.showScaleLibraryDetent = true
            } label: {
                let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)

                ZStack {
                    // Wide (empty) content stays in-tree and animates out
                    HStack(spacing: 8) {
                        Image(systemName: "tray.fill")
                            .font(.footnote.weight(.bold))
                        Text("Library")
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .foregroundStyle(.black)
                    .opacity(isActive ? 0 : 1)
                    .scaleEffect(isActive ? 0.92 : 1.0)
                    .allowsHitTesting(false)

                    // Compact (active) content animates in
                    Image(systemName: "tray.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .frame(height: ctl)
                .frame(width: isActive ? ctl : nil)              // <- truly compact when active
                .padding(.horizontal, isActive ? 0 : 12)         // <- NO padding in icon-only state
                .background(
                    ZStack {
                        Color.clear
                            .modifier(GlassWhiteRoundedRect(corner: corner))
                            .opacity(isActive ? 0 : 1)
                        Color.clear
                            .modifier(GlassBlackRoundedRect(corner: corner))
                            .opacity(isActive ? 1 : 0)
                    }
                )
                .contentShape(rr)
                .animation(.snappy(duration: 0.28), value: isActive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Library")
        }


        
        private var emptyQuickToggle: some View {
            HStack(spacing: 10) {
                emptyModeCircle(.recents)
                emptyModeCircle(.favorites)
            }
        }

        private func emptyModeCircle(_ mode: EmptyMode) -> some View {
            let isSelected = (emptyMode == mode)

            return Button {
                emptyMode = mode
                store.beginStaging()
                app.scaleLibraryLaunchMode = (mode == .favorites ? .favorites : .recents)
                app.showScaleLibraryDetent = true
            } label: {
                Image(systemName: mode.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: ctl, height: ctl)
                    .modifier(GlassWhiteCircle())
                    .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 1)) // subtle base stroke
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.gray.opacity(0.28) : Color.clear, lineWidth: 1.5)
                    )
            }
            .padding(.leading, mode == .recents ? 8 : 0)   // <- more horizontal padding for the Recents circle
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel(mode.a11y)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }


        // MARK: - Main rows

        private var activeRow: some View {
            HStack(spacing: 10) {
                statusCluster
                toolsCapsule
                addButton
                libraryButton
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }


        private var emptyRow: some View {
            HStack(spacing: 10) {
                emptyQuickToggle
                Spacer(minLength: 0)
                libraryButton
            }
            .frame(maxWidth: .infinity)
        }

        // MARK: - Body

        var body: some View {
            let status = builderSessionStatus
            let railTransition: AnyTransition = reduceMotion
                ? .opacity
                : .move(edge: .bottom).combined(with: .opacity)

            return VStack(spacing: railSpacing) {
                ZStack {
                    emptyRow
                        .opacity(isActive ? 0 : 1)
                        .offset(y: isActive ? 6 : 0)
                        .allowsHitTesting(!isActive)

                    activeRow
                        .opacity(isActive ? 1 : 0)
                        .offset(y: isActive ? 0 : 6)
                        .allowsHitTesting(isActive)
                }

                if status.exists {
                    builderSessionRail
                        .transition(railTransition)
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, trayPadV) // <- reduced to keep tray height stable while controls grow
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: isActive)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: status.exists)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.2), value: status.isEdited)
            .frame(maxWidth: .infinity)
            .modifier(_SelectionTrayContainer(showsRail: status.exists, reduceTransparency: reduceTransparency))
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SelectionTrayHeightKey.self, value: proxy.size.height)
                }
            )
        }

    }

    // MARK: - Container polish (heavier than AxisShiftHUD)

    private struct _SelectionTrayContainer: ViewModifier {
        let showsRail: Bool
        let reduceTransparency: Bool

        private var strokeOpacity: Double {
            reduceTransparency ? 0.18 : (showsRail ? 0.14 : 0.10)
        }

        func body(content: Content) -> some View {
            Group {
                if #available(iOS 26.0, *) {
                    content
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.secondary.opacity(strokeOpacity), lineWidth: 1)
                        )
                } else {
                    GlassCard {
                        content
                    }
                    .overlay(
                        Group {
                            if showsRail || reduceTransparency {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.secondary.opacity(strokeOpacity), lineWidth: 1)
                            }
                        }
                    )
                }
            }
        }
    }

    
    private struct ShiftRibbonGlass: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.bottom, 4) // gap above the Utility Bar
            } else {
                content
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    
    private struct ShiftChipGlass: ViewModifier {
        let tint: Color
        let isActive: Bool
        let isPlanePrime: Bool
        
        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: shape)
                    .overlay(
                        shape.strokeBorder(
                            tint.opacity(isActive ? 0.60 : 0.30),
                            lineWidth: 1
                        )
                    )
                    .overlay(
                        Group {
                            if isActive && !isPlanePrime {
                                shape.fill(tint.opacity(0.06))
                            }
                        }
                    )
            } else {
                content
                    .background(.thinMaterial, in: shape)
                    .overlay {
                        if isActive { shape.fill(tint.opacity(0.14)) }
                    }
                    .overlay(
                        shape.strokeBorder(tint.opacity(isActive ? 0.18 : 0.32), lineWidth: 1)
                    )
            }
        }
    }

    

    private let gridMinZoom: CGFloat = 48   // threshold (B)

    private func gridStride(for zoom: CGFloat) -> Int {
        // stepwise subsample (B)
        if zoom < (gridMinZoom + 14) { return 6 }
        if zoom < (gridMinZoom + 44) { return 3 }
        return 1
    }

    private func gridBasisUV() -> (u: CGPoint, v: CGPoint) {
        let o = layout.position(for: LatticeCoord(e3: 0, e5: 0))
        let u1 = layout.position(for: LatticeCoord(e3: 1, e5: 0))
        let v1 = layout.position(for: LatticeCoord(e3: 0, e5: 1))
        return (
            CGPoint(x: u1.x - o.x, y: u1.y - o.y),
            CGPoint(x: v1.x - o.x, y: v1.y - o.y)
        )
    }

    private func drawGrid(ctx: inout GraphicsContext, viewRect: CGRect) {
        guard gridMode != .off else { return }


        let zoom = store.camera.appliedScale
        guard zoom >= gridMinZoom else { return }

        let isDark = effectiveIsDark

        let w = LatticeGridWeight.fromStrength01(gridStrength)
        let baseAlpha = w.strokeAlpha
        let baseWidth = w.strokeWidth

        guard baseAlpha > 0.001 else { return }

        let majorAlpha = w.majorStrokeAlpha
        let majorWidth = w.majorStrokeWidth

        let tintA = activeTheme.primeTint(3)
        let tintB = activeTheme.primeTint(5)

        let tintShade = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [tintA, tintB]),
            startPoint: CGPoint(x: viewRect.minX, y: viewRect.minY),
            endPoint: CGPoint(x: viewRect.maxX, y: viewRect.maxY)
        )

        let highlightColor: Color = isDark ? .white : .black
        let tintBlend: GraphicsContext.BlendMode = isDark ? .screen : .multiply

        let (u0, v0) = gridBasisUV()

        let step = gridStride(for: zoom)
        let pad: CGFloat = 90

        let pivotWorld = layout.position(for: store.pivot)
        let pivotScreen = store.camera.worldToScreen(pivotWorld)
        let maxR = maxRadius(from: pivotScreen, in: viewRect)

        func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
        func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
        func mul(_ a: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }

        func fade(at sp: CGPoint) -> CGFloat {
            let d = hypot(sp.x - pivotScreen.x, sp.y - pivotScreen.y)
            let t = clamp01(1 - d / maxR)

            // Boost low-t so the grid doesn't die near the edges.
            // 0.70 = slower fade; try 0.60 (even slower) .. 0.85 (closer to current).
            let boosted = CGFloat(pow(Double(t), 0.70))
            return smoothstep(boosted)
        }

        func hexPath(centerWorld: CGPoint, u: CGPoint, v: CGPoint) -> Path {
            // Voronoi hex for triangular lattice: corners = ±(u+v)/3, ±(2u-v)/3, ±(u-2v)/3
            let a = mul(add(u, v), 1.0 / 3.0)
            let b = mul(sub(mul(u, 2), v), 1.0 / 3.0)
            let c = mul(sub(u, mul(v, 2)), 1.0 / 3.0)

            let cornersWorld: [CGPoint] = [
                add(centerWorld, a),
                add(centerWorld, b),
                add(centerWorld, c),
                sub(centerWorld, a),
                sub(centerWorld, b),
                sub(centerWorld, c)
            ]

            let corners = cornersWorld.map { store.camera.worldToScreen($0) }

            var p = Path()
            if let first = corners.first {
                p.move(to: first)
                for pt in corners.dropFirst() { p.addLine(to: pt) }
                p.closeSubpath()
            }
            return p
        }

        func shouldDraw(_ sp: CGPoint) -> Bool {
            sp.x >= viewRect.minX - pad &&
            sp.x <= viewRect.maxX + pad &&
            sp.y >= viewRect.minY - pad &&
            sp.y <= viewRect.maxY + pad
        }
        
        func drawHexCellsPass(step: Int, alphaBase: CGFloat, lineWidth: CGFloat, emphasizePivot: Bool) {
            let u = mul(u0, CGFloat(step))
            let v = mul(v0, CGFloat(step))

            let R = Int(max(12, min(96, zoom / 2)))
            let pad: CGFloat = 90

            for de3 in stride(from: -R, through: R, by: step) {
                for de5 in stride(from: -R, through: R, by: step) {
                    let coord = LatticeCoord(e3: store.pivot.e3 + de3, e5: store.pivot.e5 + de5)
                    let cw = layout.position(for: coord)
                    let cs = store.camera.worldToScreen(cw)

                    if cs.x < viewRect.minX - pad || cs.x > viewRect.maxX + pad ||
                       cs.y < viewRect.minY - pad || cs.y > viewRect.maxY + pad { continue }

                    let f = fade(at: cs)
                    var a = alphaBase * f
                    if a < 0.003 { continue }

                    let isPivotCell = (de3 == 0 && de5 == 0)
                    if emphasizePivot && isPivotCell { a *= 1.25 }

                    let hex = hexPath(centerWorld: cw, u: u, v: v)

                    // Fill (subtle “cell” presence)
                    var g = ctx
                    g.opacity = a * 0.55
                    g.fill(hex, with: tintShade)

                    // Light etched outline for definition
                    var o = ctx
                    o.opacity = a * 0.85
                    o.stroke(hex, with: .color(highlightColor.opacity(isDark ? 0.18 : 0.12)), lineWidth: lineWidth * 0.75)
                    o.blendMode = tintBlend
                    o.stroke(hex, with: tintShade, lineWidth: lineWidth * 0.85)
                }
            }
        }


        func drawHexPass(step: Int, alphaBase: CGFloat, lineWidth: CGFloat, emphasizePivot: Bool) {
            let u = mul(u0, CGFloat(step))
            let v = mul(v0, CGFloat(step))

            // radius tuned to match view coverage without going insane
            let R = Int(max(12, min(96, zoom / 2)))

            for de3 in stride(from: -R, through: R, by: step) {
                for de5 in stride(from: -R, through: R, by: step) {
                    let coord = LatticeCoord(e3: store.pivot.e3 + de3, e5: store.pivot.e5 + de5)
                    let cw = layout.position(for: coord)
                    let cs = store.camera.worldToScreen(cw)
                    if !shouldDraw(cs) { continue }

                    let f = fade(at: cs)
                    var a = alphaBase * f
                    if a < 0.003 { continue }

                    let isPivotCell = (de3 == 0 && de5 == 0)
                    var lw = lineWidth
                    if emphasizePivot && isPivotCell {
                        a *= 1.35
                        lw *= 1.20
                    }

                    let hex = hexPath(centerWorld: cw, u: u, v: v)

                    // etched: faint bevel + tinted etch
                    var g = ctx
                    g.opacity = a

                    g.stroke(hex, with: .color(highlightColor.opacity(isDark ? 0.26 : 0.18)), lineWidth: lw * 0.80)

                    g.blendMode = tintBlend
                    g.stroke(hex, with: tintShade, lineWidth: lw)
                }
            }
        }

        func drawTriMeshPass(step: Int, alphaBase: CGFloat, lineWidth: CGFloat, emphasizePivot: Bool) {
            let u = mul(u0, CGFloat(step))
            let v = mul(v0, CGFloat(step))

            let R = Int(max(12, min(96, zoom / 2)))
            var segments: [(CGPoint, CGPoint, CGFloat, Bool)] = []

            for de3 in stride(from: -R, through: R, by: step) {
                for de5 in stride(from: -R, through: R, by: step) {
                    let coord = LatticeCoord(e3: store.pivot.e3 + de3, e5: store.pivot.e5 + de5)
                    let cw = layout.position(for: coord)
                    let cs = store.camera.worldToScreen(cw)
                    if !shouldDraw(cs) { continue }

                    let f = fade(at: cs)
                    var a = alphaBase * f
                    if a < 0.003 { continue }

                    let isPivotCell = (de3 == 0 && de5 == 0)
                    if emphasizePivot && isPivotCell { a *= 1.35 }

                    let p0 = cs
                    let pU = store.camera.worldToScreen(add(cw, u))
                    let pV = store.camera.worldToScreen(add(cw, v))
                    let pVU = store.camera.worldToScreen(add(cw, sub(v, u)))

                    segments.append((p0, pU, a, isPivotCell))
                    segments.append((p0, pV, a, isPivotCell))
                    segments.append((p0, pVU, a, isPivotCell))
                }
            }

            for (aPt, bPt, a, isPivot) in segments {
                var lw = lineWidth
                var aa = a
                if emphasizePivot && isPivot { lw *= 1.25 }

                var g = ctx
                g.opacity = aa
                var p = Path()
                p.move(to: aPt)
                p.addLine(to: bPt)

                g.stroke(p, with: .color(highlightColor.opacity(isDark ? 0.24 : 0.16)), lineWidth: lw * 0.80)
                g.blendMode = tintBlend
                g.stroke(p, with: tintShade, lineWidth: lw)
            }
        }

        switch gridMode {
        case .off:
            return

        case .outlines:
            drawHexPass(step: step, alphaBase: baseAlpha, lineWidth: baseWidth, emphasizePivot: true)
            if gridMajorEnabled {
                drawHexPass(step: step * gridMajorEveryClamped, alphaBase: majorAlpha, lineWidth: majorWidth, emphasizePivot: true)
            }

        case .cells:
            drawHexCellsPass(step: step, alphaBase: baseAlpha, lineWidth: baseWidth, emphasizePivot: true)
            if gridMajorEnabled {
                drawHexPass(step: step * gridMajorEveryClamped, alphaBase: majorAlpha, lineWidth: majorWidth, emphasizePivot: true)
            }

        case .triMesh:
            drawTriMeshPass(step: step, alphaBase: baseAlpha, lineWidth: baseWidth, emphasizePivot: true)
            if gridMajorEnabled {
                drawTriMeshPass(step: step * gridMajorEveryClamped, alphaBase: majorAlpha, lineWidth: majorWidth, emphasizePivot: true)
            }
        }

    }

    
    
    
    
    /// Long-press to set pivot (nearest plane node to last tap)
    private func longPresser(viewRect: CGRect) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .onEnded { _ in
                if let cand = hitTestCandidate(at: lastTapPoint, viewRect: viewRect),
                   cand.isPlane, let c = cand.coord {
                    store.setPivot(c)
                }
            }
    }
    @ViewBuilder
    private func canvasLayer(viewRect: CGRect) -> some View {
        TimelineView(.animation) { _ in
            Canvas(rendersAsynchronously: true) { ctx, _ in
                let now = CACurrentMediaTime()
                // Nodes on 3×5 plane (with shift applied)
                let radius: Int = Int(max(8, min(48, store.camera.appliedScale / 5)))
                let anyNodes = layout.planeNodes(
                    in: viewRect,
                    camera: store.camera,
                    primeLimit: app.primeLimit,
                    radius: radius,
                    shift: store.axisShift
                )
                
                guard let nodes = anyNodes as? [LatticeRenderNode] else { return }
                
                drawGrid(ctx: &ctx, viewRect: viewRect)

                // Axes
                drawAxes(ctx: &ctx)
                
                // Overlays for visible higher primes
                for p in store.renderPrimes {
                    drawOverlay(prime: p, in: &ctx, viewRect: viewRect, now: now)
                }
                
                // Plane nodes
                for node in nodes { draw(node: node, in: &ctx) }
                
                // Optional guides (line of fifths + selection path)
                if store.guidesOn {
                    // Line of fifths guide
                    var guide = Path()
                    let pivotPos: CGPoint = layout.position(for: store.pivot)
                    let left: CGPoint  = store.camera.worldToScreen(CGPoint(x: pivotPos.x - 5000, y: pivotPos.y))
                    let right: CGPoint = store.camera.worldToScreen(CGPoint(x: pivotPos.x + 5000, y: pivotPos.y))
                    guide.move(to: left); guide.addLine(to: right)
                    ctx.stroke(guide, with: .color(.accentColor.opacity(0.15)), lineWidth: 1)
                }
                
                // grid width baseline (0 if grid is off / below threshold)
                let gridW: CGFloat = {
                    guard gridMode != .off else { return 0 }
                    guard store.camera.appliedScale >= gridMinZoom else { return 0 }
                    return LatticeGridWeight.fromStrength01(gridStrength).strokeWidth
                }()

                // Selection path (always, when 2+ selections)
                let pathKeys = orderedSelectionKeysForPath()
                drawSelectionPath(
                    ctx: &ctx,
                    keys: pathKeys,
                    now: now,
                    pivot: store.pivot,
                    shift: store.axisShift,
                    camera: store.camera,
                    zoom: store.camera.appliedScale,
                    gridStrokeWidth: gridW
                )

                // Selection rims on top (selected + animating-off)
                do {
                    let pivotSnapshot = store.pivot
                    let shiftSnapshot = store.axisShift
                    let cameraSnapshot = store.camera
                    let zoom = store.camera.appliedScale
                    let keys = store.selectionKeysToDraw()

                    // Focus info (plane only)
                    let focusedPlane: LatticeCoord? = focusedPoint?.coord
                    let scheme = systemScheme

                    // Precompute focused prime ticks once (if available)
                    var focusedTicks: [(prime: Int, exp: Int)] = []
                    if let fp = focusedPoint {
                        let prioritized = [3,5,7,11,13,17,19,23,29,31]
                        let exps = primeExponentMap(num: fp.num, den: fp.den, primes: prioritized)
                        focusedTicks = prioritized.compactMap { p in
                            guard let e = exps[p], e != 0 else { return nil }
                            return (p, e)
                        }
                    }

                    for key in keys {
                        let sp = selectionScreenPoint(for: key, pivot: pivotSnapshot, shift: shiftSnapshot, camera: cameraSnapshot)
                        let nodeR = selectionNodeRadius(for: key, pivot: pivotSnapshot, shift: shiftSnapshot)
                        let tint = selectionTint(for: key, pivot: pivotSnapshot, shift: shiftSnapshot)

                        let phase = store.selectionPhase(for: key, now: now)
                        let isFocused: Bool = {
                            guard case .plane(let c) = key else { return false }
                            return (focusedPlane == c)
                        }()

                        drawSelectionRim(
                            ctx: &ctx,
                            center: sp,
                            nodeR: nodeR,
                            tint: tint,
                            focused: isFocused,
                            phase: phase,
                            now: now,
                            zoom: zoom,
                            scheme: scheme,
                            primeTicks: isFocused ? focusedTicks : []
                        )
                    }
                }

            }
            .id(
                "canvas-\(themeIDRaw)-\(themeStyleRaw)" +
                    "-grid:\(gridModeRaw)" +
                    "-st:\(Int(gridStrengthRaw * 100))" +
                    "-mj:\(gridMajorEnabled ? 1 : 0)" +
                    "-me:\(gridMajorEvery)"
            )

            .allowsHitTesting(false)
        }
    }
    @ViewBuilder
    private func latticeStack(in geo: GeometryProxy) -> some View {
        let viewRect = CGRect(origin: .zero, size: geo.size)
        
        ZStack {
            canvasLayer(viewRect: viewRect)
                .allowsHitTesting(false)
#if os(macOS) || targetEnvironment(macCatalyst)
                .overlay(alignment: .topLeading) {
                    LatticeTrackpadBridge(
                        onPointer: { loc in
                            pointerInLattice = loc
                            logPointer(loc)
#if targetEnvironment(macCatalyst)
                            updateContextTarget(at: loc, in: geo.size)
#endif
                        },
                        onScrollPan: { delta in
                            applyTrackpadPan(delta: delta)
                        },
                        onZoom: { factor in
                            let anchor = zoomAnchor(in: geo)
                            applyZoom(by: factor, anchor: anchor)
                        },
                        onHover: { hovering in
                            isHoveringLattice = hovering
                            if !hovering {
                                pointerInLattice = nil
#if targetEnvironment(macCatalyst)
                                contextTarget = nil
#endif
                            }
                        }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .zIndex(0)
                }
#endif
            
            gestureCatcher(in: geo, viewRect: viewRect)
                .zIndex(1)
            
            chipsOverlayLayer
                .zIndex(2)
            
            infoOverlayLayer
                .zIndex(3)
            
            bottomHUDLayer
                .zIndex(4)
            
            
        }
        .onAppear {
            latticeViewSize = geo.size
            if latticePreviewMode {
                withAnimation(.snappy) { store.resetView(in: geo.size) }
                return
            }
            
            // Always-recenter: only fires after a *cold relaunch* (pending was set when the app went to background).
                        if latticeAlwaysRecenterOnQuit && latticeRecenterPending {
                            latticeRecenterPending = false
                            withAnimation(.snappy) { store.resetView(in: geo.size) }
                            return
                        }
            
            // First-run/no-persist fallback: if translation is still zero, center using default zoom
            if store.camera.translation == .zero {
                store.camera.center(in: geo.size, scale: store.defaultZoomScale())
            }
        }
        .onChange(of: geo.size) { latticeViewSize = $0 }
    }
    
    @ViewBuilder
    private func gestureCatcher(in geo: GeometryProxy, viewRect: CGRect) -> some View {
        let pan   = panGesture()
        let pinch = pinchGesture(in: geo)
        let tap   = tapper(viewRect: viewRect)
        let press = longPresser(viewRect: viewRect)
        let brush = brushGesture(in: geo, viewRect: viewRect)
        
        let activeHeight = max(0, geo.size.height - bottomHUDHeight)
        
        VStack(spacing: 0) {
            Color.clear
                .frame(height: activeHeight)
                .contentShape(Rectangle())
                .simultaneousGesture(pan, including: .gesture)
                .simultaneousGesture(pinch, including: .gesture)
                .simultaneousGesture(tap, including: .gesture)
                .simultaneousGesture(press, including: .gesture)
                .simultaneousGesture(brush, including: .gesture)

            
            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var chipsOverlayLayer: some View {
        VStack {
            HStack {
                if !latticePreviewMode && !latticePreviewHideChips {
                    VStack(alignment: .leading, spacing: 8) {
                        overlayChips
                    }
                    .padding(8)
#if os(macOS) || targetEnvironment(macCatalyst)
                    .padding(.top, 20)
                    .padding(.leading, 164)
#endif
                    .allowsHitTesting(true)
                }
                
                Spacer()
            }
            Spacer()
        }
    }
    
    private var infoOverlayLayer: some View {
        VStack {
            HStack {
                Spacer()
                if focusedPoint != nil {
                    infoCard
                        .padding(.top, infoCardTopPad)
                        .padding(.trailing, 12)
                        .frame(maxWidth: infoCardMaxWidth, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                }
            }
            Spacer()
        }
    }
    
    private var bottomHUDLayer: some View {
        VStack {
            Spacer()
            if !latticePreviewMode {
                VStack(spacing: 8) {
                    SelectionTray(
                        store: store,
                        app: app,
                        stopInfoPreview: { hard in releaseInfoVoice(hard: hard) }
                    )

                    AxisShiftHUD(
                        store: store,
                        app: app,
                        tint: { activeTheme.primeTint($0) }
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BottomHUDHeightKey.self, value: proxy.size.height)
                    }
                )
            }
        }
        .allowsHitTesting(!latticePreviewMode)
    }
    
    @ToolbarContentBuilder
    private var clearToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Clear") { store.clearSelection() }
        }
    }
    
    @ViewBuilder
    private var tenneyOverlay: some View {
        if !latticePreviewMode &&
           !latticePreviewHideDistance &&
           store.tenneyDistanceMode != .off {

            let nodes = tenneyDistanceNodes()
            if nodes.count == 2 {
                TenneyDistanceOverlay(
                    a: nodes[0],
                    b: nodes[1],
                    mode: store.tenneyDistanceMode,
                    theme: activeTheme
                )
                .allowsHitTesting(false)
            }
        }
    }
    
    
    
    private func applySettingsChanged(_ note: Notification) {
        if let v = note.userInfo?[SettingsKeys.tenneyThemeID] as? String { themeIDRaw = v }
        if let v = note.userInfo?[SettingsKeys.latticeThemeID] as? String { themeIDRaw = v } // legacy sender
        if let v = note.userInfo?[SettingsKeys.latticeThemeStyle] as? String { themeStyleRaw = v }
        
        // Settings preview: if default zoom preset changes, re-apply default zoom immediately.
        guard latticePreviewMode else { return }
        guard note.userInfo?[SettingsKeys.latticeDefaultZoomPreset] != nil else { return }
        guard latticeViewSize != .zero else { return }
        withAnimation(.snappy) { store.resetView(in: latticeViewSize) }
    }
    
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                        TenneySceneBackground(
                            isDark: effectiveIsDark,
                            preset: activeTheme.sceneBackgroundPreset,
                            tintA: activeTheme.primeTint(3),
                            tintB: activeTheme.primeTint(5)
                        )
            
                        latticeStack(in: geo)
                            .sensoryFeedback(.selection, trigger: selectionHapticTick)
                            .sensoryFeedback(.selection, trigger: focusHapticTick)
                            .navigationTitle("Lattice")
                            .toolbar { clearToolbar }
                            .onPreferenceChange(SelectionTrayHeightKey.self) { trayHeight = $0 }
                            .onPreferenceChange(BottomHUDHeightKey.self) { bottomHUDHeight = $0 }
                    }
            .onAppear { viewSize = geo.size }
            .onChange(of: geo.size) { viewSize = $0 }
#if targetEnvironment(macCatalyst)
            .contextMenu { latticeContextMenu() }
            .catalystCursor(currentCursor)
#elseif os(macOS)
            .background(
                MacMouseTrackingView(
                    onMove: { loc in
                        lastPointerLocation = loc
                        logPointer(loc)
                    },
                    onScroll: { delta, loc in
                        lastPointerLocation = loc
                        logPointer(loc)
                        applyTrackpadPan(delta: delta)
                    }
                )
                .allowsHitTesting(false)
            )
#endif
            .onChange(of: latticeSoundEnabled) { enabled in
                guard !enabled else { return }
                // ✅ kill any local preview voice immediately
                releaseInfoVoice(hard: true)
                // ✅ also stop any selection audition/sustain currently running
                stopAllLatticeVoices(hard: true)
            }

                .onReceive(NotificationCenter.default.publisher(for: .settingsChanged)) { note in
                    applySettingsChanged(note)
                    
                    // ✅ make default zoom preset changes affect the live view too
                    guard note.userInfo?[SettingsKeys.latticeDefaultZoomPreset] != nil else { return }
                    
                    if latticePreviewMode {
                        withAnimation(.snappy) { store.resetView(in: geo.size) }
                    } else {
                        withAnimation(.snappy) { store.camera.scale = store.defaultZoomScale() }
                    }
                }
            
                .overlay { tenneyOverlay }
                .onChange(of: latticePreviewMode) { isPreview in
                    if isPreview { bottomHUDHeight = 0 }
                }
                .onReceive(NotificationCenter.default.publisher(for: .tenneyBuilderDidFinish)) { note in
                    let u = note.userInfo

                    if (u?["clearSelection"] as? Bool) == true {
                        withAnimation(.snappy) { store.clearSelection() }
                    }

                    if (u?["endStaging"] as? Bool) == true {
                        DispatchQueue.main.async {
                            store.endStaging()
                        }
                    } else if (u?["resetDelta"] as? Bool) == true {
                        // Canonical “baseline reset” you already have (used when starting builder/staging).
                        // This is the safest no-regression primitive if it exists.
                        DispatchQueue.main.async {
                            store.beginStaging()
                        }
                    }
                }
                .onChange(of: app.builderLoadedScale?.id) { id in
                    if id != nil {
                        store.captureLoadedScaleBaseline()
                    } else {
                        store.clearLoadedScaleBaseline()
                    }
                    app.updateBuilderSessionEdited(
                        loadedScaleEdited: store.loadedScaleEdited,
                        metadataEdited: app.loadedScaleMetadataEdited
                    )
                }
                .onChange(of: store.loadedScaleEdited) { edited in
                    app.updateBuilderSessionEdited(
                        loadedScaleEdited: edited,
                        metadataEdited: app.loadedScaleMetadataEdited
                    )
                }
                .onChange(of: app.loadedScaleMetadataEdited) { edited in
                    app.updateBuilderSessionEdited(
                        loadedScaleEdited: store.loadedScaleEdited,
                        metadataEdited: edited
                    )
                }

                .onChange(of: store.selected) { newValue in
                    if let fp = focusedPoint, let c = fp.coord, !newValue.contains(c), !autoSelectInFlight {
                        releaseInfoVoice()
                        withAnimation(.easeOut(duration: 0.2)) { focusedPoint = nil }
                    }
                    if newValue.isEmpty, !autoSelectInFlight { releaseInfoVoice() }

                    if !newValue.isEmpty {
                        LearnEventBus.shared.send(.latticeNodeSelected("selected"))
                    }
                }
#if os(macOS) || targetEnvironment(macCatalyst)
                .scrollDisabled(isHoveringLattice)
#endif

        }
    }
    
    
    
    // MARK: - Drawing helpers
    private func drawAxes(ctx: inout GraphicsContext) {
        let origin = store.camera.worldToScreen(.zero)
        // e3 axis
        var path = Path(); path.move(to: origin)
        path.addLine(to: store.camera.worldToScreen(CGPoint(x: 1000, y: 0)))
        ctx.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
        // e5 axis (60°)
        path = Path()
        let angle = Double.pi / 3
        let e5End = CGPoint(x: CGFloat(cos(angle) * 1000), y: -CGFloat(sin(angle) * 1000))
        path.move(to: origin); path.addLine(to: store.camera.worldToScreen(e5End))
        ctx.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
    }
    
    
    private func draw(node: LatticeRenderNode, in ctx: inout GraphicsContext) {
        let sp = store.camera.worldToScreen(node.pos)
        let base = nodeBaseSize()
        let lift = CGFloat(18.0 * (1.0 / sqrt(Double(node.tenneyHeight))))
        let sz = max(8, base + lift)
        
        let rect = CGRect(x: sp.x - sz * 0.5, y: sp.y - sz * 0.5, width: sz, height: sz)
        
        let fill: Color = activeTheme.nodeColor(e3: node.coord.e3, e5: node.coord.e5)
        let alpha = min(1.0, 0.35 + 2.0 / sqrt(Double(node.tenneyHeight)))
        
        let circle = Path(ellipseIn: rect)

        // base tint
        ctx.fill(circle, with: .color(fill.opacity(alpha)))

        // glass depth + sheen (clipped)
        var g = ctx
        g.clip(to: circle)

        // depth: brighter TL → darker BR
        let depth = USE_STOP_GRADIENTS
        ? Gradient(stops: [
            .init(color: Color.white.opacity(0.10 * alpha), location: 0.00),
            .init(color: Color.white.opacity(0.05 * alpha), location: 0.38),
            .init(color: Color.black.opacity(0.08 * alpha), location: 1.00)
        ])
        : Gradient(colors: [
            Color.white.opacity(0.10 * alpha),
            Color.white.opacity(0.05 * alpha),
            Color.black.opacity(0.08 * alpha)
        ])
        g.fill(circle, with: .radialGradient(
            depth,
            center: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.26),
            startRadius: 0,
            endRadius: rect.width * 0.78
        ))

        // rim / bevel (crisper “glass” edge)
        ctx.stroke(circle, with: .color(Color.white.opacity(0.18 * alpha)), lineWidth: 1.0)
        ctx.stroke(circle, with: .color(Color.black.opacity(0.08 * alpha)), lineWidth: 0.7)

        // --- label (ratio / HEJI) ---
        if shouldDrawPlaneLabel(coord: node.coord),
           let label = planeLabelText(for: node.coord) {

            let zoomT = clamp01((store.camera.appliedScale - 42) / 70)
            let a: CGFloat = 0.85 * zoomT * CGFloat(labelDensity)
            if a > 0.02 {
                let text = Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(Double(a)))

                ctx.draw(
                    text,
                    at: CGPoint(x: sp.x, y: sp.y - sz * 0.85 - 6),
                    anchor: .center
                )
            }
        }

    }
    
    
    
    private func overlayColor(forPrime p: Int) -> Color {
        activeTheme.primeTint(p)
    }
    
    
    private func drawOverlay(prime p: Int, in ctx: inout GraphicsContext, viewRect: CGRect, now: Double) {
        let center = store.camera.worldToScreen(.zero)
        let maxR = maxRadius(from: center, in: viewRect)

        // Skip period (2) and plane primes (3,5)
        guard p != 2 && p != 3 && p != 5 else { return }

        // Phase once (no per-ep duplication)
        let phase = store.inkPhase(for: p, now: now)
        let isVisible = store.visiblePrimes.contains(p)
        let isAnimating = (phase != nil)

        if !isVisible && !isAnimating { return }

        let targetOn: Bool = phase?.targetOn ?? true
        let tNorm: CGFloat = phase?.t ?? 1.0
        let dur: Double = phase?.duration ?? 0.65

        let col = overlayColor(forPrime: p)

        // Base exponents from pivot + axis shift on the plane
        let e3 = store.pivot.e3 + (store.axisShift[3] ?? 0)
        let e5 = store.pivot.e5 + (store.axisShift[5] ?? 0)
        let shiftP = store.axisShift[p] ?? 0

        let epSpan = max(6, min(12, Int(store.camera.appliedScale / 8)))

        // (recommended) skip far-offscreen points
        let pad: CGFloat = 60

        for ep in (-epSpan...epSpan) where ep != 0 {
            let eP = ep + shiftP

            let monzo: [Int:Int] = [3: e3, 5: e5, p: eP]
            let world = layout.position(monzo: monzo)
            let sp = store.camera.worldToScreen(world)

            if sp.x < viewRect.minX - pad || sp.x > viewRect.maxX + pad || sp.y < viewRect.minY - pad || sp.y > viewRect.maxY + pad {
                continue
            }

            let dist = hypot(sp.x - center.x, sp.y - center.y)

            // presence wave only while animating; steady-state draws crisp-only at full strength
            let local: CGFloat = {
                guard isAnimating else { return 1.0 }

                let bandPx: CGFloat = 160
                let bandT: CGFloat = max(0.035, min(0.22, bandPx / maxR))

                let hitT = dist / maxR
                let jitter = inkJitterFrac(prime: p, e3: e3, e5: e5, eP: eP, duration: dur)
                let x = (tNorm - (hitT + jitter)) / bandT
                let wave = smoothstep(x)
                return targetOn ? wave : (1 - wave)
            }()

            if local <= 0.001 { continue }

            guard let (num, den) = overlayPQ(e3: e3, e5: e5, prime: p, eP: eP) else { continue }
            let tenney = max(num, den)

            let base = nodeBaseSize()
            let lift = CGFloat(18.0 * (1.0 / sqrt(Double(tenney))))
            let sz = max(8, base + lift)

            let scale: CGFloat = {
                guard isAnimating else { return 1.0 } // steady-state: no overshoot

                let inkT = min(1, local / 0.60)
                let popT = max(0, min(1, (local - 0.60) / 0.40))

                let pop = easeOutBack(popT)
                let punch = CGFloat(min(1.0, 1.7 / sqrt(Double(tenney))))
                let overshootAmt: CGFloat = 0.06 * punch
                let overshoot = 1 + overshootAmt * (pop - popT)

                let appearScale = lerp(0.92, 1.0, inkT) * overshoot
                let offScale = 0.97 + 0.03 * local
                return targetOn ? appearScale : offScale
            }()

            let rr = (sz * 0.5) * scale
            let rect = CGRect(x: sp.x - rr, y: sp.y - rr, width: rr * 2, height: rr * 2)

            // match plane-node “normal” feel; only modulate during animation
            let baseAlpha = min(1.0, 0.35 + 2.0 / sqrt(Double(tenney)))
            let alpha: CGFloat = isAnimating ? (baseAlpha * local) : baseAlpha

            // ✅ crisp ONLY (no bloom / blur / screen passes)
            let circle = Path(ellipseIn: rect)

            // base tint
            ctx.fill(circle, with: .color(col.opacity(alpha)))

            // glass depth + sheen (clipped)
            var g = ctx
            g.clip(to: circle)

            let depth = USE_STOP_GRADIENTS
            ? Gradient(stops: [
                .init(color: Color.white.opacity(0.14 * alpha), location: 0.00),
                .init(color: Color.white.opacity(0.04 * alpha), location: 0.40),
                .init(color: Color.black.opacity(0.12 * alpha), location: 1.00)
            ])
            : Gradient(colors: [
                Color.white.opacity(0.14 * alpha),
                Color.white.opacity(0.04 * alpha),
                Color.black.opacity(0.12 * alpha)
            ])
            g.fill(circle, with: .radialGradient(
                depth,
                center: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.26),
                startRadius: 0,
                endRadius: rect.width * 0.78
            ))


            // rim / bevel (keep prime tint identity)
            ctx.stroke(circle, with: .color(col.opacity(0.40 * alpha)), lineWidth: 1.0)
            ctx.stroke(circle, with: .color(Color.white.opacity(0.14 * alpha)), lineWidth: 0.8)


            // ✅ labels for 7+ overlays (ratio / HEJI), analogous to plane nodes
            if shouldDrawOverlayLabel(ep: ep),
               let label = overlayLabelText(num: num, den: den) {

                let zoomT = clamp01((store.camera.appliedScale - 52) / 80)
                let a: CGFloat = 0.85 * zoomT * CGFloat(labelDensity)
                let labelA: CGFloat = isAnimating ? (a * local) : a

                if labelA > 0.02 {
                    let text = Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(Double(labelA)))

                    ctx.draw(
                        text,
                        at: CGPoint(x: sp.x, y: sp.y - sz * 0.85 - 6),
                        anchor: .center
                    )
                }
            }
        }
    }
    
    // MARK: - Overlays (UI)
    private var overlayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            let primes = overlayChipPrimes

            HStack(spacing: 6) {
                ForEach(primes, id: \.self) { p in
                    let on = store.visiblePrimes.contains(p)

                    GlassChip(
                        title: on ? "● \(p)" : "○ \(p)",
                        active: on,
                        color: activeTheme.primeTint(p)
                    ) {
                        // If a long-press just fired, swallow the “button tap” that can follow on release.
                        if overlayPrimeHoldConsumedTap {
                            overlayPrimeHoldConsumedTap = false
                            return
                        }
                        store.setPrimeVisible(p, !on, animated: true)
                    }
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .onEnded { _ in
                                overlayPrimeHoldConsumedTap = true
                                // Clear even if the underlying button doesn’t fire.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    overlayPrimeHoldConsumedTap = false
                                }
                                toggleAllOverlayChipPrimes()
                            }
                        , including: .gesture)
                }
            }
            .padding(8)
        }
#if os(macOS) || targetEnvironment(macCatalyst)
        .scaleEffect(1.3)
#endif
    }

    
    
    
    @AppStorage("Tenney.SoundOn") private var soundOn: Bool = true
    private func postStep(idx: Int, delta: Int) {
        NotificationCenter.default.post(name: .tenneyStepPadOctave,
                                        object: nil,
                                        userInfo: ["idx": idx, "delta": delta])
    }
    
    private var infoCard: some View {
        Group {
            if let f = focusedPoint {
                if #available(iOS 26.0, *) {
                    infoCardBody(f)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        .padding(.horizontal, 8)
                } else {
                    GlassCard { infoCardBody(f) }
                        .padding(.horizontal, 8)
                }
            }
        }
    }
    private struct DrawerGlassButton: View {
        let title: String
        let systemImage: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if #available(iOS 26.0, *) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.clear)
                                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func infoCardBody(
        _ f: (pos: CGPoint, label: String, etCents: Double, hz: Double, coord: LatticeCoord?, num: Int, den: Int)
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Adjusted frequency for staff + metrics (unfolded for display)
            let baseHz = foldToAudible(app.rootHz * (Double(f.num) / Double(f.den)), minHz: 20, maxHz: 5000)
            let hzAdj = baseHz * pow(2.0, Double(infoOctaveOffset))
            let pref = AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
            let helmholtzPref = helmholtzPreference(from: pref)
            let noteLabel = NotationFormatter.closestHelmholtzLabel(
                freqHz: hzAdj,
                a4Hz: staffA4Hz,
                preference: helmholtzPref
            )
            // Adjusted ratio string (NO FOLD to 1–2; preserves +/- octaves in ratio)
            let (adjP, adjQ) = ratioWithOctaveOffsetNoFold(num: f.num, den: f.den, offset: infoOctaveOffset)
            let jiText: String = (store.labelMode == .ratio)
            ? "\(adjP)/\(adjQ)"
            : hejiTextLabel(p: f.num, q: f.den, octave: infoOctaveOffset, rootHz: app.rootHz)
            let ratioRef = RatioRef(p: f.num, q: f.den, octave: infoOctaveOffset, monzo: [:])
            let hejiContext = HejiContext(
                referenceA4Hz: staffA4Hz,
                rootHz: app.rootHz,
                rootRatio: nil,
                preferred: pref,
                maxPrime: max(3, app.primeLimit),
                allowApproximation: false,
                scaleDegreeHint: ratioRef
            )
            
            // Octave step availability (audible range)
            let nextUpHz   = baseHz * pow(2.0, Double(infoOctaveOffset + 1))
            let nextDownHz = baseHz * pow(2.0, Double(infoOctaveOffset - 1))
            let canUp   = nextUpHz   >= 20 && nextUpHz   <= 5000
            let canDown = nextDownHz >= 20 && nextDownHz <= 5000
            
            HStack(alignment: .top, spacing: 10) {
                // Left: names/metrics
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        if store.labelMode == .heji {
                            HejiPitchLabel(context: hejiContext, pitch: .ratio(ratioRef))
                        } else {
                            Text(noteLabel)
                                .font(.title2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            Text(jiText)
                                .font(.headline.monospaced())
                                .opacity(0.9)
                        }
                        
                        // ( +n oct ) badge while offset active
                        if infoOctaveOffset != 0 {
                            Text("(\(infoOctaveOffset > 0 ? "+\(infoOctaveOffset)" : "\(infoOctaveOffset)") oct)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                    HStack(spacing: 12) {
                        // keep your ET text; use adjusted Hz for cents if desired
                        Text(String(format: "%+.1f¢ vs ET", RatioMath.centsFromET(freqHz: hzAdj, refHz: app.rootHz)))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(String(format: "%.1f Hz", hzAdj))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 6)
                
                // Right: octave steppers at top-right + (optional) staff below
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 6) {
                        GlassPuckButton(systemName: "chevron.down", isEnabled: canDown) {
                            let newOffset = infoOctaveOffset - 1
                                let raw = app.rootHz * (Double(f.num) / Double(f.den)) * pow(2.0, Double(newOffset))
                                let hz2 = foldToAudible(raw, minHz: 20, maxHz: 5000)
                                switchInfoTone(toHz: hz2, newOffset: newOffset)
                            if let coord = f.coord, store.selected.contains(coord) {
                                store.setOctaveOffset(for: coord, to: newOffset)
                            }
                        }

                        GlassPuckButton(systemName: "chevron.up", isEnabled: canUp) {
                            let newOffset = infoOctaveOffset + 1
                                let raw = app.rootHz * (Double(f.num) / Double(f.den)) * pow(2.0, Double(newOffset))
                                let hz2 = foldToAudible(raw, minHz: 20, maxHz: 5000)
                                switchInfoTone(toHz: hz2, newOffset: newOffset)
                            if let coord = f.coord, store.selected.contains(coord) {
                                store.setOctaveOffset(for: coord, to: newOffset)
                            }
                        }
                    }
                }
            }
            
            
            
            // Bottom row: prime badges
            let primes = NotationFormatter.primeBadges(p: f.num, q: f.den)
            HStack(spacing: 6) {
                ForEach(primes, id:\.self) { pr in
                    // let col = theme.primeTint(pr)
                    Text("\(pr)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                    //   .background(col.opacity(0.20))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(8)
        .frame(maxWidth: 320, alignment: .leading)
        // Ensure octave changes always retune immediately (even if other gestures also fire while the card is up).
                .onChange(of: infoOctaveOffset) { newOffset in
                let baseHzLocal = foldToAudible(app.rootHz * (Double(f.num) / Double(f.den)), minHz: 20, maxHz: 5000)
                let hzNew = baseHzLocal * pow(2.0, Double(newOffset))
                    switchInfoTone(toHz: hzNew, newOffset: newOffset)
                }
    }
    // Glass circle chevron (top-right octave stepper)
    private struct GlassPuckButton: View {
        let systemName: String
        let isEnabled: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1.0 : 0.35)
            .disabled(!isEnabled)
            .modifier(GlassPuckSurface())
        }
    }
    
    private struct GlassPuckSurface: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: .circle)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.9)
                    )
            } else {
                content
                    .background(.thinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.0)
                    )
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.8)
                    )
            }
        }
    }
    
    
    
    // MARK: - HEJI minimal staff row (clef + staff + notehead; Bravura/Bravura Text)
    // MARK: - HEJI staff row (Bravura/Bravura Text)
    // MARK: - HEJI staff row (precise placement via Canvas)
    private struct HejiStaffRow: View {
        let letter: String   // "A"..."G"
        let octave: Int
        let etCents: Double  // deviation vs ET, for HEJI accidental
        
        private struct M {
            static let gap: CGFloat = 8           // staff-space (distance between lines)
            static let thickness: CGFloat = 1
            static let width: CGFloat = 140
            static let height: CGFloat = gap * 4 + 12
            static let noteX: CGFloat = 100       // after clef & accidental
            static let accX: CGFloat  = noteX - 18
            static let clefX: CGFloat = 16
            static let clefSize: CGFloat = 28
            static let headSize: CGFloat = 20
            static let accSize: CGFloat  = 18
            static let topInset: CGFloat = 4
        }
        private let gClef = "\u{E050}"       // SMuFL gClef
        private let noteheadBlack = "\u{E0A4}"
        
        var body: some View {
            Canvas { ctx, size in
                // Five staff lines
                let topY = M.topInset
                for i in 0..<5 {
                    let y = topY + CGFloat(i) * M.gap
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: M.width, y: y))
                    ctx.stroke(line, with: .color(Color.primary.opacity(0.55)), lineWidth: M.thickness)
                }
                
                // Geometry
                let bottomLineY = topY + 4 * M.gap
                let y = yFor(letter: letter, octave: octave, bottomLineY: bottomLineY)
                
                // Clef centered on the second line (G4) ≈ bottomLineY - 2 * gap
                let gLineY = bottomLineY - 2 * M.gap
                let clefTxt = Text(gClef).font(.custom("Bravura", size: M.clefSize))
                ctx.draw(clefTxt, at: CGPoint(x: M.clefX, y: gLineY), anchor: .center)
                
                // Accidental (if any), centered to notehead Y
                if let acc = NotationFormatter.hejiAccidentalGlyph(forCents: etCents) {
                    let accTxt = Text(acc).font(.custom("Bravura Text", size: M.accSize))
                    ctx.draw(accTxt, at: CGPoint(x: M.accX, y: y), anchor: .center)
                }
                
                // Notehead centered on Y
                let headTxt = Text(noteheadBlack).font(.custom("Bravura", size: M.headSize))
                ctx.draw(headTxt, at: CGPoint(x: M.noteX, y: y), anchor: .center)
                
                // One ledger line if needed
                drawLedgerIfNeeded(y: y, topY: topY, bottomY: bottomLineY, in: &ctx)
            }
            .frame(width: M.width, height: M.height)
        }
        
        // E4 (bottom line) = diatonic index 0
        private func yFor(letter: String, octave: Int, bottomLineY: CGFloat) -> CGFloat {
            let stepFromE: [String:Int] = ["E":0,"F":1,"G":2,"A":3,"B":4,"C":5,"D":6]
            let s = stepFromE[letter.uppercased()] ?? 0
            let diatonic = (octave - 4) * 7 + s
            let dy = CGFloat(diatonic) * (M.gap / 2)
            return bottomLineY - dy
        }
        
        private func drawLedgerIfNeeded(y: CGFloat, topY: CGFloat, bottomY: CGFloat, in ctx: inout GraphicsContext) {
            if y < topY - M.gap/2 {
                var p = Path()
                let ly = topY - M.gap
                p.move(to: CGPoint(x: M.noteX - 8, y: ly))
                p.addLine(to: CGPoint(x: M.noteX + 8, y: ly))
                ctx.stroke(p, with: .color(Color.primary.opacity(0.6)), lineWidth: M.thickness)
            } else if y > bottomY + M.gap/2 {
                var p = Path()
                let ly = bottomY + M.gap
                p.move(to: CGPoint(x: M.noteX - 8, y: ly))
                p.addLine(to: CGPoint(x: M.noteX + 8, y: ly))
                ctx.stroke(p, with: .color(Color.primary.opacity(0.6)), lineWidth: M.thickness)
            }
        }
    }
    
    private struct StaffLines: Shape {
        let gap: CGFloat
        let thickness: CGFloat
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let top = rect.minY + 4   // small inset for nicer optics
            for i in 0..<5 {
                let y = top + CGFloat(i) * gap
                p.move(to: CGPoint(x: rect.minX, y: y))
                p.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            return p
        }
    }
    
    // MARK: - HEJI helper (simple Monzo from p/q)
    private func monzoString(p: Int, q: Int) -> String {
        func factors(_ n: Int) -> [Int:Int] {
            var n = n, out: [Int:Int] = [:], p = 2
            while p*p <= n {
                while n % p == 0 { out[p, default: 0] += 1; n /= p }
                p += (p == 2 ? 1 : 2)
            }
            if n > 1 { out[n, default: 0] += 1 }
            return out
        }
        let numF = factors(p), denF = factors(q)
        let basis = [2,3,5,7,11,13]
        var vec = basis.map { (numF[$0] ?? 0) - (denF[$0] ?? 0) }
        while vec.last == 0 && vec.count > 1 { _ = vec.popLast() }
        return "<" + vec.map(String.init).joined(separator: ", ") + ">"
    }

    private func hejiTextLabel(p: Int, q: Int, octave: Int, rootHz: Double) -> String {
        let pref = AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
        let anchor = resolveRootAnchor(rootHz: rootHz, a4Hz: staffA4Hz, preference: pref)
        let context = PitchContext(
            a4Hz: staffA4Hz,
            rootHz: rootHz,
            rootAnchor: anchor,
            accidentalPreference: pref,
            maxPrime: max(3, app.primeLimit)
        )
        let (adjP, adjQ) = applyOctaveToPQ(p: p, q: q, octave: octave)
        let spelling = spellRatio(p: adjP, q: adjQ, context: context)
        return spelling.labelText
    }

#if os(macOS) || targetEnvironment(macCatalyst)
    private func logPointer(_ point: CGPoint) {
#if DEBUG
        let now = Date()
        if let last = lastPointerLog, now.timeIntervalSince(last) < 0.15 { return }
        lastPointerLog = now
        print("[LatticePointer] loc=\(String(format: "%.1f", point.x)), \(String(format: "%.1f", point.y))")
#endif
    }

    private func logTrackpadPan(delta: CGSize, before: CGPoint, after: CGPoint) {
#if DEBUG
        print("[LatticePan] delta=(\(String(format: "%.2f", delta.width)), \(String(format: "%.2f", delta.height))) -> translation (\(String(format: "%.2f", before.x)), \(String(format: "%.2f", before.y))) -> (\(String(format: "%.2f", after.x)), \(String(format: "%.2f", after.y)))")
#endif
    }

    private func logZoom(factor: CGFloat, anchor: CGPoint, before: LatticeCamera, after: LatticeCamera) {
#if DEBUG
        print("[LatticeZoom] factor=\(String(format: "%.3f", factor)) anchor=\(String(format: "%.1f", anchor.x)), \(String(format: "%.1f", anchor.y)) scale \(String(format: "%.2f", before.scale)) -> \(String(format: "%.2f", after.scale)) translation (\(String(format: "%.2f", before.translation.x)), \(String(format: "%.2f", before.translation.y))) -> (\(String(format: "%.2f", after.translation.x)), \(String(format: "%.2f", after.translation.y)))")
#endif
    }

    private func applyTrackpadPan(delta: CGSize) {
        let before = store.camera.translation
        store.camera.pan(by: delta)
        logTrackpadPan(delta: delta, before: before, after: store.camera.translation)
    }

    private func zoomAnchor(in geo: GeometryProxy) -> CGPoint {
        // Mac/Catalyst: anchor zoom around the hovered cursor so the world point
        // under the pointer stays pinned during magnification.
        pointerInLattice ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
    }

    private func applyZoom(by factor: CGFloat, anchor: CGPoint) {
        let before = store.camera
        store.camera.zoom(by: factor, anchor: anchor)
        logZoom(factor: factor, anchor: anchor, before: before, after: store.camera)
    }
#else
    private func zoomAnchor(in geo: GeometryProxy) -> CGPoint {
        CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
    }
    private func applyZoom(by factor: CGFloat, anchor: CGPoint) {
        store.camera.zoom(by: factor, anchor: anchor)
    }
#endif
    
    // MARK: - Gestures
    
    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
#if targetEnvironment(macCatalyst)
                isMousePanning = true
#endif
                let dx = v.translation.width - lastDrag.width
                let dy = v.translation.height - lastDrag.height
                store.camera.pan(by: CGSize(width: dx, height: dy))
                lastDrag = v.translation
            }
            .onEnded { v in
                let pan = hypot(v.translation.width, v.translation.height)
                if pan > 0.5 {
                    LearnEventBus.shared.send(.latticeCameraChanged(pan: Double(pan), zoom: 1.0))
                }
                lastDrag = .zero
#if targetEnvironment(macCatalyst)
                isMousePanning = false
#endif
            }
    }
    
    private func pinchGesture(in geo: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                // apply *delta* zoom for smoothness
                let factor = max(0.5, min(2.0, scale / max(0.01, lastMag)))
                let anchor = zoomAnchor(in: geo)
                applyZoom(by: factor, anchor: anchor)
                lastMag = scale
            }
            .onEnded { scale in
                LearnEventBus.shared.send(.latticeCameraChanged(pan: 0.0, zoom: Double(scale)))
                lastMag = 1
            }
    }
    // Brush-select: toggles nodes as you drag over them (only in .select mode)
    private func brushGesture(in geo: GeometryProxy, viewRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard store.mode == .select else { return }
                // world-space sample
                let world = store.camera.screenToWorld(v.location)
                // snap to the nearest visible plane coord using small local search
                let r = 2
                var target: LatticeCoord? = nil
                for e3 in (-r...r) {
                    for e5 in (-r...r) {
                        let c = LatticeCoord(e3: e3 + store.pivot.e3, e5: e5 + store.pivot.e5)
                        let p = layout.position(for: c)
                        let d2 = pow(world.x - p.x, 2) + pow(world.y - p.y, 2)
                        if d2 < 0.05 { target = c; break }
                    }
                }
                if let c = target, !store.brushVisited.contains(c) {
                    store.toggleSelection(c)
                    store.brushVisited.insert(c)
                }
            }
            .onEnded { _ in
                store.brushVisited.removeAll()
            }
    }
    
    private struct TenneyDistanceOverlay: View {
        let a: TenneyDistanceNode
        let b: TenneyDistanceNode
        let mode: TenneyDistanceMode
        let theme: LatticeTheme

        var body: some View {
            let A = a.screen
            let B = b.screen
            let mid = CGPoint(x: (A.x + B.x) * 0.5, y: (A.y + B.y) * 0.5)

            // Offset the label stack slightly off the segment so it doesn’t sit on top of nodes/line
            let vx = B.x - A.x
            let vy = B.y - A.y
            let len = max(1, hypot(vx, vy))
            let nx = -vy / len
            let ny =  vx / len
            let anchor = CGPoint(x: mid.x + nx * 16, y: mid.y + ny * 16)

            let delta = tenneyDelta(a.exps, b.exps)
            let H = tenneyHeightDelta(delta)

            let parts: [(prime: Int, text: String)] =
                delta.keys.sorted().compactMap { p in
                    let d = delta[p, default: 0]
                    guard d != 0 else { return nil }
                    return (p, labelFor(prime: p, exp: d))
                }

            VStack(spacing: 6) {
                // Total (always visible when not .off)
                GlassChip(text: String(format: "H %.2f", H))

                // Breakdown (only in .breakdown)
                if mode == .breakdown, !parts.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(parts, id: \.prime) { part in
                            GlassChip(text: part.text, tint: theme.primeTint(part.prime))
                        }
                    }
                }
            }
            .position(anchor)
        }

        private func tenneyDelta(_ a: [Int:Int], _ b: [Int:Int]) -> [Int:Int] {
            var out: [Int:Int] = [:]
            let keys = Set(a.keys).union(b.keys)
            for p in keys {
                let d = (b[p] ?? 0) - (a[p] ?? 0)
                if d != 0 { out[p] = d }
            }
            return out
        }

        private func labelFor(prime: Int, exp: Int) -> String {
            // Keep your existing 3/5 formatting if you already have deltaLabel(prime, exp)
            if prime == 3 || prime == 5 {
                return deltaLabel(prime, exp)
            }
            let sign = exp > 0 ? "+" : ""
            return "\(prime)^\(sign)\(exp)"
        }
    }


    
    private func hitTestCandidate(
        at point: CGPoint,
        viewRect: CGRect
    ) -> (pos: CGPoint, label: String, isPlane: Bool, coord: LatticeCoord?, p: Int, q: Int, ghost: (prime:Int, e3:Int, e5:Int, eP:Int)?)? {

    // Screen-space radii so overlays can't steal taps from plane nodes.
    let screenRadiusPlane:   CGFloat = 18
    let screenRadiusOverlay: CGFloat = 12

    // Helpers (avoid Double->Int traps on huge values)
    func safeMul(_ a: Int, _ b: Int) -> Int? {
        let (r, o) = a.multipliedReportingOverflow(by: b)
        return o ? nil : r
    }
    func intPow(_ base: Double, exp: Int) -> Int? {
        guard exp >= 0 else { return nil }
        if exp == 0 { return 1 }
        let v = pow(base, Double(exp))
        guard v.isFinite, v < Double(Int.max) else { return nil }
        return Int(v.rounded(.toNearestOrAwayFromZero))
    }
    func buildPQ(e3: Int, e5: Int, prime: Int? = nil, eP: Int = 0) -> (Int, Int)? {
        var num = 1
        var den = 1

        if e3 >= 0 {
            guard let f = intPow(3.0, exp: e3), let r = safeMul(num, f) else { return nil }
            num = r
        } else {
            guard let f = intPow(3.0, exp: -e3), let r = safeMul(den, f) else { return nil }
            den = r
        }

        if e5 >= 0 {
            guard let f = intPow(5.0, exp: e5), let r = safeMul(num, f) else { return nil }
            num = r
        } else {
            guard let f = intPow(5.0, exp: -e5), let r = safeMul(den, f) else { return nil }
            den = r
        }

        if let p = prime, eP != 0 {
            if eP >= 0 {
                guard let f = intPow(Double(p), exp: eP), let r = safeMul(num, f) else { return nil }
                num = r
            } else {
                guard let f = intPow(Double(p), exp: -eP), let r = safeMul(den, f) else { return nil }
                den = r
            }
        }

        let g = gcd(abs(num), abs(den))
        return (num / g, den / g)
    }

    // 1) Prefer plane nodes around the pivot (screen distance)
    let R = max(6, min(24, Int(store.camera.appliedScale / 6)))
    var bestPlane: (d: CGFloat, pos: CGPoint, coord: LatticeCoord, p: Int, q: Int)?

    for de3 in (-R...R) {
        for de5 in (-R...R) {
            let c  = LatticeCoord(e3: store.pivot.e3 + de3, e5: store.pivot.e5 + de5)
            let wp = layout.position(for: c)
            let sp = store.camera.worldToScreen(wp)
            let d  = hypot(sp.x - point.x, sp.y - point.y)

            if d <= screenRadiusPlane {
                // Axis shift affects meaning (ratio), not plane geometry.
                let e3m = c.e3 + (store.axisShift[3] ?? 0)
                let e5m = c.e5 + (store.axisShift[5] ?? 0)

                guard let (p, q) = buildPQ(e3: e3m, e5: e5m) else { continue }
                if bestPlane == nil || d < bestPlane!.d { bestPlane = (d, sp, c, p, q) }
            }
        }
    }

    if let b = bestPlane {
        let (cp, cq) = canonicalPQ(b.p, b.q)
        return (b.pos, "\(cp)/\(cq)", true, b.coord, b.p, b.q, nil)
    }

    // 2) Otherwise, allow overlay hits — but only when they are drawable:
    //    - steady-state ON (no animation): crisp exists everywhere
    //    - animating: only nodes with local>~0 exist (same wave gating as drawOverlay)
    let now = CACurrentMediaTime()
    let center = store.camera.worldToScreen(.zero)
    let maxR = maxRadius(from: center, in: viewRect)
    let pad: CGFloat = 60

    var bestOverlay: (d2: CGFloat, pos: CGPoint, p: Int, q: Int, prime: Int, e3: Int, e5: Int, eP: Int)?

    let baseE3 = store.pivot.e3 + (store.axisShift[3] ?? 0)
    let baseE5 = store.pivot.e5 + (store.axisShift[5] ?? 0)
    let epSpan = max(6, min(12, Int(store.camera.appliedScale / 8)))

    // Use the same prime set used for rendering so hit-testing matches what can appear.
    let overlayPrimes = store.renderPrimes.filter { $0 != 2 && $0 != 3 && $0 != 5 }

    for prime in overlayPrimes {
        let phase = store.inkPhase(for: prime, now: now)
        let isVisible = store.visiblePrimes.contains(prime)
        let isAnimating = (phase != nil)

        if !isVisible && !isAnimating { continue }

        let targetOn: Bool = phase?.targetOn ?? true
        let tNorm: CGFloat = phase?.t ?? 1.0
        let dur: Double = phase?.duration ?? 0.65

        let s = store.axisShift[prime] ?? 0

        for ep in (-epSpan...epSpan) where ep != 0 {
            let eP = ep + s

            var monzo: [Int:Int] = [3: baseE3, 5: baseE5]
            monzo[prime] = eP

            let wp = layout.position(monzo: monzo)
            let sp = store.camera.worldToScreen(wp)

            // skip far-offscreen work
            if sp.x < viewRect.minX - pad || sp.x > viewRect.maxX + pad || sp.y < viewRect.minY - pad || sp.y > viewRect.maxY + pad {
                continue
            }

            let dist = hypot(sp.x - center.x, sp.y - center.y)

            // match drawOverlay existence gating
            let local: CGFloat = {
                guard isAnimating else { return 1.0 } // steady-state: fully present (crisp only)

                let bandPx: CGFloat = 160
                let bandT: CGFloat = max(0.035, min(0.22, bandPx / maxR))

                let hitT = dist / maxR
                let jitter = inkJitterFrac(prime: prime, e3: baseE3, e5: baseE5, eP: eP, duration: dur)
                let x = (tNorm - (hitT + jitter)) / bandT
                let wave = smoothstep(x)
                return targetOn ? wave : (1 - wave)
            }()

            if local <= 0.001 { continue }

            // tap radius shrinks a touch while ink is barely present (feels less “ghosty”)
            let tapR = screenRadiusOverlay * (0.75 + 0.25 * local)
            let dTap = hypot(sp.x - point.x, sp.y - point.y)
            if dTap > tapR { continue }

            guard let (num, den) = buildPQ(e3: baseE3, e5: baseE5, prime: prime, eP: eP) else { continue }

            let d2 = dTap * dTap
            if bestOverlay == nil || d2 < bestOverlay!.d2 {
                bestOverlay = (d2, sp, num, den, prime, baseE3, baseE5, eP)
            }
        }
    }

    if let o = bestOverlay {
        let (cp, cq) = canonicalPQ(o.p, o.q)
        return (o.pos, "\(cp)/\(cq)", false, nil, o.p, o.q, (prime: o.prime, e3: o.e3, e5: o.e5, eP: o.eP))
    }

    return nil

    }

    
}
// MARK: - HEJI accidental mapping (SMuFL Extended Helmholtz–Ellis)
extension NotationFormatter {
    /// Returns a Bravura/SMuFL glyph string for a HEJI accidental near the given ET deviation (in cents).
    /// Uses Extended Helmholtz–Ellis codepoints U+E2C0–U+E2FF.
    ///  - 1 syntonic comma (~21.51¢):   accidentalNaturalOneArrowUp/Down (U+E2C7 / U+E2C2)
    ///  - 2 syntonic commas (~43.02¢):  accidentalNaturalTwoArrowsUp/Down (U+E2D1 / U+E2CC)
    ///  - 1 septimal comma (~27.26¢):   accidentalRaise/LowerOneSeptimalComma (U+E2DF / U+E2DE)
    ///  - 1 undecimal quartertone (~48.77¢): accidentalRaise/LowerOneUndecimalQuartertone (U+E2E3 / U+E2E2)
    static func hejiAccidentalGlyph(forCents cents: Double) -> String? {
        let a = abs(cents); let up = cents >= 0
        if a < 6 { return nil } // treat <6¢ as “no microtonal accidental”
        struct Step { let cents: Double; let up: String; let down: String }
        let table: [Step] = [
            .init(cents: 21.51, up: "\u{E2C7}", down: "\u{E2C2}"), // NaturalOneArrowUp/Down
            .init(cents: 27.26, up: "\u{E2DF}", down: "\u{E2DE}"), // Raise/LowerOneSeptimalComma
            .init(cents: 43.02, up: "\u{E2D1}", down: "\u{E2CC}"), // NaturalTwoArrowsUp/Down
            .init(cents: 48.77, up: "\u{E2E3}", down: "\u{E2E2}")  // Raise/LowerOneUndecimalQuartertone
        ]
        let nearest = table.min(by: { abs($0.cents - a) < abs($1.cents - a) })!
        return up ? nearest.up : nearest.down
    }
}

// MARK: - Hit testing (extension)
extension LatticeView {
    func hitTest(_ point: CGPoint, in viewRect: CGRect) -> LatticeCoord? {
        // Inverse-project point to world; find nearest node within a pixel radius threshold
        let world = store.camera.screenToWorld(point)
        // Approximate back to lattice coords by solving small linear system; here we brute-force local neighborhood
        let radius = 3
        let layout = self.layout
        var nearest: (coord: LatticeCoord, dist2: CGFloat)? = nil
        for e3 in (-radius...radius) {
            for e5 in (-radius...radius) {
                let c = LatticeCoord(e3: e3 + store.pivot.e3, e5: e5 + store.pivot.e5)
                let pos = layout.position(for: c)
                let d = hypot(world.x - pos.x, world.y - pos.y)
                let d2 = d*d
                if d2 < 0.05 { // threshold in world units (~pixels/scale)
                    if nearest == nil || d2 < nearest!.dist2 { nearest = (c, d2) }
                }
            }
        }
        return nearest?.coord
    }
}

private extension View {
    func erased() -> AnyView { AnyView(self) }
    
}
