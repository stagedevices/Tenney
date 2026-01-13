//  LatticeStore.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import UIKit

@MainActor
final class LatticeStore: ObservableObject {
    private static var didBootSelectionClearThisProcess = false
    
    
    // Add alongside your other selection state
    @Published var selectionOrderKeys: [SelectionKey] = []

    private func touchOrder(_ key: SelectionKey) {
        selectionOrderKeys.removeAll { $0 == key }
        selectionOrderKeys.append(key)
    }

    private func removeOrder(_ key: SelectionKey) {
        selectionOrderKeys.removeAll { $0 == key }
    }


    // Supply rootHz without reaching into AppModel here. LatticeScreen sets this onAppear.
    static var rootHzProvider: () -> Double = { 415.0 }

    // Adapter for external overlay monzo lookup (e.g. set once from LatticeScreen):
    // LatticeStore.overlayMonzoForCoord = OverlayLocator.monzo(at:)
    static var overlayMonzoForCoord: (@Sendable (LatticeCoord) -> [Int:Int]?)?

    // MARK: - Model
    @Published var camera = LatticeCamera()
    @Published var pivot = LatticeCoord(e3: 0, e5: 0)

    // Plane (3×5) selection
    @Published var selected: Set<LatticeCoord> = []
    @Published var selectionOrder: [LatticeCoord] = []
    @Published private var octaveOffsetByCoord: [LatticeCoord: Int] = [:]

    // Overlay (higher-prime) selections: absolute world monzos
    struct GhostMonzo: Hashable {
        let e3: Int, e5: Int, p: Int, eP: Int   // monzo {3:e3, 5:e5, p:eP}
    }
    @Published var selectedGhosts: Set<GhostMonzo> = []
    @Published var selectionOrderGhosts: [GhostMonzo] = []
    @Published private var octaveOffsetByGhost: [GhostMonzo: Int] = [:]

    @Published var auditionEnabled: Bool = true
    @Published private var latticeSoundEnabled: Bool = true
    @Published var guidesOn: Bool = true
    @Published var labelMode: JILabelMode = .ratio
    @Published var showHelp: Bool = false
    
    
    // Debounced auditions (prevents “selected but silent” when tapping fast)
    private var pendingPlaneAudition: [LatticeCoord: DispatchWorkItem] = [:]
    private var pendingGhostAudition: [GhostMonzo: DispatchWorkItem] = [:]
    private let auditionMinInterval: TimeInterval = 0.12

    /// Which higher primes are visible as overlays (defaults: 7 & 11 on)
    @Published var visiblePrimes: Set<Int> = [7, 11]
    
    // MARK: - Overlay “Ink” toggle animation (7–31)

    struct PrimeInkAnim: Equatable {
        let targetOn: Bool          // true when toggling ON, false when toggling OFF
        let t0: Double              // CACurrentMediaTime()
        let duration: Double        // seconds
    }

    @Published private var primeInk: [Int: PrimeInkAnim] = [:]
    private var primeInkWork: [Int: DispatchWorkItem] = [:]

    /// Render union: visible primes + primes currently animating off/on.
    var renderPrimes: [Int] {
        let animating = Set(primeInk.keys)
        return Array(visiblePrimes.union(animating)).sorted()
    }

    /// Returns (targetOn, normalizedProgress 0...1) if the prime is animating.
    func inkPhase(for prime: Int, now: Double) -> (targetOn: Bool, t: CGFloat, duration: Double)? {
        guard let a = primeInk[prime] else { return nil }
        let dt = max(0.0, now - a.t0)
        let t = min(1.0, dt / max(0.0001, a.duration))
        return (a.targetOn, CGFloat(t), a.duration)
    }

    private var didRestorePersist: Bool = false
    private var didPerformBootSelectionClear: Bool = false
    private var suppressPersist: Bool = false

    /// Axis shifts (transpositions) along any prime axis (includes 3 and 5)
    @Published var axisShift: [Int:Int] = [3:0, 5:0, 7:0, 11:0, 13:0, 17:0, 19:0, 23:0, 29:0, 31:0]

    // v0.3
    enum LatticeMode: String, CaseIterable, Identifiable { case explore, select; var id: String { rawValue } }
    @Published var mode: LatticeMode = .explore

    // Brush selection de-bounce (session-only)
    @Published var brushVisited: Set<LatticeCoord> = []

    // Focused ref (for info card)
    @Published var focusedLabel: String? = nil
    @Published var focusedHz: Double? = nil
    @Published var focusedCents: Double? = nil
    
    @Published var tenneyDistanceMode: TenneyDistanceMode = .breakdown

    

    // MARK: - Prime visibility
    func togglePrime(_ p: Int) {
        setPrimeVisible(p, !visiblePrimes.contains(p), animated: true)
    }

    /// Primary API used by UI and Settings changes.
    func setPrimeVisible(_ p: Int, _ on: Bool, animated: Bool) {
        // Always update the logical (target) set immediately so UI chips reflect the new state.
        if on { visiblePrimes.insert(p) } else { visiblePrimes.remove(p) }

        guard animated else {
            primeInkWork[p]?.cancel(); primeInkWork[p] = nil
            primeInk[p] = nil
            return
        }

        startInkAnim(prime: p, targetOn: on)
    }
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    // deterministic 0–30ms jitter per node (stable across frames)
    private func mix32(_ x: UInt32) -> UInt32 {
        var z = x
        z ^= z >> 16
        z &*= 0x7feb352d
        z ^= z >> 15
        z &*= 0x846ca68b
        z ^= z >> 16
        return z
    }

    private func inkJitterFrac(prime: Int, e3: Int, e5: Int, eP: Int, duration: Double) -> CGFloat {
        var h: UInt32 = 2166136261
        func add(_ v: Int) {
            h = (h ^ UInt32(bitPattern: Int32(v))) &* 16777619
        }
        add(prime); add(e3); add(e5); add(eP)
        h = mix32(h)
        let ms = Double(h % 31) // 0...30ms
        return CGFloat((ms / 1000.0) / max(0.001, duration)) // normalized to anim duration
    }

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private func inkDuration(targetOn: Bool) -> Double {
        // camera.scale: smaller = zoomed out, larger = zoomed in
        let z = Double(camera.appliedScale)

        // Tune these once you feel it:
        let z0 = 24.0
        let z1 = 140.0
        let zoomInT = clamp01((z - z0) / (z1 - z0))

        // Spec: ~0.55–0.85s (faster when zoomed out)
        let on  = lerp(0.55, 0.85, zoomInT)
        let off = lerp(0.45, 0.70, zoomInT)   // slightly quicker “evaporate”
        return targetOn ? on : off
    }


