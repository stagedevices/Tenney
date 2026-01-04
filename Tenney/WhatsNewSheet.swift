//
//  WhatsNewSheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

struct WhatsNewItem: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let summary: String
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
    static var majorMinor: String {
        let parts = version.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : version
    }
}

// MARK: v0.3 content
enum WhatsNewContent {
    // “Big three” are rendered as custom cards below. Keep the rest here.
    static let v0_3Items: [WhatsNewItem] = [
        .init(
            symbol: "textformat.size",
            title: "Label Density Controls",
            summary: "Tune label density from Off → Max for clean screenshots or full-detail editing."
        ),
        .init(
            symbol: "gearshape.2",
            title: "Settings, Tightened",
            summary: "A tighter, clearer Settings layout with better visual hierarchy."
        ),
        .init(
            symbol: "paintpalette",
            title: "Theme Polish",
            summary: "More consistent theming across screens, with a cleaner dark/light presentation."
        ),
        .init(
            symbol: "sparkles",
            title: "Motion & Feel",
            summary: "Smoother transitions and a more responsive, tactile feel across the app."
        ),
        .init(
            symbol: "checkmark.shield.fill",
            title: "Stability & Performance",
            summary: "Crash fixes, fewer edge-case glitches, and faster interactions."
        )
    ]
}

// MARK: - Sheet
struct WhatsNewSheet: View {
    let app: AppModel
    let items: [WhatsNewItem]
    let primaryAction: () -> Void


    // v0.3 deep-link actions (shown only if provided)
    var onOpenExport: (() -> Void)? = nil
    var onSeeInLattice: (() -> Void)? = nil
    var onRateApp: (() -> Void)? = nil

    // Back-compat shims (safe to delete once call sites are migrated)
    var onSeeIntervalInLattice: (() -> Void)? = nil
    var onOpenProAudio: (() -> Void)? = nil

    private var seeInLatticeAction: (() -> Void)? { onSeeInLattice ?? onSeeIntervalInLattice }

    // Auto values from Info.plist
    private let versionString = AppInfo.version
    private let buildString   = AppInfo.build

