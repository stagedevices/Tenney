//
//  WhatsNewSheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI
import StoreKit
import AVFAudio
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

// MARK: v0.2 content
enum WhatsNewContent {
    // “Big three” are rendered as custom cards below. Keep the rest here.
    static let v0_2Items: [WhatsNewItem] = [
        .init(
            symbol: "square.grid.3x3.fill",
            title: "More Nodes & Pads",
            summary: "Scale up to 13–31 nodes with larger pads. Faster layout, smoother guides."
        ),
        .init(
            symbol: "sparkles.rectangle.stack",
            title: "Setup Wizard",
            summary: "First-run setup (and rerun anytime) to dial in roots, A4, and defaults."
        ),
        .init(
            symbol: "wifi.circle",
            title: "Cast Audio",
            summary: "AirPlay, Bluetooth, USB, and Inter-App Audio—use the best route available."
        ),
        .init(
            symbol: "gearshape.2",
            title: "Better Settings",
            summary: "Glass cards, live previews, clearer controls, and theme polish."
        ),
        .init(
            symbol: "checkmark.shield.fill",
            title: "Stability & Polish",
            summary: "Crash fixes, quicker launches, and snappier interactions."
        )
    ]
}

// MARK: - Sheet
struct WhatsNewSheet: View {
    let items: [WhatsNewItem]
    let primaryAction: () -> Void

    // Optional deep-link actions (shown only if provided)
    var onSeeIntervalInLattice: (() -> Void)? = nil
    var onOpenProAudio: (() -> Void)? = nil
    var onRateApp: (() -> Void)? = nil

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
                bigThree // custom rich cards
                featureList // the rest
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
                                    .init(color: .white,            location: 0.00),
                                    .init(color: .white,            location: 0.65),
                                    .init(color: .white.opacity(0.6), location: 0.85),
                                    .init(color: .clear,            location: 1.00),
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

                    // Platform chip
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