    private func startInkAnim(prime p: Int, targetOn: Bool) {
        // Cancel any in-flight animation work (handles quick re-toggles cleanly).
        primeInkWork[p]?.cancel()

        let a = PrimeInkAnim(
            targetOn: targetOn,
            t0: CACurrentMediaTime(),
            duration: inkDuration(targetOn: targetOn)
        )
        primeInk[p] = a

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.primeInk[p] = nil
            self.primeInkWork[p] = nil
        }
        primeInkWork[p] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + a.duration + 0.06, execute: work)
    }

    // MARK: - Undo/Redo
    private enum Action { case shift(p:Int, delta:Int), toggle(c:LatticeCoord), toggleGhost(g:GhostMonzo) }
    private var undoStack: [Action] = []
    private var redoStack: [Action] = []

    func undo() {
        guard let a = undoStack.popLast() else { return }
        switch a {
        case .shift(let p, let d):
            setAxisShift(p, axisShift[p, default: 0] - d)
            redoStack.append(.shift(p: p, delta: d))
        case .toggle(let c):
            toggleSelection(c, pushUndo: false)
            redoStack.append(.toggle(c: c))
        case .toggleGhost(let g):
            toggleOverlay(prime: g.p, e3: g.e3, e5: g.e5, eP: g.eP, pushUndo: false)
            redoStack.append(.toggleGhost(g: g))
        }
    }

    func redo() {
        guard let a = redoStack.popLast() else { return }
        switch a {
        case .shift(let p, let d):
            setAxisShift(p, axisShift[p, default: 0] + d)
            undoStack.append(.shift(p: p, delta: d))
        case .toggle(let c):
            toggleSelection(c, pushUndo: false)
            undoStack.append(.toggle(c: c))
        case .toggleGhost(let g):
            toggleOverlay(prime: g.p, e3: g.e3, e5: g.e5, eP: g.eP, pushUndo: false)
            undoStack.append(.toggleGhost(g: g))
        }
    }

    func shift(prime p: Int, delta: Int) {
        setAxisShift(p, axisShift[p, default: 0] + delta)
        undoStack.append(.shift(p: p, delta: delta))
        redoStack.removeAll()
    }
    
    private func setAxisShift(_ p: Int, _ newValue: Int) {
        let clamped = max(-5, min(5, newValue))
        var m = axisShift
        m[p] = clamped
        axisShift = m
    }
    
    func resetView(in size: CGSize) {
        camera.center(in: size, scale: defaultZoomScale())
        pivot = LatticeCoord(e3: 0, e5: 0)
        resetShift() // resets all primes
    }

    func setDefaultZoomFromCurrentScale() {
        let nearest = LatticeZoomPreset.nearest(toScale: camera.scale)
        UserDefaults.standard.set(nearest.rawValue, forKey: SettingsKeys.latticeDefaultZoomPreset)
        postSetting(SettingsKeys.latticeDefaultZoomPreset, nearest.rawValue)
    }

    
    private var rememberLastViewSetting: Bool {
        // UserDefaults.bool(forKey:) defaults to false when unset; we want default true.
        if UserDefaults.standard.object(forKey: SettingsKeys.latticeRememberLastView) == nil { return true }
        return UserDefaults.standard.bool(forKey: SettingsKeys.latticeRememberLastView)
    }

    func defaultZoomScale() -> CGFloat {
        LatticeZoomPreset.fromDefaults().scale
    }


    func resetShift(prime p: Int? = nil) {
        if let p {
                setAxisShift(p, 0)
            } else {
                var m = axisShift
                for k in m.keys { m[k] = 0 }
                axisShift = m
            }
    }
    
    // MARK: - Selection Animations

    enum SelectionKey: Hashable {
        case plane(LatticeCoord)
        case ghost(GhostMonzo)
    }

    struct SelectionAnim: Hashable {
        let startTime: Double
        let targetOn: Bool
        let duration: Double
        let seed: UInt64        // stable per-key jitter phase
    }

    @Published private var selectionAnims: [SelectionKey: SelectionAnim] = [:]

    
    func selectionPhase(for key: SelectionKey, now: Double) -> (targetOn: Bool, t: CGFloat, duration: Double, seed: UInt64)? {
        guard let a = selectionAnims[key] else { return nil }
        let dt = max(0, now - a.startTime)
        let t = min(1.0, dt / max(0.0001, a.duration))
        return (a.targetOn, CGFloat(t), a.duration, a.seed)
    }

    /// Keys that should be rendered (selected + animating-off).
    func selectionKeysToDraw() -> [SelectionKey] {
        var out: [SelectionKey] = []
        out.reserveCapacity(selected.count + selectedGhosts.count + selectionAnims.count)

        for c in selected { out.append(.plane(c)) }
        for g in selectedGhosts { out.append(.ghost(g)) }

        // Include animating keys even if they are no longer selected
        for k in selectionAnims.keys where !out.contains(k) { out.append(k) }
        return out
    }

    private func selectionDuration(targetOn: Bool) -> Double {
        // Match the user-configured envelope times (visual ring draw-in/out)
        targetOn ? configuredAttackSec() : configuredReleaseSec()
    }
    private func configuredAttackSec() -> Double {
            // Prefer explicit UI setting if present; otherwise fall back to the old default.
            let ud = UserDefaults.standard
            if ud.object(forKey: SettingsKeys.attackMs) != nil {
                return max(0.05, ud.double(forKey: SettingsKeys.attackMs))
            }
            return 0.22
        }
    
        private func configuredReleaseSec() -> Double {
            // Prefer explicit UI setting if present; otherwise fall back to engine config (already used elsewhere).
            let ud = UserDefaults.standard
            if ud.object(forKey: SettingsKeys.releaseSec) != nil {
                return max(0.05, ud.double(forKey: SettingsKeys.releaseSec))
            }
            return max(0.05, ToneOutputEngine.shared.config.releaseMs / 1000.0)
        }

    private func selectionSeed(for key: SelectionKey) -> UInt64 {
        // deterministic hash (stable per node)
        var x: UInt64 = 0x9E3779B97F4A7C15
        func mix(_ v: Int) {
            x &+= UInt64(truncatingIfNeeded: v) &* 0xBF58476D1CE4E5B9
            x ^= x >> 27
            x &*= 0x94D049BB133111EB
            x ^= x >> 31
        }
        switch key {
        case .plane(let c):
            mix(3); mix(c.e3); mix(c.e5)
        case .ghost(let g):
            mix(g.p); mix(g.e3); mix(g.e5); mix(g.eP)
        }
        return x
    }

    private func startSelectionAnim(_ key: SelectionKey, targetOn: Bool) {
        let a = SelectionAnim(
            startTime: CACurrentMediaTime(),
            targetOn: targetOn,
            duration: selectionDuration(targetOn: targetOn),
            seed: selectionSeed(for: key)
        )
        selectionAnims[key] = a

        let work = DispatchWorkItem { [weak self] in self?.selectionAnims[key] = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + a.duration + 0.06, execute: work)
    }

    private func ratioStringPlane(_ c: LatticeCoord) -> String {
        let e3 = c.e3 + pivot.e3 + (axisShift[3] ?? 0)
        let e5 = c.e5 + pivot.e5 + (axisShift[5] ?? 0)
        let p = (e3 > 0 ? Int(pow(3.0, Double(e3))) : 1) * (e5 > 0 ? Int(pow(5.0, Double(e5))) : 1)
        let q = (e3 < 0 ? Int(pow(3.0, Double(-e3))) : 1) * (e5 < 0 ? Int(pow(5.0, Double(-e5))) : 1)
        return "\(p)/\(q)"
    }

    private func ratioStringGhost(_ g: GhostMonzo) -> String {
        let e3 = g.e3, e5 = g.e5, eP = g.eP, prime = g.p
        let p = (e3 > 0 ? Int(pow(3.0, Double(e3))) : 1)
              * (e5 > 0 ? Int(pow(5.0, Double(e5))) : 1)
              * (eP > 0 ? Int(pow(Double(prime), Double(eP))) : 1)
        let q = (e3 < 0 ? Int(pow(3.0, Double(-e3))) : 1)
              * (e5 < 0 ? Int(pow(5.0, Double(-e5))) : 1)
              * (eP < 0 ? Int(pow(Double(prime), Double(-eP))) : 1)
        return "\(p)/\(q)"
    }

    private func latticeOwnerKey(for c: LatticeCoord) -> String {
        "lattice:plane:\(c.e3):\(c.e5)"
    }

    private func latticeOwnerKey(for g: GhostMonzo) -> String {
        "lattice:ghost:\(g.p):\(g.e3):\(g.e5):\(g.eP)"
    }

    private enum AuditionSyncReason: String {
        case auditionToggle
        case selectionChange
        case octaveChange
        case resume
    }

    func octaveOffset(for c: LatticeCoord) -> Int {
        octaveOffsetByCoord[c] ?? 0
    }

    func octaveOffset(for g: GhostMonzo) -> Int {
        octaveOffsetByGhost[g] ?? 0
    }

    func setOctaveOffset(for c: LatticeCoord, to offset: Int) {
        guard selected.contains(c) else { return }
        if offset == 0 {
            octaveOffsetByCoord.removeValue(forKey: c)
        } else {
            octaveOffsetByCoord[c] = offset
        }
        syncAuditionVoicesToSelection(reason: .octaveChange)
    }

    func setOctaveOffset(for g: GhostMonzo, to offset: Int) {
        guard selectedGhosts.contains(g) else { return }
        if offset == 0 {
            octaveOffsetByGhost.removeValue(forKey: g)
        } else {
            octaveOffsetByGhost[g] = offset
        }
        syncAuditionVoicesToSelection(reason: .octaveChange)
    }

    private func configuredAttackMs() -> Double {
        ToneOutputEngine.shared.config.attackMs
    }

    private func configuredReleaseMs() -> Double {
        ToneOutputEngine.shared.config.releaseMs
    }

    private func configuredReleaseSeconds() -> Double {
        max(0.05, configuredReleaseMs() / 1000.0)
    }

    func resyncAuditionToSelection(forceRebuild: Bool, reason: String) {
        resyncAuditionToSelection(
            effectiveEnabled: auditionEnabled && latticeSoundEnabled,
            forceRebuild: forceRebuild,
            reason: reason
        )
    }

    func resyncAuditionToSelection(effectiveEnabled: Bool, forceRebuild: Bool, reason: String) {
        cancelPendingAuditions()

        let orderedPlane = selectionOrder.filter { selected.contains($0) }
        let missingPlane = selected.subtracting(Set(orderedPlane))
            .sorted { lhs, rhs in
                if lhs.e3 != rhs.e3 { return lhs.e3 < rhs.e3 }
                return lhs.e5 < rhs.e5
            }
        let desiredPlaneCoords = orderedPlane + missingPlane

        let orderedGhosts = selectionOrderGhosts.filter { selectedGhosts.contains($0) }
        let missingGhosts = selectedGhosts.subtracting(Set(orderedGhosts))
            .sorted { lhs, rhs in
                if lhs.p != rhs.p { return lhs.p < rhs.p }
                if lhs.e3 != rhs.e3 { return lhs.e3 < rhs.e3 }
                if lhs.e5 != rhs.e5 { return lhs.e5 < rhs.e5 }
                return lhs.eP < rhs.eP
            }
        let desiredGhostCoords = orderedGhosts + missingGhosts

        let desiredPlane = Set(desiredPlaneCoords)
        let desiredGhosts = Set(desiredGhostCoords)

        var desiredOwners: [String] = []
        desiredOwners.reserveCapacity(desiredPlaneCoords.count + desiredGhostCoords.count)
        desiredOwners.append(contentsOf: desiredPlaneCoords.map { latticeOwnerKey(for: $0) })
        desiredOwners.append(contentsOf: desiredGhostCoords.map { latticeOwnerKey(for: $0) })

#if DEBUG
        print(
            "[LatticeAudition] resync start forceRebuild=\(forceRebuild) auditionEnabled=\(auditionEnabled) latticeSoundEnabled=\(latticeSoundEnabled) effectiveEnabled=\(effectiveEnabled) desired=\(desiredOwners.count) selected=\(selected.count) ghosts=\(selectedGhosts.count) voices=\(voiceForCoord.count + voiceForGhost.count) reason=\(reason)"
        )
#endif
#if DEBUG
        if effectiveEnabled && selected.count > 0 && desiredPlaneCoords.isEmpty {
            assertionFailure("[LatticeAudition] desiredPlaneCoords empty with selection present reason=\(reason)")
        }
#endif

#if DEBUG
        debugLogSelectionState(reason: "resync audition \(reason)")
#endif

        guard effectiveEnabled else {
            stopSelectionAudio(hard: false)
#if DEBUG
            logLatticeAuditionSummary(
                action: "STOP_ALL",
                desiredOwners: desiredOwners,
                forceRebuild: forceRebuild,
                reason: reason
            )
#endif
            return
        }

        if forceRebuild {
            resetAuditionStateForReenable()
        }

        let attackMs = configuredAttackMs()
        let releaseMs = configuredReleaseMs()
        let releaseSeconds = configuredReleaseSeconds()

        for c in desiredPlaneCoords {
            if pausedPlane.contains(c) { continue }
            let f = exactFreq(for: c)
            let amp = amplitude(for: c)
            let existed = voiceForCoord[c] != nil
            let id = ToneOutputEngine.shared.sustain(
                freq: f,
                amp: amp,
                owner: .lattice,
                ownerKey: latticeOwnerKey(for: c),
                attackMs: attackMs,
                releaseMs: releaseMs
            )
            voiceForCoord[c] = id
#if DEBUG
            logLatticeAuditionEvent(
                existed ? "UPDATE" : "START",
                ownerKey: latticeOwnerKey(for: c),
                ratio: ratioStringPlane(c),
                freq: f,
                attackMs: attackMs,
                releaseMs: releaseMs,
                reason: reason
            )
#endif
        }

        for g in desiredGhostCoords {
            let f = exactFreq(for: g)
            let amp = amplitude(for: g)
            let existed = voiceForGhost[g] != nil
            let id = ToneOutputEngine.shared.sustain(
                freq: f,
                amp: amp,
                owner: .lattice,
                ownerKey: latticeOwnerKey(for: g),
                attackMs: attackMs,
                releaseMs: releaseMs
            )
            voiceForGhost[g] = id
#if DEBUG
            logLatticeAuditionEvent(
                existed ? "UPDATE" : "START",
                ownerKey: latticeOwnerKey(for: g),
                ratio: ratioStringGhost(g),
                freq: f,
                attackMs: attackMs,
                releaseMs: releaseMs,
                reason: reason
            )
#endif
        }

        for c in voiceForCoord.keys.filter({ !desiredPlane.contains($0) }) {
            ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: c), releaseSeconds: releaseSeconds)
            voiceForCoord.removeValue(forKey: c)