    // URLs built from version
    private var releaseNotesURL: URL? {
        URL(string: "https://cdn.jsdelivr.net/gh/stagedevices/Tenney/changelog.md")
    }
    private var supportURL: URL? {
        URL(string: "https://www.stagedevices.com/support")
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @Namespace private var heroNS
    @State private var animateHero = false
    
    private struct RealLatticePreview: View {
        let app: AppModel
        @StateObject private var store = LatticeStore()

        let gridMode: LatticeGridMode?
        let connectionMode: LatticeConnectionMode?
        let seedSelection: [LatticeCoord]

        init(
            app: AppModel,
            gridMode: LatticeGridMode? = nil,
            connectionMode: LatticeConnectionMode? = nil,
            seedSelection: [LatticeCoord] = []
        ) {
            self.app = app
            self.gridMode = gridMode
            self.connectionMode = connectionMode
            self.seedSelection = seedSelection
        }

        var body: some View {
            LatticeView(previewGridMode: gridMode, previewConnectionMode: connectionMode)
                .environmentObject(app)
                .environmentObject(store)
                .environment(\.latticePreviewMode, true)
                .environment(\.latticePreviewHideChips, true)
                .environment(\.latticePreviewHideDistance, true)
                .allowsHitTesting(false)
                .onAppear {
                    // deterministic “real nodes” for node-restyle previews
                    if !seedSelection.isEmpty {
                        store.clearSelection()
                        store.setPivot(.init(e3: 0, e5: 0))
                        for c in seedSelection { store.toggleSelection(c) }
                    }
                }
        }
    }
    
    @available(iOS 26.0, *)
    private var heroPalette: HeroPalette {
        // ✅ If you already have explicit theme colors, prefer them:
        // return .init(primary: app.theme.primary, secondary: app.theme.secondary, accent: app.theme.accent)

        // 🔁 Generic fallback: drive from SwiftUI accentColor (and derive siblings)
        .init(primary: .accentColor, secondary: nil, accent: nil)
    }


    var body: some View {
        ZStack(alignment: .top) {
                if #available(iOS 26.0, *) {
                    SheetTopChromaWash(palette: heroPalette)
                        .frame(height: 260)                 // “colors the top of the sheet”
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroHeader
                        bigThree
                        featureList
                        footerActions
                    }
                    .padding(16)
                }
            }
    }
    
    @available(iOS 26.0, *)
    private struct HeroPalette {
        let primary: Color
        let secondary: Color?
        let accent: Color?
    }

    @available(iOS 26.0, *)
    private static func meshColors(from palette: HeroPalette, scheme: ColorScheme) -> [Color] {
        // Convert base colors to UIColors for HSB math
        let base = UIColor(palette.primary)
        let sec  = palette.secondary.map { UIColor($0) } ?? base
        let acc  = palette.accent.map { UIColor($0) } ?? base

        func hot(_ u: UIColor, hueShift: CGFloat, satBoost: CGFloat, briShift: CGFloat, alpha: CGFloat) -> Color {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            u.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

            // High-chroma, iOS 26-ish: boost saturation, keep brightness controlled in light mode
            let nh = (h + hueShift).truncatingRemainder(dividingBy: 1.0)
            let ns = min(1.0, max(0.0, s * satBoost))
            let nbBase = b + briShift
            let nb = scheme == .dark ? min(1.0, max(0.0, nbBase)) : min(0.92, max(0.0, nbBase))

            return Color(uiColor: UIColor(hue: nh, saturation: ns, brightness: nb, alpha: alpha))
        }

        // Build a 4×4 that “breathes” around the theme hue:
        // primary = anchor, secondary = counter-hue, accent = highlight
        let c0 = hot(base, hueShift:  0.00, satBoost: 1.25, briShift:  0.08, alpha: 0.95)
        let c1 = hot(base, hueShift:  0.04, satBoost: 1.30, briShift:  0.06, alpha: 0.92)
        let c2 = hot(acc,  hueShift: -0.03, satBoost: 1.35, briShift:  0.04, alpha: 0.88)
        let c3 = hot(sec,  hueShift:  0.08, satBoost: 1.20, briShift:  0.05, alpha: 0.90)

        let c4 = hot(sec,  hueShift: -0.06, satBoost: 1.25, briShift:  0.03, alpha: 0.86)
        let c5 = hot(base, hueShift:  0.02, satBoost: 1.35, briShift:  0.02, alpha: 0.84)
        let c6 = hot(acc,  hueShift:  0.06, satBoost: 1.40, briShift:  0.01, alpha: 0.86)
        let c7 = hot(sec,  hueShift:  0.00, satBoost: 1.25, briShift:  0.02, alpha: 0.82)

        let c8 = hot(acc,  hueShift: -0.08, satBoost: 1.30, briShift:  0.00, alpha: 0.80)
        let c9 = hot(sec,  hueShift:  0.05, satBoost: 1.25, briShift: -0.01, alpha: 0.86)
        let cA = hot(base, hueShift: -0.02, satBoost: 1.35, briShift: -0.01, alpha: 0.84)
        let cB = hot(acc,  hueShift:  0.03, satBoost: 1.28, briShift:  0.00, alpha: 0.84)

        let cC = hot(base, hueShift:  0.07, satBoost: 1.18, briShift: -0.02, alpha: 0.78)
        let cD = hot(acc,  hueShift: -0.04, satBoost: 1.22, briShift: -0.02, alpha: 0.74)
        let cE = hot(sec,  hueShift:  0.02, satBoost: 1.18, briShift: -0.01, alpha: 0.78)
        let cF = hot(base, hueShift:  0.00, satBoost: 1.15, briShift: -0.03, alpha: 0.76)

        return [c0,c1,c2,c3, c4,c5,c6,c7, c8,c9,cA,cB, cC,cD,cE,cF]
    }

    
    @available(iOS 26.0, *)
    private struct SheetTopChromaWash: View {
        let palette: HeroPalette
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var phase: Float = 0

        private var drift: Float { reduceMotion ? 0 : 0.045 }

        private var points: [SIMD2<Float>] {
            // 4×4: anchors on edges, lively interior
            [
                .init(0.00, 0.00), .init(0.33, 0.00), .init(0.66, 0.00), .init(1.00, 0.00),
                .init(0.00, 0.33), .init(0.33 + sin(phase)*drift, 0.33), .init(0.66, 0.33 + cos(phase)*drift), .init(1.00, 0.33),
                .init(0.00, 0.66), .init(0.33, 0.66 + cos(phase)*drift), .init(0.66 + sin(phase)*drift, 0.66), .init(1.00, 0.66),
                .init(0.00, 1.00), .init(0.33, 1.00), .init(0.66, 1.00), .init(1.00, 1.00),
            ]
        }

        var body: some View {
            ZStack {
                MeshGradient(
                    width: 4, height: 4,
                    points: points,
                    colors: WhatsNewSheet.meshColors(from: palette, scheme: scheme)
                )
                .saturation(1.25)
                .blur(radius: 10)

                // “specular” lift (iOS-ish sheen, no noise)
                LinearGradient(
                  colors: [
                    .white.opacity(scheme == .dark ? 0.20 : 0.12),
                    .clear
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
                .blendMode(.screen)

            }
            .task {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            }
            .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.00),
                            .init(color: .white, location: 0.66), // keep top ~2/3 fully on
                            .init(color: .clear, location: 1.00)  // fade out bottom third
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }


    // MARK: Header (hero gradient + matched symbol)
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .bold))
                        .imageScale(.large)
                        .foregroundStyle(.white)
                        .matchedGeometryEffect(id: "spark", in: heroNS)
                        .symbolEffect(.bounce, value: animateHero) // consider “once” not repeating

                    VStack(alignment: .leading, spacing: 2) {
                        Text("What’s New")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Tenney \(versionString) (build \(buildString))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.90))
                    }

                    Spacer()

                    if #available(iOS 26.0, *) {
                        Text("Designed for iOS 26")
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 6)
                .onAppear { animateHero = true }
            }
    }

    // MARK: Big Three (v0.3)
    private var bigThree: some View {
        VStack(spacing: 12) {
            // 1) Export scala + more
            bigCard(
                symbol: "square.and.arrow.up",
                title: "Export & Share Scales",
                blurb: "Export saved scales and send them anywhere—Scala and other formats, ready for other devices and apps.",
                preview: AnyView(ExportPreview()),
                primaryCTA: onOpenExport == nil ? nil : ("Export Saved Scales", {
                    onOpenExport?()
                })
            )

            // 2) Lattice restyle
            bigCard(
                symbol: "circle.grid.2x2.fill",
                title: "Node Restyle",
                blurb: "Nodes got a visual upgrade, plus path connection modes (Chain, Loop, Map) and better selection that follows your Attack/Release timing.",
                preview: AnyView(
                    HStack(spacing: 10) {
                        RealLatticePreview(app: app, gridMode: .triMesh)
                    }
                ),
                primaryCTA: seeInLatticeAction == nil ? nil : ("See in Lattice", {
                    seeInLatticeAction?()
                })
            )

            // 3) Grid + connection modes
            bigCard(
                symbol: "hexagon.fill",
                title: "Hex & Triangle Grids",
                blurb: "New hex and triangle grids reveal the lattice structure more clearly at any zoom.",
                preview: AnyView(
                    RealLatticePreview(
                        app: app,
                        gridMode: .outlines,
                        connectionMode: .chain,
                        seedSelection: [
                            .init(e3: 0, e5: 0),
                            .init(e3: 1, e5: 0),
                            .init(e3: 0, e5: 1)
                        ]
                    )
                ),
                primaryCTA: nil
            )
        }
    }

    // MARK: Remaining list (simple glass cards)
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol)
                        .imageScale(.large)
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
                .modifier(WhatsNewGlass(corner: 16))
            }
        }
    }

    // MARK: Footer
    private var footerActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let u = releaseNotesURL {
                    Link(destination: u) {
                        Label("Release notes", systemImage: "list.bullet.rectangle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                if let u = supportURL {
                    Link(destination: u) {
                        Label("Support", systemImage: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    requestRating()
                    onRateApp?()
                } label: {
                    Label("Rate", systemImage: "star.bubble")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }

            Button {
                primaryAction()
            } label: {
                Text("OK, got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.top, 8)
    }

    // MARK: Helpers
    private func bigCard(
        symbol: String,
        title: String,
        blurb: String,
        preview: AnyView,
        primaryCTA: (title: String, action: () -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .imageScale(.large)
                        .foregroundStyle(.primary)
                        .symbolEffect(.pulse, options: .repeating, value: animateHero)

                    Text(title).font(.headline)
                }

                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let cta = primaryCTA {
                    Button(cta.title, action: cta.action)
                        .buttonStyle(.borderedProminent)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 10)

            preview
                .frame(width: 148, height: 96)
        }
        .padding(12)
        .modifier(WhatsNewGlass(corner: 16))
    }

    private func requestRating() {
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            SKStoreReviewController.requestReview(in: scene)
        }
        #else
        SKStoreReviewController.requestReview()
        #endif
    }
}

// MARK: - iOS 26 glass, fallback earlier
private struct WhatsNewGlass: ViewModifier {
    let corner: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

// MARK: - Hero gradient (red→orange, subtle motion)
@available(iOS 18.0, *)
private struct HeroGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Float = 0

    // 3×3 mesh: corners anchored, center drifts slightly
    private var pts: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : 0.035
        return [
            .init(0.00, 0.00), .init(0.50, 0.00), .init(1.00, 0.00),
            .init(0.00, 0.50), .init(0.50 + sin(phase)*d, 0.50 + cos(phase)*d), .init(1.00, 0.50),
            .init(0.00, 1.00), .init(0.50, 1.00), .init(1.00, 1.00),
        ]
    }

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: pts,
            colors: [
                .red.opacity(0.55),    .orange.opacity(0.40), .red.opacity(0.30),
                .orange.opacity(0.35), .pink.opacity(0.25),   .orange.opacity(0.30),
                .red.opacity(0.35),    .orange.opacity(0.28), .red.opacity(0.45),
            ]
        )
        .overlay { // gentle vignette to keep edges quiet
            LinearGradient(colors: [.black.opacity(0.18), .clear],
                           startPoint: .top, endPoint: .bottom)
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: true)) { phase = .pi * 2 }
        }
    }
}


