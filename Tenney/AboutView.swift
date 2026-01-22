//
//  AboutView.swift
//  Tenney
//
//  About / Info v2 (Settings-only entry)
//

import Foundation
import SwiftUI
import StoreKit
import UIKit

enum AboutAppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Tenney"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var maker: String { "Stage Devices LLC" }
    static var model: String { "Tenney" }

    static var modelNoPlatform: String {
#if targetEnvironment(macCatalyst)
        return "for macOS"
#else
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "for iPad"
        case .phone: return "for iPhone"
        default: return "for iOS"
        }
#endif
    }

    static var includePrivacyClaimsIfTrue: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "TENNEY_PRIVACY_CLAIMS_TRUE") as? Bool) ?? false
    }

    static var appStoreID: String? {
        Bundle.main.object(forInfoDictionaryKey: "TENNEY_APPSTORE_ID") as? String
    }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tenneyTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityIncreaseContrast) private var increaseContrast

    @AppStorage(SettingsKeys.tenneyThemeID) private var tenneyThemeIDRaw: String = "default"

    // Icon Lab (persists until app version changes)
    @State private var iconLabUnlocked: Bool = false
    @State private var unlockPulse: Bool = false
    @State private var showUnlockedPill: Bool = false

    @State private var heroIsAlt: Bool = false
    @State private var dividerProgress: CGFloat = 0
    @Namespace private var railNS

    private let supportURL = URL(string: "https://www.stagedevices.com/support")!
    private let docsURL = URL(string: "https://tenneyapp.com/docs")!
    private let featsURL = URL(string: "https://tenneyapp.com/features")!
    
    private let featureURL = URL(string: "https://github.com/stagedevices/Tenney/issues/new?template=feature_request.yml")!
    private let bugURL = URL(string: "https://github.com/stagedevices/Tenney/issues/new?template=bug_report.yml")!

    private var isWideRail: Bool {
        hSize == .regular
    }

    private var columnMaxWidth: CGFloat { 620 }

    private var iconUnlockStoreKey: String { "tenney.iconlab.unlockedForVersion" }
    private var storedUnlockedVersion: String? { UserDefaults.standard.string(forKey: iconUnlockStoreKey) }

    private var isUnlockedForCurrentVersion: Bool {
        storedUnlockedVersion == AboutAppInfo.version
    }

    private func refreshUnlockState() {
        if storedUnlockedVersion != nil, storedUnlockedVersion != AboutAppInfo.version {
            UserDefaults.standard.removeObject(forKey: iconUnlockStoreKey)
        }
        iconLabUnlocked = isUnlockedForCurrentVersion
    }

    private func unlockIconLab() {
        UserDefaults.standard.setValue(AboutAppInfo.version, forKey: iconUnlockStoreKey)
        iconLabUnlocked = true
        
        if reduceMotion {
                    iconLabUnlocked = true
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        iconLabUnlocked = true
                    }
                }

        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        
        showUnlockedPill = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if reduceMotion { showUnlockedPill = false }
                    else { withAnimation(.easeOut(duration: 0.25)) { showUnlockedPill = false } }
                }

        if !reduceMotion {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                unlockPulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    unlockPulse = false
                }
            }
        }
    }

    var body: some View {
        Form {
                    Section {
                        identityPlate
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Just-intonation lattice workflows for performance.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
        
                            Text("A performance-first just-intonation instrument: fast selection, clear labeling, and stage-ready presentation.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
        
                            if AboutAppInfo.includePrivacyClaimsIfTrue {
                                Text("No ads. No tracking. Offline-first.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
        
                    Section {
                        LabeledContent("Version") {
                            Text("v\(AboutAppInfo.version) (\(AboutAppInfo.build))")
                        }
        
                        LabeledContent("Theme") {
                            Text(tenneyThemeIDRaw)
                                .lineLimit(1)
                        }
        
                        LabeledContent("Model") {
                            Text("\(AboutAppInfo.model) \(AboutAppInfo.modelNoPlatform)")
                                .lineLimit(1)
                        }
                        } header: {
                            Text("APP")
                        }
                       
        
                    Section {
                        Link(destination: docsURL) {
                            Label("Docs & Tutorials", systemImage: "book")
                        }
        
                        Link(destination: supportURL) {
                            Label("Contact Support", systemImage: "envelope")
                        }
                    } header: {
                        Text("RESOURCES")
                    } footer: {
                        Text("Include steps to reproduce, screenshots, and your version/build.")
                    }
        
                    Section {
                        Button {
                            rateTenney()
                        } label: {
                            Label("Rate Tenney", systemImage: "star")
                        }
        
                        Link(destination: featureURL) {
                            Label("Request Feature", systemImage: "sparkles")
                        }
        
                        Link(destination: bugURL) {
                            Label("Report Bug", systemImage: "ladybug")
                        }
                    } header: {
                        Text("FEEDBACK")
                    }
        
                    if iconLabUnlocked {
                        Section {
                            iconLabCard
                                .listRowSeparator(.hidden)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        } header: {
                               Text("ICON LAB")
                           }
                       }
        
                    Section {
                        NavigationLink {
                            AcknowledgementsView()
                        } label: {
                            Label("Acknowledgements", systemImage: "doc.text")
                        }
        
                        Text("© Stage Devices LLC")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("LEGAL")
                    }
                }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshUnlockState()
            animateHeroIfAllowed()
        }
        .onChange(of: AboutAppInfo.version) { _ in
            refreshUnlockState()
        }
    }

    private var identityPlate: some View {
        HStack(alignment: .top, spacing: 14) {
            logoBadge
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AboutAppInfo.maker)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.6)

                        Text(AboutAppInfo.model)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    heroGlyph
                }

                VStack(alignment: .leading, spacing: 4) {
                    plateRow(label: "Model No.", value: AboutAppInfo.modelNoPlatform)
                    plateRow(label: "Designed in", value: "California")
                    Text("Built for just-intonation lattice workflows for performance.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var logoBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            Image("Logo")
                .resizable()
                .scaledToFit()
                .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(themeGradientStroke, lineWidth: unlockPulse ? 2.0 : 1.0)
                .opacity(unlockPulse ? 1.0 : 0.55)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onLongPressGesture(minimumDuration: 2.0) {
            if !iconLabUnlocked { unlockIconLab() }
        }
        .contextMenu {
            if !iconLabUnlocked {
                Button("Unlock Icon Lab") { unlockIconLab() }
            }
        }
        .accessibilityLabel("Tenney logo")
        .accessibilityHint(iconLabUnlocked ? "Icon Lab unlocked." : "Long-press for two seconds to unlock Icon Lab.")
        .accessibilityAction(named: "Unlock Icon Lab") {
            if !iconLabUnlocked { unlockIconLab() }
        }
    }

    private var heroGlyph: some View {
        Group {
            if #available(iOS 17.0, *) {
                Image(systemName: heroIsAlt ? "waveform" : "tuningfork")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, value: heroIsAlt)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: heroIsAlt ? "waveform" : "tuningfork")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func animateHeroIfAllowed() {
        guard !reduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                heroIsAlt.toggle()
            }
        }
    }

    private func plateRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Icon Lab (hidden until unlock)

    private var iconLabCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                           Label("Icon Lab", systemImage: "app.badge")
                               .font(.headline)
                               .symbolRenderingMode(.hierarchical)
           
                           Spacer(minLength: 0)
           
                           if showUnlockedPill {
                               Text("Unlocked")
                                   .font(.caption.weight(.semibold))
                                   .padding(.vertical, 4)
                                   .padding(.horizontal, 8)
                                   .background(.ultraThinMaterial, in: Capsule())
                                   .overlay(
                                       Capsule()
                                           .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                                   )
                                   .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                   .accessibilityHidden(true)
                           }
                       }

