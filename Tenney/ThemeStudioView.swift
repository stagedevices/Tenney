
//
//  ThemeStudioView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ThemeStudioView: View {
@Environment(\.colorScheme) private var scheme

@State private var customs: [TenneyThemePersistence.CustomTheme] = TenneyThemePersistence.loadAll()

@State private var navPath: [UUID] = []
@State private var pendingDeleteID: UUID?
@State private var showDeleteConfirm: Bool = false

var body: some View {
    NavigationStack(path: $navPath) {
        List {
            Section {
                headerRow
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(customs) { t in
                    themeRow(t)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                pendingDeleteID = t.id
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                duplicateTheme(id: t.id)
                            } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                            .tint(.secondary)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Theme Studio")
        .navigationDestination(for: UUID.self) { id in
            ThemeStudioEditor(
                theme: binding(for: id),
                onCommit: { commitTheme($0) },
                onDuplicate: { duplicateTheme(id: id) }
            )
        }
        .alert("Delete Theme?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID { deleteTheme(id: id) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .onDisappear {
            // belt-and-suspenders: if view disappears unexpectedly, persist current list state
            persistAll()
        }
    }
}

private var headerRow: some View {
    HStack {
        Text("Custom Themes").font(.headline)
        Spacer()
        Button {
            createThemeAndEdit()
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
        .accessibilityLabel("Create theme")
    }
}

private func themeRow(_ t: TenneyThemePersistence.CustomTheme) -> some View {
    let idRaw = "custom:\(t.id.uuidString)"
    let resolved = TenneyThemeRegistry.resolvedCurrent(
        themeIDRaw: idRaw,
        scheme: scheme,
        // Per spec: behavioral defaults are global; still supply stable values for resolution.
        mixBasis: TenneyMixBasis(rawValue: t.mixBasis) ?? .complexityWeight,
        mixMode: TenneyMixMode(rawValue: t.mixMode) ?? .blend,
        scopeMode: TenneyScopeColorMode(rawValue: t.scopeMode) ?? .constant
    )

    return Button {
        navPath.append(t.id)
    } label: {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.name).font(.headline)
            ThemeTilePreviewStrip()
                .environment(\.tenneyTheme, resolved)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .tenneyChromaShadow(true, radius: 18, y: 8)
    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
}

private func binding(for id: UUID) -> Binding<TenneyThemePersistence.CustomTheme> {
    Binding(
        get: { customs.first(where: { $0.id == id }) ?? makeDefaultTheme(id: id) },
        set: { newValue in
            if let i = customs.firstIndex(where: { $0.id == id }) { customs[i] = newValue }
        }
    )
}

// MARK: - Persistence (commit-only)

private func persistAll() {
    TenneyThemePersistence.saveAll(customs)
}

private func commitTheme(_ updated: TenneyThemePersistence.CustomTheme) {
    if let i = customs.firstIndex(where: { $0.id == updated.id }) {
        customs[i] = updated
        persistAll()
    }
}

// MARK: - Operations

private func createThemeAndEdit() {
    let new = makeDefaultTheme(id: UUID())
    customs.insert(new, at: 0)
    persistAll()
    navPath.append(new.id) // create then immediately enter editor
}

    private func duplicateTheme(id: UUID) {
        guard let src = customs.first(where: { $0.id == id }) else { return }

        let copy = TenneyThemePersistence.CustomTheme(
            id: UUID(),
            name: src.name.isEmpty ? "Custom Copy" : "\(src.name) Copy",
            paletteHex: src.paletteHex,

            // kept for forward compatibility
            mixBasis: src.mixBasis,
            mixMode: src.mixMode,

            lightTintHex: src.lightTintHex,
            lightStrength: src.lightStrength,
            darkTintHex: src.darkTintHex,
            darkStrength: src.darkStrength,

            tunerNeedleHex: src.tunerNeedleHex,
            tunerTicksHex: src.tunerTicksHex,
            tunerTickOpacity: src.tunerTickOpacity,
            tunerInTuneNeutralHex: src.tunerInTuneNeutralHex,
            tunerInTuneStrength: src.tunerInTuneStrength,

            scopeTraceHex: src.scopeTraceHex,
            scopeMode: src.scopeMode
        )

        customs.insert(copy, at: 0)
        persistAll()
        navPath.append(copy.id)
    }

    

private func deleteTheme(id: UUID) {
    customs.removeAll(where: { $0.id == id })
    persistAll()
    navPath.removeAll(where: { $0 == id })
}

private func makeDefaultTheme(id: UUID) -> TenneyThemePersistence.CustomTheme {
    var pal: [Int: String] = [:]
    for p in TenneyPrime.themed {
        pal[p] = (p == 3 ? "#5C7CFF" : p == 5 ? "#FF6FA3" : "#77E4DD")
    }

    return TenneyThemePersistence.CustomTheme(
        id: id,
        name: "Custom",
        paletteHex: pal,

        // Kept for forward compatibility; editor hides behavioral controls in v1.
        mixBasis: TenneyMixBasis.complexityWeight.rawValue,
        mixMode: TenneyMixMode.blend.rawValue,

        lightTintHex: "#FFFFFF",
        lightStrength: 0.04,
        darkTintHex: "#000000",
        darkStrength: 0.06,

        tunerNeedleHex: "#FF6FA3",
        tunerTicksHex: "#FFFFFF",
        tunerTickOpacity: 0.70,
        tunerInTuneNeutralHex: "#5C7CFF",
        tunerInTuneStrength: 0.85,

        scopeTraceHex: "#77E4DD",
        scopeMode: TenneyScopeColorMode.constant.rawValue
    )
}

}

// MARK: - Editor

private struct ThemeStudioEditor: View {
@Environment(\.colorScheme) private var scheme

@Binding var theme: TenneyThemePersistence.CustomTheme
let onCommit: (TenneyThemePersistence.CustomTheme) -> Void
let onDuplicate: () -> Void

@State private var draft: TenneyThemePersistence.CustomTheme
@State private var openSections: Set<String> = ["identity", "palette", "glass", "tuner", "scope"]

@State private var colorEdit: ColorEditTarget?
@FocusState private var focus: Field?

init(
    theme: Binding<TenneyThemePersistence.CustomTheme>,
    onCommit: @escaping (TenneyThemePersistence.CustomTheme) -> Void,
    onDuplicate: @escaping () -> Void
) {
    self._theme = theme
    self.onCommit = onCommit
    self.onDuplicate = onDuplicate
    self._draft = State(initialValue: theme.wrappedValue)
}

private enum Field: Hashable {
    case name
}

var body: some View {
    let resolved = TenneyThemeRegistry.resolvedCurrent(
        themeIDRaw: "custom:\(draft.id.uuidString)",
        scheme: scheme,
        mixBasis: TenneyMixBasis(rawValue: draft.mixBasis) ?? .complexityWeight,
        mixMode: TenneyMixMode(rawValue: draft.mixMode) ?? .blend,
        scopeMode: TenneyScopeColorMode(rawValue: draft.scopeMode) ?? .constant
    )

    ViewThatFits(in: .horizontal) {
        // Regular width: sticky preview column + scrolling inspector
        HStack(alignment: .top, spacing: 14) {
            previewCard(resolved: resolved)
                .frame(maxWidth: 360)
                .padding(.top, 8)

            ScrollView {
                inspector(resolved: resolved)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.automatic)
        }
        .padding()

        // Compact width: preview on top, then inspector
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                previewCard(resolved: resolved)
                inspector(resolved: resolved)
            }
            .padding()
            .padding(.bottom, 24)
        }
    }
    .navigationTitle(draft.name.isEmpty ? "Theme" : draft.name)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { draft = theme }
    .sheet(item: $colorEdit) { target in
        ThemeColorEditorSheet(
            title: target.title,
            initialHex: target.getHex(draft),
            onCommitHex: { newHex in
                target.setHex(&draft, newHex)
                commit()
            }
        )
        .presentationDetents([.medium, .large])
        .tenneySheetSizing()
    }
    .onChange(of: focus) { newFocus in
        // Commit on focus loss (identity only)
        if newFocus != .name { commit() }
    }
}

private func previewCard(resolved: ResolvedTenneyTheme) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Preview").font(.headline)

        ThemeTilePreviewStrip()
            .environment(\.tenneyTheme, resolved)
    }
    .padding(14)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .tenneyChromaShadow(true, radius: 18, y: 8)
}