// MARK: - Mini previews (v0.3)

// 1) Export preview (scale card + share arrow)
private struct ExportPreview: View {
    @State private var bounce = false

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Saved Scale")
                        .font(.caption2.weight(.semibold))
                    Text("Scala • .scl")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .symbolEffect(.bounce, options: .repeating.speed(0.65), value: bounce)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { bounce = true }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// 2) Node restyle preview (one–two nodes, close up + selection attack/release feel)
private struct NodeRestylePreview: View {
@State private var t: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { _ in
            GeometryReader { _ in
                Canvas { ctx, size in
                    let bg = Color(uiColor: .systemBackground)

                    let a = CGPoint(x: size.width * 0.42, y: size.height * 0.58)
                    let b = CGPoint(x: size.width * 0.72, y: size.height * 0.40)

                    let r: CGFloat = 16
                    let innerR: CGFloat = 13

                    // Connection modes mini-motifs:
                    // Chain: straight link
                    // Loop: orbit ring
                    // Map: a dashed branch

                    // Chain
                    var chain = Path()
                    chain.move(to: a)
                    chain.addLine(to: b)
                    ctx.stroke(chain, with: .color(.primary.opacity(0.70)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    // Map (branch)
                    let c = CGPoint(x: size.width * 0.80, y: size.height * 0.72)
                    var map = Path()
                    map.move(to: a)
                    map.addLine(to: c)
                    ctx.stroke(map, with: .color(.secondary.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))

                    // Loop (orbit)
                    let loopR = r + 9
                    let loopRect = CGRect(x: a.x - loopR, y: a.y - loopR, width: loopR * 2, height: loopR * 2)
                    ctx.stroke(Path(ellipseIn: loopRect), with: .color(.secondary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 2))

                    // Nodes (close-up)
                    ctx.fill(Path(ellipseIn: CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2)),
                             with: .color(.primary))
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)),
                             with: .color(.primary.opacity(0.92)))

                    // Inner cut for “upgraded” node look
                    ctx.fill(Path(ellipseIn: CGRect(x: a.x - innerR, y: a.y - innerR, width: innerR * 2, height: innerR * 2)),
                             with: .color(bg))
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - innerR, y: b.y - innerR, width: innerR * 2, height: innerR * 2)),
                             with: .color(bg))

                    // Selection halo (approx attack/release envelope)
                    let s = (sin(t) * 0.5 + 0.5) // 0..1
                    let attack = min(1, s * 1.8)
                    let release = pow(max(0, 1 - s), 1.7)
                    let haloAlpha = 0.55 * attack + 0.20 * release
                    let haloR = r + 6 + 10 * attack

                    let haloRect = CGRect(x: a.x - haloR, y: a.y - haloR, width: haloR * 2, height: haloR * 2)
                    ctx.stroke(Path(ellipseIn: haloRect), with: .color(.primary.opacity(haloAlpha)),
                               style: StrokeStyle(lineWidth: 3))

                    // Tiny label chip (implies selection polish)
                    let chip = CGRect(x: a.x - 22, y: a.y + r + 6, width: 44, height: 18)
                    ctx.fill(RoundedRectangle(cornerRadius: 6).path(in: chip),
                             with: .color(Color.secondary.opacity(0.15)))
                    ctx.draw(Text("SEL").font(.system(size: 10, weight: .semibold)),
                             at: CGPoint(x: chip.midX, y: chip.midY))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                t = 2 * .pi
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}



