//
//  WhatsNewSheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI
import StoreKit
import UIKit

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
        URL(string: "https://www.stagedevices.com/whats-new/\(AppInfo.majorMinor)")
    }
    private var supportURL: URL? {
        URL(string: "https://www.stagedevices.com/support")
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @Namespace private var heroNS
    @State private var animateHero = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroHeader
                bigThree
                featureList
                footerActions
            }
            .padding(16)
        }
        .background(
            (scheme == .dark ? Color.black : Color.white)
                .opacity(0.001)
                .ignoresSafeArea()
        )
    }

    // MARK: Header (hero gradient + matched symbol)
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                // Red→Orange animated gradient blobs (iOS 26)
                if #available(iOS 26.0, *) {
                    HeroGradient()
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .white,              location: 0.00),
                                    .init(color: .white,              location: 0.65),
                                    .init(color: .white.opacity(0.6), location: 0.85),
                                    .init(color: .clear,              location: 1.00),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .padding(.bottom, -48)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .bold))
                        .imageScale(.large)
                        .foregroundStyle(.white)
                        .matchedGeometryEffect(id: "spark", in: heroNS)
                        .symbolEffect(.bounce, options: .repeating.speed(0.5), value: animateHero)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("What’s New")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Tenney \(versionString) (build \(buildString))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
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
                .padding(14)
            }
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
                title: "Lattice Restyle",
                blurb: "New node styling, cleaner theming, and a redesigned motion/feel across the lattice.",
                preview: AnyView(LatticeRestylePreview()),
                primaryCTA: seeInLatticeAction == nil ? nil : ("See in Lattice", {
                    seeInLatticeAction?()
                })
            )

            // 3) Grid + connection modes
            bigCard(
                symbol: "square.grid.3x3.fill",
                title: "Grids & Connections",
                blurb: "New grid styles and connection modes for clearer structure—especially at higher node counts.",
                preview: AnyView(GridConnectionsPreview()),
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
                    Label("Rate Tenney", systemImage: "star.bubble")
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
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            SKStoreReviewController.requestReview(in: scene)
        }
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
@available(iOS 26.0, *)
private struct HeroGradient: View {
    @State private var t: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                ctx.blendMode = .plusLighter

                let red = Color(uiColor: .systemRed)
                let org = Color(uiColor: .systemOrange)
                let ylw = Color(uiColor: .systemYellow)

                let w = size.width
                let h = size.height * 1.35
                let rBase = min(w, h) * 0.52

                let c1 = CGPoint(x: w*0.25 + cos(t*0.60+0.00)*w*0.08, y: h*0.35 + sin(t*0.70+0.30)*h*0.06)
                let c2 = CGPoint(x: w*0.75 + cos(t*0.55+1.70)*w*0.09, y: h*0.32 + sin(t*0.60+0.90)*h*0.07)
                let c3 = CGPoint(x: w*0.52 + cos(t*0.45+2.40)*w*0.07, y: h*0.78 + sin(t*1.00+1.20)*h*0.05)
                let c4 = CGPoint(x: w*0.10 + cos(t*0.80+0.50)*w*0.10, y: h*0.62 + sin(t*0.85+0.20)*h*0.05)
                let c5 = CGPoint(x: w*0.92 + cos(t*0.75+2.10)*w*0.06, y: h*0.58 + sin(t*0.95+1.50)*h*0.05)

                let r1 = rBase * (0.95 + 0.06 * sin(t*0.80))
                let r2 = rBase * (0.85 + 0.06 * sin(t*0.90+1.10))
                let r3 = rBase * (0.72 + 0.08 * sin(t*1.10+2.00))
                let r4 = rBase * (0.60 + 0.08 * sin(t*0.70+0.60))
                let r5 = rBase * (0.55 + 0.07 * sin(t*0.65+1.30))

                let g1 = Gradient(colors: [red.opacity(0.80), red.opacity(0.35), .clear])
                let g2 = Gradient(colors: [org.opacity(0.75), org.opacity(0.35), .clear])
                let g3 = Gradient(colors: [red.opacity(0.55), org.opacity(0.30), .clear])
                let g4 = Gradient(colors: [ylw.opacity(0.45), org.opacity(0.28), .clear])
                let g5 = Gradient(colors: [red.opacity(0.45), ylw.opacity(0.25), .clear])

