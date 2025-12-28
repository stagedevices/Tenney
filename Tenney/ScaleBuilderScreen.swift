
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
    // MARK: - Export config types
    
    private struct ExportFormat: OptionSet {
        let rawValue: Int
        
        static let scl     = ExportFormat(rawValue: 1 << 0)
        static let kbm     = ExportFormat(rawValue: 1 << 1)
        static let freqs   = ExportFormat(rawValue: 1 << 2)
        static let cents   = ExportFormat(rawValue: 1 << 3)
        static let ableton = ExportFormat(rawValue: 1 << 4) // Ableton .ascl (Scala-based stub)
        
        static let `default`: ExportFormat = [.scl, .kbm]
    }
    
    private enum ExportA4Mode: String, CaseIterable, Identifiable {
        case appDefault
        case hz440
        case custom
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .appDefault: return "App default"
            case .hz440:      return "440 Hz"
            case .custom:     return "Custom"
            }
        }
    }
    
    private var scopeSignals: [ToneOutputEngine.ScopeSignal] {
        // stable pad order: by pad index
        let ordered = voiceForIndex.keys.sorted()
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
    @State private var enteredWithSoundOn: Bool = true
    @State private var pausedMicForBuilder = false
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
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
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
            }
            .onAppear {
                // Pause tuner mic while in Builder (restored on exit)
                app.builderPresented = true
                ToneOutputEngine.shared.builderWillPresent()
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

            
            // Top-right controls: Export + Save (magic-replace)
            HStack(spacing: 8) {
                exportModeButton
                
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
                    .accessibilityLabel("Save scale to Library")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20) // extra breathing room from the detent edge
        }
        
    }
        // MARK: - Header
        
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
                    .font(.callout)
                    .lineLimit(1...3)
                
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
                        dismiss()
                    } label: {
                        Text("Add from Lattice")
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
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 140), spacing: 10),
                        GridItem(.flexible(minimum: 140), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    // Lissajous oscilloscope (spans both columns)
                    LissajousCard(
                        activeSignals: scopeSignals,
                        rootHz: store.payload.rootHz
                    )

                    .frame(minHeight: 220)                // iPhone; grows on iPad naturally
                    .gridCellColumns(2)                   // span both columns
                    .accessibilityIdentifier("LissajousCard")
                    
                    ForEach(Array(store.degrees.enumerated()), id: \.offset) { idx, r in
                        padButton(idx: idx, r: r)
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
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack {
                Label {
                    Text("Export “\(resolvedName())”")
                        .font(.headline)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isExportMode = false
                        exportErrorMessage = nil
                    }
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            
            // Microcopy
            Text("Choose formats to export and share this tuning to other apps and devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Formats section
            VStack(alignment: .leading, spacing: 8) {
                Text("Formats")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                
                // Group 1: For synths & DAWs
                VStack(alignment: .leading, spacing: 6) {
                    Text("For synths & DAWs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        exportFormatRow(
                            format: .scl,
                            title: "Scala scale (.scl)",
                            subtitle: "Ratio-based tuning for Scala-compatible synths."
                        )
                        exportFormatRow(
                            format: .kbm,
                            title: "Scala keyboard mapping (.kbm)",
                            subtitle: "Maps the scale to a MIDI note and reference frequency."
                        )
                        exportFormatRow(
                            format: .ableton,
                            title: "Ableton scale (.ascl)",
                            subtitle: "Live 12 tuning (Scala-compatible stub)."
                        )
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                
                // Group 2: For documentation
                VStack(alignment: .leading, spacing: 6) {
                    Text("For documentation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        exportFormatRow(
                            format: .freqs,
                            title: "Plain text frequencies (freqs.txt)",
                            subtitle: "One frequency per line in Hz."
                        )
                        exportFormatRow(
                            format: .cents,
                            title: "Plain text cents (cents.txt)",
                            subtitle: "One offset per line in cents from unison."
                        )
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            
            // A4 reference section
            VStack(alignment: .leading, spacing: 8) {
                Text("A4 reference")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                
                Picker("A4 reference", selection: exportA4ModeBinding) {
                    ForEach(ExportA4Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                if exportA4Mode == .custom {
                    HStack {
                        Text("Custom A4 (Hz)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("440", value: $customExportA4Hz, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            
            // Builder root display
            VStack(alignment: .leading, spacing: 4) {
                Text("Builder root")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(builderRootSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Summary row
            Text(exportSummaryText)
                .font(.footnote)
                .foregroundStyle(exportFormats.isEmpty ? .secondary : .primary)
            
            // Export button
            Button {
                beginExportFlow()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up.on.square")
                    Text("Export Selected")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(exportFormats.isEmpty)
            
            // Inline error row
            if let message = exportErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 6)
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
                selectedPad = idx
                toggleLatch(idx: idx, ratio: r)
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
        
        
        private func exportFormatRow(format: ExportFormat, title: String, subtitle: String) -> some View {
            let isOn = exportFormats.contains(format)
            
            return Button {
                toggleFormat(format)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                            .background(
                                (isOn ? Color.accentColor.opacity(0.08) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            )
                            .frame(width: 24, height: 24)
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        
    private var exportModeButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                isExportMode.toggle()
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
                let id = ToneOutputEngine.shared.sustain(freq: f, amp: Float(safeAmp), owner: .builder, attackMs: 4, releaseMs: 40)
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
                let voiceID = ToneOutputEngine.shared.sustain(freq: f, amp: Float(safeAmp), owner: .builder, attackMs: 4, releaseMs: 40)
                voiceForIndex[idx] = voiceID
            }
        }
        
        private func stopAllPadVoices() {
            for id in voiceForIndex.values {
                ToneOutputEngine.shared.release(id: id, seconds: 0.03)
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

                    let voiceID = ToneOutputEngine.shared.sustain(freq: f, amp: Float(safeAmp), owner: .builder, attackMs: 4, releaseMs: 40)

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

private struct GlassBlueCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Back to your original: blue-tinted glass using system accent
            content.glassEffect(.regular.tint(.blue), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                )
        }
    }
}

// Neutral / white glass circle for export button
private struct GlassWhiteCircle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(
                                .regular,
                                in: Circle()
                            )
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay(
                Circle()
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
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