// 3) Lattice grid preview (triangle/hex lattice, not square)
private struct LatticeGridPreview: View {
    @State private var phase = false

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let inset: CGFloat = 10
                let left = inset
                let right = size.width - inset
                let top = inset
                let bottom = size.height - inset

                // Triangle lattice (three families of parallel lines)
                let step: CGFloat = phase ? 16 : 20
                let a: CGFloat = step
                let h: CGFloat = step * 0.8660254 // sin(60°)

                var tri = Path()

                // Horizontal-ish (actually horizontal)
                var y = top
                while y <= bottom {
                    tri.move(to: CGPoint(x: left, y: y))
                    tri.addLine(to: CGPoint(x: right, y: y))
                    y += h
                }

                // +60° lines
                var x0 = left - step * 4
                while x0 <= right + step * 4 {
                    tri.move(to: CGPoint(x: x0, y: bottom))
                    tri.addLine(to: CGPoint(x: x0 + (bottom - top) / 0.5773503, y: top)) // tan(30)=0.577...
                    x0 += a
                }

                // -60° lines
                var x1 = left - step * 4
                while x1 <= right + step * 4 {
                    tri.move(to: CGPoint(x: x1, y: top))
                    tri.addLine(to: CGPoint(x: x1 + (bottom - top) / 0.5773503, y: bottom))
                    x1 += a
                }