                ctx.fill(Path(ellipseIn: .init(x: c1.x - r1, y: c1.y - r1, width: r1*2, height: r1*2)),
                         with: .radialGradient(g1, center: c1, startRadius: 0, endRadius: r1))
                ctx.fill(Path(ellipseIn: .init(x: c2.x - r2, y: c2.y - r2, width: r2*2, height: r2*2)),
                         with: .radialGradient(g2, center: c2, startRadius: 0, endRadius: r2))
                ctx.fill(Path(ellipseIn: .init(x: c3.x - r3, y: c3.y - r3, width: r3*2, height: r3*2)),
                         with: .radialGradient(g3, center: c3, startRadius: 0, endRadius: r3))
                ctx.fill(Path(ellipseIn: .init(x: c4.x - r4, y: c4.y - r4, width: r4*2, height: r4*2)),
                         with: .radialGradient(g4, center: c4, startRadius: 0, endRadius: r4))
                ctx.fill(Path(ellipseIn: .init(x: c5.x - r5, y: c5.y - r5, width: r5*2, height: r5*2)),
                         with: .radialGradient(g5, center: c5, startRadius: 0, endRadius: r5))

                // Pointillist grain (denser, larger)
                let dots = 1200
                for i in 0..<dots {
                    let fx = sin((CGFloat(i)*12.9898) + t*0.35)
                    let fy = sin((CGFloat(i)*78.233)  + t*0.33 + 1.1)
                    let px = (fx*0.5+0.5) * w
                    let py = (fy*0.5+0.5) * h
                    let s  = 1.0 + 1.2 * abs(sin(CGFloat(i)*3.1 + t))
                    let a  = 0.06 + 0.06 * abs(cos(CGFloat(i)*1.7 + t*0.6))
                    let rect = CGRect(x: px, y: py, width: s, height: s).insetBy(dx: -0.5, dy: -0.5)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(a)))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { t = 2 * .pi }
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

// 2) Lattice restyle preview (different node styles)
private struct LatticeRestylePreview: View {
    @State private var phase = false

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let y = size.height * 0.54
                let xs: [CGFloat] = [size.width*0.22, size.width*0.50, size.width*0.78]
                let r: CGFloat = 9

                // A faint “motion” guide line
                var guide = Path()
                guide.move(to: CGPoint(x: xs.first ?? 0, y: y))
                guide.addQuadCurve(to: CGPoint(x: xs.last ?? 0, y: y),
                                   control: CGPoint(x: size.width*0.50, y: y + (phase ? 10 : -10)))
                ctx.stroke(guide, with: .color(.secondary.opacity(0.35)), lineWidth: 1)

                // Style 1: filled
                let p1 = CGPoint(x: xs[0], y: y)
                ctx.fill(Path(ellipseIn: CGRect(x: p1.x-r, y: p1.y-r, width: r*2, height: r*2)),
                         with: .color(.primary))

                // Style 2: ring
                let p2 = CGPoint(x: xs[1], y: y)
                ctx.stroke(Path(ellipseIn: CGRect(x: p2.x-r, y: p2.y-r, width: r*2, height: r*2)),
                           with: .color(.primary), lineWidth: 2)

                // Style 3: diamond (alternate silhouette)
                let p3 = CGPoint(x: xs[2], y: y)
                var diamond = Path()
                diamond.move(to: CGPoint(x: p3.x, y: p3.y - r))
                diamond.addLine(to: CGPoint(x: p3.x + r, y: p3.y))
                diamond.addLine(to: CGPoint(x: p3.x, y: p3.y + r))
                diamond.addLine(to: CGPoint(x: p3.x - r, y: p3.y))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(.primary.opacity(phase ? 0.75 : 1.0)))
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { phase.toggle() } }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// 3) Grid + connection styles preview
private struct GridConnectionsPreview: View {
    @State private var phase = false

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let step: CGFloat = phase ? 16 : 20
                let inset: CGFloat = 10

                // Grid
                let left = inset
                let right = size.width - inset
                let top = inset
                let bottom = size.height - inset

                var grid = Path()
                var x = left
                while x <= right {
                    grid.move(to: CGPoint(x: x, y: top))
                    grid.addLine(to: CGPoint(x: x, y: bottom))
                    x += step
                }
                var y = top
                while y <= bottom {
                    grid.move(to: CGPoint(x: left, y: y))
                    grid.addLine(to: CGPoint(x: right, y: y))
                    y += step
                }
                ctx.stroke(grid, with: .color(.secondary.opacity(0.20)), lineWidth: 1)

                // Nodes
                let a = CGPoint(x: size.width * 0.28, y: size.height * 0.68)
                let b = CGPoint(x: size.width * 0.76, y: size.height * 0.36)
                let r: CGFloat = 8

                ctx.fill(Path(ellipseIn: CGRect(x: a.x-r, y: a.y-r, width: r*2, height: r*2)),
                         with: .color(.primary))
                ctx.fill(Path(ellipseIn: CGRect(x: b.x-r, y: b.y-r, width: r*2, height: r*2)),
                         with: .color(.primary))

                // Connection (style swap)
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)

                let style = StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: phase ? [6, 5] : []
                )
                ctx.stroke(line, with: .color(.primary.opacity(0.75)), style: style)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { phase.toggle() } }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