    // MARK: Big Three (rich cards with tiny previews)
    private var bigThree: some View {
        VStack(spacing: 12) {
            // 1) Interval Distance badges (Tenney Height)
            bigCard(
                symbol: "chart.xyaxis.line",
                title: "Interval Distance",
                blurb: "Tenney Height—total or per-prime breakdown—now right on the lattice.",
                preview: AnyView(TenneyPreview()),
                primaryCTA: onSeeIntervalInLattice == nil ? nil : ("See in Lattice", {
                    onSeeIntervalInLattice?()
                })
            )

            // 2) Hold-to-Select-All (pads)
            bigCard(
                symbol: "hand.tap.fill",
                title: "Hold to Select",
                blurb: "Press & hold a ratio pill to select the whole row—fast multi-edits.",
                preview: AnyView(HoldSelectPreview()),
                primaryCTA: nil
            )

            // 3) Pro Audio handling
            bigCard(
                symbol: "hifispeaker.2.fill",
                title: "Pro Audio",
                blurb: "Input device picker, sample rate, and latency awareness.",
                preview: AnyView(ProAudioPreview()),
                primaryCTA: onOpenProAudio == nil ? nil : ("Open in Settings", {
                    onOpenProAudio?()
                })
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
                        .matchedGeometryEffect(id: item.symbol == "chart.xyaxis.line" ? "spark" : UUID().uuidString, in: heroNS, properties: .position, isSource: false)

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
            // Links row
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

            // Primary CTA
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
                        .symbolEffect(.pulse, options: .repeating, value: true)
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
// Meshy, moving blobs (red → orange), plus grain
                ctx.blendMode = .plusLighter
                let red   = Color(uiColor: .systemRed)
                let org   = Color(uiColor: .systemOrange)
                let ylw   = Color(uiColor: .systemYellow)
                let w = size.width, h = size.height * 1.35   // overfill into body
                let rBase = min(w, h) * 0.52

                // Control centers drift at different phases/speeds
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

                // Five overlapping radial shadings to mimic a mesh
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


// MARK: - Tenney mini preview (animated chips)
private struct TenneyPreview: View {
    @State private var pulse = false
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let a = CGPoint(x: size.width * 0.26, y: size.height * 0.70)
                let b = CGPoint(x: size.width * 0.78, y: size.height * 0.34)
                // nodes
                for p in [a,b] {
                    let r: CGFloat = 8
                    ctx.fill(Path(ellipseIn: .init(x: p.x-r, y: p.y-r, width: r*2, height: r*2)), with: .color(.primary))
                }
                // guide
                var line = Path(); line.move(to: a); line.addLine(to: b)
                ctx.stroke(line, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

                // total chip
                let mid = CGPoint(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
                let totalR = CGRect(x: mid.x-24, y: mid.y-10, width: 48, height: 20)
                ctx.fill(RoundedRectangle(cornerRadius: 6).path(in: totalR),
                         with: .color(Color.secondary.opacity(0.15)))
                ctx.draw(Text("H 3.84").font(.system(size: 10, weight: .semibold)), at: mid)

                // per-axis chips
                let chips = [("+2×3", Color.orange), ("−1×5", .pink), ("+1×7", .blue)]
                let offs: [CGPoint] = [ .init(x: -28, y: -18), .init(x: 0, y: 18), .init(x: 28, y: -14) ]
                for i in 0..<chips.count {
                    let pos  = CGPoint(x: mid.x + offs[i].x, y: mid.y + offs[i].y + (pulse ? 0 : -2))
                    let rr = CGRect(x: pos.x-16, y: pos.y-8, width: 32, height: 16)
                    ctx.fill(RoundedRectangle(cornerRadius: 5).path(in: rr),
                             with: .color(chips[i].1.opacity(0.20)))
                    ctx.draw(Text(chips[i].0).font(.system(size: 9, weight: .semibold)), at: pos)
                }
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { pulse.toggle() } }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Hold-to-select preview (animated pills + long-press ripple)
private struct HoldSelectPreview: View {
    // Show 7–31 (real chips); we’ll render as many as fit
private let labels = Array(7...31).map { "\($0)" }

    var body: some View {
        GeometryReader { geo in
            let maxW = geo.size.width
            let maxH = geo.size.height
            // Realistic pill sizing to match .footnote.semibold
            let uiFont = UIFont.systemFont(ofSize: 12, weight: .semibold) // GlassChip uses .caption.semibold
            let hPad: CGFloat = 10, vPad: CGFloat = 6, spacing: CGFloat = 6
            let pillH = ceil(uiFont.lineHeight) + vPad * 2

// Compute how many pills fit (flow layout; may early-exit)
            let placed: [(text: String, frame: CGRect)] = {
                var arr: [(text: String, frame: CGRect)] = []
                var x: CGFloat = 0, y: CGFloat = 0
                for t in labels {
                    let textW = ceil((t as NSString).size(withAttributes: [.font: uiFont]).width)
                    let pillW = textW + hPad * 2
                    if x + pillW > maxW { x = 0; y += (pillH + spacing) }
                    if y + pillH > maxH { break }
                    arr.append((t, CGRect(x: x, y: y, width: pillW, height: pillH)))
                    x += pillW + spacing
                }
                return arr
            }()

            ZStack(alignment: .topLeading) {
                ForEach(placed.indices, id: \.self) { i in
                    let item = placed[i]
                    GlassChip(title: item.text, active: false, color: .accentColor, action: {})
                                            .frame(width: item.frame.width, height: item.frame.height, alignment: .center)
                                            .position(x: item.frame.midX, y: item.frame.midY)
                                            .allowsHitTesting(false)
                }
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Pro Audio preview (route + sample rate shimmer)
private struct ProAudioPreview: View {
    @State private var label = ProAudioPreview.currentRouteSummary()
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill").imageScale(.small)
            Text(label)
                .font(.caption2.weight(.semibold))
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: shimmer ? 0 : nil, height: 1)
                        .offset(y: 10)
                        .opacity(0.0)
                )
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.10), in: Capsule())
        .onAppear {
            label = ProAudioPreview.currentRouteSummary()
            withAnimation(.easeInOut(duration: 1.6).delay(0.4)) { shimmer.toggle() }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func currentRouteSummary() -> String {
        let s = AVAudioSession.sharedInstance()
        let name = s.currentRoute.outputs.first?.portName ?? "Built-in Speaker"
        let kHz = s.sampleRate / 1000.0
        let rateText = (abs(kHz - 44.1) < 0.2) ? "44.1" : String(format: "%.0f", kHz)
        return "\(name) • \(rateText) kHz"
    }
}
