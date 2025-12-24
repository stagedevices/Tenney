//
//  LatticeView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import SwiftUI
import UIKit


extension LatticeCamera {
    mutating func center(in size: CGSize, scale: CGFloat? = nil) {
        translation = CGPoint(x: size.width/2, y: size.height/2)
        if let s = scale { self.scale = max(12, min(240, s)) }
    }
}

struct NodeInfoCard: View {
    let rootHz: Double
    let selectedNode: RatioRef?
    let onAddToBuilder: (RatioRef) -> Void

    /// Use parent’s “info voice” pipeline (pauses selection sustain, swaps voice ID, etc.)
    let onAuditionHz: (Double, Int) -> Void   // (audibleHz, newOctaveOffset)
    let onStopAudition: () -> Void

    @State var octaveOffset: Int = 0

    private var effective: RatioRef? {
        selectedNode.map { $0.withOctaveOffset(octaveOffset) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(primaryLabel())
                    .font(.headline.monospaced())

                if octaveOffset != 0 {
                    Text("(\(octaveOffset > 0 ? "+\(octaveOffset)" : "\(octaveOffset)") oct)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityHidden(true)
                }

                Spacer()

                if let base = selectedNode {
                    OctaveNudger(
                        canDown: canStep(.down, base),
                        canUp: canStep(.up, base),
                        stepDown: { step(.down, base) },
                        stepUp: { step(.up, base) },
                        compact: false
                    )
                }
            }

            if let e = effective {
                let fAud = frequencyHz(rootHz: rootHz, ratio: e, foldToAudible: true)
                let (name, oct, cents) = hejiDisplay(freqHz: fAud)
                Text("\(name)\(oct)  \(String(format: "%+.2f¢", cents))  •  \(Int(round(fAud))) Hz")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Add to Builder") {
                    guard let adjusted = effective else { return }
                    onAddToBuilder(adjusted)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                .buttonStyle(.borderedProminent)
                .disabled(effective == nil)

                Spacer()
            }
        }
        .padding(14)
        .background {
             if #available(iOS 26.0, *) {
                 RoundedRectangle(cornerRadius: 16, style: .continuous)
                     .glassEffect(.regular)
             } else {
                 RoundedRectangle(cornerRadius: 16, style: .continuous)
                     .fill(.ultraThinMaterial)
                     .overlay(
                         RoundedRectangle(cornerRadius: 16, style: .continuous)
                             .stroke(Color.white.opacity(0.12), lineWidth: 1)
                     )
             }
         }
        .onChange(of: selectedNode?.p) { _ in reset() }
        .onChange(of: selectedNode?.q) { _ in reset() }
        .onChange(of: selectedNode?.octave) { _ in reset() }
        .accessibilityElement(children: .contain)
    }

    // MARK: helpers
    private func reset() {
        octaveOffset = 0
        onStopAudition()
    }

    private func primaryLabel() -> String {
        guard let e = effective else { return "—" }
        return ratioDisplayString(e)
    }

    private func canStep(_ dir: OctaveStepDirection, _ base: RatioRef) -> Bool {
        canStepOctave(rootHz: rootHz, ratio: base.withOctaveOffset(octaveOffset), direction: dir)
    }

    private func step(_ dir: OctaveStepDirection, _ base: RatioRef) {
        let delta = (dir == .up ? 1 : -1)
        let nextOffset = octaveOffset + delta
        let next = base.withOctaveOffset(nextOffset)

        // keep your existing can-step logic
        guard canStepOctave(rootHz: rootHz, ratio: next, direction: .up)
           || canStepOctave(rootHz: rootHz, ratio: next, direction: .down)
        else { return }

        octaveOffset = nextOffset

        // audition via parent pipeline (folded)
        let fAud = frequencyHz(rootHz: rootHz, ratio: next, foldToAudible: true)
        onAuditionHz(fAud, nextOffset)
    }
}




struct LatticeView: View {
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

