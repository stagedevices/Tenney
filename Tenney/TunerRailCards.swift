//
//  TunerRailCards.swift
//  Tenney
//
//  Created by OpenAI on 2024-05-07.
//

import SwiftUI

struct TunerRailCardShell<Content: View>: View {
    let title: String
    let systemImage: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                header
                if !isCollapsed {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .imageScale(.small)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Cards (minimal MVP scaffolding)

struct TunerRailNowTuningCard: View {
    let snapshot: TunerRailSnapshot
    @Binding var collapsed: Bool

    var body: some View {
        TunerRailCardShell(
            title: "Now Tuning",
            systemImage: "tuningfork",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snapshot.ratioText).font(.title3.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.1f Hz", snapshot.hz)).monospacedDigit()
                }
                HStack {
                    Text(String(format: "%+.1f ¢", snapshot.cents)).monospacedDigit()
                    Spacer()
                    Text(String(format: "Conf %.2f", snapshot.confidence)).font(.footnote)
                }
                if !snapshot.lowerText.isEmpty || !snapshot.higherText.isEmpty {
                    Text("Lower: \(snapshot.lowerText) · Higher: \(snapshot.higherText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !snapshot.isListening {
                    Text("Listening…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TunerRailIntervalTapeCard: View {
    @Binding var collapsed: Bool

    var body: some View {
        TunerRailCardShell(
            title: "Interval Tape",
            systemImage: "timeline.selection",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            Text("Captures will appear here when stability conditions are met.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct TunerRailMiniLatticeCard: View {
    @Binding var collapsed: Bool

    var body: some View {
        TunerRailCardShell(
            title: "Mini Lattice Focus",
            systemImage: "hexagon",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            Text("Interactive lattice preview (Mac only).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct TunerRailNearestTargetsCard: View {
    @Binding var collapsed: Bool

    var body: some View {
        TunerRailCardShell(
            title: "Nearest Targets",
            systemImage: "list.bullet.rectangle",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Candidates will populate here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TunerRailSessionCaptureCard: View {
    @Binding var collapsed: Bool

    var body: some View {
        TunerRailCardShell(
            title: "Session Capture",
            systemImage: "tray.and.arrow.down",
            isCollapsed: collapsed,
            onToggleCollapse: { collapsed.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Capture") { }
                    .buttonStyle(.borderedProminent)
                Text("Captured items will appear here for export.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Host

#if targetEnvironment(macCatalyst)
struct TunerContextRailHost: View {
    @ObservedObject var store: TunerRailStore
    @Binding var showSettings: Bool
    var onCustomize: (() -> Void)?

    @StateObject private var clock: TunerRailClock
    @SceneStorage("tenney.tunerRail.width") private var railWidth: Double = 340
    @State private var collapsed: Set<TunerRailCardID> = []

    private let minWidth: Double = 260
    private let maxWidth: Double = 520

    init(store: TunerRailStore, app: AppModel, showSettings: Binding<Bool>, onCustomize: (() -> Void)? = nil) {
        self.store = store
        self._showSettings = showSettings
        self.onCustomize = onCustomize
        _clock = StateObject(wrappedValue: TunerRailClock(app: app))
    }

    var body: some View {
        HStack(spacing: 0) {
            divider
            content
        }
        .frame(width: railWidth)
        .contextMenu {
            Toggle(isOn: Binding(get: { store.showRail }, set: store.setShowRail)) {
                Label(store.showRail ? "Hide Rail" : "Show Rail", systemImage: store.showRail ? "sidebar.trailing" : "sidebar.leading")
            }
            Button {
                onCustomize?()
                showSettings = true
            } label: {
                Label("Customize…", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 6)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newWidth = min(maxWidth, max(minWidth, railWidth + value.translation.width))
                        railWidth = newWidth
                    }
            )
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var content: some View {
        if store.showRail {
            ScrollView {
                VStack(spacing: 12) {
                    if store.enabledCards.isEmpty {
                        emptyPlaceholder
                    } else {
                        ForEach(store.enabledCards) { card in
                            cardView(for: card)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
            }
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func cardView(for id: TunerRailCardID) -> some View {
        switch id {
        case .nowTuning:
            TunerRailNowTuningCard(snapshot: clock.snapshot, collapsed: binding(for: id))
        case .intervalTape:
            TunerRailIntervalTapeCard(collapsed: binding(for: id))
        case .miniLatticeFocus:
            TunerRailMiniLatticeCard(collapsed: binding(for: id))
        case .nearestTargets:
            TunerRailNearestTargetsCard(collapsed: binding(for: id))
        case .sessionCapture:
            TunerRailSessionCaptureCard(collapsed: binding(for: id))
        }
    }

    private func binding(for id: TunerRailCardID) -> Binding<Bool> {
        Binding(
            get: { collapsed.contains(id) },
            set: { newValue in
                if newValue { collapsed.insert(id) } else { collapsed.remove(id) }
            }
        )
    }

    private var emptyPlaceholder: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No cards enabled").font(.headline)
                Text("Use Settings → Tuner Context Rail to add cards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