private func inspector(resolved: ResolvedTenneyTheme) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        identitySection()
        paletteSection()
        glassSection()
        tunerSection()
        scopeSection()
    }
}
    private func sectionExpanded(_ key: String) -> Binding<Bool> {
        Binding(
            get: { openSections.contains(key) },
            set: { isOn in
                if isOn { openSections.insert(key) }
                else { openSections.remove(key) }
            }
        )
    }


// MARK: - Sections

private func identitySection() -> some View {
    DisclosureGroup(
        isExpanded: sectionExpanded("identity")
    ) {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .name)
                .onSubmit { commit() }

            HStack {
                Spacer()
                Button {
                    onDuplicate()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
    } label: {
        Text("Identity").font(.headline)
    }
    .padding(14)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

private func paletteSection() -> some View {
    DisclosureGroup(
        isExpanded: sectionExpanded("palette")

    ) {
        let cols = [GridItem(.adaptive(minimum: 64), spacing: 10)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            ForEach(TenneyPrime.themed, id: \.self) { p in
                primeChip(p)
            }
        }
        .padding(.top, 8)
    } label: {
        Text("Palette (Primes)").font(.headline)
    }
    .padding(14)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

private func primeChip(_ p: Int) -> some View {
    let hex = draft.paletteHex[p] ?? "#777777"
    let swatch = Color(uiColor: UIColor(hex: hex) ?? UIColor.secondaryLabel)

    return Button {
        colorEdit = .prime(p)
    } label: {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(swatch)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )

            Text("\(p)")
                .font(.headline)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Prime \(p) color")
}

private func glassSection() -> some View {
    DisclosureGroup(
        isExpanded: sectionExpanded("glass")

    ) {
        VStack(spacing: 12) {
            HStack {
                Text("Light").frame(width: 60, alignment: .leading)

                Button { colorEdit = .lightTint } label: {
                    Label("Edit Color", systemImage: "eyedropper.halffull")
                }
                .buttonStyle(.bordered)

                Spacer()

                Slider(
                    value: $draft.lightStrength,
                    in: 0...0.18,
                    onEditingChanged: { editing in
                        if !editing { commit() }
                    }
                )
                .frame(maxWidth: 220)
            }

            HStack {
                Text("Dark").frame(width: 60, alignment: .leading)

                Button { colorEdit = .darkTint } label: {
                    Label("Edit Color", systemImage: "eyedropper.halffull")
                }
                .buttonStyle(.bordered)

                Spacer()

                Slider(
                    value: $draft.darkStrength,
                    in: 0...0.18,
                    onEditingChanged: { editing in
                        if !editing { commit() }
                    }
                )
                .frame(maxWidth: 220)
            }
        }
        .padding(.top, 8)
    } label: {
        Text("Glass Tint").font(.headline)
    }
    .padding(14)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

private func tunerSection() -> some View {
    DisclosureGroup(
        isExpanded: sectionExpanded("tuner")

    ) {
        VStack(spacing: 12) {
            HStack {
                Text("Needle").frame(width: 80, alignment: .leading)
                Button { colorEdit = .needle } label: {
                    Label("Edit Color", systemImage: "eyedropper.halffull")
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            HStack {
                Text("Ticks").frame(width: 80, alignment: .leading)
                Button { colorEdit = .ticks } label: {
                    Label("Edit Color", systemImage: "eyedropper.halffull")
                }
                .buttonStyle(.bordered)

                Spacer()

                Slider(
                    value: $draft.tunerTickOpacity,
                    in: 0.2...1.0,
                    onEditingChanged: { editing in if !editing { commit() } }
                )
                .frame(maxWidth: 220)
            }

            HStack {
                Text("In-Tune").frame(width: 80, alignment: .leading)
                Button { colorEdit = .inTuneNeutral } label: {
                    Label("Edit Color", systemImage: "eyedropper.halffull")
                }
                .buttonStyle(.bordered)

                Spacer()

                Slider(
                    value: $draft.tunerInTuneStrength,
                    in: 0.2...1.0,
                    onEditingChanged: { editing in if !editing { commit() } }
                )
                .frame(maxWidth: 220)
            }
        }
        .padding(.top, 8)
    } label: {
        Text("Tuner").font(.headline)
    }
    .padding(14)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

private func scopeSection() -> some View {
    DisclosureGroup(
        isExpanded: sectionExpanded("scope")

    ) {
        HStack {
            Text("Trace").frame(width: 80, alignment: .leading)
            Button { colorEdit = .scopeTrace } label: {
                Label("Edit Color", systemImage: "eyedropper.halffull")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.top, 8)
    } label: {
        Text("Scope").font(.headline)
    }
    .padding(14)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

// MARK: - Commit

private func commit() {
    normalizeDraftHexes()
    theme = draft
    onCommit(draft)
}

private func normalizeDraftHexes() {
    draft.lightTintHex = normalizeHex(draft.lightTintHex) ?? "#FFFFFF"
    draft.darkTintHex  = normalizeHex(draft.darkTintHex)  ?? "#000000"

    draft.tunerNeedleHex        = normalizeHex(draft.tunerNeedleHex)        ?? "#FFFFFF"
    draft.tunerTicksHex         = normalizeHex(draft.tunerTicksHex)         ?? "#FFFFFF"
    draft.tunerInTuneNeutralHex = normalizeHex(draft.tunerInTuneNeutralHex) ?? "#FFFFFF"
    draft.scopeTraceHex         = normalizeHex(draft.scopeTraceHex)         ?? "#FFFFFF"

    for p in TenneyPrime.themed {
        let raw = draft.paletteHex[p] ?? "#777777"
        draft.paletteHex[p] = normalizeHex(raw) ?? "#777777"
    }
}

// MARK: - Color edit target

private enum ColorEditTarget: Identifiable {
    case prime(Int)
    case lightTint
    case darkTint
    case needle
    case ticks
    case inTuneNeutral
    case scopeTrace

    var id: String {
        switch self {
        case .prime(let p): return "prime-\(p)"
        case .lightTint: return "lightTint"
        case .darkTint: return "darkTint"
        case .needle: return "needle"
        case .ticks: return "ticks"
        case .inTuneNeutral: return "inTuneNeutral"
        case .scopeTrace: return "scopeTrace"
        }
    }

    var title: String {
        switch self {
        case .prime(let p): return "Prime \(p)"
        case .lightTint: return "Light Tint"
        case .darkTint: return "Dark Tint"
        case .needle: return "Needle"
        case .ticks: return "Ticks"
        case .inTuneNeutral: return "In-Tune"
        case .scopeTrace: return "Scope Trace"
        }
    }

    func getHex(_ t: TenneyThemePersistence.CustomTheme) -> String {
        switch self {
        case .prime(let p): return t.paletteHex[p] ?? "#777777"
        case .lightTint: return t.lightTintHex
        case .darkTint: return t.darkTintHex
        case .needle: return t.tunerNeedleHex
        case .ticks: return t.tunerTicksHex
        case .inTuneNeutral: return t.tunerInTuneNeutralHex
        case .scopeTrace: return t.scopeTraceHex
        }
    }

    func setHex(_ t: inout TenneyThemePersistence.CustomTheme, _ hex: String) {
        switch self {
        case .prime(let p): t.paletteHex[p] = hex
        case .lightTint: t.lightTintHex = hex
        case .darkTint: t.darkTintHex = hex
        case .needle: t.tunerNeedleHex = hex
        case .ticks: t.tunerTicksHex = hex
        case .inTuneNeutral: t.tunerInTuneNeutralHex = hex
        case .scopeTrace: t.scopeTraceHex = hex
        }
    }
}

}

// MARK: - Color Editor Sheet

private struct ThemeColorEditorSheet: View {
let title: String
let initialHex: String
let onCommitHex: (String) -> Void

@Environment(\.dismiss) private var dismiss

@State private var hexText: String
@State private var color: Color

init(title: String, initialHex: String, onCommitHex: @escaping (String) -> Void) {
    self.title = title
    self.initialHex = initialHex
    self.onCommitHex = onCommitHex

    let norm = normalizeHex(initialHex) ?? "#777777"
    _hexText = State(initialValue: norm)
    _color = State(initialValue: Color(uiColor: UIColor(hex: norm) ?? UIColor.secondaryLabel))
}

var body: some View {
    NavigationStack {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color)
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )

            HStack(spacing: 10) {
                TextField("#RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { commitFromHex() }

                Button("Normalize") { normalizeInPlace() }
                    .buttonStyle(.bordered)
            }

            ColorPicker("Color", selection: $color, supportsOpacity: false)
                .onChange(of: color) { _ in
                    hexText = UIColor(color).toHexRGB()
                }

            harmonyRow

            Spacer()
        }
        .padding()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    commitFromHex()
                    dismiss()
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button { copyHex() } label: {
                        Label("Copy Hex", systemImage: "doc.on.doc")
                    }

                    Button { pasteHex() } label: {
                        Label("Paste Hex", systemImage: "clipboard")
                    }

                    Spacer()
                }
            }
        }
    }
    .onChange(of: hexText) { _ in
        // calm validation: normalize/commit happens on submit or Done
    }
}

private var harmonyRow: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Harmony").font(.headline)

        let base = UIColor(color)
        let hsv = base.toHSV()

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                harmonyButton("Complement", hsv.rotatedHue(180))
                harmonyButton("Analogous -30", hsv.rotatedHue(-30))
                harmonyButton("Analogous +30", hsv.rotatedHue(30))
                harmonyButton("Triad +120", hsv.rotatedHue(120))
                harmonyButton("Triad -120", hsv.rotatedHue(-120))
                harmonyButton("Split -150", hsv.rotatedHue(-150))
                harmonyButton("Split +150", hsv.rotatedHue(150))
            }
        }
    }
}

