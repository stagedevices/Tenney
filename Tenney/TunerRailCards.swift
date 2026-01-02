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

    private let app: AppModel
    @StateObject private var clock: TunerRailClock
    @SceneStorage("tunerRail.width") private var railWidth: Double = 340
    @GestureState private var dragDX: CGFloat = 0
    @State private var dividerHover = false
    @AppStorage(SettingsKeys.tunerRailShow) private var tunerRailShow: Bool = true
    @State private var collapsed: Set<TunerRailCardID> = []

    private let minWidth: Double = 260
    private let maxWidth: Double = 520
    private var effectiveWidth: Double {
        clampWidth(railWidth + Double(dragDX))
    }

    init(store: TunerRailStore, app: AppModel, showSettings: Binding<Bool>, onCustomize: (() -> Void)? = nil) {
        self.store = store
        self.app = app
        self._showSettings = showSettings
        self.onCustomize = onCustomize
        _clock = StateObject(wrappedValue: TunerRailClock(app: app))
    }

    var body: some View {
        let drag = DragGesture(minimumDistance: 0)
            .updating($dragDX) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                railWidth = clampWidth(railWidth + Double(value.translation.width))
            }

        HStack(spacing: 0) {
            divider
                .gesture(drag)
            content
        }
        .frame(width: effectiveWidth)
        .contextMenu {
            Toggle(isOn: $tunerRailShow) {
                Label(tunerRailShow ? "Hide Rail" : "Show Rail", systemImage: tunerRailShow ? "sidebar.trailing" : "sidebar.leading")
            }
            Button {
                onCustomize?()
                app.openSettingsToTunerRail = true
                showSettings = true
            } label: {
                Label("Customize…", systemImage: "slider.horizontal.3")
            }
        }
        .onChange(of: tunerRailShow) { show in
            store.setShowRail(show)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(dividerHover ? 0.32 : 0.18))
            .frame(width: 6)
            .onHover { dividerHover = $0 }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
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

    private func clampWidth(_ width: Double) -> Double {
        min(maxWidth, max(minWidth, width))
    }
}
#endif
