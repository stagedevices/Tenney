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
            symbol: "hexagon.grid",
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
            symbol: "shield.leadinghalf.filled",
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
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
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
                let colors = [UIColor.systemRed, UIColor.systemOrange].map { Color($0) }
                let g = Gradient(colors: [
                    colors[0],
                    colors[0].opacity(0.8),
                    colors[1].opacity(0.9),
                    colors[1]
                ])
                let center = CGPoint(x: size.width/2, y: size.height/2)
                let r1 = min(size.width, size.height) * (0.45 + 0.05 * sin(t))
                let r2 = r1 * 0.66

                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r1, y: center.y - r1, width: r1*2, height: r1*2)),
                         with: .radialGradient(g, center: center, startRadius: r2, endRadius: r1))

                // spark specks
                let specks = 18
                for i in 0..<specks {
                    let a = (CGFloat(i)/CGFloat(specks)) * .pi * 2 + t*0.6
                    let p = CGPoint(x: center.x + cos(a) * (r1 * 0.7),
                                    y: center.y + sin(a) * (r1 * 0.35))
                    let dot = Path(ellipseIn: CGRect(x: p.x-2, y: p.y-2, width: 4, height: 4))
                    ctx.fill(dot, with: .color(.white.opacity(0.25)))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: true)) { t = 2 * .pi }
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
    @State private var pressed = false
    private let labels = ["13","17","19","23","29","31"]

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(labels, id:\.self) { t in
                    Text(t)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(pressed ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10), in: Capsule())
                }
            }
            .padding(8)

            if pressed {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    .scaleEffect(pressed ? 1.1 : 0.9)
                    .opacity(pressed ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 0.8), value: pressed)
            }
        }
        .onAppear {
            // auto “demo” pulse
            withAnimation(.easeInOut(duration: 1.0)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 0.4)) { pressed = false }
            }
        }
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