private func harmonyButton(_ label: String, _ hsv: HSV) -> some View {
    let c = hsv.toUIColor()
    return Button {
        color = Color(uiColor: c)
        hexText = c.toHexRGB()
    } label: {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: c))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
            Text(label).font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
}

private func normalizeInPlace() {
    if let n = normalizeHex(hexText) {
        hexText = n
        color = Color(uiColor: UIColor(hex: n) ?? UIColor.secondaryLabel)
    }
}

private func commitFromHex() {
    let n = normalizeHex(hexText) ?? UIColor(color).toHexRGB()
    hexText = n
    onCommitHex(n)
}

private func copyHex() {
    #if canImport(UIKit)
    UIPasteboard.general.string = normalizeHex(hexText) ?? hexText
    #endif
}

private func pasteHex() {
    #if canImport(UIKit)
    if let s = UIPasteboard.general.string {
        hexText = s
        normalizeInPlace()
    }
    #endif
}

}

// MARK: - Hex normalization + UIColor helpers

private func normalizeHex(_ raw: String) -> String? {
let upper = raw.uppercased()
let hexChars = upper.filter { ch in
("0"..."9").contains(ch) || ("A"..."F").contains(ch)
}

if hexChars.count == 3 {
    let i0 = hexChars.startIndex
    let i1 = hexChars.index(i0, offsetBy: 1)
    let i2 = hexChars.index(i0, offsetBy: 2)

    let r = hexChars[i0]
    let g = hexChars[i1]
    let b = hexChars[i2]
    return "#\(r)\(r)\(g)\(g)\(b)\(b)"
}

if hexChars.count == 6 {
    return "#\(hexChars)"
}

if hexChars.count == 8 {
    // v1: ignore alpha, keep RGB
    let start = hexChars.startIndex
    let end = hexChars.index(start, offsetBy: 6)
    return "#\(hexChars[start..<end])"
}

return nil

}

