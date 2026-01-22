#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @EnvironmentObject private var latticeStore: LatticeStore
    @EnvironmentObject private var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.tenneyTheme) private var theme
    @Environment(\.openWindow) private var openWindow

    @SceneStorage("tenney.mac.splitRatio") private var splitRatio: Double = 0.56
    @State private var stageActive = false

    var body: some View {
        ZStack(alignment: .top) {
            TenneySceneBackground(
                isDark: scheme == .dark,
                preset: theme.sceneBackgroundPreset,
                tintA: theme.primeTint(3),
                tintB: theme.primeTint(5)
            )

            VStack(spacing: 0) {
                ResizableSplitView(
                    ratio: $splitRatio,
                    minLeading: 520,
                    minTrailing: 420
                ) {
                    MacPane {
                        LatticeScreen(store: latticeStore)
                            .environmentObject(app)
                            .padding(12)
                    }
                    .accessibilityIdentifier("mac.lattice-pane")
                } trailing: {
                    MacPane {
                        TunerCard(stageActive: $stageActive)
                            .environmentObject(app)
                            .padding(16)
                    }
                    .accessibilityIdentifier("mac.tuner-pane")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
                .padding(.top, 10)
            }
        }
        .safeAreaInset(edge: .top) {
            MacTopBar(openPreferences: { openWindow(id: "preferences") })
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        .background(MacWindowConfigurator())
    }
}

// MARK: - Split
private struct ResizableSplitView<Leading: View, Trailing: View>: View {
    @Binding var ratio: Double
    let minLeading: CGFloat
    let minTrailing: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(
        ratio: Binding<Double>,
        minLeading: CGFloat,
        minTrailing: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        _ratio = ratio
        self.minLeading = minLeading
        self.minTrailing = minTrailing
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(geo.size.width, minLeading + minTrailing + 1)
            let clampedRatio = clampRatio(current: ratio, total: total)
            let leadingWidth = total * clampedRatio
            let dividerWidth: CGFloat = 1

            HStack(spacing: 0) {
                leading
                    .frame(width: leadingWidth)
                    .frame(maxHeight: .infinity)

                Divider()
                    .frame(width: dividerWidth)
                    .background(.secondary.opacity(0.28))
                    .overlay {
                        Capsule()
                            .fill(.linearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 3, height: 48)
                            .padding(.vertical, 6)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let proposed = leadingWidth + value.translation.width
                                ratio = clampRatio(current: proposed / total, total: total)
                            }
                    )

                trailing
                    .frame(width: total - leadingWidth - dividerWidth)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func clampRatio(current: Double, total: CGFloat) -> Double {
        let minLeadRatio = minLeading / total
        let maxLeadRatio = 1.0 - (minTrailing / total)
        return min(max(current, minLeadRatio), maxLeadRatio)
    }
}

// MARK: - Chrome
private struct MacPane<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.22), radius: 24, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct MacTopBar: View {
    @Environment(\.colorScheme) private var scheme
    let openPreferences: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tenney")
                    .font(.title3.weight(.semibold))
                Text("Lattice · Tuner")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: openPreferences) {
                Label("Preferences", systemImage: "gearshape.fill")
                    .labelStyle(.iconOnly)
                    .font(.headline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.18), radius: 14, y: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(scheme == .dark ? 0.42 : 0.24), radius: 24, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

// MARK: - Window styling
private struct MacWindowConfigurator: View {
    var body: some View {
        #if canImport(AppKit)
        MacWindowAccessor()
            .allowsHitTesting(false)
        #else
        Color.clear
        #endif
    }
}

#if canImport(AppKit)
import AppKit

private struct MacWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configureWindow(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configureWindow(from: nsView) }
    }

    private func configureWindow(from view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.title = ""
    }
}
#endif
#endif