#if DEBUG
            logLatticeAuditionEvent(
                "STOP",
                ownerKey: latticeOwnerKey(for: c),
                ratio: ratioStringPlane(c),
                freq: nil,
                attackMs: nil,
                releaseMs: releaseMs,
                reason: reason
            )
#endif
        }

        for g in voiceForGhost.keys.filter({ !desiredGhosts.contains($0) }) {
            ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: g), releaseSeconds: releaseSeconds)
            voiceForGhost.removeValue(forKey: g)
#if DEBUG
            logLatticeAuditionEvent(
                "STOP",
                ownerKey: latticeOwnerKey(for: g),
                ratio: ratioStringGhost(g),
                freq: nil,
                attackMs: nil,
                releaseMs: releaseMs,
                reason: reason
            )
#endif
        }

#if DEBUG
        logLatticeAuditionSummary(
            action: "RESYNC",
            desiredOwners: desiredOwners,
            forceRebuild: forceRebuild,
            reason: reason
        )
        print(
            "[LatticeAudition] resync end forceRebuild=\(forceRebuild) selected=\(selected.count) ghosts=\(selectedGhosts.count) voices=\(voiceForCoord.count + voiceForGhost.count) reason=\(reason)"
        )
#endif
    }

    private func syncAuditionVoicesToSelection(reason: AuditionSyncReason) {
        resyncAuditionToSelection(forceRebuild: false, reason: reason.rawValue)
    }

    func normalizeSelectionState(reason: String) {
        var nextOrder = selectionOrder.filter { selected.contains($0) }
        let missingPlane = selected.subtracting(Set(nextOrder))
            .sorted { lhs, rhs in
                if lhs.e3 != rhs.e3 { return lhs.e3 < rhs.e3 }
                return lhs.e5 < rhs.e5
            }
        nextOrder.append(contentsOf: missingPlane)
        if nextOrder != selectionOrder {
            selectionOrder = nextOrder
        }

        var nextGhostOrder = selectionOrderGhosts.filter { selectedGhosts.contains($0) }
        let missingGhosts = selectedGhosts.subtracting(Set(nextGhostOrder))
            .sorted { lhs, rhs in
                if lhs.p != rhs.p { return lhs.p < rhs.p }
                if lhs.e3 != rhs.e3 { return lhs.e3 < rhs.e3 }
                if lhs.e5 != rhs.e5 { return lhs.e5 < rhs.e5 }
                return lhs.eP < rhs.eP
            }
        nextGhostOrder.append(contentsOf: missingGhosts)
        if nextGhostOrder != selectionOrderGhosts {
            selectionOrderGhosts = nextGhostOrder
        }

        if !selectionOrderKeys.isEmpty {
            let validKeys = selectionOrderKeys.filter { key in
                switch key {
                case .plane(let c):
                    return selected.contains(c)
                case .ghost(let g):
                    return selectedGhosts.contains(g)
                }
            }
            let desiredKeys = selectionOrder.map { SelectionKey.plane($0) } + selectionOrderGhosts.map { SelectionKey.ghost($0) }
            var mergedKeys = validKeys
            for key in desiredKeys where !mergedKeys.contains(key) {
                mergedKeys.append(key)
            }
            if mergedKeys != selectionOrderKeys {
                selectionOrderKeys = mergedKeys
            }
        }

#if DEBUG
        debugLogSelectionState(reason: "normalize \(reason)")
#endif
    }