private extension UIColor {
convenience init?(hex: String) {
guard let n = normalizeHex(hex) else { return nil }
let s = n.dropFirst()
guard s.count == 6 else { return nil }

    let r = Int(s.prefix(2), radix: 16) ?? 0
    let g = Int(s.dropFirst(2).prefix(2), radix: 16) ?? 0
    let b = Int(s.dropFirst(4).prefix(2), radix: 16) ?? 0

    self.init(
        red: CGFloat(r) / 255.0,
        green: CGFloat(g) / 255.0,
        blue: CGFloat(b) / 255.0,
        alpha: 1.0
    )
}

func toHexRGB() -> String {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
}

func toHSV() -> HSV {
    var h: CGFloat = 0
    var s: CGFloat = 0
    var v: CGFloat = 0
    var a: CGFloat = 0

    if getHue(&h, saturation: &s, brightness: &v, alpha: &a) {
        return HSV(h: Double(h * 360.0), s: Double(s), v: Double(v))
    }

    // Fallback for colors that don't expose hue (e.g., grayscale): derive from RGB
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)

    let maxV = max(r, g, b)
    let minV = min(r, g, b)
    let delta = maxV - minV

    var hue: CGFloat = 0
    if delta != 0 {
        if maxV == r { hue = (g - b) / delta }
        else if maxV == g { hue = 2 + (b - r) / delta }
        else { hue = 4 + (r - g) / delta }
        hue *= 60
        if hue < 0 { hue += 360 }
    }

    let sat = maxV == 0 ? 0 : (delta / maxV)
    return HSV(h: Double(hue), s: Double(sat), v: Double(maxV))
}

}

private struct HSV {
var h: Double   // degrees 0...360
var s: Double   // 0...1
var v: Double   // 0...1

func rotatedHue(_ deg: Double) -> HSV {
    var nh = h + deg
    while nh < 0 { nh += 360 }
    while nh >= 360 { nh -= 360 }
    return HSV(h: nh, s: s, v: v)
}

func toUIColor() -> UIColor {
    UIColor(
        hue: CGFloat(h / 360.0),
        saturation: CGFloat(s),
        brightness: CGFloat(v),
        alpha: 1.0
    )
}

}