#if targetEnvironment(macCatalyst)
            Text("On macOS, the app icon is managed by the system. Choose an in-app badge instead.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CatalystBadgePicker(theme: theme)
#else
            if UIApplication.shared.supportsAlternateIcons {
                AlternateIconPicker(theme: theme)
            } else {
                Text("Alternate app icons aren’t available on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
#endif
        }
        .padding(16)
        .modifier(MuseumCard(corner: 16, theme: theme))
    }

    // MARK: - Rating

    private func rateTenney() {
#if targetEnvironment(macCatalyst)
        if let id = AboutAppInfo.appStoreID,
           let url = URL(string: "macappstore://itunes.apple.com/app/id\(id)?action=write-review") {
            openURL(url)
        } else if let url = URL(string: "https://tenneyapp.com") {
            openURL(url)
        }
#else
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            SKStoreReviewController.requestReview(in: scene)
        }
#endif
    }

    // MARK: - Theme helpers

    private var themeAccentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
    }

    private var themeGradientStroke: some ShapeStyle {
        themeAccentStyle
    }
}

private struct MuseumCard: ViewModifier {
    let corner: CGFloat
    let theme: ResolvedTenneyTheme
    var emphasize: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityIncreaseContrast) private var increaseContrast

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.white.opacity(theme.isDark ? 0.05 : 0.18))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        ThemeAccent.shapeStyle(
                            base: theme.accent.opacity(emphasize ? 0.9 : 0.55),
                            reduceTransparency: reduceTransparency,
                            increaseContrast: increaseContrast
                        ),
                        lineWidth: emphasize ? 2.0 : 1.0
                    )
            )
            .shadow(color: Color.black.opacity(theme.isDark ? 0.30 : 0.10), radius: 14, x: 0, y: 8)
            .modifier(GlassCompat(corner: corner))
    }
}

private struct GlassCompat: ViewModifier {
    let corner: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            content
        }
    }
}