    @AppStorage(SettingsKeys.latticeThemeID) private var themeIDRaw: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.latticeThemeStyle) private var themeStyleRaw: String = ThemeStyleChoice.system.rawValue


    private let layout = LatticeLayout()
        @State private var infoOctaveOffset: Int = 0
    // LatticeView.swift (near other state vars)
    @State private var infoVoiceID: Int? = nil
    @State private var pausedForInfoCoord: LatticeCoord? = nil

    // LatticeView.swift
    @State private var reenableAuditionWorkItem: DispatchWorkItem?

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

    private func tapper(viewRect: CGRect) -> some Gesture {
            DragGesture(minimumDistance: 0)
                .onEnded { v in
                    lastTapPoint = v.location
                    guard let cand = hitTestCandidate(at: v.location, viewRect: viewRect) else {
                        releaseInfoVoice()                                      // stop preview on blur
                        focusedPoint = nil
                        return
                    }
                    // Canonicalize to [1,2) so 5/1 → 5/4, 9/1 → 9/8, etc.
                    let (cn, cd) = canonicalPQ(cand.p, cand.q)
                    let raw = app.rootHz * (Double(cn) / Double(cd))
                    let freq = foldToAudible(raw, minHz: 20, maxHz: 5000)
    
                    focusedPoint = (
                        pos: cand.pos,
                        label: "\(cn)/\(cd)",
                        etCents: RatioMath.centsFromET(freqHz: freq, refHz: app.rootHz),
                        hz: freq,
                        coord: cand.coord,
                        num: cn,
                        den: cd
                    )
    
                    // Only plane nodes are selectable
                    if cand.isPlane, let c = cand.coord {
                                        store.toggleSelection(c)
                                    } else if let g = cand.ghost {
                                        store.toggleOverlay(prime: g.prime, e3: g.e3, e5: g.e5, eP: g.eP)
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
            LatticeTone.shared.release(id: id, releaseSeconds: hard ? 0.0 : 0.05)
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
        if let id = infoVoiceID { LatticeTone.shared.release(id: id, releaseSeconds: 0.0) }
        infoVoiceID = LatticeTone.shared.sustain(freq: hz, amp: 0.22, attackMs: 8)
        infoOctaveOffset = newOffset
    }



    // MARK: - Shift Tile (used inside AxisShiftRibbon)
    private struct ShiftTile: View {
        let prime: Int
        let value: Int
        let color: Color
        let minus: () -> Void
        let plus:  () -> Void
        let reset: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Text("±\(prime)")
                    .font(.caption2)
                    .foregroundStyle(color)
                    .frame(minWidth: 26)

                Button(action: minus) {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())

                Text(verbatim: "\(value)")
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(value == 0 ? .clear : color.opacity(0.22))
                    .clipShape(Capsule())
                    .contentTransition(.numericText())
                    .sensoryFeedback(.selection, trigger: value)

                Button(action: plus) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu {
                Button("Reset ±\(prime) axis", role: .destructive, action: reset)
            }
            .onTapGesture(count: 2, perform: reset) // double-tap quick reset
            .modifier(ShiftChipGlass(color: color, active: value != 0))
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

    // MARK: - Axis Shift Ribbon (v0.2)
    private struct AxisShiftRibbon: View {
        @ObservedObject var store: LatticeStore
        @ObservedObject var app: AppModel

        /// Provide tint from the caller so we don’t couple this to a specific color system.
        let tint: (Int) -> Color

        @State private var expanded = false
        private let allPrimes = [3,5,7,11,13,17,19,23,29,31]

        // Collapsed shows ALL primes up to the current limit (so extended limits don’t disappear)
        private var visiblePrimesCollapsed: [Int] { allPrimes.filter { $0 <= app.primeLimit } }
        private var visiblePrimesExpanded:  [Int] { allPrimes }

        var body: some View {
            GlassCard {
                VStack(spacing: 6) {
                    // Handle / grabber (detent-style)
                    HStack {
                        Spacer()
                        Capsule()
                            .frame(width: 28, height: 4)
                            .foregroundStyle(.secondary.opacity(0.7))
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
                            .gesture(
                                DragGesture(minimumDistance: 5)
                                    .onEnded { value in
                                        if value.translation.height < -8 { withAnimation(.snappy) { expanded = true } }
                                        if value.translation.height >  8 { withAnimation(.snappy) { expanded = false } }
                                    }
                            )
                        Spacer()
                    }

                    // Content (scrolls horizontally)
                    if expanded {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(visiblePrimesExpanded, id: \.self) { p in shiftTile(for: p) }
                                resetAllButton
                            }
                            .padding(.horizontal, 2) // inner balance
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(visiblePrimesCollapsed, id: \.self) { p in shiftTile(for: p) }
                                resetAllButton
                            }
                            .padding(.horizontal, 2) // inner balance
                        }
                    }
                }
            }
        }

        // MARK: Helpers
        @ViewBuilder
        private func shiftTile(for p: Int) -> some View {
            let disabled = p > app.primeLimit
            ShiftTile(
                prime: p,
                value: store.axisShift[p, default: 0],
                color: tint(p),
                minus: {
                    if !disabled { withAnimation(.snappy) { store.shift(prime: p, delta: -1) } }
                },
                plus: {
                    if !disabled { withAnimation(.snappy) { store.shift(prime: p, delta: +1) } }
                },
                reset: {
                    if !disabled { withAnimation(.snappy) { store.resetShift(prime: p) } }
                }
            )
            .opacity(disabled ? 0.45 : 1.0)
            .disabled(disabled)
        }

        @ViewBuilder
        private var resetAllButton: some View {
            if store.axisShift.values.contains(where: { $0 != 0 }) {
                Button("Reset All") { withAnimation(.snappy) { store.resetShift() } }
                    .buttonStyle(.borderedProminent)
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
        let color: Color
        let active: Bool
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular.tint(color),
                                 in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                content
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        Canvas(rendersAsynchronously: true) { ctx, _ in
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


            // Axes
            drawAxes(ctx: &ctx)

            // Overlays for visible higher primes
            for p in store.visiblePrimes.sorted() {
                drawOverlay(prime: p, in: &ctx, viewRect: viewRect)
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
                    ctx.stroke(path, with: .color(.accentColor.opacity(0.55)), lineWidth: 1.5)
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

            // Selection halos on top
            if !store.selected.isEmpty {
                // snapshot the few values we actually need to avoid heavy type-checking
                let shiftSnapshot  = store.axisShift
                let pivotSnapshot  = store.pivot
                let cameraSnapshot = store.camera
                let selectedSnapshot = store.selected

                for coord in selectedSnapshot {
                    // plane position with pivot + 3/5 shifts (no overlayExtras here)
                    let e3 = coord.e3 + pivotSnapshot.e3 + (shiftSnapshot[3] ?? 0)
                    let e5 = coord.e5 + pivotSnapshot.e5 + (shiftSnapshot[5] ?? 0)
                    let pos = layout.position(for: LatticeCoord(e3: e3, e5: e5))

                    let sp  = cameraSnapshot.worldToScreen(pos)
                    let r: CGFloat = 22
                    let rect = CGRect(x: sp.x - r, y: sp.y - r, width: 2*r, height: 2*r)
                    ctx.stroke(Circle().path(in: rect), with: .color(.accentColor.opacity(0.9)), lineWidth: 2.0)
                    ctx.stroke(Circle().path(in: rect.insetBy(dx: 2, dy: 2)), with: .color(.white.opacity(0.9)), lineWidth: 1.2)
                }
            }



            // Overlay selection halos (same style)
            if !store.selectedGhosts.isEmpty {
                for g in store.selectedGhosts {
                    let world = layout.position(monzo: [3: g.e3, 5: g.e5, g.p: g.eP])
                    let sp = store.camera.worldToScreen(world)
                    let r: CGFloat = 22
                    let rect = CGRect(x: sp.x - r, y: sp.y - r, width: 2*r, height: 2*r)
                    ctx.stroke(Circle().path(in: rect), with: .color(.accentColor.opacity(0.9)), lineWidth: 2.0)
                    ctx.stroke(Circle().path(in: rect.insetBy(dx: 2, dy: 2)), with: .color(.white.opacity(0.9)), lineWidth: 1.2)
                }
            }
        }
        .id("canvas-\(themeIDRaw)-\(themeStyleRaw)")
        .allowsHitTesting(false)
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
        .onAppear { store.camera.center(in: geo.size, scale: 72) }
    }

    @ViewBuilder
    private func gestureCatcher(in geo: GeometryProxy, viewRect: CGRect) -> some View {
        let pan   = panGesture()
        let pinch = pinchGesture(in: geo)
        let tap   = tapper(viewRect: viewRect)
        let press = longPresser(viewRect: viewRect)
        let brush = brushGesture(in: geo, viewRect: viewRect)

        Color.clear
            .contentShape(Rectangle())
            .simultaneousGesture(pan)
            .simultaneousGesture(pinch)
            .simultaneousGesture(tap)
            .simultaneousGesture(press)
            .simultaneousGesture(brush)
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
            VStack(spacing: 8) {
                if !latticePreviewMode {
                    if store.selectedCount > 0 || store.additionsSinceBaseline > 0 {
                        SelectionTray(store: store, app: app)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    AxisShiftRibbon(
                        store: store,
                        app: app,
                        tint: { activeTheme.primeTint($0) }   // keeps ribbon colors consistent with your theme
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .allowsHitTesting(true)
    }

    @ToolbarContentBuilder
    private var clearToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Clear") { store.clearSelection() }
        }
    }

    @ViewBuilder
    private var tenneyOverlay: some View {
                if !latticePreviewMode && !latticePreviewHideDistance,
                   store.tenneyDistanceMode != .off,
                   let pair = store.selectedPair() {   // if selectedPair is a var, remove the ()
                    let (a, b) = pair
                     TenneyDistanceOverlay(
                        a: a, b: b,
                         mode: store.tenneyDistanceMode,
                        layout: layout,
                         theme: activeTheme
                     )
                     .allowsHitTesting(false)
                 }
    }

    private func applySettingsChanged(_ note: Notification) {
        if let v = note.userInfo?[SettingsKeys.latticeThemeID] as? String { themeIDRaw = v }
        if let v = note.userInfo?[SettingsKeys.latticeThemeStyle] as? String { themeStyleRaw = v }
    }


    var body: some View {
        GeometryReader { geo in
            latticeStack(in: geo)
        }
        .navigationTitle("Lattice")
        .toolbar { clearToolbar }
        .background(Color.clear)
        .onPreferenceChange(SelectionTrayHeightKey.self) { trayHeight = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .settingsChanged)) { applySettingsChanged($0) }
        .overlay { tenneyOverlay }
        .onChange(of: store.selected) { newValue in
            if let fp = focusedPoint, let c = fp.coord, !newValue.contains(c) {
                releaseInfoVoice()
                withAnimation(.easeOut(duration: 0.2)) { focusedPoint = nil }
            }
            if newValue.isEmpty { releaseInfoVoice() }
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

        // theme ONLY the node fill (3- vs 5-limit); everything else stays as before
        let baseColor: Color = activeTheme.nodeColor(e3: node.coord.e3, e5: node.coord.e5)
        let alpha: Double = min(1.0, 0.35 + 2.0 / sqrt(Double(node.tenneyHeight)))
        ctx.fill(Ellipse().path(in: CGRect(x: sp.x - sz/2, y: sp.y - sz/2, width: sz, height: sz)),
                 with: .color(baseColor.opacity(alpha)))

        // Label opacity uses labelDensity
        let z = store.camera.scale
        let z0: CGFloat = 36
        let z1: CGFloat = 96
        let zoomT = max(0, min(1, (z - z0) / (z1 - z0)))
        let complexityT = CGFloat(min(1.0, (1.0 + labelDensity) / sqrt(Double(node.tenneyHeight))))
        let labelOpacity = Double(zoomT * complexityT)


        if labelOpacity > 0.02 {
            let e3 = node.coord.e3 + (store.axisShift[3] ?? 0) + store.pivot.e3
            let e5 = node.coord.e5 + (store.axisShift[5] ?? 0) + store.pivot.e5
            let num = (e3 >= 0 ? Int(pow(3.0, Double(e3))) : 1) * (e5 >= 0 ? Int(pow(5.0, Double(e5))) : 1)
            let den = (e3 <  0 ? Int(pow(3.0, Double(-e3))) : 1) * (e5 <  0 ? Int(pow(5.0, Double(-e5))) : 1)
            let (cn, cd) = canonicalPQ(num, den)
            let label = "\(cn)/\(cd)"

            let text = Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            // keep label color behavior exactly as before (primary with opacity)
                .foregroundStyle(Color.primary.opacity(labelOpacity))
            ctx.draw(text, at: CGPoint(x: sp.x, y: sp.y - sz - 6), anchor: .bottom)
        }
    }


    private func drawOverlay(prime p: Int, in ctx: inout GraphicsContext, viewRect: CGRect) {
        // Skip period (2) and plane primes (3,5)
        guard p != 2 && p != 3 && p != 5 else { return }

        // Use the same visual treatment as plane nodes
        let baseTint: Color = activeTheme.primeTint(p)

        // Base exponents from pivot + axis shift on the plane
        let e3 = store.pivot.e3 + (store.axisShift[3] ?? 0)
        let e5 = store.pivot.e5 + (store.axisShift[5] ?? 0)
        let s  = store.axisShift[p] ?? 0

        // Span tuned by zoom so taps don’t stall
        let epSpan = max(6, min(12, Int(store.camera.scale / 8)))

        // Build positions along this prime axis (no duplicate dict keys)
        for ep in (-epSpan...epSpan) where ep != 0 {
            let eP = ep + s

            // World position for monzo {3:e3, 5:e5, p:eP}
            let monzo: [Int:Int] = [3: e3, 5: e5, p: eP]
            let world = layout.position(monzo: monzo)
            let sp    = store.camera.worldToScreen(world)

            // Tenney-ish size (simple proxy)
            let num = (e3 >= 0 ? Int(pow(3.0, Double(e3))) : 1)
                    * (e5 >= 0 ? Int(pow(5.0, Double(e5))) : 1)
                    * (eP >= 0 ? Int(pow(Double(p), Double(eP))) : 1)
            let den = (e3 <  0 ? Int(pow(3.0, Double(-e3))) : 1)
                    * (e5 <  0 ? Int(pow(5.0, Double(-e5))) : 1)
                    * (eP <  0 ? Int(pow(Double(p), Double(-eP))) : 1)
            let tenney = max(num, den)

            // Match plane size, but draw a solid rim so the hue reads clearly
                        let base = nodeBaseSize()
                        let lift = CGFloat(18.0 * (1.0 / sqrt(Double(tenney))))
                        let sz = max(8, base + lift)
                        let r  = sz / 2
                        let fillAlpha: Double = min(1.0, 0.30 + 1.6 / sqrt(Double(tenney)))
                        let oval = CGRect(x: sp.x - r, y: sp.y - r, width: 2*r, height: 2*r)
                        // soft colored fill
                        ctx.fill(Ellipse().path(in: oval), with: .color(baseTint.opacity(fillAlpha)))
                        // crisp colored rim (full opacity)
                        ctx.stroke(Ellipse().path(in: oval.insetBy(dx: 0.6, dy: 0.6)),
                                   with: .color(baseTint),
                                   lineWidth: 1.3)
                        // tiny inner white kiss for contrast (optional, very faint)
                        ctx.stroke(Ellipse().path(in: oval.insetBy(dx: 2.0, dy: 2.0)),
                                   with: .color(Color.white.opacity(0.12)),
                                   lineWidth: 0.8)

            // Label opacity vs zoom & complexity
            let z  = store.camera.scale
            let z0: CGFloat = 44
            let z1: CGFloat = 104
            let zoomT = max(0, min(1, (z - z0) / (z1 - z0)))
            let compT = CGFloat(min(1.0, 1.2 / sqrt(Double(tenney))))
            let op = Double(zoomT * compT) * 0.85

            if op > 0.02 {
                // *** Canonical label for display only (audio stays exact) ***
                let (cp, cq) = canonicalPQ(num, den)
                let t = Text("\(cp)/\(cq)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(op))
                ctx.draw(t, at: CGPoint(x: sp.x, y: sp.y - (sz/2) - 6), anchor: .bottom)            }
        }
    }

        // MARK: - Overlays (UI)
        private var overlayChips: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PrimeConfig.primes.filter { $0 != 2 && $0 != 3 && $0 != 5 }, id: \.self) { p in
                        let on = store.visiblePrimes.contains(p)
                        GlassChip(title: on ? "● \(p)" : "○ \(p)",
                                  active: on,
                                  color: activeTheme.primeTint(p)) {
                            if on { store.visiblePrimes.remove(p) } else { store.visiblePrimes.insert(p) }
                        }
                    }
                }
                .padding(8)
            }
        }
        
    

    @AppStorage("Tenney.SoundOn") private var soundOn: Bool = true
    private func postStep(idx: Int, delta: Int) {
    //    NotificationCenter.default.post(name: Notification.Name.tenneyStepPadOctave,
    //                                    object: nil,
  //                                      userInfo: ["idx": idx, "delta": delta])
    }

    private var infoCard: some View {
        Group {
            if let f = focusedPoint {
                NodeInfoCard(
                    rootHz: app.rootHz,
                    selectedNode: RatioRef(p: f.num, q: f.den, octave: 0),
                    onAddToBuilder: { ref in
                        let payload = ScaleBuilderPayload(
                            rootHz: app.rootHz,
                            primeLimit: app.primeLimit,
                            refs: [ref]
                        )
                        store.beginStaging()
                        app.builderPayload = payload
                    },
                    onAuditionHz: { hz, newOffset in
                        switchInfoTone(toHz: hz, newOffset: newOffset)
                    },
                    onStopAudition: {
                        releaseInfoVoice()
                    }
                )
                .padding(.horizontal, 8)
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
        let a: LatticeCoord
        let b: LatticeCoord
        let mode: TenneyDistanceMode
        let layout: LatticeLayout
        let theme: LatticeTheme
        

        var body: some View {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                let pa = layout.position(for: a)
                let pb = layout.position(for: b)
                let A = CGPoint(x: center.x + pa.x, y: center.y + pa.y)
                let B = CGPoint(x: center.x + pb.x, y: center.y + pb.y)
                let mid = CGPoint(x: (A.x + B.x) * 0.5, y: (A.y + B.y) * 0.5)

                let d3 = b.e3 - a.e3
                let d5 = b.e5 - a.e5
                let delta: [Int:Int] = [3: d3, 5: d5]
                let H = tenneyHeightDelta(delta)

                ZStack {
                    // Total (always when not .off)
                    GlassChip(text: String(format: "H %.2f", H))
                        .position(mid)

                    // Breakdown chips
                    if mode == .breakdown {
                        if d3 != 0 {
                            GlassChip(text: deltaLabel(3, d3), tint: theme.primeTint(3))
                                .position(x: mid.x - 28, y: mid.y - 18)
                        }
                        if d5 != 0 {
                            GlassChip(text: deltaLabel(5, d5), tint: theme.primeTint(5))
                                .position(x: mid.x + 28, y: mid.y + 18)
                        }
                    }
                }
            }
        }
    }

    
    private func hitTestCandidate(
            at point: CGPoint,
            viewRect: CGRect
        ) -> (pos: CGPoint, label: String, isPlane: Bool, coord: LatticeCoord?, p: Int, q: Int, ghost: (prime:Int, e3:Int, e5:Int, eP:Int)?)? {
            // Screen-space radii so overlays can't steal taps from plane nodes.
            let screenRadiusPlane:   CGFloat = 18
            let screenRadiusOverlay: CGFloat = 12
    
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
                        let e3 = c.e3 + (store.axisShift[3] ?? 0)
                        let e5 = c.e5 + (store.axisShift[5] ?? 0)
                        let p  = (e3 >= 0 ? Int(pow(3.0, Double(e3))) : 1) * (e5 >= 0 ? Int(pow(5.0, Double(e5))) : 1)
                        let q  = (e3 <  0 ? Int(pow(3.0, Double(-e3))) : 1) * (e5 <  0 ? Int(pow(5.0, Double(-e5))) : 1)
                        if bestPlane == nil || d < bestPlane!.d { bestPlane = (d, sp, c, p, q) }
                    }
                }
            }
            if let b = bestPlane {
                let (cp, cq) = canonicalPQ(b.p, b.q)
                return (b.pos, "\(cp)/\(cq)", true, b.coord, b.p, b.q, nil)
            }
    
            // 2) Otherwise, allow overlay hits (screen distance)
            var bestOverlay: (d2: CGFloat, pos: CGPoint, p: Int, q: Int, prime: Int, e3: Int, e5: Int, eP: Int)?
            let baseE3 = store.pivot.e3 + (store.axisShift[3] ?? 0)
            let baseE5 = store.pivot.e5 + (store.axisShift[5] ?? 0)
            let epSpan = max(6, min(12, Int(store.camera.scale / 8)))
            for prime in store.visiblePrimes where prime != 2 && prime != 3 && prime != 5 {
                let s = store.axisShift[prime] ?? 0
                for ep in (-epSpan...epSpan) where ep != 0 {
                    var monzo: [Int:Int] = [3: baseE3, 5: baseE5]
                    monzo[prime] = ep + s
                    let wp = layout.position(monzo: monzo)
                    let sp = store.camera.worldToScreen(wp)
                    let d  = hypot(sp.x - point.x, sp.y - point.y)
                    // after computing d
                    let d2 = d * d
                    if d <= screenRadiusOverlay {
                        let eP  = ep + s
                        let num = (baseE3 >= 0 ? Int(pow(3.0, Double(baseE3))) : 1)
                                * (baseE5 >= 0 ? Int(pow(5.0, Double(baseE5))) : 1)
                                * (eP     >= 0 ? Int(pow(Double(prime), Double(eP))) : 1)
                        let den = (baseE3 <  0 ? Int(pow(3.0, Double(-baseE3))) : 1)
                                * (baseE5 <  0 ? Int(pow(5.0, Double(-baseE5))) : 1)
                                * (eP     <  0 ? Int(pow(Double(prime), Double(-eP))) : 1)

                        if bestOverlay == nil || d2 < bestOverlay!.d2 {
                            bestOverlay = (d2, sp, num, den, prime, baseE3, baseE5, eP)
                        }
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
