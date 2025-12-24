//
//  TutorialSheet.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI
import AVFAudio
import UIKit

// MARK: Tutorial content (curated, separate from What's New)
struct TutorialItem: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let subtitle: String
    let bullets: [String]
}

enum TutorialTab: String, CaseIterable, Identifiable {
    case lattice, tuner, builder, studio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lattice: return "Lattice"
        case .tuner:   return "Tuner"
        case .builder: return "Builder"
        case .studio:  return "Studio"
        }
    }

    var symbol: String {
        switch self {
        case .lattice: return "hexagon"
        case .tuner:   return "tuningfork"
        case .builder: return "hammer"
        case .studio:  return "slider.horizontal.3"
        }
    }
}

struct TutorialSheet: View {
    let items: [TutorialItem]
    let primaryAction: () -> Void   // “Done”

    @Environment(\.colorScheme) private var scheme
    @Namespace private var heroNS
    @State private var animateHero = false
    @State private var tab: TutorialTab = .lattice

    private var backgroundStrength: Double { scheme == .dark ? 1.0 : 0.85 }

    private var filteredItems: [TutorialItem] {
        let t = tab
        return items.filter { item in
            switch t {
            case .lattice: return item.title.contains("Lattice") || item.title.contains("Prime") || item.title.contains("Distance")
            case .tuner:   return item.title.contains("Tuner") || item.title.contains("Pitch")
            case .builder: return item.title.contains("Builder") || item.title.contains("Scale")
            case .studio:  return item.title.contains("Studio") || item.title.contains("Console") || item.title.contains("Setup")
            }
        }
    }

    var body: some View {
        ZStack {
            MeshSheetBackgroundAurora(strength: backgroundStrength)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                tabBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(filteredItems) { item in
                            tutorialCard(item)
                        }

                        TenneyPreview()
                            .padding(.top, 6)

                        Button(action: primaryAction) {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear { animateHero = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .matchedGeometryEffect(id: "heroIcon", in: heroNS)

                Text("Tutorials")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .matchedGeometryEffect(id: "heroTitle", in: heroNS)

                Spacer()
            }

            Text("Short, practical guides for the parts you’ll use most.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(TutorialTab.allCases) { t in
                Button {
                    withAnimation(.snappy) { tab = t }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.symbol)
                        Text(t.title)
                            .font(.callout.weight(.semibold))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        (tab == t ? Color.primary.opacity(0.12) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Cards

    private func tutorialCard(_ item: TutorialItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.bullets, id: \.self) { b in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(b)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Background

private struct MeshSheetBackgroundAurora: View {
    let strength: Double

    var body: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.22 * strength),
                Color.purple.opacity(0.18 * strength),
                Color.cyan.opacity(0.18 * strength),
                Color.indigo.opacity(0.22 * strength)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [
                    Color.white.opacity(0.10 * strength),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
        )
    }
}

// MARK: - Tenney preview (distance hint)

private struct TenneyPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tenney distance preview")
                .font(.headline)

            Text("If you enable distance overlays, nodes group by harmonic proximity. Try switching modes in Console.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TenneyMiniPreview()
                .environment(\.latticePreviewHideDistance, false)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
