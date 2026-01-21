
//  ScaleBuilderScreen.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/4/25.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
    
struct ScaleBuilderScreen: View {
    @AppStorage(SettingsKeys.lissaGridDivs)   private var lissaGridDivs: Int = 8
    @AppStorage(SettingsKeys.lissaShowGrid)   private var lissaShowGrid: Bool = true
    @AppStorage(SettingsKeys.lissaShowAxes)   private var lissaShowAxes: Bool = true
    @AppStorage(SettingsKeys.lissaStrokeWidth) private var lissaRibbonWidth: Double = 1.5
    @AppStorage(SettingsKeys.lissaDotMode)    private var lissaDotMode: Bool = false
    @AppStorage(SettingsKeys.lissaDotSize)    private var lissaDotSize: Double = 2.0
    @AppStorage(SettingsKeys.lissaLiveSamples) private var lissaLiveSamples: Int = 768
    @AppStorage(SettingsKeys.lissaGlobalAlpha) private var lissaGlobalAlpha: Double = 1.0
    @AppStorage(SettingsKeys.latticeThemeID) private var latticeThemeID: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.latticeThemeStyle) private var themeStyleRaw: String = ThemeStyleChoice.system.rawValue

    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var effectiveIsDark: Bool {
        (themeStyleRaw == "dark") || (themeStyleRaw == "system" && systemScheme == .dark)
    }
    
    private func finishBuilder() {
        persistBuilderDraftToSession(reason: "done")
        didPersistOnDismiss = true
        // 1) De-load the current scale if loaded
        if store.payload.existing != nil {
            store.payload.existing = nil
        }
        app.unloadBuilderScale()

        // 2) Deselect nodes + 3) reset delta flag (handled by Lattice via NotificationCenter)
        NotificationCenter.default.post(
            name: .tenneyBuilderDidFinish,
            object: nil,
            userInfo: ["clearSelection": true, "endStaging": true]
        )

        // 4) Dismiss
        dismiss()
    }

    private func syncLoadedScaleMetadata() {
        let edited: Bool
        if let existing = store.payload.existing {
            edited = store.makeScaleSnapshot() != existing
        } else {
            edited = false
        }
        app.updateLoadedScaleMetadata(
            name: store.name,
            description: store.descriptionText,
            existing: store.payload.existing,
            isEdited: edited
        )
    }

    private func syncBuilderSessionPayload() {
        app.updateBuilderDraft(
            name: store.name,
            description: store.descriptionText,
            rootHz: store.payload.rootHz,
            degrees: store.degrees
        )
    }

    private func applyPendingAddsIfNeeded() {
        guard let pending = app.builderSession.pendingAddRefs, !pending.isEmpty else { return }
        store.payload.items.append(contentsOf: pending)
        store.rebuild()
#if DEBUG
        let draftHash = AppModel.debugDegreeHash(store.degrees)
        print("[BuilderHydrate] appendingPendingRefs count=\(pending.count) storeCount=\(store.degrees.count) draftHash=\(draftHash)")
#endif
        app.builderSession.pendingAddRefs = nil
        syncLoadedScaleMetadata()
        syncBuilderSessionPayload()
    }

    private var oscEffectiveValues: LissajousPreviewConfigBuilder.EffectiveValues {
        LissajousPreviewConfigBuilder.effectiveValues(
            liveSamples: lissaLiveSamples,
            globalAlpha: lissaGlobalAlpha,
            dotSize: lissaDotSize,
            persistenceEnabled: true,          // Builder preview is Canvas-only; keep Settings behavior
            halfLife: 0.6,                     // (value irrelevant here; EffectiveValues just gates alpha/dots)
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }

    private typealias RatioTuple = (n: Int, d: Int)

    /// Stable latched order for routing (does NOT reshuffle based on `selectedPad`).
    private var builderPadOrderForRouting: [Int] {
        var ordered = activePadOrder.filter { latched.contains($0) }
        // Append any latched pads we somehow missed (stable, ascending).
        for idx in latched.sorted() where !ordered.contains(idx) {
            ordered.append(idx)
        }
        // Keep only valid indices.
        ordered = ordered.filter { store.degrees.indices.contains($0) }
        return ordered
    }

    /// Channel lists: X = 1st,3rd,5th...  Y = 2nd,4th,6th...
    private var builderLissajousChannels: (x: [RatioTuple], y: [RatioTuple]) {
        let ids = builderPadOrderForRouting
        guard let first = ids.first else { return ([], []) }

        func tuple(for idx: Int) -> RatioTuple {
            let base = store.degrees[idx]
            let off = padOctaveOffset[idx, default: 0]
            let baked = ratioWithPadOffsetBaked(base, offset: off)
            let (cn, cd) = canonicalPQUnit(baked.p, baked.q)
            return (n: cn, d: cd)
        }

        let tuples = ids.map(tuple(for:))
        var xs: [RatioTuple] = []
        var ys: [RatioTuple] = []
        for (i, t) in tuples.enumerated() {
            if i.isMultiple(of: 2) { xs.append(t) } else { ys.append(t) }
        }
        // 1-pad case: X and Y are the same.
        if xs.isEmpty { xs = [tuple(for: first)] }
        if ys.isEmpty { ys = [xs[0]] }
        return (x: xs, y: ys)
    }

    /// Render pairs (one canvas per pair). Extra X (or Y) repeats the last opposite channel.
    private var builderLissajousPairs: [(x: RatioTuple, y: RatioTuple)] {
        let ch = builderLissajousChannels
        guard !ch.x.isEmpty else { return [] }
        let count = max(ch.x.count, ch.y.count)
        return (0..<count).map { i in
            let x = ch.x[min(i, ch.x.count - 1)]
            let y = ch.y[min(i, ch.y.count - 1)]
            return (x: x, y: y)
        }
    }

    private func ratioListLabel(_ list: [RatioTuple]) -> String {
        guard !list.isEmpty else { return "—" }
        return list.map { "\($0.n)/\($0.d)" }.joined(separator: " · ")
    }
    
    private var scopeSignals: [ToneOutputEngine.ScopeSignal] {
        // stable pad order: by pad index
        reconcileActivePadOrderWithLatched()
        let ordered = activePadOrder.filter { voiceForIndex[$0] != nil }

        return ordered.compactMap { idx in
            guard let vid = voiceForIndex[idx] else { return nil }
            return .init(voiceID: vid, label: "Pad \(idx + 1)")
        }
    }

    // MARK: - State
    
    @State private var padOctaveOffset: [Int: Int] = [:]
    
    @AppStorage("Tenney.SoundOn") private var soundOn: Bool = true
    @AppStorage(SettingsKeys.safeAmp) private var safeAmp: Double = 0.18
    
    // Export preferences (persisted)
    @AppStorage(SettingsKeys.builderExportFormats) private var exportFormatsRaw: Int = ExportFormat.default.rawValue
    @AppStorage(SettingsKeys.builderExportRootMode) private var exportA4ModeRaw: String = ExportA4Mode.appDefault.rawValue
    @AppStorage(SettingsKeys.builderExportCustomA4Hz) private var customExportA4Hz: Double = 440.0

    private var exportFormats: ExportFormat {
        ExportFormat(rawValue: exportFormatsRaw)
    }

    private var exportA4Mode: ExportA4Mode {
        ExportA4Mode(rawValue: exportA4ModeRaw) ?? .appDefault
    }

    private var exportA4ModeBinding: Binding<ExportA4Mode> {
        Binding(
            get: { ExportA4Mode(rawValue: exportA4ModeRaw) ?? .appDefault },
            set: { exportA4ModeRaw = $0.rawValue }
        )
    }

    private var exportA4Hz: Double {
        switch exportA4Mode {
        case .appDefault:
            // For now, treat the app default as 440 Hz.
            // This can be wired to your global A4 setting (e.g. UserDefaults) later.
            return 440.0
        case .hz440:
            return 440.0
        case .custom:
            return max(1.0, customExportA4Hz)
        }
    }

    @ObservedObject var store: ScaleBuilderStore
    @ObservedObject var lib = ScaleLibraryStore.shared
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: ScaleLibraryStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var showLibrary = false
    @State private var showSavedToast = false
    @State private var latched = Set<Int>()
    @State private var voiceForIndex: [Int:Int] = [:]   // BuilderTone voice IDs
    @State private var selectedPad: Int? = nil          // inspector selection
    @State private var activePadOrder: [Int] = []
    @State private var enteredWithSoundOn: Bool = true
    @State private var pausedMicForBuilder = false
    @State private var didPersistOnDismiss = false
    @Namespace private var saveSlot
    @Namespace private var exportSlot
    
    // Builder audio defaults (sheet-level). Per-pad overrides can be added later.
    @State private var wasSoundOnBeforePresenting: Bool? = nil
    
    // Name conflict prompt
    @State private var pendingSnapshot: TenneyScale? = nil
    @State private var showSaveConflict = false
    
    // Export mode UI
    @State private var isExportMode = false
    @State private var showSaveBeforeExport = false
    @State private var exportErrorMessage: String? = nil
    
    @State private var exportURLs: [URL] = []
    @State private var isPresentingShareSheet = false
    @State private var lastHydratedLoadedScaleID: TenneyScale.ID? = nil

    private enum BuilderTextField: Hashable {
        case name
        case description
    }

    @FocusState private var focusedField: BuilderTextField?
    private var isNameEditing: Bool { focusedField == .name }
    private var isDescEditing: Bool { focusedField == .description }
    private var isUserEditingText: Bool { isNameEditing || isDescEditing }
    
    
    private func notePadOn(_ idx: Int) {
        activePadOrder.removeAll { $0 == idx }
        activePadOrder.append(idx)
    }

    private func notePadOff(_ idx: Int) {
        activePadOrder.removeAll { $0 == idx }
    }

    private func reconcileActivePadOrderWithLatched() {
        // drop anything no longer latched
        activePadOrder.removeAll { !latched.contains($0) }
        // append any latched pads we somehow missed (best-effort)
        for idx in latched where !activePadOrder.contains(idx) {
            activePadOrder.append(idx)
        }
    }

    private func hydrateExistingScaleIfNeeded(_ existing: TenneyScale) {
        guard !isUserEditingText else { return }
        guard existing.id != lastHydratedLoadedScaleID else { return }
        store.name = existing.name
        store.descriptionText = existing.descriptionText
        store.payload.rootHz = existing.referenceHz
        store.payload.items = existing.degrees
        store.rebuild()
        lastHydratedLoadedScaleID = existing.id
#if DEBUG
        let draftHash = AppModel.debugDegreeHash(store.degrees)
        print("[BuilderHydrate] source=payloadExisting storeCount=\(store.degrees.count) draftHash=\(draftHash)")
#endif
    }

    private func hydrateDraftIfNeeded() {
        guard !isUserEditingText else { return }
        if app.builderSession.draftInitialized {
            if app.builderSession.savedScaleID != nil, app.builderSession.savedScaleID == lastHydratedLoadedScaleID {
                return
            }
            store.name = app.builderSession.draftName
            store.descriptionText = app.builderSession.draftDescription
            store.payload.rootHz = app.builderSession.draftRootHz
            store.payload.items = app.builderSession.draftDegrees
            store.rebuild()
            lastHydratedLoadedScaleID = app.builderSession.savedScaleID
#if DEBUG
            let draftHash = AppModel.debugDegreeHash(store.degrees)
            print("[BuilderHydrate] source=sessionDraft storeCount=\(store.degrees.count) draftHash=\(draftHash)")
#endif
        } else if let existing = store.payload.existing {
            hydrateExistingScaleIfNeeded(existing)
        } else {
#if DEBUG
            let draftHash = AppModel.debugDegreeHash(store.degrees)
            print("[BuilderHydrate] source=new storeCount=\(store.degrees.count) draftHash=\(draftHash)")
#endif
        }
    }

    private func persistBuilderDraftToSession(reason: String) {
        let degrees = store.degrees
        app.updateBuilderDraft(
            name: store.name,
            description: store.descriptionText,
            rootHz: store.payload.rootHz,
            degrees: degrees
        )
        if let existing = store.payload.existing {
            app.updateBuilderSessionEdited(
                loadedScaleEdited: store.makeScaleSnapshot() != existing,
                metadataEdited: app.loadedScaleMetadataEdited
            )
        }
#if DEBUG
        let draftHash = AppModel.debugDegreeHash(degrees)
        print("[BuilderDismiss] reason=\(reason) persisted=true draftCount=\(degrees.count) draftHash=\(draftHash)")
#endif
    }

    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemBackground).ignoresSafeArea()   //  baseline
            VStack(spacing: 12) {
                header
                
                if let warn = store.warningText {
                    Text(warn)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                
                if isExportMode {
                    exportPanel
                } else {
                    pads
                    toolbar
                }
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
                LearnEventBus.shared.send(.builderPadOctaveChanged(idx, delta))
            }
            .onAppear {
                didPersistOnDismiss = false
                reconcileActivePadOrderWithLatched()
                // Pause tuner mic while in Builder (restored on exit)
                app.builderPresented = true
                ToneOutputEngine.shared.builderWillPresent()
                app.setMicActive(false)
                pausedMicForBuilder = true
                
                // If opening an existing saved scale, load it now
                hydrateDraftIfNeeded()
                syncLoadedScaleMetadata()
                applyPendingAddsIfNeeded()
                syncBuilderSessionPayload()
                
                // Sound gating per spec (turn on while in Builder, and remember original)
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
                    for id in voiceForIndex.values {
                        ToneOutputEngine.shared.release(id: id, seconds: 0.0)
                    }
                    voiceForIndex.removeAll()
                    latched.removeAll()
                }
            }
            // Release all latched voices when the sheet closes
            .onDisappear {
                if !didPersistOnDismiss, app.builderPayload != nil {
                    persistBuilderDraftToSession(reason: "dragDismiss")
                }
                ToneOutputEngine.shared.builderDidDismiss()
                app.builderPresented = false
                stopAllPadVoices()
                // restore sound toggle if it was off before
                if !enteredWithSoundOn { soundOn = false }
                if pausedMicForBuilder {
                    app.setMicActive(true)
                    pausedMicForBuilder = false
                }
            }
            .onChange(of: store.name) { _ in
                syncLoadedScaleMetadata()
                syncBuilderSessionPayload()
            }
            .onChange(of: store.descriptionText) { _ in
                syncLoadedScaleMetadata()
                syncBuilderSessionPayload()
            }
            .onChange(of: store.payload.rootHz) { _ in
                syncLoadedScaleMetadata()
                syncBuilderSessionPayload()
            }
            .onChange(of: store.payload.existing?.id) { _ in
                guard let existing = store.payload.existing else {
                    lastHydratedLoadedScaleID = nil
                    return
                }
                hydrateDraftIfNeeded()
            }
            .onChange(of: focusedField) { _ in
                guard !isUserEditingText, let existing = store.payload.existing else { return }
                hydrateDraftIfNeeded()
            }
            .onChange(of: store.payload.items) { _ in
                syncLoadedScaleMetadata()
                syncBuilderSessionPayload()
            }
            .onChange(of: soundOn) { enabled in
                if !enabled { stopAllPadVoices() } // hard mute when toggled off
            }
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
                            tagIDs: existing.tagIDs,
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
            .alert("Save before exporting?", isPresented: $showSaveBeforeExport) {
                Button("Save & Export") {
                    performSave()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        performExportNow()
                    }
                }
                Button("Export Without Saving") {
                    performExportNow()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you want to save “\(resolvedName())” to your Library before exporting?")
            }
            .sheet(isPresented: $isPresentingShareSheet, onDismiss: {
                exportURLs.removeAll()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isExportMode = false
                }
            }) {
                ActivityView(activityItems: exportURLs)
            }

            
            // Top-right controls: Export + Save + Done
            HStack(spacing: 8) {
                exportModeButton
                saveButton
                doneButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 20) // extra breathing room from the detent edge

        }
        
    }
    
    private var saveButton: some View {
            Button { performSave() } label: {
                let name = showSavedToast ? "checkmark" : "tray.and.arrow.down"
                Group {
                    if #available(iOS 17.0, *) {
                        Image(systemName: name)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace.downUp))
                    } else {
                        Image(systemName: name)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(showSavedToast ? .green : .primary)
                .frame(width: 44, height: 44)
                .modifier(GlassWhiteCircle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("Save scale to Library")
        }

    private var doneButton: some View {
        Button {
            finishBuilder()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .modifier(GlassRedCircle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Done")
    }

        // MARK: - Header
        
        private var header: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    TextField("Untitled Scale", text: $store.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .name)
                    Spacer()
                }
                
                TextField("Description / notes", text: $store.descriptionText, axis: .vertical)
                    .font(.callout)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .description)
                
                HStack(spacing: 8) {
                    // Auto-filled prime limit chip (non-interactive)
                    HStack(spacing: 6) {
                        Text("\(store.detectedPrimeLimit)-limit JI")
                            .font(.callout.weight(.semibold))
                        // Root Hz pill (read-only display)
                        Text("Root \(Int(store.payload.rootHz)) Hz")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    
                    Spacer()
                    
                    if isExportMode {
                        Text("Export")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .accessibilityHidden(true)
                    }
                    
                    Button {
                        app.builderStagingBaseCount = store.degrees.count
                        persistBuilderDraftToSession(reason: "addMore")
                        didPersistOnDismiss = true
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                        Text("Add More")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        
        // MARK: - Pads (Builder mode)
        
        private var pads: some View {
            // Large tap zones for performance; two columns by default
            ScrollView {
                VStack(spacing: 10) {
                    let theme = ThemeRegistry.theme(
                        LatticeThemeID(rawValue: latticeThemeID) ?? .classicBO,
                        dark: effectiveIsDark
                    )

                    let pairs = builderLissajousPairs
                    let ch = builderLissajousChannels

                    LissajousPreviewFrame(contentPadding: 0, showsFill: false) {
                        if pairs.isEmpty {
                            LissajousCanvasPreview(
                                e3: theme.e3,
                                e5: theme.e5,
                                samples: oscEffectiveValues.liveSamples,
                                gridDivs: lissaGridDivs,
                                showGrid: lissaShowGrid,
                                showAxes: lissaShowAxes,
                                strokeWidth: lissaRibbonWidth,
                                dotMode: lissaDotMode,
                                dotSize: oscEffectiveValues.dotSize,
                                globalAlpha: oscEffectiveValues.alpha,
                                idleMode: .empty,
                                xRatio: nil,
                                yRatio: nil
                            )
                        } else {
                            ZStack {
                                ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
                                    LissajousCanvasPreview(
                                        e3: theme.e3,
                                        e5: theme.e5,
                                        samples: oscEffectiveValues.liveSamples,
                                        gridDivs: lissaGridDivs,
                                        showGrid: (i == 0) ? lissaShowGrid : false,
                                        showAxes: (i == 0) ? lissaShowAxes : false,
                                        strokeWidth: lissaRibbonWidth,
                                        dotMode: lissaDotMode,
                                        dotSize: oscEffectiveValues.dotSize,
                                        globalAlpha: oscEffectiveValues.alpha / Double(max(1, pairs.count)),
                                        idleMode: .empty,
                                        xRatio: pair.x,
                                        yRatio: pair.y
                                    )
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(i != 0)
                                }
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if !pairs.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("X: \(ratioListLabel(ch.x))")
                                Text("Y: \(ratioListLabel(ch.y))")
                            }
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(10)
                            .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .accessibilityIdentifier("LissajousCard")


                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 140), spacing: 10),
                            GridItem(.flexible(minimum: 140), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(Array(store.degrees.enumerated()), id: \.offset) { idx, r in
                            padButton(idx: idx, r: r)
                        }
                    }
                }
            }
        }
        
        // MARK: - Toolbar (Builder mode)
        
        private var toolbar: some View {
            HStack(spacing: 10) {
                if !store.degrees.contains(where: { $0.p == 1 && $0.q == 1 && $0.octave == 0 }) {
                    Button("Add Root") {
                        store.add(RatioRef(p: 1, q: 1, octave: 0, monzo: [:]))
                    }
                }
                
                Spacer()
                
                Button("Cancel") { dismiss() }
            }
            .padding(.top, 4)
        }
        
        // MARK: - Export mode UI
        
    private var exportPanel: some View {
        ScaleExportSheet(
            title: resolvedName(),
            builderRootSummary: builderRootSummary,
            exportSummaryText: exportSummaryText,
            exportFormats: exportFormats,
            exportErrorMessage: exportErrorMessage,
            onToggleFormat: { toggleFormat($0) },
            onExport: { beginExportFlow() },
            onDone: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isExportMode = false
                    exportErrorMessage = nil
                }
            },
            exportA4Mode: exportA4ModeBinding,
            customA4Hz: $customExportA4Hz
        )
    }

        
        @ViewBuilder
        private func padButton(idx: Int, r: RatioRef) -> some View {
            let root = store.payload.rootHz
            let offset = padOctaveOffset[idx, default: 0]
            let adjusted = RatioRef(p: r.p, q: r.q, octave: r.octave + offset, monzo: r.monzo)
            
            // Canonicalize p/q for display + audio, but include adjusted octave for Hz
            let (cn, cd) = canonicalPQUnit(adjusted.p, adjusted.q)
            let baseHz = root * (Double(cn) / Double(cd)) * pow(2.0, Double(adjusted.octave))
            let hz = foldToAudible(baseHz)
                let _ = hz   // This is a *binding* statement, not a bare expression
            let cents = 1200.0 * log2(Double(cn) / Double(cd))
                let _ = cents

                let (name, oct) = NotationFormatter.staffNoteName(freqHz: hz)
                let _ = name
                let _ = oct
            
            Button {
                toggleLatch(idx: idx, ratio: r)
                selectedPad = idx
            } label: {
                HStack(spacing: 6) {
                    Text("\(cn)/\(cd)")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                    
                    if offset != 0 {
                        Text("(\(offset > 0 ? "+\(offset)" : "\(offset)") oct)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                    
                    // Prime badges
                    HStack(spacing: 4) {
                        ForEach(NotationFormatter.primeBadges(p: r.p, q: r.q), id: \.self) { p in
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
                        .stroke(
                            latched.contains(idx)
                            ? Color.accentColor.opacity(0.8)
                            : Color.clear,
                            lineWidth: 1.2
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Remove") { store.remove(at: IndexSet(integer: idx)) }
                Button("Inspect") { selectedPad = idx }
            }
        }
        
        
    private var exportModeButton: some View {
        Button {
            let was = isExportMode
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                isExportMode.toggle()
            }
            if !was {
                LearnEventBus.shared.send(.builderExportOpened)
            }
        } label: {
            Image(systemName: isExportMode ? "chevron.backward" : "square.and.arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .modifier(GlassWhiteCircle())
        }
        .buttonStyle(.plain) // ⬅️ kill system blue pill
        .contentShape(Circle())
        .accessibilityLabel(isExportMode ? "Back to pads" : "Export options")
        .accessibilityAddTraits(.isButton)
    }

        
        // MARK: - Export flow
        
    private func beginExportFlow() {
        // Guard 1: at least one format
        guard !exportFormats.isEmpty else {
            exportErrorMessage = "Select at least one export format."
            return
        }
        
        exportErrorMessage = nil
        
        let name = resolvedName()
        let alreadyInLibrary = library.scales.values.contains(where: { $0.name == name }) || (store.payload.existing != nil)
        
        if alreadyInLibrary {
            // Scale is already in Library (or opened from Library) → export directly
            performExportNow()
        } else {
            // Prompt to save before exporting
            showSaveBeforeExport = true
        }
    }

        
    private func performExportNow() {
        exportErrorMessage = nil
        
        let degrees = adjustedDegreesForSave()
        guard !degrees.isEmpty else {
            exportErrorMessage = "Scale has no degrees to export."
            return
        }
        
        let name = sanitizedFilename(from: resolvedName())
        let desc = store.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootHz = exportBaseRootHz()
        
        var urls: [URL] = []
        
        // Scala .scl
        if exportFormats.contains(.scl) {
            let text = ScalaExporter.sclText(
                scaleName: resolvedName(),
                description: desc,
                degrees: degrees
            )
            if let url = writeExportFile(named: "\(name).scl", contents: text) {
                urls.append(url)
            }
        }
        
        // Scala .kbm (use export A4)
        if exportFormats.contains(.kbm) {
            let text = ScalaExporter.kbmText(
                referenceHz: rootHz,
                scaleSize: max(1, degrees.count)
            )
            if let url = writeExportFile(named: "\(name).kbm", contents: text) {
                urls.append(url)
            }
        }
        
        // Plain frequencies (Hz)
        if exportFormats.contains(.freqs) {
            let lines: [String] = degrees.map { r in
                let ratio = (Double(r.p) / Double(r.q)) * pow(2.0, Double(r.octave))
                let hz = ratio * store.payload.rootHz
                return String(format: "%.8f", hz)
            }
            let text = lines.joined(separator: "\n")
            if let url = writeExportFile(named: "\(name)_freqs.txt", contents: text) {
                urls.append(url)
            }
        }
        
        // Plain cents
        if exportFormats.contains(.cents) {
            let lines: [String] = degrees.map { r in
                let ratio = (Double(r.p) / Double(r.q)) * pow(2.0, Double(r.octave))
                let cents = 1200.0 * log2(ratio)
                return String(format: "%.8f", cents)
            }
            let text = lines.joined(separator: "\n")
            if let url = writeExportFile(named: "\(name)_cents.txt", contents: text) {
                urls.append(url)
            }
        }
        
        // Ableton .ascl (Scala-compatible stub – writes .scl text with .ascl extension)
        if exportFormats.contains(.ableton) {
            let text = ScalaExporter.sclText(
                scaleName: resolvedName(),
                description: desc,
                degrees: degrees
            )
            if let url = writeExportFile(named: "\(name).ascl", contents: text) {
                urls.append(url)
            }
        }
        
        // README (always if any export formats are enabled)
        if let readmeURL = writeReadmeFile(baseName: name, degrees: degrees) {
            urls.append(readmeURL)
        }
        
        guard !urls.isEmpty else {
            exportErrorMessage = "Nothing was exported."
            return
        }
        
        exportErrorMessage = nil
        exportURLs = urls
        isPresentingShareSheet = true
    }

        
    private func exportBaseRootHz() -> Double {
        exportA4Hz
    }

    
    private func writeReadmeFile(baseName: String, degrees: [RatioRef]) -> URL? {
        let scaleName = resolvedName()
        let desc = store.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let a4Hz = exportA4Hz
        let rootHz = store.payload.rootHz
        let (rootName, rootOct) = NotationFormatter.staffNoteName(freqHz: rootHz)
        
        let a4ModeLabel: String = {
            switch exportA4Mode {
            case .appDefault: return "App default"
            case .hz440:      return "440 Hz"
            case .custom:     return "Custom"
            }
        }()
        
        var lines: [String] = []
        lines.append("Name: \(scaleName)")
        lines.append("Description: \(desc)")
        lines.append(String(format: "A4 reference: %.4f Hz (%@)", a4Hz, a4ModeLabel))
        lines.append(String(format: "Builder root: %@%d (%.4f Hz)", rootName, rootOct, rootHz))
        lines.append("Prime limit: \(store.detectedPrimeLimit)-limit JI")
        lines.append("Degrees (p/q [octave]):")
        
        for (idx, r) in degrees.enumerated() {
            lines.append("\(idx + 1): \(r.p)/\(r.q) [\(r.octave)]")
        }
        
        let text = lines.joined(separator: "\n")
        return writeExportFile(named: "\(baseName)_README.txt", contents: text)
    }

        
    private func writeExportFile(named: String, contents: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(named)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            exportErrorMessage = "Could not write export files. Please try again."
            return nil
        }
    }
        
        private func sanitizedFilename(from name: String) -> String {
            let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            if cleaned.isEmpty { return "Untitled_Scale" }
            return cleaned
        }
        
    private func toggleFormat(_ f: ExportFormat) {
        var current = exportFormats
        if current.contains(f) {
            current.remove(f)
        } else {
            current.insert(f)
        }
        exportFormatsRaw = current.rawValue
        // Clear stale error once user changes formats
        if exportErrorMessage != nil {
            exportErrorMessage = nil
        }
    }

        // MARK: - Audio helpers
        
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
                guard soundOn else { return }
                    let id = ToneOutputEngine.shared.sustain(
                        freq: f,
                        amp: Float(safeAmp),
                        owner: .builder,
                        ownerKey: "builder:pad:\(idx)",
                        attackMs: 4,
                        releaseMs: 40
                    )
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
        
        /// Build the degrees array with offsets baked into p/q for saving/export.
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
#if DEBUG
            let draftHash = AppModel.debugDegreeHash(adj)
            print("[BuilderSave] source=storeDegrees count=\(adj.count) draftHash=\(draftHash)")
#endif
            if let existing = library.scales.values.first(where: { $0.name == base.name }) {
                // Prepare a pending snapshot that already carries adjusted degrees
                pendingSnapshot = TenneyScale(
                    id: existing.id,
                    name: base.name,
                    descriptionText: base.descriptionText,
                    degrees: adj,
                    tagIDs: existing.tagIDs,
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
                    tagIDs: base.tagIDs,
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
                ToneOutputEngine.shared.stop(ownerKey: "builder:pad:\(idx)", releaseSeconds: 0.35)
                voiceForIndex[idx] = nil
                latched.remove(idx)
                notePadOff(idx)
                padOctaveOffset[idx] = 0
            } else {
                // Turn ON
                _ = ToneOutputEngine.shared  // touch singleton
                notePadOn(idx)

                latched.insert(idx)
                guard soundOn else { voiceForIndex[idx] = nil; return }
                let (cn, cd) = canonicalPQUnit(ratio.p, ratio.q)
                let off = padOctaveOffset[idx, default: 0]
                let f = foldToAudible(root * (Double(cn) / Double(cd)) * pow(2.0, Double(ratio.octave + off)))
                guard soundOn else { return }
                let voiceID = ToneOutputEngine.shared.sustain(
                    freq: f,
                    amp: Float(safeAmp),
                    owner: .builder,
                    ownerKey: "builder:pad:\(idx)",
                    attackMs: 4,
                    releaseMs: 40
                )
                voiceForIndex[idx] = voiceID
                
            }
            
        }
        
        private func stopAllPadVoices() {
            for idx in voiceForIndex.keys {
                ToneOutputEngine.shared.stop(ownerKey: "builder:pad:\(idx)", releaseSeconds: 0.03)
            }
            voiceForIndex.removeAll()
            latched.removeAll()
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
                    guard soundOn else { return }

                    guard soundOn else { return }
                    let voiceID = ToneOutputEngine.shared.sustain(
                        freq: f,
                        amp: Float(safeAmp),
                        owner: .builder,
                        ownerKey: "builder:preview:\(i)",
                        attackMs: 4,
                        releaseMs: 40
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        ToneOutputEngine.shared.release(id: voiceID, seconds: 0.06)
                    }
                }
            }
        }
        
        // MARK: - Save helpers
    private var builderRootSummary: String {
        let hz = store.payload.rootHz
        let (name, oct) = NotationFormatter.staffNoteName(freqHz: hz)
        let hzInt = Int(round(hz))
        return "Root: \(name)\(oct) (\(hzInt) Hz)"
    }

    private var exportSummaryText: String {
        let exts: [String] = [
            exportFormats.contains(.scl)     ? ".scl"      : nil,
            exportFormats.contains(.kbm)     ? ".kbm"      : nil,
            exportFormats.contains(.ableton) ? ".ascl"     : nil,
            exportFormats.contains(.freqs)   ? "freqs.txt" : nil,
            exportFormats.contains(.cents)   ? "cents.txt" : nil
        ].compactMap { $0 }
        
        if exts.isEmpty {
            return "Select at least one format to export."
        }
        
        let formatsPart = "Will export: " + exts.joined(separator: ", ")
        
        let a4Label: String
        switch exportA4Mode {
        case .appDefault:
            let hzInt = Int(round(exportA4Hz))
            a4Label = "A4: App default (\(hzInt) Hz)"
        case .hz440:
            a4Label = "A4: 440 Hz"
        case .custom:
            let hzInt = Int(round(exportA4Hz))
            a4Label = "A4: Custom (\(hzInt) Hz)"
        }
        
        return "\(formatsPart) • \(a4Label)"
    }

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
            while nameExists(candidate) {
                idx += 1
                candidate = "\(base) (\(idx))"
            }
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
        let (P, Q) = normalizedPQ()
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

struct GlassBlueCircle: ViewModifier {
    func body(content: Content) -> some View {
        content
            // keep the glyph crisp above the glass plate
            .foregroundStyle(.primary)

            // ✅ glass belongs on a background “plate”, not on the glyph
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(.blue), in: Circle())
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }

            // ✅ specular / rim highlight (this is what makes it read “liquid”)
            .overlay {
                // top-left sheen
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.30), location: 0.00),
                                .init(color: .white.opacity(0.10), location: 0.22),
                                .init(color: .clear,              location: 0.70)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)

                // rim
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
                    .blendMode(.overlay)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }
}





struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // nothing to update
    }
}