                ctx.stroke(tri, with: .color(.secondary.opacity(0.22)), lineWidth: 1)

                // Hex overlay hint when phase toggles (a couple cells)
                if phase {
                    let centers: [CGPoint] = [
                        CGPoint(x: size.width * 0.40, y: size.height * 0.42),
                        CGPoint(x: size.width * 0.62, y: size.height * 0.62)
                    ]
                    let R = step * 0.65
                    for c in centers {
                        var hex = Path()
                        for i in 0..<6 {
                            let ang = CGFloat(i) * (.pi / 3)
                            let p = CGPoint(x: c.x + cos(ang) * R, y: c.y + sin(ang) * R)
                            if i == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
                        }
                        hex.closeSubpath()
                        ctx.stroke(hex, with: .color(.primary.opacity(0.25)), style: .init(lineWidth: 2, lineJoin: .round))
                    }
                }

                // A couple nodes to “ground” it as the lattice
                let n1 = CGPoint(x: size.width * 0.34, y: size.height * 0.70)
                let n2 = CGPoint(x: size.width * 0.74, y: size.height * 0.36)
                let r: CGFloat = 7
                ctx.fill(Path(ellipseIn: CGRect(x: n1.x - r, y: n1.y - r, width: r*2, height: r*2)), with: .color(.primary))
                ctx.fill(Path(ellipseIn: CGRect(x: n2.x - r, y: n2.y - r, width: r*2, height: r*2)), with: .color(.primary))

                var link = Path()
                link.move(to: n1)
                link.addLine(to: n2)
                ctx.stroke(link, with: .color(.primary.opacity(0.55)), style: .init(lineWidth: 2, lineCap: .round))
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { phase.toggle() } }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