#if DEBUG
    private func logLatticeAuditionEvent(
        _ kind: String,
        ownerKey: String,
        ratio: String,
        freq: Double?,
        attackMs: Double?,
        releaseMs: Double?,
        reason: String,
        callsite: StaticString = #fileID,
        line: Int = #line
    ) {
        let freqStr = freq.map { String(format: "%.2f", $0) } ?? "n/a"
        let attackStr = attackMs.map { String(format: "%.1f", $0) } ?? "n/a"
        let releaseStr = releaseMs.map { String(format: "%.1f", $0) } ?? "n/a"
        print("[LatticeAudition] \(kind) owner=\(ownerKey) ratio=\(ratio) freq=\(freqStr) attackMs=\(attackStr) releaseMs=\(releaseStr) reason=\(reason) from=\(callsite):\(line)")
    }

    private func logLatticeAuditionSummary(action: String, desiredOwners: [String], forceRebuild: Bool, reason: String) {
        let owners = desiredOwners.sorted().joined(separator: ",")
        print("[LatticeAudition] \(action) forceRebuild=\(forceRebuild) desiredOwners=[\(owners)] reason=\(reason)")
    }

    func debugLogSelectionState(reason: String) {
        print(
            "[LatticeSelection] \(reason) selected=\(selected.count) order=\(selectionOrder.count) ghosts=\(selectedGhosts.count) ghostOrder=\(selectionOrderGhosts.count) orderKeys=\(selectionOrderKeys.count)"
        )
    }
