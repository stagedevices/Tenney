//
//  LatticeView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import SwiftUI


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
    
    @AppStorage(SettingsKeys.latticeConnectionMode)
    private var latticeConnectionModeRaw: String = LatticeConnectionMode.chain.rawValue

    private var latticeConnectionMode: LatticeConnectionMode {
        LatticeConnectionMode(rawValue: latticeConnectionModeRaw) ?? .chain
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
        LatticeGridMode(rawValue: gridModeRaw) ?? .outlines
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
        let id = LatticeThemeID(rawValue: themeIDRaw) ?? .classicBO
        return ThemeRegistry.theme(id, dark: effectiveIsDark)
    }
    
    
    private struct TenneyDistanceNode: Hashable {
        let screen: CGPoint
        let exps: [Int:Int]   // prime -> exponent (absolute, includes axisShift where appropriate)
    }

    private func tenneyDistanceNodes() -> [TenneyDistanceNode] {
        var out: [TenneyDistanceNode] = []

        // Plane selections (3×5 plane)
        for c in store.selected {
            let e3 = c.e3 + store.pivot.e3 + (store.axisShift[3] ?? 0)
            let e5 = c.e5 + store.pivot.e5 + (store.axisShift[5] ?? 0)

            let world = layout.position(for: LatticeCoord(e3: e3, e5: e5))
            let screen = store.camera.worldToScreen(world)

            out.append(.init(screen: screen, exps: [3: e3, 5: e5]))
        }

        // Ghost selections (7+ etc.) — `selectedGhosts` already stores absolute exps from hitTestCandidate
        for g in store.selectedGhosts {
            let exps: [Int:Int] = [3: g.e3, 5: g.e5, g.p: g.eP]
            let world = layout.position(monzo: exps)
            let screen = store.camera.worldToScreen(world)

            out.append(.init(screen: screen, exps: exps))
        }

        // Stable ordering (selection sets are unordered)
        out.sort { (lhs, rhs) in
            if lhs.screen.x != rhs.screen.x { return lhs.screen.x < rhs.screen.x }
            return lhs.screen.y < rhs.screen.y
        }

        return out
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
            let raw = app.rootHz * (Double(cp) / Double(cq))
            let freq = foldToAudible(raw, minHz: 20, maxHz: 5000)
            return NotationFormatter.hejiLabel(p: cp, q: cq, freqHz: freq, rootHz: app.rootHz)
        }
    }

    private func shouldDrawOverlayLabel(ep: Int) -> Bool {
        guard labelDensity > 0.01 else { return false }

        let zoom = store.camera.scale
        let zoomT = clamp01((zoom - 52) / 80)
        guard zoomT >= 0.15 else { return false }

        // keep labels close to the prime-axis origin to prevent clutter
        let baseR  = max(3, min(14, Int(zoom / 16)))
        let labelR = Int(CGFloat(baseR) * CGFloat(labelDensity))
        return abs(ep) <= labelR
    }

    
    @AppStorage(SettingsKeys.latticeThemeID) private var themeIDRaw: String = LatticeThemeID.classicBO.rawValue
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
    @State private var reenableAuditionWorkItem: DispatchWorkItem?
    
    @State private var selectionHapticTick: Int = 0
    @State private var focusHapticTick: Int = 0

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
            let wash = Gradient(stops: [
                .init(color: tint.opacity(0.00), location: 0.00),
                .init(color: tint.opacity(0.22 * bA), location: 0.18),
                .init(color: tint.opacity(0.00), location: 0.55),
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
               let route = shortestGridPath(from: aC, to: bC, gridMode: gridMode, radius: radius),
               route.count >= 2 {

                // Convert routed vertices -> points in the exact same space as nodes.
                // Route is expressed in lattice vertices; we draw on top of grid edges.
                var routePts: [CGPoint] = []
                routePts.reserveCapacity(route.count)
                for c in route {
                    routePts.append(pt(.plane(c)))
                }

                // Stroke each routed edge segment using the SAME passes.
                // Shade is deterministically anchored to the original endpoints A/B.
                for i in 0..<(routePts.count - 1) {
                    strokeSegment(a: routePts[i], b: routePts[i + 1], shade: endpointShade)
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
            let raw = app.rootHz * (Double(cp) / Double(cq))
            let freq = foldToAudible(raw, minHz: 20, maxHz: 5000)
            return NotationFormatter.hejiLabel(p: cp, q: cq, freqHz: freq, rootHz: app.rootHz)
        }
    }

    private func shouldDrawPlaneLabel(coord: LatticeCoord) -> Bool {
        guard labelDensity > 0.01 else { return false }

        let zoom = store.camera.scale
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
        store.auditionEnabled = false
        reenableAuditionWorkItem?.cancel()
        let work = DispatchWorkItem { store.auditionEnabled = true }
        reenableAuditionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
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
    
    @Environment(\.latticePreviewHideDistance) private var latticePreviewHideDistance
    
    private func nodeBaseSize() -> CGFloat {
        switch nodeSize {
        case "s":     return 10
        case "m":     return 12
        case "mplus": return 14
        case "l":     return 16
        default:      return 12
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
                    releaseInfoVoice()
                    focusedPoint = nil
                    return
                }
                
                let (cn, cd) = canonicalPQ(cand.p, cand.q)
                let raw = app.rootHz * (Double(cn) / Double(cd))
                let freq = foldToAudible(raw, minHz: 20, maxHz: 5000)
                releaseInfoVoice()
                infoOctaveOffset = 0

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
                    // if this tap will deselect the currently focused plane node, add a touch more punch
                    if let fp = focusedPoint?.coord, fp == c, store.selected.contains(c) {
                #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1.0)
                #endif
                    }
                    store.toggleSelection(c)
                    selectionHapticTick &+= 1
                } else if let g = cand.ghost {
                    store.toggleOverlay(prime: g.prime, e3: g.e3, e5: g.e5, eP: g.eP)
                    selectionHapticTick &+= 1
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
    
    
    // ⬇️ REPLACE your releaseInfoVoice(...) with:
    private func releaseInfoVoice(hard: Bool = true) {
        if let id = infoVoiceID {
            ToneOutputEngine.shared.release(id: id, seconds: hard ? 0.0 : 0.05)
            infoVoiceID = nil
        }
        // Resume the selection sustain for the focused coord if still selected
        if let c = pausedForInfoCoord {
            store.resumeSelectionVoiceIfNeeded(for: c)
            pausedForInfoCoord = nil
        }
    }
    
    // ⬇️ REPLACE your switchInfoTone(...) with:
    private func switchInfoTone(toHz hz: Double, newOffset: Int) {
        // Pause ONLY the focused node’s selection sustain so we don’t hear both
        if let c = focusedPoint?.coord, pausedForInfoCoord == nil {
            store.pauseSelectionVoice(for: c, hard: true)
            pausedForInfoCoord = c
        }
        // Stop any previous preview instantly, then start the new one
        if let id = infoVoiceID { ToneOutputEngine.shared.release(id: id, seconds: 0.0) }
        infoVoiceID = ToneOutputEngine.shared.sustain(freq: hz, amp: 0.22)
        infoOctaveOffset = newOffset
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
    
    
    
    
    // MARK: - Selection Tray (v0.2)
    private struct SelectionTray: View {
        @ObservedObject var store: LatticeStore
        @ObservedObject var app: AppModel
        // ADD inside SelectionTray (above var body)
        private var trayRow: some View {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("Selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text("\(store.selectedCount)")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .contentTransition(.numericText())
                    
                    if store.additionsSinceBaseline > 0 {
                        Text("Δ+\(store.additionsSinceBaseline)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                
                Divider().opacity(0.2)
                
                Button { store.undo() } label: { Image(systemName: "arrow.uturn.left") }
                    .buttonStyle(.plain)
                
                Button { store.redo() } label: { Image(systemName: "arrow.uturn.right") }
                    .buttonStyle(.plain)
                
                Divider().opacity(0.2)
                
                Button("Clear") {
                    withAnimation(.snappy) { store.clearSelection() }
                }
                .disabled(store.selectedCount == 0)
                
                Spacer(minLength: 8)
                
                Button {
                    let refs = store.selectionRefs(pivot: store.pivot, axisShift: store.axisShift)
                    let payload = ScaleBuilderPayload(
                        rootHz: app.rootHz,
                        primeLimit: app.primeLimit,
                        refs: refs
                    )
                    store.beginStaging()
                    app.builderPayload = payload
                } label: {
                    Text("Add")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedCount == 0)
                
                Button("Library") {
                    store.beginStaging()
                    app.showScaleLibraryDetent = true
                }
                .buttonStyle(.bordered)
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .font(.footnote)
            .controlSize(.small)
        }
        
        var body: some View {
            Group {
                if #available(iOS 26.0, *) {
                    trayRow
                        .frame(maxWidth: .infinity) // ensures rounded-rect container, not pill-fit
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                } else {
                    // Keep your existing pre-26 appearance (fallback)
                    GlassCard {
                        trayRow
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SelectionTrayHeightKey.self, value: proxy.size.height)
                }
            )
        }
        
        
    }
    
    // MARK: - Audition (sound on/off) pill (v0.2)
    private struct AuditionPill: View {
        @ObservedObject var store: LatticeStore
        
        var body: some View {
            GlassCard {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { store.auditionEnabled.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: store.auditionEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .imageScale(.medium)
                                .symbolRenderingMode(.hierarchical)
                            
                            Text(store.auditionEnabled ? "Sound On" : "Sound Off")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: store.auditionEnabled)
                    .accessibilityLabel(store.auditionEnabled ? "Audition on" : "Audition off")
                }
            }
            .controlSize(.small)
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


        let zoom = store.camera.scale
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
                let radius: Int = Int(max(8, min(48, store.camera.scale / 5)))
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
                    var guide = Path()
                    let pivotPos: CGPoint = layout.position(for: store.pivot)
                    let left: CGPoint  = store.camera.worldToScreen(CGPoint(x: pivotPos.x - 5000, y: pivotPos.y))
                    let right: CGPoint = store.camera.worldToScreen(CGPoint(x: pivotPos.x + 5000, y: pivotPos.y))
                    guide.move(to: left); guide.addLine(to: right)
                    ctx.stroke(guide, with: .color(.accentColor.opacity(0.15)), lineWidth: 1)
                    
                    if store.selectionOrder.count > 1 {
                        var path = Path()
                        for (i,c) in store.selectionOrder.enumerated() {
                            let wp = layout.position(for: c)
                            let sp = store.camera.worldToScreen(wp)
                            if i == 0 { path.move(to: sp) } else { path.addLine(to: sp) }
                        }
                    }
                    // NEW: show a guide when the selection pair includes ghosts (7+ etc.)
                    let planeCount  = store.selected.count
                    let ghostCount  = store.selectedGhosts.count
                    if planeCount + ghostCount == 2 {
                        var pts: [CGPoint] = []
                        // plane selections
                        for c in store.selected {
                            let e3 = c.e3 + store.pivot.e3 + (store.axisShift[3] ?? 0)
                            let e5 = c.e5 + store.pivot.e5 + (store.axisShift[5] ?? 0)
                            let wp = layout.position(for: LatticeCoord(e3: e3, e5: e5))
                            pts.append(store.camera.worldToScreen(wp))
                        }
                        // ghost selections (7/11/…)
                        for g in store.selectedGhosts {
                            let monzo: [Int:Int] = [3: g.e3, 5: g.e5, g.p: g.eP]
                            let wp = layout.position(monzo: monzo)
                            pts.append(store.camera.worldToScreen(wp))
                        }
                        if pts.count == 2 {
                            var path = Path()
                            path.move(to: pts[0]); path.addLine(to: pts[1])
                            ctx.stroke(path, with: .color(.accentColor.opacity(0.55)), lineWidth: 1.5)
                        }
                    }
                }
                
                // grid width baseline (0 if grid is off / below threshold)
                let gridW: CGFloat = {
                    guard gridMode != .off else { return 0 }
                    guard store.camera.scale >= gridMinZoom else { return 0 }
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
                    zoom: store.camera.scale,
                    gridStrokeWidth: gridW
                )

                // Selection rims on top (selected + animating-off)
                do {
                    let pivotSnapshot = store.pivot
                    let shiftSnapshot = store.axisShift
                    let cameraSnapshot = store.camera
                    let zoom = store.camera.scale
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
                .simultaneousGesture(pan)
                .simultaneousGesture(pinch)
                .simultaneousGesture(tap)
                .simultaneousGesture(press)
                .simultaneousGesture(brush)
            
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
                infoCard
                    .padding(.top, 72)
                    .padding(.trailing, 12)
                    .frame(maxWidth: 320, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
            }
            Spacer()
        }
    }
    
    private var bottomHUDLayer: some View {
        VStack {
            Spacer()
            if !latticePreviewMode {
                VStack(spacing: 8) {
                    if store.selectedCount > 0 || store.additionsSinceBaseline > 0 {
                        SelectionTray(store: store, app: app)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
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
        if let v = note.userInfo?[SettingsKeys.latticeThemeID] as? String { themeIDRaw = v }
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
                .onChange(of: store.selected) { newValue in
                    if let fp = focusedPoint, let c = fp.coord, !newValue.contains(c) {
                        releaseInfoVoice()
                        withAnimation(.easeOut(duration: 0.2)) { focusedPoint = nil }
                    }
                    if newValue.isEmpty { releaseInfoVoice() }
                }
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
        let depth = Gradient(stops: [
            .init(color: Color.white.opacity(0.10 * alpha), location: 0.00),
            .init(color: Color.white.opacity(0.05 * alpha), location: 0.38),
            .init(color: Color.black.opacity(0.08 * alpha), location: 1.00)
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

            let zoomT = clamp01((store.camera.scale - 42) / 70)
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

        let epSpan = max(6, min(12, Int(store.camera.scale / 8)))

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

            let depth = Gradient(stops: [
                .init(color: Color.white.opacity(0.14 * alpha), location: 0.00),
                .init(color: Color.white.opacity(0.04 * alpha), location: 0.40),
                .init(color: Color.black.opacity(0.12 * alpha), location: 1.00)
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

                let zoomT = clamp01((store.camera.scale - 52) / 80)
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
                    )
                }
            }
            .padding(8)
        }
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
            let hzAdj = f.hz * pow(2.0, Double(infoOctaveOffset))
            let staff = NotationFormatter.staffNoteName(freqHz: hzAdj)
            // Adjusted ratio string (NO FOLD to 1–2; preserves +/- octaves in ratio)
            let (adjP, adjQ) = ratioWithOctaveOffsetNoFold(num: f.num, den: f.den, offset: infoOctaveOffset)
            let jiText: String = (store.labelMode == .ratio)
            ? "\(adjP)/\(adjQ)"
            : NotationFormatter.hejiLabel(p: f.num, q: f.den, freqHz: hzAdj, rootHz: app.rootHz)
            
            // Octave step availability (audible range)
            let nextUpHz   = f.hz * pow(2.0, Double(infoOctaveOffset + 1))
            let nextDownHz = f.hz * pow(2.0, Double(infoOctaveOffset - 1))
            let canUp   = nextUpHz   >= 20 && nextUpHz   <= 5000
            let canDown = nextDownHz >= 20 && nextDownHz <= 5000
            
            HStack(alignment: .top, spacing: 10) {
                // Left: names/metrics
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(staff.name)\(staff.octave)")
                            .font(.title3.weight(.semibold))
                        Text(jiText)
                            .font(.headline.monospaced())
                            .opacity(store.labelMode == .heji ? 1 : 0.9)
                        
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
                        Text(String(format: "%+.1f¢ vs ET", f.etCents))
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
                            let hzNew = f.hz * pow(2.0, Double(newOffset))
                            switchInfoTone(toHz: hzNew, newOffset: newOffset)
                        }

                        GlassPuckButton(systemName: "chevron.up", isEnabled: canUp) {
                            let newOffset = infoOctaveOffset + 1
                            let hzNew = f.hz * pow(2.0, Double(newOffset))
                            switchInfoTone(toHz: hzNew, newOffset: newOffset)
                        }
                    }
                    if store.labelMode == .heji {
                        HejiStaffRow(letter: staff.name,
                                     octave: staff.octave,
                                     etCents: f.etCents)
                        .frame(width: 140, height: 60)
                        .accessibilityHidden(true)
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
    
    // MARK: - Gestures
    
    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let dx = v.translation.width - lastDrag.width
                let dy = v.translation.height - lastDrag.height
                store.camera.pan(by: CGSize(width: dx, height: dy))
                lastDrag = v.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }
    
    private func pinchGesture(in geo: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                // apply *delta* zoom for smoothness
                let factor = max(0.5, min(2.0, scale / max(0.01, lastMag)))
                let anchor = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                store.camera.zoom(by: factor, anchor: anchor)
                lastMag = scale
            }
            .onEnded { _ in lastMag = 1 }
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
    let R = max(6, min(24, Int(store.camera.scale / 6)))
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
    let epSpan = max(6, min(12, Int(store.camera.scale / 8)))

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
