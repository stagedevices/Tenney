//
//  ScaleLibrarySheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/5/25.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif


struct ScaleLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = ScaleLibraryStore.shared
    @State private var showOnlyFavorites = false
    @Environment(\.colorScheme) private var scheme
    @State private var actionTarget: TenneyScale? = nil   // ← selected row for the action sheet

    // simple sort/local filter
    private var filteredScales: [TenneyScale] {
        var items = Array(library.scales.values)
        if showOnlyFavorites { items = items.filter { $0.favorite } }
        let q = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                (!$0.descriptionText.isEmpty && $0.descriptionText.localizedCaseInsensitiveContains(q))
            }
        }
        switch library.sortKey {
        case .recent:
            items.sort { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .alpha:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            items.sort { $0.size > $1.size }
        case .limit:
            items.sort { $0.detectedLimit < $1.detectedLimit }
        }
        return items
    }

    private let limits = [3,5,7,11,13,17,19]
    private func count(for limit: Int) -> Int {
        Array(library.scales.values).filter { $0.detectedLimit <= limit }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if library.scales.isEmpty {
                    Section {
                        ContentUnavailableView("No saved scales yet",
                                               systemImage: "music.quarternote.3",
                                               description: Text("Save a scale from the Builder, or start by browsing limits."))
                    }
                } else {
                    // Quick controls
                    Section {
                        HStack(spacing: 10) {
                            Picker("", selection: $library.sortKey) {
                                Text("Recent").tag(ScaleLibraryStore.SortKey.recent)
                                Text("A–Z").tag(ScaleLibraryStore.SortKey.alpha)
                                Text("Size").tag(ScaleLibraryStore.SortKey.size)
                                Text("Limit").tag(ScaleLibraryStore.SortKey.limit)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)

                            Toggle(isOn: $showOnlyFavorites) {
                                Image(systemName: showOnlyFavorites ? "star.fill" : "star")
                            }
                            .toggleStyle(.button)
                            .tint(.yellow)
                            .accessibilityLabel("Show only favorites")
                        }
                    }

                    // Browse by limit
                    Section("Collections by Limit") {
                        ForEach(limits, id:\.self) { p in
                            NavigationLink {
                                ScaleLimitBrowserView(limit: p) { chosen in
                                        addToBuilder(chosen)
                                    }
                            } label: {
                                HStack {
                                    Text("\(p)-limit")
                                    Spacer()
                                    if count(for: p) > 0 {
                                        Text("\(count(for: p))")
                                            .font(.caption2.monospacedDigit())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                
                                }
                            }
                        }
                    }

                    // All scales (filtered/sorted)
                    Section("My Scales (\(filteredScales.count))") {
                        ForEach(filteredScales) { s in
                                                    // Primary tap: open the Library action sheet for this scale
                                                    Button {
                                                        actionTarget = s
                                                    } label: {
                                                        ScaleRow(scale: s, disclosure: true) // show chevron on the right
                                                    }
                                                    .buttonStyle(.plain)
                                                    // Trailing swipe: Open / Add / Play (plus Delete)
                                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                        Button("Open") { openInBuilder(s) }.tint(.accentColor)
                                                        Button("Add")  { addToBuilder(s) }.tint(.blue)
                                                        Button("Play") { playScalePreview(s) }.tint(.gray)
                                                        Button(role: .destructive) {
                                                            library.deleteScale(id: s.id)
                                                        } label: { Label("Delete", systemImage: "trash") }
                                                    }
                                                    // Leading swipe: Favorite toggle
                                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                                        Button {
                                                            var t = s; t.favorite.toggle(); library.updateScale(t)
                                                        } label: {
                                                            Label(s.favorite ? "Unfavorite" : "Favorite",
                                                                  systemImage: s.favorite ? "star.slash" : "star")
                                                        }.tint(.yellow)
                                                    }
                                                    // Context menu: ensure three actions, with Open first
                                                    .contextMenu {
                                                        Button("Open in Builder") { openInBuilder(s) }
                                                        Button("Add to Builder") { addToBuilder(s) }
                                                        Button("Play Scale") { playScalePreview(s) }
                                                    }
                                                }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .searchable(text: $library.searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Per-scale actions presented as a medium detent sheet
            .sheet(item: $actionTarget) { s in
                ScaleActionsSheet(
                    scale: s,
                    onOpen: { openInBuilder(s) },
                    onAdd:  { addToBuilder(s) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Row
private struct ScaleRow: View {
    let scale: TenneyScale
    var disclosure: Bool = false
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                VStack(spacing: 2) {
                    Text("\(scale.size)")
                        .font(.headline.monospacedDigit())
                    Text("notes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                // Bolded name aligns with “Open in Builder” as the primary action
                        Text(scale.name).font(.headline.weight(.semibold))
                HStack(spacing: 8) {
                    Text("\(scale.detectedLimit)-limit").font(.caption).foregroundStyle(.secondary)
                    Text("Root \(Int(scale.referenceHz)) Hz").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if scale.favorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            if disclosure {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
        }
        .contentShape(Rectangle())
    }
}
// MARK: - Actions & Helpers
private extension ScaleLibrarySheet {
    func openInBuilder(_ s: TenneyScale) {
        // Open THIS file (not a new buffer)
        model.builderPayload = ScaleBuilderPayload(
            rootHz: s.referenceHz,
            primeLimit: s.detectedLimit,
            axisShift: [:],
            items: s.degrees,
            autoplayAll: model.latticeAuditionOn,
            startInLibrary: false,
            existing: s
        )
        // Close the medium detent; Builder sheet will present
        model.showScaleLibraryDetent = false
    }
    func addToBuilder(_ s: TenneyScale) {
        // Create a working buffer seeded with this scale (does NOT bind to file)
        model.builderPayload = ScaleBuilderPayload(
            rootHz: s.referenceHz,
            primeLimit: s.detectedLimit,
            axisShift: [:],
            items: s.degrees,
            autoplayAll: model.latticeAuditionOn,
            startInLibrary: false,
            existing: nil
        )
        model.showScaleLibraryDetent = false
    }
    func playScalePreview(_ s: TenneyScale) {
        let root = s.referenceHz
        for (i, r) in s.degrees.enumerated() {
            let when = DispatchTime.now() + .milliseconds(180 * i)
            DispatchQueue.main.asyncAfter(deadline: when) {
                let (cn, cd) = canonicalPQUnit(r.p, r.q)
                let f = foldToAudible(root * (Double(cn) / Double(cd)))
                guard (UserDefaults.standard.object(forKey: "Tenney.SoundOn") as? Bool ?? true) else { return }
                let id = ToneOutputEngine.shared.sustain(
                    freq: f,
                    amp: 0.16,
                    owner: .other,
                    ownerKey: "scaleLibrary:preview",
                    attackMs: nil,
                    releaseMs: nil
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                    ToneOutputEngine.shared.release(id: id, seconds: 0.0)
                                }
            }
        }
    }
    // Keep 1 ≤ p/q < 2 so 3/2 never shows/plays as 3/1
    func canonicalPQUnit(_ p: Int, _ q: Int) -> (Int, Int) {
        guard p > 0 && q > 0 else { return (p, q) }
        var n = p, d = q
        while Double(n)/Double(d) >= 2 { d &*= 2 }
        while Double(n)/Double(d) <  1 { n &*= 2 }
        var a = n, b = d
        while b != 0 { let t = a % b; a = b; b = t }
        let g = max(1, a)
        return (n/g, d/g)
    }
    func foldToAudible(_ f: Double, minHz: Double = 20, maxHz: Double = 5000) -> Double {
        guard f.isFinite && f > 0 else { return f }
        var x = f; while x < minHz { x *= 2 }; while x > maxHz { x *= 0.5 }; return x
    }
}
// MARK: - Per-scale Action Sheet (Open • Add • Play)
private struct ScaleActionsSheet: View {
    let scale: TenneyScale
    let onOpen: () -> Void
    let onAdd:  () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = ScaleLibraryStore.shared
    @AppStorage(SettingsKeys.staffA4Hz) private var staffA4Hz: Double = 440
    @AppStorage(SettingsKeys.builderExportFormats) private var exportFormatsRaw: Int = ExportFormat.default.rawValue
    @AppStorage(SettingsKeys.builderExportRootMode) private var exportA4ModeRaw: String = ExportA4Mode.appDefault.rawValue
    @AppStorage(SettingsKeys.builderExportCustomA4Hz) private var customExportA4Hz: Double = 440.0
    @AppStorage("Tenney.SoundOn") private var soundOn: Bool = true
    @AppStorage(SettingsKeys.safeAmp) private var safeAmp: Double = 0.18
    @State private var playback = ScaleSheetPlayback()
    @State private var page: Int = 0

    @State private var playbackMode: ScalePlaybackMode = .arp
    @State private var focusedDegreeID: String? = nil
    @State private var showExportSheet = false
    @State private var exportErrorMessage: String? = nil
    @State private var exportURLs: [URL] = []
    @State private var isPresentingShareSheet = false
    @State private var showRenameSheet = false
    @State private var showTagsSheet = false
    @State private var showDeleteConfirm = false
    @State private var renameText = ""
    @State private var tagsDraft: [String] = []
    @State private var newTagText = ""
    @State private var folderDraft = ""
    @State private var copyMessage: String? = nil

    private var currentScale: TenneyScale {
        library.scales[scale.id] ?? scale
    }

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
            return 440.0
        case .hz440:
            return 440.0
        case .custom:
            return max(1.0, customExportA4Hz)
        }
    }

    private var degreesSorted: [RatioRef] {
        currentScale.degrees.enumerated().sorted { lhs, rhs in
            let l = degreeFrequency(lhs.element)
            let r = degreeFrequency(rhs.element)
            if l == r { return lhs.offset < rhs.offset }
            return l < r
        }.map(\.element)
    }

    private var folderName: String? {
        currentScale.tags.first { isFolderTag($0) }
            .map { String($0.dropFirst(folderPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var visibleTags: [String] {
        currentScale.tags.filter { !isFolderTag($0) }
    }

    private var headerSummary: String {
        let rootNote = NotationFormatter.spelledETNote(freqHz: currentScale.referenceHz, a4Hz: staffA4Hz)
        let hzInt = Int(round(currentScale.referenceHz))
        return "\(currentScale.size) notes · \(currentScale.detectedLimit)-limit · Root: \(rootNote.letter)\(rootNote.accidental)\(rootNote.octave) (\(hzInt) Hz)"
    }

    private var referenceSummary: String {
        let hzInt = Int(round(staffA4Hz))
        return "A4 = \(hzInt) Hz"
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

    private var builderRootSummary: String {
        let hz = currentScale.referenceHz
        let (name, oct) = NotationFormatter.staffNoteName(freqHz: hz)
        let hzInt = Int(round(hz))
        return "Root: \(name)\(oct) (\(hzInt) Hz)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $page) {
                Text("Overview").tag(0)
                Text("Hear").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            GeometryReader { proxy in
                TabView(selection: $page) {
                    OverviewPage(
                        title: currentScale.name,
                        headerSummary: headerSummary,
                        referenceSummary: referenceSummary,
                        folderName: folderName,
                        tags: visibleTags,
                        onOpen: {
                            onOpen()
                            dismiss()
                        },
                        onAdd: {
                            onAdd()
                            dismiss()
                        },
                        onExport: { showExportSheet = true },
                        onCopyRatios: { copyRatios() },
                        onCopyJSON: { copyJSON() },
                        onCopySCL: { copySCL() },
                        onRename: {
                            renameText = currentScale.name
                            showRenameSheet = true
                        },
                        onTags: {
                            tagsDraft = visibleTags
                            folderDraft = folderName ?? ""
                            newTagText = ""
                            showTagsSheet = true
                        },
                        onDelete: { showDeleteConfirm = true }
                    )
                    .tag(0)

                    HearPage(
                        playbackMode: $playbackMode,
                        focusedDegreeID: focusedDegreeID,
                        focusedDegreeLabel: focusedDegreeLabel(),
                        degrees: degreesSorted,
                        rootHz: currentScale.referenceHz,
                        onSelectDegree: { selectDegree(id: $0) },
                        onPlay: { playScale() }
                    )
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let copyMessage {
                Text(copyMessage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ScrollView {
                ScaleExportSheet(
                    title: resolvedName(),
                    builderRootSummary: builderRootSummary,
                    exportSummaryText: exportSummaryText,
                    exportFormats: exportFormats,
                    exportErrorMessage: exportErrorMessage,
                    onToggleFormat: { toggleFormat($0) },
                    onExport: { performExportNow() },
                    onDone: { showExportSheet = false },
                    exportA4Mode: exportA4ModeBinding,
                    customA4Hz: $customExportA4Hz
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isPresentingShareSheet) {
            ActivityView(activityItems: exportURLs)
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rename Scale")
                        .font(.headline)
                    TextField("Scale name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                }
                .padding(16)
                .navigationTitle("Rename")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showRenameSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            applyRename()
                            showRenameSheet = false
                        }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showTagsSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Folder")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    TextField("Folder name", text: $folderDraft)
                        .textFieldStyle(.roundedBorder)

                    Text("Tags")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    if tagsDraft.isEmpty {
                        Text("No tags yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            ForEach(tagsDraft, id: \.self) { tag in
                                RemovableChip(text: tag) {
                                    tagsDraft.removeAll { $0 == tag }
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Add tag", text: $newTagText)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            if !tagsDraft.contains(trimmed) {
                                tagsDraft.append(trimmed)
                            }
                            newTagText = ""
                        }
                        .buttonStyle(.bordered)
                        .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Spacer()
                }
                .padding(16)
                .navigationTitle("Tags & Folder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTagsSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            applyTags()
                            showTagsSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Delete scale?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                library.deleteScale(id: currentScale.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove “\(currentScale.name)” from your Library.")
        }
        .onDisappear {
            playback.stop()
        }
    }

    private func playScale() {
        guard soundOn else { return }
        let focus = degreesSorted.first { $0.id == focusedDegreeID }
        playback.play(
            mode: playbackMode,
            scale: currentScale,
            degrees: degreesSorted,
            focus: focus,
            safeAmp: safeAmp
        )
    }

    private func focusedDegreeLabel() -> String? {
        guard let id = focusedDegreeID,
              let ratio = degreesSorted.first(where: { $0.id == id }) else { return nil }
        let label = ratioDisplay(ratio).label
        if ratio.octave != 0 {
            return "\(label) (\(ratio.octave > 0 ? "+\(ratio.octave)" : "\(ratio.octave)") oct)"
        }
        return label
    }

    private func degreeFrequency(_ ratio: RatioRef) -> Double {
        RatioMath.hz(rootHz: currentScale.referenceHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: false)
    }

    private func ratioDisplay(_ ratio: RatioRef) -> (label: String, octave: Int) {
        let (p, q) = RatioMath.canonicalPQUnit(ratio.p, ratio.q)
        return ("\(p)/\(q)", ratio.octave)
    }

    private func selectDegree(id: String) {
        guard focusedDegreeID != id else { return }
        focusedDegreeID = id
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }

    private func copyRatios() {
        let lines = degreesSorted.map { ratio -> String in
            let display = ratioDisplay(ratio)
            if display.octave != 0 {
                return "\(display.label) [\(display.octave)]"
            }
            return display.label
        }
        copyToPasteboard(lines.joined(separator: "\n"), message: "Copied ratios")
    }

    private func copyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(currentScale)
            if let string = String(data: data, encoding: .utf8) {
                copyToPasteboard(string, message: "Copied JSON")
            }
        } catch {
            copyToPasteboard("{}", message: "Copy failed")
        }
    }

    private func copySCL() {
        let text = ScalaExporter.sclText(
            scaleName: resolvedName(),
            description: currentScale.descriptionText,
            degrees: currentScale.degrees
        )
        copyToPasteboard(text, message: "Copied .scl")
    }

    private func copyToPasteboard(_ string: String, message: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = string
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
#endif
        showCopyMessage(message)
    }

    private func showCopyMessage(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            copyMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                copyMessage = nil
            }
        }
    }

    private func applyRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = currentScale
        updated.name = trimmed
        updated.lastPlayed = Date()
        library.updateScale(updated)
    }

    private func applyTags() {
        var updated = currentScale
        var tags = tagsDraft
        tags.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let folder = folderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !folder.isEmpty {
            tags.append("\(folderPrefix)\(folder)")
        }
        updated.tags = Array(Set(tags)).sorted()
        updated.lastPlayed = Date()
        library.updateScale(updated)
    }

    private func toggleFormat(_ format: ExportFormat) {
        var current = exportFormats
        if current.contains(format) {
            current.remove(format)
        } else {
            current.insert(format)
        }
        exportFormatsRaw = current.rawValue
        if exportErrorMessage != nil {
            exportErrorMessage = nil
        }
    }

    private func performExportNow() {
        exportErrorMessage = nil

        let degrees = currentScale.degrees
        guard !degrees.isEmpty else {
            exportErrorMessage = "Scale has no degrees to export."
            return
        }

        let name = sanitizedFilename(from: resolvedName())
        let desc = currentScale.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootHz = exportA4Hz

        var urls: [URL] = []

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

        if exportFormats.contains(.kbm) {
            let text = ScalaExporter.kbmText(
                referenceHz: rootHz,
                scaleSize: max(1, degrees.count)
            )
            if let url = writeExportFile(named: "\(name).kbm", contents: text) {
                urls.append(url)
            }
        }

        if exportFormats.contains(.freqs) {
            let lines: [String] = degrees.map { r in
                let ratio = (Double(r.p) / Double(r.q)) * pow(2.0, Double(r.octave))
                let hz = ratio * currentScale.referenceHz
                return String(format: "%.8f", hz)
            }
            if let url = writeExportFile(named: "\(name)_freqs.txt", contents: lines.joined(separator: "\n")) {
                urls.append(url)
            }
        }

        if exportFormats.contains(.cents) {
            let lines: [String] = degrees.map { r in
                let ratio = (Double(r.p) / Double(r.q)) * pow(2.0, Double(r.octave))
                let cents = 1200.0 * log2(ratio)
                return String(format: "%.8f", cents)
            }
            if let url = writeExportFile(named: "\(name)_cents.txt", contents: lines.joined(separator: "\n")) {
                urls.append(url)
            }
        }

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

    private func writeReadmeFile(baseName: String, degrees: [RatioRef]) -> URL? {
        let scaleName = resolvedName()
        let desc = currentScale.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let a4Hz = exportA4Hz
        let rootHz = currentScale.referenceHz
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
        lines.append("Prime limit: \(currentScale.detectedLimit)-limit JI")
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

    private func resolvedName() -> String {
        let n = currentScale.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Untitled Scale" : n
    }

    private var folderPrefix: String { "folder:" }

    private func isFolderTag(_ tag: String) -> Bool {
        tag.lowercased().hasPrefix(folderPrefix)
    }

}

private enum ScalePlaybackMode: String, CaseIterable, Identifiable {
    case arp
    case chord
    case drone

    var id: String { rawValue }
    var title: String {
        switch self {
        case .arp: return "Arp"
        case .chord: return "Chord"
        case .drone: return "Drone"
        }
    }
}

private final class ScaleSheetPlayback {
    private var activeVoiceIDs: [Int] = []
    private var token = UUID()

    func play(mode: ScalePlaybackMode, scale: TenneyScale, degrees: [RatioRef], focus: RatioRef?, safeAmp: Double) {
        stop()
        let newToken = UUID()
        token = newToken

        let rootHz = RatioMath.foldToAudible(scale.referenceHz)
        let selected = focus ?? degrees.first
        let amp = Float(safeAmp)

        func startTone(_ freq: Double) -> Int {
            let ownerKey = "scaleLibrary:\(scale.id.uuidString):\(UUID().uuidString)"
            return ToneOutputEngine.shared.sustain(
                freq: freq,
                amp: amp,
                owner: .other,
                ownerKey: ownerKey,
                attackMs: 6,
                releaseMs: 120
            )
        }

        func scheduleRelease(id: Int, after seconds: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, self.token == newToken else { return }
                ToneOutputEngine.shared.release(id: id, seconds: 0.06)
                self.activeVoiceIDs.removeAll { $0 == id }
            }
        }

        switch mode {
        case .arp:
            for (index, ratio) in degrees.enumerated() {
                let delay = Double(index) * 0.18
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.token == newToken else { return }
                    let hz = RatioMath.hz(rootHz: scale.referenceHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: true)
                    let id = startTone(hz)
                    self.activeVoiceIDs.append(id)
                    scheduleRelease(id: id, after: 0.22)
                }
            }
        case .chord:
            for ratio in degrees {
                let hz = RatioMath.hz(rootHz: scale.referenceHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: true)
                let id = startTone(hz)
                activeVoiceIDs.append(id)
                scheduleRelease(id: id, after: 0.38)
            }
        case .drone:
            let rootID = startTone(rootHz)
            activeVoiceIDs.append(rootID)
            scheduleRelease(id: rootID, after: 0.48)
            if let selected {
                let hz = RatioMath.hz(rootHz: scale.referenceHz, p: selected.p, q: selected.q, octave: selected.octave, fold: true)
                let id = startTone(hz)
                activeVoiceIDs.append(id)
                scheduleRelease(id: id, after: 0.48)
            }
        }
    }

    func stop() {
        token = UUID()
        for id in activeVoiceIDs {
            ToneOutputEngine.shared.release(id: id, seconds: 0.0)
        }
        activeVoiceIDs.removeAll()
    }
}

private struct OverviewPage: View {
    let title: String
    let headerSummary: String
    let referenceSummary: String
    let folderName: String?
    let tags: [String]
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onExport: () -> Void
    let onCopyRatios: () -> Void
    let onCopyJSON: () -> Void
    let onCopySCL: () -> Void
    let onRename: () -> Void
    let onTags: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(headerSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(referenceSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()

                    if !tags.isEmpty || (folderName?.isEmpty == false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            if let folderName, !folderName.isEmpty {
                                tagChip(text: folderName, systemImage: "folder.fill")
                            }
                            ForEach(tags, id: \.self) { tag in
                                tagChip(text: tag, systemImage: "tag.fill")
                            }
                        }
                    } else {
                        Text("No tags or folders yet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Actions")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        Button(action: onOpen) {
                            ActionTile(
                                title: "Open",
                                systemImage: "square.stack.3d.up.fill",
                                style: .standard(.accentColor)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onAdd) {
                            ActionTile(
                                title: "Set Current",
                                systemImage: "arrow.turn.down.right",
                                style: .standard(.blue)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onExport) {
                            ActionTile(
                                title: "Export…",
                                systemImage: "square.and.arrow.up",
                                style: .standard(.accentColor)
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                onCopyRatios()
                            } label: {
                                Label("Copy ratios", systemImage: "list.number")
                            }
                            Button {
                                onCopyJSON()
                            } label: {
                                Label("Copy as JSON", systemImage: "curlybraces")
                            }
                            Button {
                                onCopySCL()
                            } label: {
                                Label("Copy .scl text", systemImage: "doc.plaintext")
                            }
                        } label: {
                            ActionTile(
                                title: "Copy…",
                                systemImage: "doc.on.doc",
                                style: .standard(.secondary)
                            )
                        }

                        Button(action: onRename) {
                            ActionTile(
                                title: "Rename…",
                                systemImage: "pencil",
                                style: .standard(.secondary)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onTags) {
                            ActionTile(
                                title: "Tags…",
                                systemImage: "tag",
                                style: .standard(.secondary)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onDelete) {
                            ActionTile(
                                title: "Delete",
                                systemImage: "trash",
                                style: .destructive
                            )
                        }
                        .buttonStyle(.plain)
                        .gridCellColumns(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }

    private func tagChip(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}

private struct HearPage: View {
    @Binding var playbackMode: ScalePlaybackMode
    let focusedDegreeID: String?
    let focusedDegreeLabel: String?
    let degrees: [RatioRef]
    let rootHz: Double
    let onSelectDegree: (String) -> Void
    let onPlay: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Hear", systemImage: "speaker.wave.2.fill")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Picker("Playback Mode", selection: $playbackMode) {
                        ForEach(ScalePlaybackMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if playbackMode == .drone, let focusedDegreeLabel {
                        Text("Drone focus: \(focusedDegreeLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Degrees")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(degrees, id: \.id) { ratio in
                            Button {
                                onSelectDegree(ratio.id)
                            } label: {
                                RatioChip(
                                    ratio: ratio,
                                    isSelected: focusedDegreeID == ratio.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(degrees, id: \.id) { ratio in
                            DegreeRow(
                                ratio: ratio,
                                rootHz: rootHz,
                                isSelected: focusedDegreeID == ratio.id
                            )
                            .onTapGesture {
                                onSelectDegree(ratio.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }
}

private struct ActionTile: View {
    enum Style {
        case standard(Color)
        case destructive
    }

    let title: String
    let systemImage: String
    let subtitle: String?
    let style: Style

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let isDestructive: Bool
        let tint: Color

        switch style {
        case .standard(let accent):
            isDestructive = false
            tint = accent
        case .destructive:
            isDestructive = true
            tint = .white
        }

        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isDestructive ? .white : .primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isDestructive ? .white.opacity(0.85) : .secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(12)
        .background(
            Group {
                if isDestructive {
                    shape.fill(Color.red)
                } else {
                    Color.clear
                }
            }
        )
        .glassEffect(.regular, in: shape)
        .overlay(
            shape.stroke(
                isDestructive ? Color.white.opacity(0.35) : Color.secondary.opacity(0.15),
                lineWidth: 1
            )
        )
    }

    init(title: String, systemImage: String, subtitle: String? = nil, style: Style) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.style = style
    }
}

private struct RatioChip: View {
    let ratio: RatioRef
    let isSelected: Bool

    var body: some View {
        let display = RatioMath.unitLabel(ratio.p, ratio.q)
        HStack(spacing: 6) {
            Text(display)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if ratio.octave != 0 {
                Text(ratio.octave > 0 ? "+\(ratio.octave)" : "\(ratio.octave)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? .thinMaterial : .ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct DegreeRow: View {
    let ratio: RatioRef
    let rootHz: Double
    let isSelected: Bool

    var body: some View {
        let (p, q) = RatioMath.canonicalPQUnit(ratio.p, ratio.q)
        let hz = RatioMath.hz(rootHz: rootHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: true)
        let cents = NotationFormatter.centsFromNearestET(freqHz: hz)
        let note = NotationFormatter.spelledETNote(freqHz: hz)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(p)/\(q)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    if ratio.octave != 0 {
                        Text(ratio.octave > 0 ? "+\(ratio.octave) oct" : "\(ratio.octave) oct")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                Text("\(note.letter)\(note.accidental)\(note.octave)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.2f Hz", hz))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if abs(cents) >= 1 {
                    let rounded = Int(cents.rounded())
                    let sign = rounded >= 0 ? "+" : "−"
                    Text("\(sign)\(abs(rounded))¢")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(isSelected ? .thinMaterial : .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct RemovableChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}