#endif

    // MARK: - Selection (plane)
    func toggleSelection(_ c: LatticeCoord, pushUndo: Bool = true) {
        let key: SelectionKey = .plane(c)
        
        if selected.contains(c) {
            selected.remove(c)
            pendingPlaneAudition[c]?.cancel()
            pendingPlaneAudition.removeValue(forKey: c)
            startSelectionAnim(key, targetOn: false)
            if let i = selectionOrder.firstIndex(of: c) { selectionOrder.remove(at: i) }
            octaveOffsetByCoord.removeValue(forKey: c)
            pausedPlane.remove(c)
        } else {
            selected.insert(c)
            LearnEventBus.shared.send(.latticeNodeSelected(ratioStringPlane(c)))

            selectionOrder.append(c)
            startSelectionAnim(key, targetOn: true)
            if auditionEnabled && latticeSoundEnabled {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
                LearnEventBus.shared.send(.latticeNodeAuditioned(ratioStringPlane(c)))
            }
        }
        if pushUndo { undoStack.append(.toggle(c: c)); redoStack.removeAll() }
        syncAuditionVoicesToSelection(reason: .selectionChange)
#if DEBUG
        debugLogSelectionState(reason: "toggle selection \(c)")
#endif
    }
    // Stop any currently-sustaining selection voices (plane + ghosts).
    func stopSelectionAudio(hard: Bool = true) {
#if DEBUG
        print(
            "[LatticeAudition] stopSelectionAudio hard=\(hard) voicesBefore=\(voiceForCoord.count + voiceForGhost.count)"
        )
#endif
        let rel = hard ? 0.0 : configuredReleaseSeconds()
        for id in voiceForCoord.values { ToneOutputEngine.shared.release(id: id, seconds: rel) }
        for c in voiceForCoord.keys { ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: c), releaseSeconds: rel) }
        for id in voiceForGhost.values { ToneOutputEngine.shared.release(id: id, seconds: rel) }
        for g in voiceForGhost.keys { ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: g), releaseSeconds: rel) }
        voiceForCoord.removeAll()
        voiceForGhost.removeAll()
        pausedPlane.removeAll()
#if DEBUG
        print(
            "[LatticeAudition] stopSelectionAudio hard=\(hard) voicesAfter=\(voiceForCoord.count + voiceForGhost.count)"
        )
#endif
    }

    private func resetAuditionStateForReenable() {
        cancelPendingAuditions()
        stopSelectionAudio(hard: true)
    }
    
    func pauseAuditionForInfoVoice(durationMS: Int) {
        guard auditionEnabled else { return }
        cancelPendingAuditions()
        stopSelectionAudio(hard: false)
        reenableAuditionWorkItem?.cancel()
        let duration = max(0.0, Double(durationMS) / 1000.0)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.resyncAuditionToSelection(forceRebuild: true, reason: "info voice resume")
        }
        reenableAuditionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
// MARK: – STOP CURRENT NODE AUDITION FOR OCTAVE SWITCHING
    // Re-start audition for the current selection set (if wanted later).
    func reAuditionSelectionIfNeeded() {
        syncAuditionVoicesToSelection(reason: .resume)
    }
    // ⬇️ ADD: track preview-paused voices so we can resume only that one
    private var pausedPlane: Set<LatticeCoord> = []

    func pauseSelectionVoice(for c: LatticeCoord, hard: Bool = true) {
        guard let id = voiceForCoord[c] else { return }
        let rel = hard ? 0.0 : configuredReleaseSeconds()
        ToneOutputEngine.shared.release(id: id, seconds: rel)
        voiceForCoord.removeValue(forKey: c)
        ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: c), releaseSeconds: rel)
        pausedPlane.insert(c)
    }

    func resumeSelectionVoiceIfNeeded(for c: LatticeCoord) {
        guard pausedPlane.remove(c) != nil else { return }               // was paused for preview?
        guard auditionEnabled, selected.contains(c), voiceForCoord[c] == nil else { return }
        guard latticeSoundEnabled else { return }
        let f = exactFreq(for: c)
        let amp = amplitude(for: c)
        let id = ToneOutputEngine.shared.sustain(
            freq: f,
            amp: amp,
            owner: .lattice,
            ownerKey: latticeOwnerKey(for: c),
            attackMs: configuredAttackMs(),
            releaseMs: configuredReleaseMs()
        )
        voiceForCoord[c] = id
    }



    // MARK: - Selection (overlay)
    /// Toggle selection for an overlay node identified by absolute monzo {3:e3,5:e5,p:eP}.
    func toggleOverlay(prime p: Int, e3: Int, e5: Int, eP: Int, pushUndo: Bool = true) {
        let g = GhostMonzo(e3: e3, e5: e5, p: p, eP: eP)

        let key: SelectionKey = .ghost(g)

        if selectedGhosts.contains(g) {
            startSelectionAnim(key, targetOn: false)
                selectedGhosts.remove(g)
            pendingGhostAudition[g]?.cancel()
            pendingGhostAudition.removeValue(forKey: g)
            if let i = selectionOrderGhosts.firstIndex(of: g) { selectionOrderGhosts.remove(at: i) }
            octaveOffsetByGhost.removeValue(forKey: g)
        } else {
            selectedGhosts.insert(g)
            LearnEventBus.shared.send(.latticeNodeSelected(ratioStringGhost(g)))

            selectionOrderGhosts.append(g)
            startSelectionAnim(key, targetOn: true)

            if auditionEnabled && latticeSoundEnabled {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
                LearnEventBus.shared.send(.latticeNodeAuditioned(ratioStringGhost(g)))
            }
        }
        if pushUndo { undoStack.append(.toggleGhost(g: g)); redoStack.removeAll() }
        syncAuditionVoicesToSelection(reason: .selectionChange)
#if DEBUG
        debugLogSelectionState(reason: "toggle ghost \(ratioStringGhost(g))")
#endif
    }

    func setPivot(_ c: LatticeCoord) { pivot = c }

    /// Clear all selections and fade out any sustaining tones.
    func clearSelection() {
        for c in selected { startSelectionAnim(.plane(c), targetOn: false) }
            for g in selectedGhosts { startSelectionAnim(.ghost(g), targetOn: false) }
        selected.removeAll()
        selectionOrder.removeAll()
        selectedGhosts.removeAll()
        selectionOrderGhosts.removeAll()
        octaveOffsetByCoord.removeAll()
        octaveOffsetByGhost.removeAll()
        pausedPlane.removeAll()
        for id in voiceForCoord.values { ToneOutputEngine.shared.release(id: id, seconds: 0.5) }
        for c in voiceForCoord.keys { ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: c), releaseSeconds: 0.5) }
        for id in voiceForGhost.values { ToneOutputEngine.shared.release(id: id, seconds: 0.5) }
        for g in voiceForGhost.keys { ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: g), releaseSeconds: 0.5) }
        voiceForCoord.removeAll()
        voiceForGhost.removeAll()
