//
//  ClipContentView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  ClipContentView.swift
//  VenueCalibrator
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI

struct ClipContentView: View {
    @EnvironmentObject private var m: CalibrateModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityIncreaseContrast) private var increaseContrast

    var body: some View {
        VStack(spacing: 16) {
            header

            // Hero: Play/Stop
            Button(action: m.togglePlay) {
                VStack(spacing: 6) {
                    Text(m.playing ? "Stop" : "A4 \(m.a4Hz.hz1) Hz")

                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .contentTransition(.opacity)
                    Text(m.playing ? "Playing folded-sine reference" : "Tap to play")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(heroBackground)
                .overlay(heroStroke)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(m.playing ? "Stop tone" : "Play A4 \(m.a4Hz.hz1) tone")


            // Root helpers
            HStack(spacing: 10) {
                pill("Octave –", system: "chevron.down") { m.octave(-1) }
                pill("Octave +", system: "chevron.up")   { m.octave(+1) }
                Spacer(minLength: 10)
                pill("−5¢", system: "minus.circle")      { m.nudgeCents(-5) }
                pill("+5¢", system: "plus.circle")       { m.nudgeCents(+5) }
            }

            // Current root
            HStack(spacing: 8) {
                Image(systemName: "tuningfork").imageScale(.medium)
                Text("Root \(m.rootHz.hz1) Hz")

                    .font(.callout.monospacedDigit())
                Spacer()
            }
            .padding(.horizontal, 4)

            // Accent (optional, but tiny)
            HStack(spacing: 10) {
                accentChip(.system)
                accentChip(.amber)
                accentChip(.red)
                Spacer()
            }
            .padding(.top, 2)

            // Route + session chips
            HStack(spacing: 8) {
                chip(system: "speaker.wave.2.fill", text: m.routeSummary)
                chip(system: "clock", text: "Saved for this session")
                Spacer()
            }

            // CTA
            Button(action: installFullApp) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").imageScale(.medium)
                    Text("Install Tenney • remember venues & auto-switch A4")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(16)
        .onChange(of: phase) { new in
            if new != .active { m.stop() }   // stop immediately in background
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.venueName)
                .font(.title2.weight(.bold))
                .lineLimit(1)
            Text("This venue standard: \(Int(m.a4Hz)) Hz")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: hero visuals

    private var heroBackground: some ShapeStyle {
        ThemeAccent.shapeStyle(
            base: m.accent.baseColor,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )
    }

    private var heroStroke: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
    }

    // MARK: chips & pills

    private func chip(system: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system).imageScale(.small)
            Text(text).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.10), in: Capsule())
    }

    private func pill(_ label: String, system: String, tap: @escaping () -> Void) -> some View {
        Button(action: {
            tap()
            if m.playing { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: system).imageScale(.small)
                Text(label).font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func accentChip(_ a: CalibrateModel.Accent) -> some View {
        Button {
            withAnimation(.snappy) { m.accent = a }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        ThemeAccent.shapeStyle(
                            base: a.baseColor,
                            reduceTransparency: reduceTransparency,
                            increaseContrast: increaseContrast
                        )
                    )
                    .frame(width: 64, height: 34)
                if m.accent == a {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .offset(x: 22, y: -10)
                        .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(m.accent == a ? Color.white.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: m.accent == a ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(a.rawValue.capitalized + (m.accent == a ? " selected" : "")))
    }

    // MARK: CTA

    private func installFullApp() {
        let venue = m.venueName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://tenney.app/open?from=clip&feature=calibrate&a4=\(m.a4Hz)&name=\(venue)&accent=\(m.accent.rawValue)"
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Formatting helpers

// Put near the top of ClipContentView.swift (outside the View)
fileprivate extension Double {
    var hz1: String { String(format: "%.1f", self) }
}
