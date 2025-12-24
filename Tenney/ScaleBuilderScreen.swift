//
//  ScaleBuilderScreen.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/4/25.

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
struct ScaleBuilderScreen: View {
    @State private var padOctaveOffset: [Int: Int] = [:]
    
    @AppStorage("Tenney.SoundOn") private var soundOn: Bool = true
    @AppStorage(SettingsKeys.safeAmp) private var safeAmp: Double = 0.18

    @ObservedObject var store: ScaleBuilderStore
    @ObservedObject var lib = ScaleLibraryStore.shared
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: ScaleLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showLibrary = false
    @State private var showSavedToast = false
    @State private var latched = Set<Int>()
        @State private var voiceForIndex: [Int:Int] = [:]   // BuilderTone voice IDs
        @State private var selectedPad: Int? = nil          // ⬅️ inspector selection
        @State private var enteredWithSoundOn: Bool = true
    @State private var pausedMicForBuilder = false
    @Namespace private var saveSlot
    // Builder audio defaults (sheet-level). Per-pad overrides can be added later.
        // Remember global sound state so we can force-on in Builder and restore on exit.
        @State private var wasSoundOnBeforePresenting: Bool? = nil
    // name conflict prompt
        @State private var pendingSnapshot: TenneyScale? = nil
        @State private var showSaveConflict = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
            header
            if let warn = store.warningText {
                Text(warn).font(.footnote).foregroundStyle(.orange)
            }
            pads
            toolbar
        }
            .padding(.horizontal, 20)
             .padding(.top, 20) // extra breathing room from the detent edge
        .navigationTitle("Scale Builder")
        .sheet(isPresented: $showLibrary) {
                    ScaleLibraryScreen(isPresented: $showLibrary) { chosen in
                        // Replace working buffer with selected scale (toast, no text)
                        store.name = chosen.name
                        store.descriptionText = chosen.descriptionText
                        store.payload.rootHz = chosen.referenceHz
                        store.payload.items = chosen.degrees
                        store.rebuild()
                        withAnimation(.spring(duration: 0.35)) { showSavedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            withAnimation(.spring(duration: 0.25)) { showSavedToast = false }
                        }
                    } onPlayPreview: { scale in
                        // Optional: play ascending scale quickly (non-blocking)
                        playScalePreview(scale)
                    }
                }
        .onChange(of: store.degrees) { _ in
                    // Any structural change (including Clear) → silence and reset offsets
                    stopAllPadVoices()
                    padOctaveOffset.removeAll()
                }
                    .onChange(of: soundOn) { enabled in
                        // Hard mute when toggled off
                                if !enabled { stopAllPadVoices() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .tenneyStepPadOctave)) { note in
                                guard
                                    let u = note.userInfo,
                                    let idx = u["idx"] as? Int,
                                    let delta = u["delta"] as? Int
                                else { return }
                                stepPadOctave(idx: idx, delta: delta)
                            }

                .onAppear {
                    // Pause tuner mic while in Builder (restored on exit)
                                        app.setMicActive(false)
                                            pausedMicForBuilder = true
                    // If opening an existing saved scale, load it now
                                        if let s = store.payload.existing {
                                            store.name = s.name
                                            store.descriptionText = s.descriptionText
                                            store.payload.rootHz = s.referenceHz
                                            store.payload.items = s.degrees
                                            store.rebuild()
                                        }
                    
                                        // sound gating per spec (turn on while in Builder, and remember original)
                                        enteredWithSoundOn = soundOn
                                        soundOn = true
                    
                                        if store.payload.autoplayAll {
                            for (idx, r) in store.degrees.enumerated() {
                                if !latched.contains(idx) {
                                    if soundOn {
                                        toggleLatch(idx: idx, ratio: r)          // plays
                                    } else {
                                        latched.insert(idx)                       // select but no audio
                                        voiceForIndex[idx] = nil
                                    }
                                }
                            }
                        } else {
                        // ensure silent
                            for id in voiceForIndex.values { ToneOutputEngine.shared.release(id: id, seconds: 0.0) }
                        voiceForIndex.removeAll(); latched.removeAll()
                    }
                }
        // release all latched voices when the sheet closes
                .onDisappear {
                    stopAllPadVoices()
                                        // restore sound toggle if it was off before
                                        if !enteredWithSoundOn { soundOn = false }
                    if pausedMicForBuilder {
                                            app.setMicActive(true)
                                            pausedMicForBuilder = false
                                        }
                                }
                    
                    .onChange(of: soundOn) { enabled in
                        if !enabled { stopAllPadVoices() } // hard mute when toggled off
                    }


            // ⬆️ SAVE SLOT (magic-replace): 44×44 circle in both states
                       Group {
                           if showSavedToast {
                               ZStack {
                                   // toast background (same size as button)
                                   Circle()
                                       .fill(.thinMaterial)
                                   Image(systemName: "checkmark")
                                       .font(.system(size: 18, weight: .bold))
                                       .foregroundStyle(.green)
                               }
                               .frame(width: 44, height: 44)
                               .matchedGeometryEffect(id: "saveSlot", in: saveSlot)
                               .transition(.scale.combined(with: .opacity))
                               .padding(8)
                               .accessibilityHidden(true)
                           } else {
                               ZStack {
                                   // glass button background
                                   Circle()
                                       .modifier(GlassBlueCircle())
                                   Image(systemName: "checkmark")
                                       .font(.system(size: 18, weight: .bold))
                                       .foregroundStyle(.white)
                               }
                               .frame(width: 44, height: 44)
                               .contentShape(Circle())
                               .onTapGesture { performSave() }
                               .matchedGeometryEffect(id: "saveSlot", in: saveSlot)
                               .padding(8)
                               .accessibilityLabel("Save scale to Library")
                               .accessibilityAddTraits(.isButton)
                           }
                       }
                       .padding(.horizontal, 8)
                        .padding(.top, 8) // extra breathing room from the detent edge
                    }
        // Name conflict dialog must be attached to the view, not inside a closure
                .confirmationDialog(
                    "A scale named “\(resolvedName())” already exists.",
                    isPresented: $showSaveConflict,
                    titleVisibility: SwiftUI.Visibility.visible
                ) {
                    Button("Replace Existing", role: .destructive) {
                        guard let snap = pendingSnapshot else { return }
                        if let existing = library.scales.values.first(where: { $0.name == snap.name }) {
                            let replaced = TenneyScale(
                                id: existing.id,
                                name: snap.name,
                                descriptionText: snap.descriptionText,
                                degrees: snap.degrees,
                                tags: existing.tags,
                                favorite: existing.favorite,
                                lastPlayed: Date(),
                                referenceHz: snap.referenceHz,
                                detectedLimit: TenneyScale.detectedLimit(for: snap.degrees),
                                periodRatio: 2.0,
                                maxTenneyHeight: TenneyScale.maxTenneyHeight(for: snap.degrees),
                                author: existing.author
                            )
                            library.updateScale(replaced)
                        }
                        saveToast()
                    }
                    Button("Save Both") {
                        guard var snap = pendingSnapshot else { return }
                        snap.name = nextAvailableName(base: snap.name)
                        library.addScale(snap)
                        saveToast()
                    }
                    Button("Cancel", role: .cancel) { pendingSnapshot = nil }
                }
        
    }

    private var header: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    
                    TextField("Untitled Scale", text: $store.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                    Spacer()
                }
                TextField("Description / notes", text: $store.descriptionText, axis: .vertical)
                    .font(.callout).lineLimit(1...3)
    
                HStack(spacing: 8) {
                    // Auto-filled prime limit chip (non-interactive)
                                        HStack(spacing: 6) {
                                            
                                            Text("\(store.detectedPrimeLimit)-limit JI")
                                                .font(.callout.weight(.semibold))
                                            // Root Hz pill (read-only display)
                                                            Text("Root \(Int(store.payload.rootHz)) Hz")
                                                                .font(.caption.monospacedDigit())
                                                                .padding(.horizontal, 10).padding(.vertical, 6)

                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.thinMaterial, in: Capsule())
                    Spacer()
                    Button {
                        app.builderStagingBaseCount = store.degrees.count
                        dismiss()
                    } label: { Text("Add from Lattice").fontWeight(.semibold) }
                    .buttonStyle(.borderedProminent)
                }
            }
       }

   
    
        private var pads: some View {
        // Large tap zones for performance; two columns by default
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(minimum: 140), spacing: 10),
                                GridItem(.flexible(minimum: 140), spacing: 10)],
                      spacing: 10) {
                // 🔷 Special card: Lissajous oscilloscope (spans both columns)
                               LissajousCard(
                                   rootHz: store.payload.rootHz,
                                   chosenRatios: store.degrees
                               )
                               .frame(minHeight: 220)                // iPhone; grows on iPad naturally
                               .gridCellColumns(2)                   // span both columns
                               .accessibilityIdentifier("LissajousCard")
                ForEach(Array(store.degrees.enumerated()), id: \.offset) { idx, r in
                    let root = store.payload.rootHz
                    let offset = padOctaveOffset[idx, default: 0]
                    let adjusted = RatioRef(p: r.p, q: r.q, octave: r.octave + offset, monzo: r.monzo)

                    // Canonicalize p/q for display + audio, but include adjusted octave for Hz
                    let (cn, cd) = canonicalPQUnit(adjusted.p, adjusted.q)
                    let baseHz = root * (Double(cn) / Double(cd)) * pow(2.0, Double(adjusted.octave))
                    let hz = foldToAudible(baseHz)
                    let cents = 1200.0 * log2(Double(cn) / Double(cd))   // cents from p/q (octave invariant)
                    let (name, oct) = NotationFormatter.staffNoteName(freqHz: hz)

                    Button {
                                            selectedPad = idx
                                            toggleLatch(idx: idx, ratio: r)
                                        } label: {
                                       HStack(spacing: 6) {
                                           Text("\(cn)/\(cd)")
                                                   .font(.system(.title3, design: .monospaced).weight(.semibold))
                                               if offset != 0 {
                                                   Text("(\(offset > 0 ? "+\(offset)" : "\(offset)") oct)")
                                                       .font(.caption2.weight(.semibold))
                                                       .padding(.horizontal, 6).padding(.vertical, 3)
                                                       .background(.thinMaterial, in: Capsule())
                                           }
                                           // Prime badges
                                           HStack(spacing: 4) {
                                               ForEach(NotationFormatter.primeBadges(p: r.p, q: r.q), id:\.self) { p in
                                                   Circle()
                                                       .fill((PrimeConfig.axes[p]?.color ?? .gray).opacity(0.9))
                                                       .frame(width: 6, height: 6)
                                               }
                                           }
                                       }
                                       .frame(maxWidth: .infinity, minHeight: 78)
                                       .padding(12)
                                       .background(latched.contains(idx) ? .thinMaterial : .ultraThinMaterial)
                                       .overlay(
                                           RoundedRectangle(cornerRadius: 14, style: .continuous)
                                               .stroke(latched.contains(idx) ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 1.2)
                                       )
                                       .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                   }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove") { store.remove(at: IndexSet(integer: idx)) }
                        Button("Inspect") { selectedPad = idx }
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if !store.degrees.contains(where: { $0.p == 1 && $0.q == 1 && $0.octave == 0 }) {
                            Button("Add Root") { store.add(RatioRef(p: 1, q: 1, octave: 0, monzo: [:])) }
                        }
            Spacer()
           
                        Button("Export Scala") { export() }.buttonStyle(.bordered)
                        Button("Cancel") { dismiss() }
        }
        .padding(.top, 4)
    }
    /// Stop & restart the sustained tone for this index at the current adjusted octave.
    /// Retune the sustained Builder voice for this pad at the current adjusted octave.
        private func retuneLatchedVoice(idx: Int, base: RatioRef, root: Double) {
            guard latched.contains(idx), soundOn else { return }
            let off = padOctaveOffset[idx, default: 0]
            let (cn, cd) = canonicalPQUnit(base.p, base.q)
            let f = foldToAudible(root * (Double(cn) / Double(cd)) * pow(2.0, Double(base.octave + off)))
            if let id = voiceForIndex[idx] {
                ToneOutputEngine.shared.retune(id: id, to: f, hardSync: false)

            } else {
                let id = ToneOutputEngine.shared.sustain(freq: f, amp: Float(safeAmp))

                voiceForIndex[idx] = id
            }
        }

    // MARK: - Octave offset helpers (no-fold into [1,2))
    private func reduceNoFold(_ p: Int, _ q: Int) -> (Int, Int) {
        let g = gcd(abs(p), abs(q))
        return (p / g, q / g)
    }
    /// Apply the pad octave offset to p/q by shifting powers of 2 into numerator/denominator.
    /// Do NOT change the octave field — we bake the step into p/q (so 5/4 ↓ becomes 5/8).
    private func ratioWithPadOffsetBaked(_ r: RatioRef, offset: Int) -> RatioRef {
        guard offset != 0 else { return r }
        if offset > 0 {
            let mul = 1 << offset      // 2^offset
            let (pn, qn) = reduceNoFold(r.p * mul, r.q)
            return RatioRef(p: pn, q: qn, octave: r.octave, monzo: r.monzo)
        } else {
            let mul = 1 << (-offset)   // 2^(-offset)
            let (pn, qn) = reduceNoFold(r.p, r.q * mul)
            return RatioRef(p: pn, q: qn, octave: r.octave, monzo: r.monzo)
        }
    }
    /// Build the degrees array with offsets baked into p/q for saving.
    private func adjustedDegreesForSave() -> [RatioRef] {
        store.degrees.enumerated().map { (idx, r) in
            let off = padOctaveOffset[idx, default: 0]
            return ratioWithPadOffsetBaked(r, offset: off)
        }
    }

    // MARK: - Save action (shared by glass button)
    private func performSave() {
            let base = store.makeScaleSnapshot()
            let adj = adjustedDegreesForSave()
            if let existing = library.scales.values.first(where: { $0.name == base.name }) {
                // Prepare a pending snapshot that already carries adjusted degrees
                pendingSnapshot = TenneyScale(
                    id: existing.id,
                    name: base.name,
                    descriptionText: base.descriptionText,
                    degrees: adj,
                    tags: existing.tags,
                    favorite: existing.favorite,
                    lastPlayed: Date(),
                    referenceHz: base.referenceHz,
                    detectedLimit: TenneyScale.detectedLimit(for: adj),
                    periodRatio: 2.0,
                    maxTenneyHeight: TenneyScale.maxTenneyHeight(for: adj),
                    author: existing.author
                )
                showSaveConflict = true
            } else {
                let final = TenneyScale(
                    id: base.id,
                    name: base.name,
                    descriptionText: base.descriptionText,
                    degrees: adj,
                    tags: base.tags,
                    favorite: base.favorite,
                    lastPlayed: Date(),
                    referenceHz: base.referenceHz,
                    detectedLimit: TenneyScale.detectedLimit(for: adj),
                    periodRatio: 2.0,
                    maxTenneyHeight: TenneyScale.maxTenneyHeight(for: adj),
                    author: base.author
                )
                library.addScale(final)
                saveToast()
            }
        }
    // MARK: - Public step hook for chevrons (pads/info-card)
    func stepPadOctave(idx: Int, delta: Int) {
        guard store.degrees.indices.contains(idx) else { return }
        // bounds policy is handled by the caller; this only applies the step
        padOctaveOffset[idx, default: 0] += delta
        // Only retune if already latched AND sounds are enabled
            if latched.contains(idx), soundOn {
                retuneLatchedVoice(idx: idx, base: store.degrees[idx], root: store.payload.rootHz)
            }
    }
    // MARK: - Actions
    
    private func toggleLatch(idx: Int, ratio: RatioRef) {
            let root = store.payload.rootHz
            if latched.contains(idx) {
                // Turn OFF
                if let id = voiceForIndex[idx] {
                    ToneOutputEngine.shared.release(id: id, seconds: 0.35)
                    voiceForIndex[idx] = nil
                }
               latched.remove(idx)
                padOctaveOffset[idx] = 0
            } else {
                // Turn ON
                _ = ToneOutputEngine.shared  // touch singleton
                latched.insert(idx)
                guard soundOn else { voiceForIndex[idx] = nil; return }
                let (cn, cd) = canonicalPQUnit(ratio.p, ratio.q)
                let off = padOctaveOffset[idx, default: 0]
                let f = foldToAudible(root * (Double(cn) / Double(cd)) * pow(2.0, Double(ratio.octave + off)))
                let voiceID = ToneOutputEngine.shared.sustain(freq: f, amp: Float(safeAmp))

                voiceForIndex[idx] = voiceID
            }
        }
    private func stopAllPadVoices() {
            for id in voiceForIndex.values { ToneOutputEngine.shared.release(id: id, seconds: 0.03) }
            ToneOutputEngine.shared.stopAll() // belt-and-suspenders
        voiceForIndex.removeAll()
        latched.removeAll()
    }
   

    private func export() {
        let scl = store.sclText
        let kbm = store.kbmText
        let sclURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(store.name).scl")
        let kbmURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(store.name).kbm")
        do {
            try scl.write(to: sclURL, atomically: true, encoding: .utf8)
            try kbm.write(to: kbmURL, atomically: true, encoding: .utf8)
            let av = UIActivityViewController(activityItems: [sclURL, kbmURL], applicationActivities: nil)
            UIApplication.shared.firstKeyWindow?.rootViewController?.present(av, animated: true)
        } catch {
            print("Export error: \(error)")
        }
    }
    private func playScalePreview(_ s: TenneyScale) {
            let root = s.referenceHz
            let seq = s.degrees
            for (i, r) in seq.enumerated() {
                let delay = DispatchTime.now() + .milliseconds(180 * i)
                DispatchQueue.main.asyncAfter(deadline: delay) {
                    // canonicalize to [1,2) so previews never jump to 3/1 etc.
                                    let (cn, cd) = canonicalPQUnit(r.p, r.q)
                                    let f = foldToAudible(root * (Double(cn) / Double(cd)))
                    if soundOn {
                        _ = ToneOutputEngine.shared.sustain(freq: f, amp: Float(safeAmp))

                                        }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        // soft release
                        // (We don’t track IDs here; short envelopes overlap acceptably for a preview.)
                        ToneOutputEngine.shared.stopAll()
                    }
                }
            }
        }
    
    // MARK: Save helpers
        private func resolvedName() -> String {
            let n = store.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "Untitled Scale" : n
        }
        private func nameExists(_ name: String) -> Bool {
            library.scales.values.contains { $0.name == name }
        }
        private func nextAvailableName(base: String) -> String {
            var idx = 1
            var candidate = "\(base) (\(idx))"
            while nameExists(candidate) { idx += 1; candidate = "\(base) (\(idx))" }
            return candidate
        }
        private func saveToast() {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showSavedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.25)) { showSavedToast = false }
            }
            pendingSnapshot = nil
        }
}
// MARK: - Ratio helpers (canonicalize to [1,2))
    
    /// Returns (num, den) with 1 ≤ num/den < 2 (powers of 2 moved between num/den), reduced by GCD.
    private func canonicalPQUnit(_ p: Int, _ q: Int) -> (Int, Int) {
        guard p > 0 && q > 0 else { return (p, q) }
        var num = p, den = q
        while Double(num) / Double(den) >= 2.0 { den &*= 2 }
        while Double(num) / Double(den) <  1.0 { num &*= 2 }
        let g = gcd(num, den)
        return (num / g, den / g)
    }
    /// Fold any Hz into a safe audible band for monitoring.
    private func foldToAudible(_ f: Double, minHz: Double = 20, maxHz: Double = 5000) -> Double {
        guard f.isFinite && f > 0 else { return f }
        var x = f
        while x < minHz { x *= 2 }
        while x > maxHz { x *= 0.5 }
        return x
    }



private extension RatioRef {
    var displayLabel: String {
        let (P,Q) = normalizedPQ()
        return "\(P)/\(Q)"
    }
}

// small UIKit helper (safe enough for export UI)
 extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
// MARK: - Glass styling helper
private struct GlassBlueCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.blue), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.blue.opacity(0.35), lineWidth: 1))
        }
    }
}