#if DEBUG
        debugLogSelectionState(reason: "clear selection")
#endif
    }

    func performBootSelectionClearIfNeeded() {
        guard !didPerformBootSelectionClear else { return }
        didPerformBootSelectionClear = true
        Self.didBootSelectionClearThisProcess = true

        cancelPendingAuditions()
        stopSelectionAudio(hard: true)
        ToneOutputEngine.shared.stopAll()

        suppressPersist = true
        clearAllSelectionsSilently()
        suppressPersist = false

        stopSelectionAudio(hard: true)
        ToneOutputEngine.shared.stopAll()
    }

    private func cancelPendingAuditions() {
        for work in pendingPlaneAudition.values { work.cancel() }
        pendingPlaneAudition.removeAll()
        for work in pendingGhostAudition.values { work.cancel() }
        pendingGhostAudition.removeAll()
    }

    private func clearAllSelectionsSilently() {
        selected.removeAll()
        selectionOrder.removeAll()
        selectedGhosts.removeAll()
        selectionOrderGhosts.removeAll()
        selectionOrderKeys.removeAll()
        selectionAnims.removeAll()
        brushVisited.removeAll()
        pausedPlane.removeAll()
        lastTriggerAt.removeAll()
        lastTriggerAtGhost.removeAll()
        octaveOffsetByCoord.removeAll()
        octaveOffsetByGhost.removeAll()
    }

    var selectedCount: Int { selectionOrder.count + selectionOrderGhosts.count }

    // ===== Builder staging (for red counter in lattice) =====
    private var stagingBaseline: Set<LatticeCoord>? = nil
    func beginStaging() { stagingBaseline = selected }
    func endStaging() { stagingBaseline = nil }
    var additionsSinceBaseline: Int {
        guard let base = stagingBaseline else { return 0 }
        return selected.subtracting(base).count
    }

    /// Ordered RatioRefs for Builder — includes plane and overlay selections.
    func selectionRefs(pivot: LatticeCoord, axisShift: [Int:Int]) -> [RatioRef] {
        var refs: [RatioRef] = []

        // Plane (3×5)
        refs += selectionOrder.map { c in
            let e3 = c.e3 + pivot.e3 + (axisShift[3] ?? 0)
            let e5 = c.e5 + pivot.e5 + (axisShift[5] ?? 0)
            let p = (e3 > 0 ? Int(pow(3.0, Double(e3))) : 1) * (e5 > 0 ? Int(pow(5.0, Double(e5))) : 1)
            let q = (e3 < 0 ? Int(pow(3.0, Double(-e3))) : 1) * (e5 < 0 ? Int(pow(5.0, Double(-e5))) : 1)
            let octave = octaveOffsetByCoord[c] ?? 0
            return RatioRef(p: p, q: q, octave: octave, monzo: [3:e3, 5:e5])
        }

        // Overlays (higher primes)
        refs += selectionOrderGhosts.map { g in
            let e3 = g.e3, e5 = g.e5, eP = g.eP, pPrime = g.p
            let pNum = (e3 > 0 ? Int(pow(3.0, Double(e3))) : 1)
                      * (e5 > 0 ? Int(pow(5.0, Double(e5))) : 1)
                      * (eP > 0 ? Int(pow(Double(pPrime), Double(eP))) : 1)
            let qDen = (e3 < 0 ? Int(pow(3.0, Double(-e3))) : 1)
                      * (e5 < 0 ? Int(pow(5.0, Double(-e5))) : 1)
                      * (eP < 0 ? Int(pow(Double(pPrime), Double(-eP))) : 1)
            var monzo: [Int:Int] = [3:e3, 5:e5]
            monzo[pPrime] = eP
            let octave = octaveOffsetByGhost[g] ?? 0
            return RatioRef(p: pNum, q: qDen, octave: octave, monzo: monzo)
        }

        return refs
    }

    // MARK: - Persistence (UserDefaults)
    private let persistKey = "lattice.persist.v1"
    private var saveWorkItem: DispatchWorkItem?

    struct PersistBlob: Codable {
        struct Cam: Codable { let tx: Double; let ty: Double; let scale: Double }
        struct Coord: Codable { let e3: Int; let e5: Int }
        let camera: Cam
        let pivot: Coord
        let visiblePrimes: [Int]
        let axisShift: [Int:Int]
        let mode: String
        let selected: [Coord]
        let guidesOn: Bool
        let labelMode: String
        let audition: Bool
    }

    private func scheduleSave() {
        guard !suppressPersist else { return }
        saveWorkItem?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: job)
    }

    @discardableResult
        func load() -> Bool {
            guard rememberLastViewSetting else { return false }
            guard let data = UserDefaults.standard.data(forKey: persistKey) else { return false }
            if let blob = try? JSONDecoder().decode(PersistBlob.self, from: data) {
            camera.translation = CGPoint(x: blob.camera.tx, y: blob.camera.ty)
            camera.scale = CGFloat(blob.camera.scale)
            pivot = LatticeCoord(e3: blob.pivot.e3, e5: blob.pivot.e5)
            visiblePrimes = Set(blob.visiblePrimes)
            visiblePrimes.subtract([2, 3, 5])
            let defaults = axisShift
            axisShift = defaults.merging(blob.axisShift) { _, new in new }
            mode = LatticeMode(rawValue: blob.mode) ?? .explore
            if Self.didBootSelectionClearThisProcess {
                selected = Set(blob.selected.map { LatticeCoord(e3: $0.e3, e5: $0.e5) })
            } else {
                clearAllSelectionsSilently()
            }
            guidesOn = blob.guidesOn
            labelMode = JILabelMode(rawValue: blob.labelMode) ?? .ratio
            auditionEnabled = blob.audition
                didRestorePersist = true
                return true
        }
            return false

    }

    private func save() {
        guard rememberLastViewSetting else { return }
        let blob = PersistBlob(
            camera: .init(tx: camera.translation.x, ty: camera.translation.y, scale: Double(camera.scale)),
            pivot: .init(e3: pivot.e3, e5: pivot.e5),
            visiblePrimes: Array(visiblePrimes).sorted(),
            axisShift: axisShift,
            mode: mode.rawValue,
            selected: selected.map { PersistBlob.Coord(e3: $0.e3, e5: $0.e5) },
            guidesOn: guidesOn,
            labelMode: labelMode.rawValue,
            audition: auditionEnabled
        )
        if let data = try? JSONEncoder().encode(blob) {
            UserDefaults.standard.set(data, forKey: persistKey)
        }
    }

    // MARK: - Init
    private var cancellables = Set<AnyCancellable>()

    init() {
        let didLoad = load()
                if !didLoad {
                    // No persisted camera yet → seed from the user’s default preset.
                    camera.scale = defaultZoomScale()
                }
        // Settings bootstrap
        let ud = UserDefaults.standard

        // Label mode
        let labStr = ud.string(forKey: SettingsKeys.labelDefault) ?? "ratio"
        self.labelMode = (labStr == "heji") ? .heji : .ratio

        // Overlays: 7 & 11 are governed by SettingsKeys.*; higher primes come from persistence (if any).
        let want7  = (ud.object(forKey: SettingsKeys.overlay7)  == nil) || ud.bool(forKey: SettingsKeys.overlay7)
        let want11 = (ud.object(forKey: SettingsKeys.overlay11) == nil) || ud.bool(forKey: SettingsKeys.overlay11)

        if !didRestorePersist {
            visiblePrimes = []
        }

        if want7  { visiblePrimes.insert(7)  } else { visiblePrimes.remove(7)  }
        if want11 { visiblePrimes.insert(11) } else { visiblePrimes.remove(11) }

        visiblePrimes.subtract([2, 3, 5])

        // Guides
        if ud.object(forKey: SettingsKeys.guidesOn) != nil {
            self.guidesOn = ud.bool(forKey: SettingsKeys.guidesOn)
        } else {
            self.guidesOn = true
        }
        
        if let raw = UserDefaults.standard.string(forKey: SettingsKeys.tenneyDistanceMode),
           let m = TenneyDistanceMode(rawValue: raw) {
            tenneyDistanceMode = m
        } else {
            tenneyDistanceMode = .breakdown
        }

        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            
            if note.userInfo?[SettingsKeys.latticeSoundEnabled] != nil {
                self.latticeSoundEnabled = Self.readLatticeSoundEnabled()
                if !self.latticeSoundEnabled {
                    self.stopAllLatticeVoices(hard: true)
                }
            }

            if let raw = note.userInfo?[SettingsKeys.tenneyDistanceMode] as? String,
               let m = TenneyDistanceMode(rawValue: raw) {
                self.tenneyDistanceMode = m
            }

            if let v = note.userInfo?[SettingsKeys.labelDefault] as? String {
                self.labelMode = (v == "heji") ? .heji : .ratio
            }
            if note.userInfo?[SettingsKeys.overlay7] != nil {
                let on = (UserDefaults.standard.object(forKey: SettingsKeys.overlay7) == nil)
                      || UserDefaults.standard.bool(forKey: SettingsKeys.overlay7)
                self.setPrimeVisible(7, on, animated: true)
            }
            if note.userInfo?[SettingsKeys.overlay11] != nil {
                let on = (UserDefaults.standard.object(forKey: SettingsKeys.overlay11) == nil)
                      || UserDefaults.standard.bool(forKey: SettingsKeys.overlay11)
                self.setPrimeVisible(11, on, animated: true)
            }

            // Keep these excluded defensively.
            self.visiblePrimes.subtract([2, 3, 5])

            if let g = note.userInfo?[SettingsKeys.guidesOn] as? Bool {
                self.guidesOn = g
            }
        }

        visiblePrimes.subtract([2, 3, 5])
        // Keep UtilityBar audition + Lattice toolbar audition in lockstep.
        if let app = AppModelLocator.shared {
            self.auditionEnabled = app.latticeAuditionOn

            app.$latticeAuditionOn
                .removeDuplicates()
                .sink { [weak self] on in
                    guard let self else { return }
                    if self.auditionEnabled != on { self.auditionEnabled = on }
                }
                .store(in: &cancellables)
        }

        latticeSoundEnabled = Self.readLatticeSoundEnabled()

        Publishers.CombineLatest(
            $auditionEnabled.removeDuplicates(),
            $latticeSoundEnabled.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .debounce(for: .milliseconds(0), scheduler: RunLoop.main)
        .dropFirst()
        .sink { [weak self] audition, sound in
            guard let self else { return }
            let effectiveEnabled = audition && sound
            self.auditionGateSequence += 1
            AppModelLocator.shared?.playTestTone = false
#if DEBUG
            print(
                "[LatticeAudition] gateSeq=\(self.auditionGateSequence) audition=\(audition) sound=\(sound) effectiveEnabled=\(effectiveEnabled) selected=\(self.selected.count)"
            )
            self.debugLogSelectionState(reason: "audition/sound gate \(self.auditionGateSequence)")
#endif
            self.resyncAuditionToSelection(
                effectiveEnabled: effectiveEnabled,
                forceRebuild: true,
                reason: "audition/sound gate changed"
            )
        }
        .store(in: &cancellables)

        // Auto-save on any relevant change
        $camera.dropFirst().sink { [weak self] _ in self?.scheduleSave() }.store(in: &cancellables)
        $pivot.dropFirst().sink { [weak self] _ in self?.scheduleSave() }.store(in: &cancellables)
        $visiblePrimes.dropFirst().sink { [weak self] _ in self?.scheduleSave() }.store(in: &cancellables)
        $axisShift.dropFirst().sink { [weak self] _ in self?.scheduleSave() }.store(in: &cancellables)
        $mode.dropFirst().sink { [weak self] _ in self?.scheduleSave() }.store(in: &cancellables)
        $selected.dropFirst().sink { [weak self] _ in self?.scheduleSave() }.store(in: &cancellables)
    }

    // MARK: - Audio helpers
    private var lastTriggerAt: [LatticeCoord: Date] = [:]
    private var voiceForCoord: [LatticeCoord: Int] = [:]
    private var lastTriggerAtGhost: [GhostMonzo: Date] = [:]
    private var voiceForGhost: [GhostMonzo: Int] = [:]
    private var reenableAuditionWorkItem: DispatchWorkItem?
    private var auditionGateSequence: Int = 0
    
    private static func readLatticeSoundEnabled() -> Bool {
        let ud = UserDefaults.standard
        if ud.object(forKey: SettingsKeys.latticeSoundEnabled) == nil { return true }
        return ud.bool(forKey: SettingsKeys.latticeSoundEnabled)
    }

    /// Exact-ratio frequency for a 3×5-plane coord, folded into [root/2, 2*root].
    private func exactFreq(for c: LatticeCoord) -> Double {
        // raw exponents including pivot & axis shift
        let e3 = c.e3 + pivot.e3 + (axisShift[3] ?? 0)
        let e5 = c.e5 + pivot.e5 + (axisShift[5] ?? 0)

        var num = (e3 >= 0 ? Int(pow(3.0, Double(e3))) : 1) * (e5 >= 0 ? Int(pow(5.0, Double(e5))) : 1)
        var den = (e3 <  0 ? Int(pow(3.0, Double(-e3))) : 1) * (e5 <  0 ? Int(pow(5.0, Double(-e5))) : 1)

        // Canonicalize to [1, 2)
        while Double(num) / Double(den) >= 2.0 { den &*= 2 }
        while Double(num) / Double(den) <  1.0 { num &*= 2 }

        let root = AppModelLocator.shared?.rootHz ?? 415.0
        let octaveOffset = octaveOffsetByCoord[c] ?? 0
        var f = root * (Double(num) / Double(den)) * pow(2.0, Double(octaveOffset))
        if UserDefaults.standard.bool(forKey: SettingsKeys.foldAudible) {
            let lo = 20.0, hi = 5000.0
            while f < lo { f *= 2 }
            while f > hi { f *= 0.5 }
        }
        return f
    }

    private func exactFreq(for g: GhostMonzo) -> Double {
        let e3 = g.e3, e5 = g.e5, eP = g.eP, pPrime = g.p
        var num = (e3 >= 0 ? Int(pow(3.0, Double(e3))) : 1)
                * (e5 >= 0 ? Int(pow(5.0, Double(e5))) : 1)
                * (eP >= 0 ? Int(pow(Double(pPrime), Double(eP))) : 1)
        var den = (e3 <  0 ? Int(pow(3.0, Double(-e3))) : 1)
                * (e5 <  0 ? Int(pow(5.0, Double(-e5))) : 1)
                * (eP <  0 ? Int(pow(Double(pPrime), Double(-eP))) : 1)

        while Double(num) / Double(den) >= 2.0 { den &*= 2 }
        while Double(num) / Double(den) <  1.0 { num &*= 2 }

        let root = AppModelLocator.shared?.rootHz ?? 415.0
        let octaveOffset = octaveOffsetByGhost[g] ?? 0
        var f = root * (Double(num) / Double(den)) * pow(2.0, Double(octaveOffset))
        if UserDefaults.standard.bool(forKey: SettingsKeys.foldAudible) {
            let lo = 20.0, hi = 5000.0
            while f < lo { f *= 2 }
            while f > hi { f *= 0.5 }
        }
        return f
    }

    /// Slight loudness boost for simpler ratios (by Tenney height), clamped.
    /// Pure-sine verification: fixed, conservative level to avoid clipping while we validate.
    private func amplitude(for _: LatticeCoord) -> Float {
        let v = UserDefaults.standard.double(forKey: SettingsKeys.safeAmp)
        return Float(v > 0 ? v : 0.18)
    }

    private func amplitude(for _: GhostMonzo) -> Float {
        let v = UserDefaults.standard.double(forKey: SettingsKeys.safeAmp)
        return Float(v > 0 ? v : 0.18)
    }
     func stopAllLatticeVoices(hard: Bool) {
         if hard {
                ToneOutputEngine.shared.stopAll()
                voiceForCoord.removeAll()
                voiceForGhost.removeAll()
                return
            }
            let rel = configuredReleaseSeconds()
            for id in voiceForCoord.values { ToneOutputEngine.shared.release(id: id, seconds: rel) }
            for c in voiceForCoord.keys { ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: c), releaseSeconds: rel) }
            for id in voiceForGhost.values { ToneOutputEngine.shared.release(id: id, seconds: rel) }
            for g in voiceForGhost.keys { ToneOutputEngine.shared.stop(ownerKey: latticeOwnerKey(for: g), releaseSeconds: rel) }
            voiceForCoord.removeAll()
            voiceForGhost.removeAll()
            pausedPlane.removeAll()
    }

}
extension LatticeStore {
    /// Exactly two **plane** nodes selected, in order; ignores overlay selections.
    func selectedPair() -> (LatticeCoord, LatticeCoord)? {
        guard selectionOrderGhosts.isEmpty, selectionOrder.count == 2 else { return nil }
        return (selectionOrder[0], selectionOrder[1])
    }
}