fileprivate extension View {
    @ViewBuilder
    func glassControlRounded(_ corner: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

private struct PressPlateButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.96 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

// MARK: - Icon Lab (iOS / iPadOS)

#if !targetEnvironment(macCatalyst)
private struct AppIconOption: Identifiable {
    let id: String
    let iconName: String?
    let displayName: String
    let previewAssetName: String?
}

private struct AlternateIconPicker: View {
    let theme: ResolvedTenneyTheme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var options: [AppIconOption] = []
    @State private var currentIconName: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?
    @State private var isSettingIcon: Bool = false
        @State private var pendingID: String? = nil
        @State private var glowID: String? = nil
        @State private var glowOn: Bool = false
     

    private var cols: [GridItem] {
            if UIDevice.current.userInterfaceIdiom == .phone {
                return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
            } else {
                let count = (hSize == .regular) ? 4 : 3
                return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
            }
        }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alternate App Icon")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(options) { opt in
                    IconChoiceCell(
                        option: opt,
                        isSelected: opt.iconName == currentIconName,
                        isBusy: pendingID == opt.id,
                        emphasize: glowOn && glowID == opt.id,
                        isDisabled: isSettingIcon,
                        theme: theme
                    ) {
                        setIcon(opt.iconName, pendingID: opt.id)
                    }
                }
            }
            
            Button {
                            setIcon(nil, pendingID: "default")
                        } label: {
                            Label("Set Default Icon", systemImage: "arrow.counterclockwise")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .glassControlRounded(12)
                        .disabled(isSettingIcon || currentIconName == nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
                    currentIconName = UIApplication.shared.alternateIconName
                    options = loadIconOptions()
                }
    }

    private func setIcon(_ name: String?, pendingID: String) {
            guard !isSettingIcon else { return }
            isSettingIcon = true
            self.pendingID = pendingID
            errorMessage = nil
        UIApplication.shared.setAlternateIconName(name) { err in
            DispatchQueue.main.async {
                isSettingIcon = false
                    self.pendingID = nil
                if let err {
                    errorMessage = err.localizedDescription
                    let gen = UINotificationFeedbackGenerator()
                        gen.notificationOccurred(.error)
                } else {
                    errorMessage = nil
                    currentIconName = name
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.success)
                    
                    glowID = pendingID
                                        if reduceMotion {
                                            glowOn = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { glowOn = false }
                                        } else {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { glowOn = true }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                                withAnimation(.easeOut(duration: 0.25)) { glowOn = false }
                                            }
                                        }
                }
            }
        }
    }

    private func loadIconOptions() -> [AppIconOption] {
        [
                    AppIconOption(id: "default", iconName: nil, displayName: "Default", previewAssetName: "IconPreview-Default"),
                    AppIconOption(id: "logolab", iconName: "LogoLab", displayName: "Logo Lab", previewAssetName: "IconPreview-LogoLab"),
                ]
    }
}

private struct IconChoiceCell: View {
    let option: AppIconOption
    let isSelected: Bool
    let isBusy: Bool
        let emphasize: Bool
         let isDisabled: Bool
    let theme: ResolvedTenneyTheme
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityIncreaseContrast) private var increaseContrast

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    iconPreview
                        .frame(width: 52, height: 52)
                                                 .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                 .overlay(
                                                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .strokeBorder(strokeStyle, lineWidth: (isSelected ? 2 : 1) + (emphasize ? 1 : 0))
                                                 )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(6)
                    }
                    
                    if isBusy {
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .padding(8)
                                        }
                }

                Text(option.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressPlateButtonStyle(reduceMotion: reduceMotion))
        .disabled(isDisabled)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    
    private var strokeStyle: AnyShapeStyle {
            if isSelected {
                return ThemeAccent.shapeStyle(
                    base: theme.accent.opacity(emphasize ? 0.95 : 1.0),
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast
                )
            } else {
                return AnyShapeStyle(Color.secondary.opacity(0.18))
            }
        }

    private var iconPreview: some View {
        Group {
            if let name = option.previewAssetName, let ui = UIImage(named: name) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(
                        ThemeAccent.shapeStyle(
                            base: theme.accent.opacity(0.35),
                            reduceTransparency: reduceTransparency,
                            increaseContrast: increaseContrast
                        )
                    )
                    Image(systemName: "app.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
        }
    }
}
#endif

// MARK: - Icon Lab (Catalyst)

#if targetEnvironment(macCatalyst)
private enum CatalystBadgeStyle: String, CaseIterable, Identifiable {
    case standard
    case plate
    case dot
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .plate: return "Plate"
        case .dot: return "Dot"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Default in-app badge"
        case .plate: return "Museum label accent"
        case .dot: return "Minimal scope dot accent"
        }
    }
}

private struct CatalystBadgePicker: View {
    let theme: ResolvedTenneyTheme
    @AppStorage("tenney.iconlab.catalystBadgeStyle") private var raw: String = CatalystBadgeStyle.standard.rawValue

    private var selection: Binding<CatalystBadgeStyle> {
        Binding(
            get: { CatalystBadgeStyle(rawValue: raw) ?? .standard },
            set: { raw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In-app badge")
                .font(.subheadline.weight(.semibold))

            Picker("In-app badge", selection: selection) {
                ForEach(CatalystBadgeStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text((CatalystBadgeStyle(rawValue: raw) ?? .standard).subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#endif
