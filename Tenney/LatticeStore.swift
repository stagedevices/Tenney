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

    // Overlay (higher-prime) selections: absolute world monzos
    struct GhostMonzo: Hashable {
        let e3: Int, e5: Int, p: Int, eP: Int   // monzo {3:e3, 5:e5, p:eP}
    }
    @Published var selectedGhosts: Set<GhostMonzo> = []
    @Published var selectionOrderGhosts: [GhostMonzo] = []

    @Published var auditionEnabled: Bool = true
    @Published var guidesOn: Bool = true
    @Published var labelMode: JILabelMode = .ratio
    @Published var showHelp: Bool = false

    /// Which higher primes are visible as overlays (defaults: 7 & 11 on)
    @Published var visiblePrimes: Set<Int> = [7, 11]

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
        if visiblePrimes.contains(p) { visiblePrimes.remove(p) } else { visiblePrimes.insert(p) }
    }

    // MARK: - Undo/Redo
    private enum Action { case shift(p:Int, delta:Int), toggle(c:LatticeCoord), toggleGhost(g:GhostMonzo) }
    private var undoStack: [Action] = []
    private var redoStack: [Action] = []

    func undo() {
        guard let a = undoStack.popLast() else { return }
        switch a {
        case .shift(let p, let d):
            axisShift[p, default: 0] -= d
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
            axisShift[p, default: 0] += d
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
        axisShift[p, default: 0] += delta
        undoStack.append(.shift(p: p, delta: delta))
        redoStack.removeAll()
    }

    func resetShift(prime p: Int? = nil) {
        if let p { axisShift[p] = 0 }
        else { for k in axisShift.keys { axisShift[k] = 0 } }
    }

    // MARK: - Selection (plane)
    func toggleSelection(_ c: LatticeCoord, pushUndo: Bool = true) {
        if selected.contains(c) {
            selected.remove(c)
            if let i = selectionOrder.firstIndex(of: c) { selectionOrder.remove(at: i) }
            if let vid = voiceForCoord[c] {
                let rel = max(0.05, UserDefaults.standard.double(forKey: SettingsKeys.releaseSec))
                LatticeTone.shared.release(id: vid, releaseSeconds: rel)
                voiceForCoord.removeValue(forKey: c)
            }
        } else {
            selected.insert(c)
            selectionOrder.append(c)
            if auditionEnabled {
                let now = Date()
                if let last = lastTriggerAt[c], now.timeIntervalSince(last) < 0.12 {
                    // rate limit: 120 ms per node
                } else {
                    let f = exactFreq(for: c)
                    let amp = amplitude(for: c)
                    let attack = UserDefaults.standard.double(forKey: SettingsKeys.attackMs)
                    let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
                    voiceForCoord[c] = id
                    lastTriggerAt[c] = now
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred(intensity: 0.9)
                }
            }
        }
        if pushUndo { undoStack.append(.toggle(c: c)); redoStack.removeAll() }
    }
    // Stop any currently-sustaining selection voices (plane + ghosts).
    func stopSelectionAudio(hard: Bool = true) {
        let rel = hard ? 0.0 : max(0.05, UserDefaults.standard.double(forKey: SettingsKeys.releaseSec))
        for id in voiceForCoord.values { LatticeTone.shared.release(id: id, releaseSeconds: rel) }
        for id in voiceForGhost.values { LatticeTone.shared.release(id: id, releaseSeconds: rel) }
        voiceForCoord.removeAll()
        voiceForGhost.removeAll()
    }
// MARK: – STOP CURRENT NODE AUDITION FOR OCTAVE SWITCHING
    // Re-start audition for the current selection set (if wanted later).
    func reAuditionSelectionIfNeeded() {
        guard auditionEnabled else { return }
        let attack = UserDefaults.standard.double(forKey: SettingsKeys.attackMs)
        for c in selectionOrder {
            let f = exactFreq(for: c)
            let amp = amplitude(for: c)
            let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
            voiceForCoord[c] = id
        }
        for g in selectionOrderGhosts {
            let f = exactFreq(for: g)
            let amp = amplitude(for: g)
            let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
            voiceForGhost[g] = id
        }
    }
    // ⬇️ ADD: track preview-paused voices so we can resume only that one
    private var pausedPlane: Set<LatticeCoord> = []

    func pauseSelectionVoice(for c: LatticeCoord, hard: Bool = true) {
        guard let id = voiceForCoord[c] else { return }
        let rel = hard ? 0.0 : max(0.05, UserDefaults.standard.double(forKey: SettingsKeys.releaseSec))
        LatticeTone.shared.release(id: id, releaseSeconds: rel)
        voiceForCoord.removeValue(forKey: c)
        pausedPlane.insert(c)
    }

    func resumeSelectionVoiceIfNeeded(for c: LatticeCoord) {
        guard pausedPlane.remove(c) != nil else { return }               // was paused for preview?
        guard auditionEnabled, selected.contains(c), voiceForCoord[c] == nil else { return }
        let f = exactFreq(for: c)
        let amp = amplitude(for: c)
        let attack = UserDefaults.standard.double(forKey: SettingsKeys.attackMs)
        let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
        voiceForCoord[c] = id
    }



    // MARK: - Selection (overlay)
    /// Toggle selection for an overlay node identified by absolute monzo {3:e3,5:e5,p:eP}.
    func toggleOverlay(prime p: Int, e3: Int, e5: Int, eP: Int, pushUndo: Bool = true) {
        let g = GhostMonzo(e3: e3, e5: e5, p: p, eP: eP)
        if selectedGhosts.contains(g) {
            selectedGhosts.remove(g)
            if let i = selectionOrderGhosts.firstIndex(of: g) { selectionOrderGhosts.remove(at: i) }
            if let vid = voiceForGhost[g] {
                let rel = max(0.05, UserDefaults.standard.double(forKey: SettingsKeys.releaseSec))
                LatticeTone.shared.release(id: vid, releaseSeconds: rel)
                voiceForGhost.removeValue(forKey: g)
            }
        } else {
            selectedGhosts.insert(g)
            selectionOrderGhosts.append(g)
            if auditionEnabled {
                let now = Date()
                if let last = lastTriggerAtGhost[g], now.timeIntervalSince(last) < 0.12 {
                    // rate-limit
                } else {
                    let f = exactFreq(for: g)
                    let amp = amplitude(for: g)
                    let attack = UserDefaults.standard.double(forKey: SettingsKeys.attackMs)
                    let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
                    voiceForGhost[g] = id
                    lastTriggerAtGhost[g] = now
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred(intensity: 0.9)
                }
            }
        }
        if pushUndo { undoStack.append(.toggleGhost(g: g)); redoStack.removeAll() }
    }

    func setPivot(_ c: LatticeCoord) { pivot = c }

    /// Clear all selections and fade out any sustaining tones.
    func clearSelection() {
        selected.removeAll()
        selectionOrder.removeAll()
        selectedGhosts.removeAll()
        selectionOrderGhosts.removeAll()
        for id in voiceForCoord.values { LatticeTone.shared.release(id: id, releaseSeconds: 0.5) }
        for id in voiceForGhost.values { LatticeTone.shared.release(id: id, releaseSeconds: 0.5) }
        voiceForCoord.removeAll()
        voiceForGhost.removeAll()
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
            return RatioRef(p: p, q: q, octave: 0, monzo: [3:e3, 5:e5])
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
            return RatioRef(p: pNum, q: qDen, octave: 0, monzo: monzo)
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
        saveWorkItem?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: job)
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: persistKey) else { return }
        if let blob = try? JSONDecoder().decode(PersistBlob.self, from: data) {
            camera.translation = CGPoint(x: blob.camera.tx, y: blob.camera.ty)
            camera.scale = CGFloat(blob.camera.scale)
            pivot = LatticeCoord(e3: blob.pivot.e3, e5: blob.pivot.e5)
            visiblePrimes = Set(blob.visiblePrimes)
            visiblePrimes.subtract([2, 3, 5])

            axisShift = blob.axisShift
            mode = LatticeMode(rawValue: blob.mode) ?? .explore
            selected = Set(blob.selected.map { LatticeCoord(e3: $0.e3, e5: $0.e5) })
            guidesOn = blob.guidesOn
            labelMode = JILabelMode(rawValue: blob.labelMode) ?? .ratio
            auditionEnabled = blob.audition
        }
    }

    private func save() {
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
        load()

        // Settings bootstrap
        let ud = UserDefaults.standard

        // Label mode
        let labStr = ud.string(forKey: SettingsKeys.labelDefault) ?? "ratio"
        self.labelMode = (labStr == "heji") ? .heji : .ratio

        // Overlays (default to 7+11 true if keys absent)
        var primes: Set<Int> = []
        if ud.object(forKey: SettingsKeys.overlay7) == nil || ud.bool(forKey: SettingsKeys.overlay7) { primes.insert(7) }
        if ud.object(forKey: SettingsKeys.overlay11) == nil || ud.bool(forKey: SettingsKeys.overlay11) { primes.insert(11) }
        self.visiblePrimes = primes
        self.visiblePrimes.subtract([2, 3, 5])

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
            
            if let raw = note.userInfo?[SettingsKeys.tenneyDistanceMode] as? String,
               let m = TenneyDistanceMode(rawValue: raw) {
                self.tenneyDistanceMode = m
            }

            if let v = note.userInfo?[SettingsKeys.labelDefault] as? String {
                self.labelMode = (v == "heji") ? .heji : .ratio
            }
            if note.userInfo?[SettingsKeys.overlay7] != nil || note.userInfo?[SettingsKeys.overlay11] != nil {
                var p = self.visiblePrimes
                if UserDefaults.standard.object(forKey: SettingsKeys.overlay7) == nil
                    || UserDefaults.standard.bool(forKey: SettingsKeys.overlay7) { _ = p.insert(7) } else { _ = p.remove(7) }
                if UserDefaults.standard.object(forKey: SettingsKeys.overlay11) == nil
                    || UserDefaults.standard.bool(forKey: SettingsKeys.overlay11) { _ = p.insert(11) } else { _ = p.remove(11) }
                p.subtract([2, 3, 5])
                self.visiblePrimes = p
            }
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
                    if let app = AppModelLocator.shared, app.latticeAuditionOn != on {
                        app.latticeAuditionOn = on
                    }

                    if self.auditionEnabled != on { self.auditionEnabled = on }
                }
                .store(in: &cancellables)
        }

        // Audition toggle: start/stop lattice tones, and ensure app test tone is off to keep output clean.
        $auditionEnabled
            .dropFirst()
            .sink { [weak self] on in
                guard let self = self else { return }
                AppModelLocator.shared?.playTestTone = false
                if on {
                    if self.selectionOrder.isEmpty && self.selectionOrderGhosts.isEmpty {
                        // Select AND start 1/1 explicitly (no dependence on toggleSelection side-effects).
                        let unison = LatticeCoord(e3: 0, e5: 0)
                        self.selected.insert(unison)
                        self.selectionOrder.append(unison)
                        let f = self.exactFreq(for: unison)
                        let amp = self.amplitude(for: unison)
                        let attack = UserDefaults.standard.double(forKey: SettingsKeys.attackMs)
                        let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
                        self.voiceForCoord[unison] = id
                    } else {
                        // Start sustained tones for all current selections.
                        for c in self.selectionOrder {
                            let f = self.exactFreq(for: c)
                            let amp = self.amplitude(for: c)
                            let attack = UserDefaults.standard.double(forKey: SettingsKeys.attackMs)
                            let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
                            self.voiceForCoord[c] = id
                        }
                        for g in self.selectionOrderGhosts {
                            let f = self.exactFreq(for: g)
                            let amp = self.amplitude(for: g)
                            let attack = UserDefaults.standard.double(forKey: SettingsKeys.attackMs)
                            let id = LatticeTone.shared.sustain(freq: f, amp: amp, attackMs: attack > 0 ? attack : 10)
                            self.voiceForGhost[g] = id
                        }
                    }
                } else {
                    LatticeTone.shared.stopAll()
                    self.voiceForCoord.removeAll()
                    self.voiceForGhost.removeAll()
                }
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
        var f = root * (Double(num) / Double(den))
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
        var f = root * (Double(num) / Double(den))
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
}
extension LatticeStore {
    /// Exactly two **plane** nodes selected, in order; ignores overlay selections.
    func selectedPair() -> (LatticeCoord, LatticeCoord)? {
        guard selectionOrderGhosts.isEmpty, selectionOrder.count == 2 else { return nil }
        return (selectionOrder[0], selectionOrder[1])
    }
}
