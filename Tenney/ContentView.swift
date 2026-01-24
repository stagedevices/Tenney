//
//  ContentView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import SwiftUI
import AVFoundation
import UIKit
enum AppScreenMode: String, CaseIterable, Identifiable { case tuner, lattice; var id: String { rawValue } }

private func loadLatticeAxisShiftSnapshot() -> [Int:Int] {
    if let data = UserDefaults.standard.data(forKey: "lattice.persist.v1"),
       let blob = try? JSONDecoder().decode(LatticeStore.PersistBlob.self, from: data) {
        return blob.axisShift
    }
    return [:]
}

struct ContentView: View {
    @AppStorage(SettingsKeys.tenneyThemeID) private var tenneyThemeIDRaw: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixBasis) private var mixBasisRaw: String = TenneyMixBasis.complexityWeight.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixMode) private var mixModeRaw: String = TenneyMixMode.blend.rawValue
    @AppStorage(SettingsKeys.tenneyThemeScopeMode) private var scopeModeRaw: String = TenneyScopeColorMode.constant.rawValue
    @AppStorage(SettingsKeys.tenneyMonochromeTintHex) private var monochromeTintHex: String = "#000000"

    @AppStorage(SettingsKeys.setupWizardDone) private var setupWizardDone: Bool = false
private let libraryStore = ScaleLibraryStore.shared
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.latticeThemeStyle) private var themeStyleRaw: String = "system"
    private var resolvedTheme: ResolvedTenneyTheme {
        let _ = monochromeTintHex
        return TenneyThemeRegistry.resolvedCurrent(
            themeIDRaw: tenneyThemeIDRaw,
            scheme: effectiveIsDark ? .dark : .light,
            mixBasis: TenneyMixBasis(rawValue: mixBasisRaw),
            mixMode: TenneyMixMode(rawValue: mixModeRaw),
            scopeMode: TenneyScopeColorMode(rawValue: scopeModeRaw)
        )
    }

    @State private var venueToast: VenueCalibrationInfo? = nil

    @State private var inkVisible = false
    @State private var inkIsDark = false
    @State private var effectiveIsDark = false
    @Environment(\.tenneyPracticeActive) private var practiceActive
    @Environment(\.verticalSizeClass) private var vSize

    @StateObject private var tunerStore = TunerStore()
    @State private var latticeAxisShift: [Int:Int] = loadLatticeAxisShiftSnapshot()
    @EnvironmentObject private var app: AppModel
    @State private var mode: AppScreenMode = .tuner
    @State private var showSettings = false
    
    @StateObject private var tunerRailStore = TunerRailStore()
    @State private var requestedSettingsCategory: StudioConsoleView.SettingsCategory? = nil
    @AppStorage(SettingsKeys.tunerStageMode) private var stageActive: Bool = false
    @Namespace private var stageNS
    @Namespace private var rootNS
    @State private var showRootStudio = false
    @State private var rootStudioTab: RootStudioTab = .calculator
    @AppStorage(SettingsKeys.stageDimLevel) private var stageDimLevel: Double = 0.35
    @AppStorage(SettingsKeys.stageAccent)   private var stageAccent: String = "system"
    @AppStorage(SettingsKeys.stageHideStatus) private var stageHideStatus: Bool = true
    @AppStorage(SettingsKeys.stageKeepAwake)  private var stageKeepAwake: Bool = true
    @AppStorage(SettingsKeys.stageMinimalUI)  private var stageMinimalUI: Bool = false
    @AppStorage(SettingsKeys.defaultView) private var defaultView: String = "tuner" // "lattice" | "tuner"
    
    @State private var swapFlashWhite: Bool = false // legacy, no longer used
        // ===== Footer (first-run wizard) =====
        @State private var footerRouteLabel: String = ""
        @State private var footerBuildStamp: String = ""
        @State private var footerTipIndex: Int = 0
       private let footerTips: [String] = [
            "Headphones recommended · Keep volume modest.",
            "You can plug a mic via USB audio interface.",
            "Hold ratio pills to select all.",
            "Long-press the dial to lock a target."
        ]
    @State private var frozenBackdrop: UIImage? = nil // ← snapshot shown behind the wizard
    @State private var wizardTopY: CGFloat = .nan    // ← measured top of the wizard (global coords)
    // In ContentView.swift (top-level state)
    @AppStorage(SettingsKeys.lastSeenBuild) private var lastSeenBuild: String = ""
    @State private var showWhatsNew = false

    // Helper
    private var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
    private var supportsTunerContextRailOnThisDevice: Bool { isPad || isMacCatalyst }

    private func shouldShowTunerContextRail(isLandscape: Bool) -> Bool {
        guard supportsTunerContextRailOnThisDevice else { return false }
        guard isLandscape else { return false }
        return tunerRailStore.showRail
    }

    private func shouldShowTunerContextRailMenu(isLandscape: Bool) -> Bool {
        guard isLandscape else { return false }
        return isMacCatalyst || isPad
    }
    private func shouldShowWhatsNew() -> Bool {
        lastSeenBuild != currentBuild
    }
    private func presentWhatsNewIfEligible() {
        guard setupWizardDone, !app.showOnboardingWizard, shouldShowWhatsNew() else { return }
        showWhatsNew = true
    }

    private func recomputeSchemeFlipIfNeeded() {
        let newEffectiveIsDark =
            (themeStyleRaw == "dark") ||
            (themeStyleRaw == "system" && systemScheme == .dark)

        guard newEffectiveIsDark != effectiveIsDark else { return }

        // ink color matches the *new* scheme so it looks like a quick ink wash
        inkIsDark = newEffectiveIsDark
        withAnimation(.easeInOut(duration: 0.25)) { inkVisible = true }
        effectiveIsDark = newEffectiveIsDark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeOut(duration: 0.15)) { inkVisible = false }
        }
    }

    var body: some View {
        let blurActive = app.showOnboardingWizard && (setupWizardDone || frozenBackdrop == nil)

        ZStack {
            // ===== Underlying app content =====
            mainContent
                .blur(radius: blurActive ? 10 : 0)
                .overlay(blurActive ? Color.black.opacity(0.28) : Color.clear)


            // ===== Onboarding overlays (first-run vs rerun) =====
            if app.showOnboardingWizard && !setupWizardDone {
                // FIRST RUN — white canvas + centered logo + wizard + footer rail
                Color(effectiveIsDark ? .black : .white).ignoresSafeArea().zIndex(1)  // Set background to black or white based on theme

                ZStack {
                    VStack(spacing: 16) {
                        // Increase vertical space allocated for the wizard
                        
                        OnboardingWizardView(
                            onRequireSwapFlash: { },
                            onDone: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.snappy) {
                                    setupWizardDone = true
                                    app.showOnboardingWizard = false
                                    frozenBackdrop = nil
                                }
                            }
                        )
                        .frame(maxWidth: 600)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: WizardTopPref.self,
                                                value: proxy.frame(in: .global).minY)
                            }
                        )

                        // measure wizard top for logo centering
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: WizardTopPref.self,
                                                value: proxy.frame(in: .global).minY)
                            }
                        )
                        
                        // Footer (quiet + useful)
                        // Footer (quiet + useful) remains pinned to the bottom
                        WizardFooterRail(
                            buildString: footerBuildStamp,
                            tips: [
                                "Pro tip: Headphones recommended · Keep volume modest.",
                                "Pro tip: You can plug a mic via USB audio interface.",
                                "Pro tip: Long-press the ratio tabs to select all.",
                                "Pro tip: Long-press the tuner dial to lock a target."
                            ],
                            onSkip: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.snappy) {
                                    setupWizardDone = true
                                    app.showOnboardingWizard = false
                                    frozenBackdrop = nil
                                }
                            }
                        )
                        .frame(maxWidth: .infinity)    // Center the footer horizontally
                        .frame(maxHeight: .infinity, alignment: .bottom)  // Pin footer to bottom
                        .padding(.horizontal, 32)

                    }
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(2)
                }
                .zIndex(2)     // ← ADD THIS LINE
            }
            else if app.showOnboardingWizard && setupWizardDone {
                // RERUNS — glass over live app, wizard only
                ZStack {
                    OnboardingWizardView(
                        onRequireSwapFlash: { },
                        onDone: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.snappy) {
                                app.showOnboardingWizard = false
                                frozenBackdrop = nil
                            }
                        }
                    )
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
            }

                
               

            // ===== Global ink cross-fade (covers EVERYTHING in this scene) =====
            if inkVisible {
                Rectangle()
                    .fill(inkIsDark ? Color.black : Color.white)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(10)
            }
#if targetEnvironment(macCatalyst)
            macKeyboardShortcuts
#endif
        }
        .environment(\.tenneyTheme, resolvedTheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenShell {
            resolvedTheme.surfaceTint
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)

        // Still in ContentView.body view modifiers
        .onAppear {
            presentWhatsNewIfEligible()
        }
        .onChange(of: app.showOnboardingWizard) { isShowing in
            // As soon as onboarding closes, show What's New (if needed)
            if !isShowing { presentWhatsNewIfEligible() }
        }
        .onAppear {
            if lastSeenBuild != AppInfo.build {
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            // Mark seen when the sheet closes (via button swipe, or drag-to-dismiss)
            lastSeenBuild = AppInfo.build
        }) {
            WhatsNewSheet(app: app, items: WhatsNewContent.v0_3Items) {
                // Primary CTA: just close; marking happens in onDismiss
                showWhatsNew = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .tenneySheetSizing()
        }

        .onReceive(NotificationCenter.default.publisher(for: .venueCalibrated)) { note in
            guard let info = note.object as? VenueCalibrationInfo else { return }
            venueToast = info
            // Auto-hide after 2.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.25)) { venueToast = nil }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tenneyLearnDeepLink)) { note in
            guard let destination = LearnTenneyDeepLinkDestination.from(note) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                handleLearnDeepLink(destination)
            }
        }
        .safeAreaInset(edge: .top) {
            if let t = venueToast {
                VenueBanner(text: "\(t.name) • A4 \(String(format: "%.1f", t.a4)) Hz")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }

        .onAppear {
            // Align initial mode to defaultView
            mode = practiceActive ? .lattice : (defaultView == "lattice" ? .lattice : .tuner)
            app.setMicActive(!practiceActive && mode == .tuner)

            // Footer bootstrap (first-run overlay)
                        computeBuildStamp()
                        updateFooterRoute()
                        footerTipIndex = Int.random(in: 0..<max(1, footerTips.count))
            // Wizard already showing on first render? Grab a backdrop now.
                if app.showOnboardingWizard && frozenBackdrop == nil {
                    DispatchQueue.main.async {
                        frozenBackdrop = captureKeyWindowSnapshot(afterScreenUpdates: false)
                    }
                }
        }
        // Live-update the audio route chip
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                    updateFooterRoute()
                }
        .onChange(of: themeStyleRaw) { _ in recomputeSchemeFlipIfNeeded() }
        .onChange(of: systemScheme)  { _ in recomputeSchemeFlipIfNeeded() }
        // Snapshot when the wizard opens; clear when it closes
                .onChange(of: app.showOnboardingWizard) { isShowing in
                    if isShowing { frozenBackdrop = captureKeyWindowSnapshot() } else { frozenBackdrop = nil }
                }
                // If defaultView changes WHILE the wizard is visible, silently swap the mode
                .onChange(of: defaultView) { val in
                    if app.showOnboardingWizard {
                        var tx = Transaction(); tx.disablesAnimations = true
                        withTransaction(tx) { mode = (val == "lattice" ? .lattice : .tuner) }
                    } else {
                        withAnimation(.snappy) { mode = (val == "lattice" ? .lattice : .tuner) }
                    }
                }
        // Capture wizard top Y (global)
            .onPreferenceChange(WizardTopPref.self) { wizardTopY = $0 }
            .alert("Microphone Access Needed", isPresented: $app.micDenied) {
                        Button("Open Settings") { MicrophonePermission.openAppSettings() }
                        Button("Not Now", role: .cancel) { }
                    } message: {
                        Text("Enable Microphone in Settings → Privacy → Microphone to use the tuner.")
                    }
    }
    // ===== Footer helpers =====
        private func updateFooterRoute() {
            let s = AVAudioSession.sharedInstance()
            let name = s.currentRoute.outputs.first?.portName ?? "Built-in Speaker"
            let kHz = s.sampleRate / 1000.0
            // Show “44.1” when close; otherwise whole kHz (48, 96, …)
            let rateText = (abs(kHz - 44.1) < 0.2) ? "44.1" : String(format: "%.0f", kHz)
            footerRouteLabel = "\(name) • \(rateText) kHz"
        }
        private func computeBuildStamp() {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            footerBuildStamp = "Tenney v\(v) (build \(b))"
        }
    // Global-minY preference to locate the wizard's top on screen
    private struct WizardTopPref: PreferenceKey {
        static var defaultValue: CGFloat = .nan
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            let v = nextValue()
            if value.isNaN { value = v } else { value = min(value, v) }
        }
    }

    // MARK: Main content (tuner or lattice)
    private var mainContent: some View {
        let base = coreContent
            .coordinateSpace(name: "stageSpace")
            .overlay { stageOverlay }
            .statusBarHidden(stageActive && stageHideStatus)
            .onChange(of: stageActive) { on in updateIdleTimer(stageOn: on) }
            .onChange(of: stageKeepAwake) { keep in updateIdleTimer(keepAwake: keep) }
            .safeAreaInset(edge: .bottom) { if !stageActive { utilityBarInset } }
            .onChange(of: mode) { new in
                if practiceActive {
                    if new != .lattice { mode = .lattice }
                    app.setMicActive(false)
                } else {
                    app.setMicActive(new == .tuner)
                }
            }

        
        return base
            .sheet(isPresented: $showSettings) { settingsSheet }
            .sheet(item: $app.builderPayload, onDismiss: builderSheetDismiss) { payload in
                builderSheet(payload: payload, startInLibrary: payload.startInLibrary)
            }
            .sheet(isPresented: $app.showScaleLibraryDetent, onDismiss: librarySheetDismiss) { scaleLibraryDetent }
            .sheet(isPresented: $showRootStudio) { rootStudioDetent }
    }

    private var coreContent: some View {
        GeometryReader { geo in
            Group {
                if mode == .tuner {
                    tunerContent(in: geo)
                } else {
                    latticeContent
                }
            }
        }
    }

    @ViewBuilder
    private func tunerContent(in geo: GeometryProxy) -> some View {
        let isLandscape = geo.size.width > geo.size.height

        let isPhoneLandscapeCompact = (!isMacCatalyst && UIDevice.current.userInterfaceIdiom == .phone && vSize == .compact)
        
        if isLandscape && isPhoneLandscapeCompact {
            tunerCardView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: [.horizontal]) // stops “side gutters” in landscape
        }  else if isLandscape {
            let spacing: CGFloat = isMacCatalyst ? 0 : 16

            let stack =
                HStack(spacing: spacing) {
                    tunerCardView
                    railView(in: geo, isLandscape: true)
                }
                .padding(16)

            if shouldShowTunerContextRailMenu(isLandscape: isLandscape) {
                stack.contextMenu {
                    Toggle(isOn: Binding(get: { tunerRailStore.showRail }, set: tunerRailStore.setShowRail)) {
                        Label("Show Rail", systemImage: "sidebar.trailing")
                    }
                    Button {
                        app.openSettingsToTunerRail = true
                        showSettings = true
                    } label: {
                        Label("Customize…", systemImage: "slider.horizontal.3")
                    }
                }
            } else {
                stack
            }
        } else {
            VStack(spacing: 16) {
                tunerCardView
                railView(in: geo, isLandscape: false)
            }
            .padding(16)
        }
    }

    private var latticeContent: some View {
        LatticeScreen()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tunerCardView: some View {
        TunerCard(store: tunerStore, stageActive: $stageActive)
            .matchedGeometryEffect(id: "tunerHero", in: stageNS)
            .opacity(stageActive ? 0 : 1)
            .allowsHitTesting(!stageActive)   //  critical: don't let the invisible source eat taps
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func railView(in geo: GeometryProxy, isLandscape: Bool) -> some View {
        if shouldShowTunerContextRail(isLandscape: isLandscape) {
            TunerContextRailHost(
                store: tunerRailStore,
                app: app,
                tunerStore: tunerStore,
                showSettings: $showSettings,
                globalPrimeLimit: app.tunerPrimeLimit,
                globalAxisShift: latticeAxisShift,
                onLockTarget: { ref in
                    LearnEventBus.shared.send(.tunerTargetPicked("\(ref.p)/\(ref.q)"))
                    tunerStore.lockedTarget = RatioResult(num: ref.p, den: ref.q, octave: ref.octave)
                },
                onExportScale: { payload in
                    app.builderPayload = payload
                },
                onCustomize: {
                    app.openSettingsToTunerRail = true
                }
            )
            .opacity(stageActive ? 0 : 1)
            .allowsHitTesting(!stageActive)
        } else if isMacCatalyst {
            EmptyView()
        } else {
            RailView(showRootStudio: $showRootStudio, rootNS: rootNS)
                .frame(width: isLandscape ? min(400, geo.size.width * 0.34) : nil)
                .opacity(stageActive ? 0 : 1)
                .allowsHitTesting(!stageActive)
        }
    }

    private func updateIdleTimer(stageOn: Bool) {
        UIApplication.shared.isIdleTimerDisabled = (stageOn && stageKeepAwake)
    }

    private func updateIdleTimer(keepAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = (stageActive && keepAwake)
    }

    private func builderSheetDismiss() {
        LatticeStore().endStaging()
        app.builderPayload = nil
        app.builderSession.pendingAddRefs = nil
        app.setMicActive(mode == .tuner)
    }

    private func librarySheetDismiss() {
        app.setMicActive(mode == .tuner)
    }

    private func handleLearnDeepLink(_ destination: LearnTenneyDeepLinkDestination) {
        DiagnosticsCenter.shared.event(category: "learn", level: .info, message: "LearnDeepLink handled: \(destination.rawValue)")
        SentryService.shared.breadcrumb(category: "learn", message: "LearnDeepLink handled: \(destination.rawValue)")
        switch destination {
        case .libraryHome:
            app.scaleLibraryLaunchMode = .recents
            app.showScaleLibraryDetent = true
        case .communityPacks:
            app.scaleLibraryLaunchMode = .communityPacks
            app.showScaleLibraryDetent = true
        case .builderHome:
            app.builderPayload = ScaleBuilderPayload(
                rootHz: app.effectiveRootHz,
                primeLimit: app.tunerPrimeLimit,
                items: []
            )
        case .communityPackSubmission:
            openURL(CommunityPacksEndpoints.issuesURL)
        }
    }

    @ViewBuilder
    private func builderSheet<Payload>(payload: Payload, startInLibrary: Bool) -> some View {
        BuilderSheetView(payload: payload, startInLibrary: startInLibrary)
            .environmentObject(libraryStore)
    }

    private struct BuilderSheetView<Payload>: View {
        let payload: Payload
        let startInLibrary: Bool

        @EnvironmentObject private var app: AppModel
        @StateObject private var store: ScaleBuilderStore

        init(payload: Payload, startInLibrary: Bool) {
            self.payload = payload
            self.startInLibrary = startInLibrary
            _store = StateObject(wrappedValue: ScaleBuilderStore(payload: payload))
        }

        var body: some View {
            ScaleBuilderScreen(store: store)
                .onAppear {
                    app.setMicActive(false)
                    if startInLibrary {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NotificationCenter.default.post(name: .tenneyOpenLibraryInBuilder, object: nil)
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .tenneySheetSizing()
        }
    }


    // Stage overlay pulled out to keep type-checker happy
    @ViewBuilder private var stageOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .opacity(stageActive ? stageDimLevel : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.18), value: stageActive)
                let isLandscape = proxy.size.width > proxy.size.height

                let isPhoneLandscapeCompact = (!isMacCatalyst && UIDevice.current.userInterfaceIdiom == .phone && vSize == .compact)

                let stageMaxW: CGFloat = isPhoneLandscapeCompact ? (proxy.size.width - 24) : min((isLandscape ? 760 : 560), proxy.size.width - 32)

                let stagePad: CGFloat = isPhoneLandscapeCompact ? 12 : 16
                TunerCard(store: tunerStore, stageActive: $stageActive)
                    .matchedGeometryEffect(id: "tunerHeroStage", in: stageNS)
                    .frame(maxWidth: stageMaxW)
                    .padding(stagePad)
                    .opacity(stageActive ? 1 : 0)
                    .animation(.snappy, value: stageActive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(stageActive)
        .zIndex(50)
    }


    private var utilityBarInset: some View {
        UtilityBar(
            mode: $mode,
            showSettings: $showSettings,
            showRootStudio: $showRootStudio,
            rootNS: rootNS,
            defaultView: defaultView
        )
    }
    private var settingsSheet: some View {
        StudioConsoleView(initialCategory: requestedSettingsCategory)
            .environmentObject(tunerRailStore)
            .environmentObject(app)
            .statusBar(hidden: stageHideStatus && stageActive)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onDisappear {
                requestedSettingsCategory = nil
            }
            .tenneySheetSizing()
    }

    private var scaleLibraryDetent: some View {
        ScaleLibrarySheet()
            .environmentObject(libraryStore)
            .presentationDetents([.large], selection: .constant(.medium))
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .onAppear { app.setMicActive(false) }
            .tenneySheetSizing()
    }
    private var rootStudioDetent: some View {
        RootStudioSheet(tab: $rootStudioTab, ns: rootNS)
            .environmentObject(app)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .tenneySheetSizing()
    }

#if targetEnvironment(macCatalyst)
    private var macKeyboardShortcuts: some View {
        Group {
            Button(action: toggleRailShortcut) { EmptyView() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button(action: lockTargetShortcut) { EmptyView() }
                .keyboardShortcut("l", modifiers: .command)
            Button(action: captureShortcut) { EmptyView() }
                .keyboardShortcut(.return, modifiers: .command)
            Button(action: { switchAltShortcut(delta: -1) }) { EmptyView() }
                .keyboardShortcut("[", modifiers: .command)
            Button(action: { switchAltShortcut(delta: 1) }) { EmptyView() }
                .keyboardShortcut("]", modifiers: .command)
        }
        .frame(width: 0, height: 0)
    }

    private func toggleRailShortcut() {
        tunerRailStore.setShowRail(!tunerRailStore.showRail)
    }

    private func lockTargetShortcut() {
        let nearest = ratioResultFromText(app.display.ratioText)
        tunerStore.toggleLock(currentNearest: nearest)
    }

    private func captureShortcut() {
        tunerRailStore.captureCurrentSnapshot()
    }

    private func switchAltShortcut(delta: Int) {
        let targetText = delta < 0 ? app.display.lowerText : app.display.higherText
        guard !targetText.isEmpty, let ref = ratioResultFromText(targetText) else { return }
        LearnEventBus.shared.send(.tunerTargetPicked(targetText))
        tunerStore.lockedTarget = ref
    }
#endif

}

// MARK: - Liquid glass wrapper (iOS 26 look; good fallback earlier)
private struct LiquidGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

   



extension Notification.Name {
    static let tenneyBuilderDidFinish = Notification.Name("tenney.builder.didFinish")
        static let tenneyStepPadOctave = Notification.Name("tenney.stepPadOctave")
    static let tenneyOpenLibraryInBuilder = Notification.Name("tenney.open.library.in.builder")
}
private struct LiquidGlassArrival: ViewModifier {
    @State private var t: CGFloat = 0
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .scaleEffect(0.985 + 0.015 * t)               // subtle “thicken then settle”
                .shadow(radius: 24 - 12 * t, y: 6)
                .onAppear { withAnimation(.easeOut(duration: 0.25)) { t = 1 } }

        } else {
            content
        }
    }
}

extension Notification.Name {
    static let venueCalibrated = Notification.Name("tenney.venue.calibrated")
    
    static let tenneyOpenBuilderFromLatticeSelection =
        Notification.Name("tenney.openBuilder.fromLatticeSelection")

    /// Broadcast when SettingsView commits changes that other views should react to.
    static let settingsChanged = Notification.Name("tenney.settingsChanged")

    /// Step a pad's octave (or related "octave stepper" UI) by delta.
    /// userInfo: ["idx": Int, "delta": Int]
    
    static let tenneyOpenBuilderFromScaleLibrary = Notification.Name("tenney.openBuilder.fromScaleLibrary")
        static let tenneyAddScaleToBuilderFromLibrary = Notification.Name("tenney.addToBuilder.fromScaleLibrary")
        static let tenneyPreviewScaleFromLibrary = Notification.Name("tenney.previewScale.fromScaleLibrary")
    
}


 struct TunerCard: View {
    @AppStorage(SettingsKeys.staffA4Hz)  private var concertA4Hz: Double = 440
    @AppStorage(SettingsKeys.noteNameA4Hz) private var noteNameA4Hz: Double = 440
    @AppStorage(SettingsKeys.tonicNameMode) private var tonicNameModeRaw: String = TonicNameMode.auto.rawValue
    @AppStorage(SettingsKeys.tonicE3) private var tonicE3: Int = 0
    @AppStorage(SettingsKeys.accidentalPreference) private var accidentalPreferenceRaw: String = AccidentalPreference.auto.rawValue
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: TunerStore
    private var liveHz: Double { model.display.hz }
    private var liveCents: Double { model.display.cents }
    private var liveConf: Double { model.display.confidence }
    private var liveNearest: RatioResult? { ratioResultFromText(model.display.ratioText) }
    private var ratioDisplayText: String {
        store.lockedTarget.map { "\($0.num)/\($0.den)" } ?? model.display.ratioText
    }

    @StateObject private var hold = NeedleHoldState()
    @Namespace private var lockFieldNS
    @State private var currentNearest: RatioResult? = nil
    @State private var showLockSheet: Bool = false
    @State private var lockNumeratorText: String = ""
    @State private var lockDenominatorText: String = ""
    @State private var lockOctave: Int = 0
    @State private var lockPulse: Bool = false
    @State private var lockFieldDim: Bool = false
    @State private var wasLocked: Bool = false
    @Binding var stageActive: Bool

    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.learnGate) private var learnGate
     
    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }

    private var lockPreview: RatioResult? {
        ratioResultFromText(lockRatioText, octave: lockOctave)
    }

    private var lockRatioText: String {
        guard !lockNumeratorText.isEmpty || !lockDenominatorText.isEmpty else { return "" }
        return "\(lockNumeratorText)/\(lockDenominatorText)"
    }

    private var lockPillText: String? {
        if let locked = store.lockedTarget {
            return tunerDisplayRatioString(locked)
        }
        if let selected = store.selectedTarget {
            return tunerDisplayRatioString(selected)
        }
        return nil
    }

    private var lockButtonWidth: CGFloat { 136 }
    private var lockButtonSpacing: CGFloat { 10 }

    private var lockFieldMatchedGeometry: LockFieldMatchedGeometry? {
        guard !reduceMotion else { return nil }
        return LockFieldMatchedGeometry(
            namespace: lockFieldNS,
            backgroundID: "lockFieldBackground",
            ratioID: "lockFieldRatio"
        )
    }

    private var lockField: some View {
        let isLocked = store.lockedTarget != nil
        let tint = theme.inTuneHighlightColor(activeLimit: store.primeLimit)
        return LockPill(
            isLocked: isLocked,
            displayText: lockPillText,
            tint: tint,
            width: lockButtonWidth,
            matchedGeometry: lockFieldMatchedGeometry
        ) {
            showLockSheet = true
        }
        .opacity(lockFieldDim ? 0.6 : 1.0)
        .accessibilityLabel(isLocked ? "Locked target" : "Edit lock target")
    }

    private var hejiLabelText: AttributedString? {
        guard store.viewStyle != .posterFraction else { return nil }
        let pref = AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
        let mode = TonicNameMode(rawValue: tonicNameModeRaw) ?? .auto
        let tonic = effectiveTonicSpelling(
            rootHz: model.effectiveRootHz,
            noteNameA4Hz: noteNameA4Hz,
            tonicNameModeRaw: tonicNameModeRaw,
            tonicE3: tonicE3,
            accidentalPreference: pref
        ) ?? TonicSpelling(e3: tonicE3)
        let hejiPreference = (mode == .auto) ? pref : .auto
        let ratioHint = store.lockedTarget ?? liveNearest
        if let ratioHint {
            let ratioRef = RatioRef(p: ratioHint.num, q: ratioHint.den, octave: ratioHint.octave, monzo: [:])
            return spellHejiRatioDisplay(
                ratio: ratioRef,
                tonic: tonic,
                rootHz: model.effectiveRootHz,
                noteNameA4Hz: noteNameA4Hz,
                concertA4Hz: concertA4Hz,
                accidentalPreference: pref,
                maxPrime: max(3, store.primeLimit),
                allowApproximation: true,
                showCents: true,
                applyAccidentalPreference: mode == .auto
            )
        }
        let context = HejiContext(
            concertA4Hz: concertA4Hz,
            noteNameA4Hz: noteNameA4Hz,
            rootHz: model.effectiveRootHz,
            rootRatio: nil,
            preferred: hejiPreference,
            maxPrime: max(3, store.primeLimit),
            allowApproximation: true,
            scaleDegreeHint: nil,
            tonicE3: tonic.e3
        )
        let spelling = HejiNotation.spelling(forFrequency: liveHz, context: context)
        return HejiNotation.textLabel(
            spelling,
            showCents: true,
            textStyle: .footnote,
            weight: .semibold,
            design: .default
        )
    }

    private var prefersStackedHejiLabel: Bool {
        dynamicTypeSize.isAccessibilitySize && !isPhoneLandscapeCompact
    }

    private func hejiLabelView(_ label: AttributedString) -> some View {
        Text(label)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func hejiAnnotatedRow<Content: View>(
        hejiLabel: AttributedString?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let hejiLabel {
            if prefersStackedHejiLabel {
                VStack(alignment: .leading, spacing: 2) {
                    hejiLabelView(hejiLabel)
                    content()
                }
            } else {
                content()
                    .overlay(alignment: .topLeading) {
                        hejiLabelView(hejiLabel)
                            .offset(y: -16)
                    }
            }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func ratioReadoutRow(label: String, hejiLabel: AttributedString?) -> some View {
        let primes = label.split(separator: "/").flatMap { Int($0) }.flatMap { factors($0) }.filter { $0 > 2 }
        let showRatioText = store.viewStyle != .posterFraction
        hejiAnnotatedRow(hejiLabel: hejiLabel) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text(label)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .opacity(showRatioText ? 1 : 0)
                        .accessibilityHidden(!showRatioText)
                    HStack(spacing: 6) {
                        ForEach(Array(Set(primes)).sorted(), id: \.self) { p in
                            if theme.accessibilityEncoding.enabled {
                                TenneyPrimeLimitBadge(
                                    prime: p,
                                    tint: theme.primeTint(p),
                                    encoding: theme.accessibilityEncoding
                                )
                            } else {
                                BadgeCapsule(text: "\(p)", style: AnyShapeStyle(theme.primeTint(p)))
                            }
                        }
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(label)
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                            .opacity(showRatioText ? 1 : 0)
                            .accessibilityHidden(!showRatioText)
                        HStack(spacing: 6) {
                            ForEach(Array(Set(primes)).sorted(), id: \.self) { p in
                                if theme.accessibilityEncoding.enabled {
                                    TenneyPrimeLimitBadge(
                                        prime: p,
                                        tint: theme.primeTint(p),
                                        encoding: theme.accessibilityEncoding
                                    )
                                } else {
                                    BadgeCapsule(text: "\(p)", style: AnyShapeStyle(theme.primeTint(p)))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Spacer()
                    }
                }
            }
        }
    }
     
     @ViewBuilder
    private func tunerDial(
        centsShown: Double,
        liveConf: Double,
        stageAccent: Color,
        showFar: Bool,
        held: Bool,
        currentNearest: RatioResult?,
        liveNearest: RatioResult?
    ) -> some View {
         let ratioText = ratioDisplayText
         switch store.viewStyle {
         case .Gauge:
             Gauge(
                 cents: centsShown,
                 confidence: liveConf,
                 inTuneWindow: 5,
                 stageMode: store.stageMode,
                 mode: store.mode,
                 stageAccent: stageAccent,
                 showFarHint: showFar,
                 heldByConfidence: held,
                 farLabel: "Far",
                 isLocked: store.lockedTarget != nil,
                 lockAccent: stageAccent
             )

         case .chronoDial:
             ChronoDial(
                heldByConfidence: held,
                 cents: centsShown,
                 confidence: liveConf,
                 inTuneWindow: 5,
                 stageMode: store.stageMode,
                 accent: stageAccent
             )

         case .posterFraction:
             PosterFractionDial(
                 ratioText: ratioText,
                 centsShown: centsShown,
                 liveConf: liveConf,
                 inTuneWindow: 5,
                 threshold: 0.35,
                 stageAccent: stageAccent
             )
             // add back in when ready to test phasescope
     //    case .phaseScope:
     //        PhaseScopeTunerView(vm: model, store: store)
         }
     }

    @ViewBuilder
    private func tunerDialWithLockDecorations(
        centsShown: Double,
        rawCents: Double,
        liveHz: Double,
        liveConf: Double,
        stageAccent: Color,
        showFar: Bool,
        held: Bool,
        currentNearest: RatioResult?,
        liveNearest: RatioResult?
    ) -> some View {
        let isLocked = store.lockedTarget != nil
        let showsLockRing = isLocked && store.viewStyle != .Gauge
        ZStack {
            if showsLockRing && !reduceTransparency {
                lockHalo(accent: stageAccent)
            }
            tunerDial(
                centsShown: centsShown,
                liveConf: liveConf,
                stageAccent: stageAccent,
                showFar: showFar,
                held: held,
                currentNearest: currentNearest,
                liveNearest: liveNearest
            )
            .overlay {
                if isLocked,
                   store.viewStyle == .posterFraction,
                   liveHz.isFinite,
                   liveConf > 0.1,
                   rawCents.isFinite {
                    ExclusionEclipse(
                        cents: rawCents,
                        confidence: liveConf,
                        inTuneWindow: 5,
                        accent: stageAccent,
                        reduceMotion: reduceMotion,
                        reduceTransparency: reduceTransparency,
                        isDark: theme.isDark
                    )
                }
            }
            .overlay {
                if showsLockRing {
                    lockRing(accent: stageAccent)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    lockBadge(accent: stageAccent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func lockHalo(accent: Color) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            Circle()
                .fill(accent.opacity(theme.isDark ? 0.16 : 0.12))
                .frame(width: size + 30, height: size + 30)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .blur(radius: 18)
        }
        .allowsHitTesting(false)
    }

    private func lockRing(accent: Color) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            Circle()
                .stroke(accent.opacity(0.9), lineWidth: 3)
                .frame(width: size + 10, height: size + 10)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .scaleEffect(lockPulse ? 1.02 : 1.0)
        }
        .allowsHitTesting(false)
    }

    private struct ExclusionEclipse: View {
        let cents: Double
        let confidence: Double
        let inTuneWindow: Double
        let accent: Color
        let reduceMotion: Bool
        let reduceTransparency: Bool
        let isDark: Bool

        @State private var settlePulse = false

        var body: some View {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let clamped = clamp(cents, -50, 50)
                let distance = min(abs(clamped), 50)
                let isPerfect = abs(cents) <= inTuneWindow && confidence >= 0.35
                let baseScale = isPerfect ? 1.0 : scale(for: clamped)
                let settleScale = reduceMotion ? 1.0 : (settlePulse ? 1.02 : 1.0)
                let proximity = 1.0 - (distance / 50.0)
                let strongNear = easeOutCubic(proximity)
                let shift = yShift(for: distance, positive: clamped > 0)
                let (opacity, blur) = visualTuning(
                    distance: distance,
                    strongNear: strongNear,
                    isPerfect: isPerfect
                )
                let blend: BlendMode = isDark ? .difference : .exclusion

                ZStack {
                    if clamped < 0 {
                        Circle()
                            .fill(accent.opacity(fillOpacity(strongNear: strongNear, isPerfect: isPerfect)))
                            .overlay(
                                Circle()
                                    .stroke(accent.opacity(0.4), lineWidth: 1.0)
                            )
                    } else {
                        Circle()
                            .fill(accent.opacity(softFillOpacity(strongNear: strongNear, isPerfect: isPerfect)))
                            .overlay(
                                Circle()
                                    .stroke(
                                        accent.opacity(strokeOpacity(strongNear: strongNear, isPerfect: isPerfect)),
                                        lineWidth: strokeWidth(distance: distance)
                                    )
                            )
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .scaleEffect(baseScale * settleScale)
                .offset(y: shift)
                .blur(radius: blur)
                .opacity(opacity)
                .blendMode(reduceTransparency ? .normal : blend)
                .compositingGroup()
            }
            .allowsHitTesting(false)
            .onChange(of: abs(cents) <= inTuneWindow && confidence >= 0.35) { isPerfect in
                guard isPerfect, !reduceMotion else { return }
                settlePulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    settlePulse = false
                }
            }
        }

        private func scale(for cents: Double) -> Double {
            if cents < 0 {
                let t = clamp(-cents / 50.0, 0, 1)
                let eased = easeOutCubic(t)
                return lerp(1.0, 0.12, eased)
            } else {
                let t = clamp(cents / 50.0, 0, 1)
                let eased = easeInOutCubic(t)
                return lerp(1.0, 1.28, eased)
            }
        }

        private func yShift(for distance: Double, positive: Bool) -> Double {
            let t = clamp(distance / 50.0, 0, 1)
            let eased = easeOutCubic(t)
            let shift = lerp(0.0, 4.0, eased)
            return positive ? -shift : shift
        }

        private func visualTuning(distance: Double, strongNear: Double, isPerfect: Bool) -> (Double, Double) {
            var opacity = 0.55 + (0.4 * strongNear)
            var blur = (1.0 - strongNear) * 3.5

            if distance > 35 {
                opacity *= 0.78
                blur += 1.5
            }

            if isPerfect {
                opacity = reduceTransparency ? 0.9 : 1.0
                blur = reduceTransparency ? 0.6 : 0.0
            }

            if reduceTransparency {
                blur = min(blur, 1.0)
                opacity = max(min(opacity, 0.95), 0.65)
            }

            return (opacity, blur)
        }

        private func fillOpacity(strongNear: Double, isPerfect: Bool) -> Double {
            if isPerfect { return reduceTransparency ? 0.9 : 0.98 }
            return 0.65 + (0.25 * strongNear)
        }

        private func softFillOpacity(strongNear: Double, isPerfect: Bool) -> Double {
            if isPerfect { return reduceTransparency ? 0.45 : 0.35 }
            return 0.12 + (0.1 * strongNear)
        }

        private func strokeOpacity(strongNear: Double, isPerfect: Bool) -> Double {
            if isPerfect { return reduceTransparency ? 0.9 : 0.95 }
            return 0.6 + (0.25 * strongNear)
        }

        private func strokeWidth(distance: Double) -> Double {
            let t = clamp(distance / 50.0, 0, 1)
            return lerp(2.0, 3.5, t)
        }

        private func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
            min(max(value, minValue), maxValue)
        }

        private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
            a + (b - a) * t
        }

        private func easeOutCubic(_ t: Double) -> Double {
            let clamped = clamp(t, 0, 1)
            return 1 - pow(1 - clamped, 3)
        }

        private func easeInOutCubic(_ t: Double) -> Double {
            let clamped = clamp(t, 0, 1)
            if clamped < 0.5 {
                return 4 * clamped * clamped * clamped
            } else {
                return 1 - pow(-2 * clamped + 2, 3) / 2
            }
        }
    }

    private func lockBadge(accent: Color) -> some View {
        ZStack {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: .circle)
            } else {
                Circle().fill(.ultraThinMaterial)
            }
            Image(systemName: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 30, height: 30)
        .overlay(
            Circle()
                .strokeBorder(accent.opacity(0.6), lineWidth: 1)
        )
        .padding(8)
        .accessibilityLabel("Locked target")
    }

    private func toggleDialLock(currentNearest: RatioResult?) {
        let wasLocked = store.lockedTarget != nil
        store.toggleLock(currentNearest: currentNearest)

        if !wasLocked, store.lockedTarget != nil {
            #if os(iOS) && !targetEnvironment(macCatalyst)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }

        #if DEBUG
        let hunting = currentNearest.map { tunerDisplayRatioString($0) } ?? "—"
        let locked = store.lockedTarget.map { tunerDisplayRatioString($0) } ?? "—"
        let effective = (store.lockedTarget ?? currentNearest).map { tunerDisplayRatioString($0) } ?? "—"
        print("[Tuner] dial lock toggle: locked=\(locked) hunting=\(hunting) effective=\(effective)")
        #endif
    }

    private func prepareLockSheetDefaults() {
        if let locked = store.lockedTarget {
            lockNumeratorText = "\(locked.num)"
            lockDenominatorText = "\(locked.den)"
            lockOctave = locked.octave
        } else if let selected = store.selectedTarget {
            lockNumeratorText = "\(selected.num)"
            lockDenominatorText = "\(selected.den)"
            lockOctave = selected.octave
        } else if let nearest = (currentNearest ?? liveNearest) {
            lockNumeratorText = "\(nearest.num)"
            lockDenominatorText = "\(nearest.den)"
            lockOctave = nearest.octave
        } else {
            lockNumeratorText = ""
            lockDenominatorText = ""
            lockOctave = 0
        }
    }

    private func commitLockFromSheet(_ target: RatioResult) {
        store.selectedTarget = target
        store.lockedTarget = target
        #if DEBUG
        let hunting = (currentNearest ?? liveNearest).map { tunerDisplayRatioString($0) } ?? "—"
        let effective = tunerDisplayRatioString(target)
        print("[Tuner] sheet lock: locked=\(effective) hunting=\(hunting) effective=\(effective)")
        #endif
        showLockSheet = false
    }

    private func setTargetFromSheet(_ target: RatioResult) {
        store.selectedTarget = target
        store.lockedTarget = nil
        store.addRecent(target)
        #if DEBUG
        let hunting = (currentNearest ?? liveNearest).map { tunerDisplayRatioString($0) } ?? "—"
        let effective = tunerDisplayRatioString(target)
        print("[Tuner] sheet set: locked=— selected=\(effective) hunting=\(hunting)")
        #endif
        showLockSheet = false
    }

    private func unlockFromSheet() {
        store.lockedTarget = nil
        #if DEBUG
        let hunting = (currentNearest ?? liveNearest).map { tunerDisplayRatioString($0) } ?? "—"
        print("[Tuner] sheet unlock: locked=— hunting=\(hunting) effective=\(hunting)")
        #endif
        showLockSheet = false
    }

    private func pulseLockRingIfNeeded() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.12)) { lockPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.12)) { lockPulse = false }
        }
    }


    private func centsVsLocked(_ locked: RatioResult?, hz: Double, root: Double) -> Double {
        guard let t = locked, hz.isFinite else { return model.display.cents }
        let targetHz = root * pow(2.0, Double(t.octave)) * (Double(t.num)/Double(t.den))
        return 1200.0 * log2(hz / targetHz)
    }
     private var stageButton: some View {
         Button {
             let newValue = !stageActive
             withAnimation(.snappy) { stageActive = newValue }
             LearnEventBus.shared.send(.tunerStageModeChanged(newValue))
         } label: {
             HStack(spacing: 6) {
                Image(systemName: stageActive ? "theatermasks.fill" : "theatermasks")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(
                        stageActive
                        ? accentStyle
                        : AnyShapeStyle(Color.secondary)
                    )
                    .blendMode(stageActive ? (theme.isDark ? .screen : .darken) : .normal)

                 Text("Stage")
                     .font(.footnote.weight(.semibold))
                     .foregroundStyle(
                         stageActive
                         ? (theme.isDark ? Color.white : Color.black)
                         : Color.secondary
                     )

                 if store.lockedTarget != nil {
                     Image(systemName: "lock.fill")
                         .font(.caption2.weight(.semibold))
                         .foregroundStyle(.secondary)
                         .transition(.opacity)
                 }
             }
             .padding(.horizontal, 10)
             .padding(.vertical, 6)
             .background(
                 stageActive
                 ? AnyShapeStyle(.thinMaterial)
                 : AnyShapeStyle(.ultraThinMaterial),
                 in: Capsule()
             )
            .overlay(
                Capsule().stroke(
                    stageActive
                    ? accentStyle
                    : AnyShapeStyle(Color.secondary.opacity(0.12)),
                    lineWidth: 1
                )
            )
             .contentTransition(.symbolEffect(.replace.downUp))
             .symbolEffect(.bounce, value: stageActive)
         }
         .buttonStyle(.plain)
         .accessibilityLabel("Stage Mode")
         .accessibilityHint("Boosts contrast, thicker strobe, calmer text motion for performance.")
         .learnTarget(id: "tuner_stage_mode")
         .gated("tuner_stage_mode", gate: learnGate)
     }

     private var isPhoneLandscapeCompact: Bool {
     #if targetEnvironment(macCatalyst)
             return false
     #else
             return (UIDevice.current.userInterfaceIdiom == .phone && vSize == .compact)
     #endif
         }
     
        var body: some View {
            GlassCard(corner: 20) {
                if isPhoneLandscapeCompact {
                    landscapeBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)   // ← add
                } else {
                    portraitBody
                }
            }
            .onChange(of: store.lockedTarget) { newValue in
                if newValue != nil {
                    pulseLockRingIfNeeded()
                }
                if wasLocked, newValue == nil {
                    withAnimation(.easeOut(duration: 0.18)) { lockFieldDim = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(.easeOut(duration: 0.18)) { lockFieldDim = false }
                    }
                }
                wasLocked = (newValue != nil)
            }
            .onChange(of: showLockSheet) { isPresented in
                if isPresented {
                    prepareLockSheetDefaults()
                }
            }
            .sheet(isPresented: $showLockSheet) {
                LockTargetSheet(
                    numeratorText: $lockNumeratorText,
                    denominatorText: $lockDenominatorText,
                    octave: $lockOctave,
                    lockedTarget: store.lockedTarget,
                    currentNearest: currentNearest ?? liveNearest,
                    lowerText: model.display.lowerText,
                    higherText: model.display.higherText,
                    recents: store.lockRecents,
                    rootHz: model.effectiveRootHz,
                    liveHz: liveHz,
                    tint: theme.inTuneHighlightColor(activeLimit: store.primeLimit),
                    matchedGeometry: lockFieldMatchedGeometry,
                    onCancel: { showLockSheet = false },
                    onUnlock: { unlockFromSheet() },
                    onSet: { target in setTargetFromSheet(target) },
                    onCommit: { target in commitLockFromSheet(target) },
                    onRemoveRecent: { target in store.removeRecent(target) },
                    onClearRecents: { store.clearRecents() }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
     
         private var portraitBody: some View {
             let dialSlotMinHeight: CGFloat = 320
             return VStack(spacing: 14) {

                 // Header row: Mode glyph strip (left) • Style strip • Stage toggle (right)
                ViewThatFits(in: .horizontal) {

                    // ✅ Preferred (fits on wider devices)
                    HStack {
                        TunerModeStrip(mode: $store.mode)
                            .gated("tuner_mode", gate: learnGate)
                        TunerViewStyleStrip(
                            style: Binding(
                                get: { store.viewStyle },
                                set: { store.viewStyle = $0 }
                            )
                        )
                        .learnTarget(id: "tuner_view_switch")
                        .gated("tuner_view_switch", gate: learnGate)

                        Spacer()
                        stageButton
                    }

                    // ✅ Fallback (narrow widths): two-line header
                    VStack(spacing: 10) {
                        HStack {
                            TunerModeStrip(mode: $store.mode)
                                .gated("tuner_mode", gate: learnGate)
                            Spacer()
                            stageButton
                        }

                        HStack {
                            TunerViewStyleStrip(
                                style: Binding(
                                    get: { store.viewStyle },
                                    set: { store.viewStyle = $0 }
                                )
                            )
                            .learnTarget(id: "tuner_view_switch")
                            .gated("tuner_view_switch", gate: learnGate)
                            Spacer()
                        }
                    }
                }



                // Chrono dial (rectangular card contains it)
                let rawCents: Double = {
                    if let locked = store.lockedTarget {
                        return signedCents(actualHz: liveHz, rootHz: model.effectiveRootHz, target: locked)
                    } else {
                        return liveCents
                    }
                }()

                let (centsShown, held) = hold.output(
                    rawCents: rawCents,
                    confidence: liveConf,
                    mode: store.needleHoldMode,
                    threshold: 0.35
                )

                let showFar = abs(rawCents) > 120

                let stageAccent: Color = theme.inTuneHighlightColor(activeLimit: store.primeLimit)

                tunerDialWithLockDecorations(
                    centsShown: centsShown,
                    rawCents: rawCents,
                    liveHz: liveHz,
                    liveConf: liveConf,
                    stageAccent: stageAccent,
                    showFar: showFar,
                    held: held,
                    currentNearest: currentNearest,
                    liveNearest: liveNearest
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: dialSlotMinHeight)
                .layoutPriority(1)
                // add back in when ready to test phasescope
                          //      .frame(
                           //         minHeight: 260,
                             //       idealHeight: (store.viewStyle == .phaseScope ? 300 : 320),
                               //     maxHeight: (store.viewStyle == .phaseScope ? 360 : nil)
                              //  )
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.35) {
                    toggleDialLock(currentNearest: (currentNearest ?? liveNearest))
                }
                .learnTarget(id: "tuner_lock")
                .gated("tuner_lock", gate: learnGate)

                // Complications (12/3/6/9 o’clock grammar)
                VStack(spacing: 8) {
                    // 12 o’clock: Ratio + prime badges
                    let label = ratioDisplayText
                    ratioReadoutRow(label: label, hejiLabel: hejiLabelText)
                    // 3 & 6 o’clock: ET cents and JI delta (mode-aware)
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            StatTile(label: "ET", value: model.display.cents.isFinite ? String(format: "%+.1f¢", model.display.cents) : "—")
                            if store.mode == .live, store.lockedTarget == nil {
                                StatTile(label: "vs JI", value: String(format: "%+.1f¢", model.display.cents))
                            } else if let lock = store.lockedTarget {
                                let vsValue: String = {
                                    guard rawCents.isFinite else { return "—" }
                                    if rawCents < -200 { return "LOW" }
                                    if rawCents >  200 { return "HIGH" }
                                    return String(format: "%+.1f¢", centsShown)
                                }()
                                StatTile(label: "vs \(lock.num)/\(lock.den)", value: vsValue)
                            }
                        } // .strict hides the extra JI label by design
                        .contentShape(Rectangle())
                        .onTapGesture {
                            LearnEventBus.shared.send(.tunerETJIDidInteract)
                        }
                        .learnTarget(id: "tuner_et_ji")
                        .gated("tuner_et_ji", gate: learnGate)
                        Spacer()
                        StatTile(label: "Hz", value: String(format: "%.1f", model.display.hz))
                        StatTile(label: "Conf", value: String(format: "%.0f%%", model.display.confidence*100))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                LearnEventBus.shared.send(.tunerConfidenceInteracted)
                            }
                            .learnTarget(id: "tuner_confidence")
                            .gated("tuner_confidence", gate: learnGate)
                    }

                    // 9 o’clock: suggestions (tap to lock)
                    if !(model.display.lowerText.isEmpty && model.display.higherText.isEmpty) {
                        HStack {
                            NextChip(title: "Lower",  text: model.display.lowerText)
                                .onTapGesture {
                                    if let r = ratioResultFromText(model.display.lowerText) {
                                        LearnEventBus.shared.send(.tunerTargetPicked(model.display.lowerText))
                                        store.lockedTarget = r
                                    }
                                }
                                .gated("tuner_target", gate: learnGate)
                            Spacer(minLength: 12)
                            NextChip(title: "Higher", text: model.display.higherText)
                                .onTapGesture {
                                    if let r = ratioResultFromText(model.display.higherText) {
                                        LearnEventBus.shared.send(.tunerTargetPicked(model.display.higherText))
                                        store.lockedTarget = r
                                    }
                                }
                                .gated("tuner_target", gate: learnGate)
                        }
                        .transition(.opacity)
                    }
                }
                .onChange(of: model.display.ratioText) { txt in
                    currentNearest = ratioResultFromText(txt) // for long-press locking
                }

                // Tuner-local prime limit chips (walled off)
                ZStack(alignment: .trailing) {
                    HStack(spacing: 8) {
                        Text("Limit").font(.caption).foregroundStyle(.secondary)
                        ForEach([3,5,7,11,13], id:\.self) { p in
                            let selected = (store.primeLimit == p)
                            if theme.accessibilityEncoding.enabled {
                                TenneyPrimeLimitChip(
                                    prime: p,
                                    isOn: selected,
                                    tint: theme.primeTint(p),
                                    encoding: theme.accessibilityEncoding
                                ) {
                                    withAnimation(.snappy) { store.primeLimit = p }
                                }
                            } else {
                                Button {
                                    withAnimation(.snappy) { store.primeLimit = p }
                                } label: {
                                    Text("\(p)")
                                        .font(.footnote.weight(selected ? .semibold : .regular))
                                        .foregroundStyle(
                                            selected
                                            ? (theme.isDark ? Color.white : Color.black)
                                            : Color.secondary
                                        )
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            selected
                                            ? AnyShapeStyle(.thinMaterial)
                                            : AnyShapeStyle(.ultraThinMaterial),
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule().stroke(
                                                selected
                                                ? AnyShapeStyle(theme.primeTint(p))
                                                : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                                lineWidth: 1
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }
                    .padding(.trailing, lockButtonWidth + lockButtonSpacing)

                    lockField
                        .frame(width: lockButtonWidth)
                }
                .padding(.top, 4)
                .learnTarget(id: "tuner_prime_limit")
                .gated("tuner_prime_limit", gate: learnGate)
                .onChange(of: store.primeLimit) { model.tunerPrimeLimit = $0 }
                .onAppear { store.primeLimit = model.tunerPrimeLimit }

            }
         }

    // iPhone landscape (compact vertical): dial left, metrics right — single card.
    private var landscapeBody: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padH: CGFloat = 0
            let padV: CGFloat = 0
            let spacing: CGFloat = 12
            let innerW = max(0, w - padH*2)
            let innerH = max(0, h - padV*2)

            let minDial: CGFloat = 290
                        let rightW: CGFloat = max(180, min(300, innerW - minDial - spacing))
                        let dialAvailW = max(0, innerW - rightW - spacing)
                        let dialSize = max(0, min(innerH, dialAvailW))

            // Match portrait semantics (lock-aware cents + needle hold).
            let rawCents: Double = {
                if let locked = store.lockedTarget {
                    return signedCents(actualHz: liveHz, rootHz: model.effectiveRootHz, target: locked)
                } else {
                    return liveCents
                }
            }()

            let (centsShown, held) = hold.output(
                rawCents: rawCents,
                confidence: liveConf,
                mode: store.needleHoldMode,
                threshold: 0.35
            )

            let showFar = abs(rawCents) > 120
            let stageAccent: Color = theme.inTuneHighlightColor(activeLimit: store.primeLimit)

            let vsValue: String = {
                guard store.lockedTarget != nil, rawCents.isFinite else {
                    return String(format: "%+.1f", centsShown)
                }
                if rawCents < -200 { return "LOW" }
                if rawCents >  200 { return "HIGH" }
                return String(format: "%+.1f", centsShown)
            }()
            
            let centsLabel: String = {
                if let lock = store.lockedTarget { return "vs \(lock.num)/\(lock.den)" }
                return (model.strictness == .strict ? "ET" : "JI")
            }()

            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: 10) {
                                    ZStack(alignment: .bottomLeading) {
                                        tunerDialWithLockDecorations(
                                            centsShown: centsShown,
                                            rawCents: rawCents,
                                            liveHz: liveHz,
                                            liveConf: liveConf,
                                            stageAccent: stageAccent,
                                            showFar: showFar,
                                            held: held,
                                            currentNearest: currentNearest,
                                            liveNearest: liveNearest
                                        )
                                        .frame(width: dialSize, height: dialSize)
                                        .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.35) {
                        toggleDialLock(currentNearest: (currentNearest ?? liveNearest))
                    }
                    .learnTarget(id: "tuner_lock")
                    .gated("tuner_lock", gate: learnGate)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 18, coordinateSpace: .local)
                            .onEnded { v in
                                let dx = v.translation.width
                                let dy = v.translation.height
                                guard dy < -32, abs(dx) < 80 else { return }
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                stepTargetOnSwipeUp()
                            }
                    )
                    .onChange(of: model.display.ratioText) { txt in
                        currentNearest = ratioResultFromText(txt)
                    }

// Prime limit chips (still “under” the dial visually),
                        // but they no longer constrain the dial’s size.
                        ViewThatFits(in: .horizontal) {
                            ZStack(alignment: .trailing) {
                                HStack(spacing: 8) {
                                    Text("Limit").font(.caption).foregroundStyle(.secondary)
                                    ForEach([3,5,7,11,13], id:\.self) { p in
                                        let selected = (store.primeLimit == p)
                                        if theme.accessibilityEncoding.enabled {
                                            TenneyPrimeLimitChip(
                                                prime: p,
                                                isOn: selected,
                                                tint: theme.primeTint(p),
                                                encoding: theme.accessibilityEncoding
                                            ) {
                                                withAnimation(.snappy) { store.primeLimit = p }
                                            }
                                        } else {
                                            Button {
                                                withAnimation(.snappy) { store.primeLimit = p }
                                            } label: {
                                                Text("\(p)")
                                                    .font(.footnote.weight(selected ? .semibold : .regular))
                                                    .foregroundStyle(selected ? (theme.isDark ? .white : .black) : .secondary)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 5)
                                                    .background(selected ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                                                    .overlay(
                                                        Capsule().stroke(
                                                            selected ? AnyShapeStyle(theme.primeTint(p)) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                                            lineWidth: 1
                                                        )
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.trailing, lockButtonWidth + lockButtonSpacing)

                                lockField
                                    .frame(width: lockButtonWidth)
                            }
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .learnTarget(id: "tuner_prime_limit")
                            .gated("tuner_prime_limit", gate: learnGate)
                        }
                        .padding(8)
                        .onChange(of: store.primeLimit) { model.tunerPrimeLimit = $0 }
                        .onAppear { store.primeLimit = model.tunerPrimeLimit }
                    }
                }
                .frame(width: dialSize, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(x: 36)
                
                Spacer(minLength: 0)


                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer()
                        stageButton
                            .offset(x: -24)
                            .offset(y: 12)
                    }

                    let ratioLabel = ratioDisplayText
                    ratioReadoutRow(label: ratioLabel, hejiLabel: hejiLabelText)

                    HStack(spacing: 10) {
                        StatTile(label: centsLabel,
                                 value: (store.lockedTarget != nil ? vsValue : String(format: "%+.1f", centsShown)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                LearnEventBus.shared.send(.tunerETJIDidInteract)
                            }
                            .learnTarget(id: "tuner_et_ji")
                            .gated("tuner_et_ji", gate: learnGate)
                        StatTile(label: "Hz", value: String(format: "%.1f", liveHz))
                    }

                    StatTile(label: "Conf", value: String(format: "%.0f%%", liveConf*100))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            LearnEventBus.shared.send(.tunerConfidenceInteracted)
                        }
                        .learnTarget(id: "tuner_confidence")
                        .gated("tuner_confidence", gate: learnGate)

                    HStack(spacing: 10) {
                        NextChip(title: "Lower",  text: model.display.lowerText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                if let r = ratioResultFromText(model.display.lowerText) {
                                    LearnEventBus.shared.send(.tunerTargetPicked(model.display.lowerText))
                                    withAnimation(.snappy) { store.lockedTarget = r }
                                }
                            }
                            .gated("tuner_target", gate: learnGate)

                        NextChip(title: "Higher", text: model.display.higherText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                if let r = ratioResultFromText(model.display.higherText) {
                                    LearnEventBus.shared.send(.tunerTargetPicked(model.display.higherText))
                                    withAnimation(.snappy) { store.lockedTarget = r }
                                }
                            }
                            .gated("tuner_target", gate: learnGate)
                    }

                    Spacer(minLength: 0)
                    
                }
                .frame(width: rightW, alignment: .topLeading)
                
            }
            
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            
        }
    }

    private func stepTargetOnSwipeUp() {
        let lower = ratioResultFromText(model.display.lowerText)
        let higher = ratioResultFromText(model.display.higherText)

        withAnimation(.snappy) {
            if let locked = store.lockedTarget, let h = higher, locked == h, let l = lower {
                store.lockedTarget = l
            } else if let h = higher {
                store.lockedTarget = h
            } else if let l = lower {
                store.lockedTarget = l
            } else {
                store.toggleLock(currentNearest: (currentNearest ?? liveNearest))
            }
        }
    }
}

// Tiny helpers (local to ContentView)
private func factors(_ n: Int) -> [Int] {
    var x = n, p = 2, out: [Int] = []
    while p*p <= x { while x % p == 0 { out.append(p); x /= p } ; p += 1 }
    if x > 1 { out.append(x) }
    return out
}

private func currentTonicSpelling(
    modeRaw: String,
    manualE3: Int,
    rootHz: Double,
    noteNameA4Hz: Double,
    accidentalPreferenceRaw: String
) -> TonicSpelling {
    let preference = AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
    return effectiveTonicSpelling(
        rootHz: rootHz,
        noteNameA4Hz: noteNameA4Hz,
        tonicNameModeRaw: modeRaw,
        tonicE3: manualE3,
        accidentalPreference: preference
    ) ?? TonicSpelling(e3: manualE3)
}

private func currentTonicDisplayName(
    modeRaw: String,
    manualE3: Int,
    rootHz: Double,
    noteNameA4Hz: Double,
    accidentalPreferenceRaw: String,
    textStyle: Font.TextStyle = .caption2,
    weight: Font.Weight = .semibold
) -> AttributedString {
    currentTonicSpelling(
        modeRaw: modeRaw,
        manualE3: manualE3,
        rootHz: rootHz,
        noteNameA4Hz: noteNameA4Hz,
        accidentalPreferenceRaw: accidentalPreferenceRaw
    ).attributedDisplayText(textStyle: textStyle, weight: weight, design: .default)
}

private struct RailView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showRootStudio: Bool
    let rootNS: Namespace.ID
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RootCardCompact(ns: rootNS, showSheet: $showRootStudio)
         //   StrictnessCard()
        //    TestToneCard()
            if model.micPermission == .denied {
                GlassCard { Text("Microphone access denied. Enable in Settings → Privacy → Microphone.").foregroundStyle(.red) }
            }
            Spacer()
        }
    }
}

private struct UtilityBar: View {

    @EnvironmentObject private var app: AppModel
    @AppStorage(SettingsKeys.noteNameA4Hz) private var noteNameA4Hz: Double = 440
    @AppStorage(SettingsKeys.tonicNameMode) private var tonicNameModeRaw: String = TonicNameMode.auto.rawValue
    @AppStorage(SettingsKeys.tonicE3) private var tonicE3: Int = 0
    @AppStorage(SettingsKeys.accidentalPreference) private var accidentalPreferenceRaw: String = AccidentalPreference.auto.rawValue
    @Binding var mode: AppScreenMode
    @Binding var showSettings: Bool
    @Binding var showRootStudio: Bool
    let rootNS: Namespace.ID
    /// Reorders the segmented picker so the user's default view appears on the **left**.
    let defaultView: String

    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.tenneyPracticeActive) private var practiceActive
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    @Namespace private var modeSwitchNS
    @Namespace private var auditionNS
    
    @Namespace private var rootChipNS

    private let rootCorner: CGFloat = 12
    @State private var rootFeedbackToken: Int = 0

    private func setRootHz(_ hz: Double) {
        // clamp if you have preferred bounds; otherwise keep as-is
        withAnimation(.snappy(duration: 0.18)) {
            app.rootHz = hz
        }
    }

    private func nudgeRootHz(_ delta: Double) {
        setRootHz(app.rootHz + delta)
    }


    private struct ModeTab: Identifiable, Hashable {
        let mode: AppScreenMode
        let title: String
        let icon: String
        var id: AppScreenMode { mode }   //  stable
    }

    private var modeTabs: [ModeTab] {
        let lattice = ModeTab(mode: .lattice, title: "Lattice", icon: "point.3.connected.trianglepath.dotted")
        let tuner  = ModeTab(mode: .tuner,  title: "Tuner",  icon: "waveform")
        return (defaultView == "lattice") ? [lattice, tuner] : [tuner, lattice]
    }

    private var rootValueText: some View {
        Text(String(format: "%.1f", app.rootHz))
            .font(.footnote.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .contentTransition(.numericText())
    }

    private func rootValueTextMaybeHero() -> some View {
        Group {
            if showRootStudio {
                rootValueText
                    .matchedGeometryEffect(id: "rootValue", in: rootNS, isSource: true)
            } else {
                rootValueText
            }
        }
    }

    @ViewBuilder
    private func rootChipBackground(isEditing: Bool) -> some View {
        let rr = RoundedRectangle(cornerRadius: rootCorner, style: .continuous)

        if #available(iOS 26.0, *) {
            // single layer: glass (no stacking)
            Color.clear
                .glassEffect(.regular, in: rr)
        } else {
            rr.fill(.ultraThinMaterial)
        }
    }

    private func rootChipStroke(isEditing: Bool) -> some View {
        let rr = RoundedRectangle(cornerRadius: rootCorner, style: .continuous)

        return rr
            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            .overlay(
                rr.stroke(Color.accentColor.opacity(isEditing ? 0.22 : 0.0), lineWidth: 1)
            )
    }

    private var rootChipLabel: some View {
        ViewThatFits(in: .horizontal) {
            // Full: icon + value + Hz + chevrons
            HStack(spacing: 6) {
                Image(systemName: "tuningfork")
                    .symbolRenderingMode(.hierarchical)
                    .font(.footnote.weight(.semibold))

                HStack(spacing: 3) {
                    rootValueTextMaybeHero()
                    tonicNameLabel
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            // Medium: icon + value(+Hz)
            HStack(spacing: 6) {
                Image(systemName: "tuningfork")
                    .symbolRenderingMode(.hierarchical)
                    .font(.footnote.weight(.semibold))

                HStack(spacing: 3) {
                    rootValueTextMaybeHero()
                    tonicNameLabel
                        .foregroundStyle(.secondary)
                }
            }

            // Compact: value + tonic
            HStack(spacing: 3) {
                rootValueTextMaybeHero()
                tonicNameLabel
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .allowsTightening(true)
    }

    private var tonicNameLabel: some View {
        Text(currentTonicDisplayName(
            modeRaw: tonicNameModeRaw,
            manualE3: tonicE3,
            rootHz: app.rootHz,
            noteNameA4Hz: noteNameA4Hz,
            accidentalPreferenceRaw: accidentalPreferenceRaw,
            textStyle: .caption2,
            weight: .semibold
        ))
        .frame(minWidth: 34, alignment: .center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .allowsTightening(true)
    }


    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }
    
    private var rimStroke: Color {
        Color.primary.opacity(theme.isDark ? 0.22 : 0.16)
    }

    private var rimStrokeMuted: Color {
        Color.secondary.opacity(theme.isDark ? 0.18 : 0.14)
    }

    private func auditionPillLabel(on: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            // Full
            HStack(spacing: 8) {
                auditionIcon(on: on)
                Text("Audition")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .lineLimit(1)

                auditionThumb(on: on)
            }

            // Compact (tight bars): icon + thumb only
            HStack(spacing: 8) {
                auditionIcon(on: on)
                auditionThumb(on: on)
            }
        }
    }

    private func auditionIcon(on: Bool) -> some View {
        Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
            .symbolRenderingMode(.hierarchical)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(on ? accentStyle : AnyShapeStyle(Color.secondary))
            .contentTransition(.symbolEffect(.replace.downUp.byLayer))
    }

    private func auditionThumb(on: Bool) -> some View {
        let trackW: CGFloat = 34
        let trackH: CGFloat = 20
        let knob: CGFloat = 18

        return ZStack {
            Capsule()
                .fill(on ? .thinMaterial : .ultraThinMaterial)

            HStack(spacing: 0) {
                if on { Spacer(minLength: 0) }
                Circle()
                    .fill(.thinMaterial)
                    .overlay(
                        Circle().stroke(on ? rimStroke : rimStrokeMuted, lineWidth: 1)
                    )
                    .frame(width: knob, height: knob)
                    .matchedGeometryEffect(id: "audition-knob", in: auditionNS)
                if !on { Spacer(minLength: 0) }
            }
            .padding(1)
        }
        .frame(width: trackW, height: trackH)
        .overlay(Capsule().stroke(on ? rimStroke : rimStrokeMuted, lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func auditionChrome(on: Bool) -> some View {
        ZStack {
            // OFF layer
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(rimStrokeMuted, lineWidth: 1))
                .opacity(on ? 0 : 1)

            // ON layer (energized)
            Capsule()
                .fill(theme.isDark ? .thinMaterial : .regularMaterial)
                .overlay(Capsule().stroke(rimStroke, lineWidth: 1))
                .shadow(color: Color.black.opacity(theme.isDark ? 0.0 : 0.10), radius: 1, x: 0, y: 1)
                .opacity(on ? 1 : 0)
        }
    }

    private var tunerStatusText: String {
        if !app.pipelineWanted { return "Tuner off" }
        if app.micPermission == .denied { return "Mic denied" }
        if app.pipelineInterrupted { return "Tuner paused" }
        if app.pipelineActive { return "Tuner active" }
        return app.micPermission == .granted ? "Recovering" : "Initializing"
    }

    private var tunerStatusIcon: String {
        if !app.pipelineWanted { return "waveform.slash" }
        if app.micPermission == .denied { return "exclamationmark.triangle.fill" }
        if app.pipelineInterrupted { return "pause.circle.fill" }
        if app.pipelineActive { return "dot.radiowaves.left.and.right" }
        return "waveform"
    }

    private var modeSwitch: some View {
        HStack(spacing: 6) {
            ForEach(modeTabs) { tab in
                modeTabButton(tab)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .animation(.snappy(duration: 0.28), value: mode)
    }

    private func modeTabButton(_ tab: ModeTab) -> some View {
        let selected = (mode == tab.mode)

        return Button {
            withAnimation(.snappy(duration: 0.28)) { mode = tab.mode }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .imageScale(.medium)
                    .font(.footnote.weight(.semibold))

                if selected {
                    Text(tab.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.vertical, 7)
            .padding(.horizontal, selected ? 12 : 10)    // ✅ selected gets more width
            .background {
                if selected {
                    Capsule()
                        .fill(.thinMaterial)
                        .matchedGeometryEffect(id: "mode-pill", in: modeSwitchNS)
                        .allowsHitTesting(false)          // ✅ pill never steals taps
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }



    var body: some View {
        HStack {
            if practiceActive {
                HStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill").imageScale(.medium)
                    Text("Lattice Practice").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
            } else {
                modeSwitch
                    .padding(.trailing, 8)
            }


            // In lattice mode, show a clear, tappable Sound toggle for audition
            if mode == .lattice {
                Button {
                    app.latticeAuditionOn.toggle()
                    LearnEventBus.shared.send(.latticeAuditionEnabledChanged(app.latticeAuditionOn))
                } label: {
                    let on = app.latticeAuditionOn

                    auditionPillLabel(on: on)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(auditionChrome(on: on))
                        .contentShape(Capsule())
                        .animation(.snappy(duration: 0.22), value: on)
                        .sensoryFeedback(.success, trigger: on)
                }
                .buttonStyle(.plain)
                .tenneyChromaShadow(true)
                .accessibilityLabel(app.latticeAuditionOn ? "Audition sound on" : "Audition sound off")
            } else {
                Image(systemName: tunerStatusIcon)
                    .imageScale(.large)
                Text(tunerStatusText)
            }
            Spacer()

            Button {
                showRootStudio = true
            } label: {
                let isEditing = showRootStudio
                let rr = RoundedRectangle(cornerRadius: rootCorner, style: .continuous)

                rootChipLabel
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background { rootChipBackground(isEditing: isEditing) }
                    .overlay(rootChipStroke(isEditing: isEditing))
                    .clipShape(rr)
                    .contentShape(rr)
                    .animation(.snappy(duration: 0.22), value: isEditing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Root pitch")
            .accessibilityValue(String(format: "%.1f hertz", app.rootHz))
            .sensoryFeedback(.selection, trigger: rootFeedbackToken)
            .onChange(of: app.rootHz) { _ in
                rootFeedbackToken &+= 1
            }
            .contextMenu {
                Button("415.0 Hz") { setRootHz(415.0) }
                Button("432.0 Hz") { setRootHz(432.0) }
                Button("440.0 Hz") { setRootHz(440.0) }

                Divider()

                Button("−0.1") { nudgeRootHz(-0.1) }
                Button("+0.1") { nudgeRootHz(0.1) }
                Button("−1.0") { nudgeRootHz(-1.0) }
                Button("+1.0") { nudgeRootHz(1.0) }

                Divider()

                Button("Reset to default") { setRootHz(440.0) }
            }

            // Gear
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.leading, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(height: 38)  // slimmer bar
        .font(.footnote)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
// Small helper to apply glass on iOS 26 only
fileprivate extension View {
    @ViewBuilder
    func ifAvailableiOS26Glass() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            self
        }
    }
}

private struct RatioChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 48, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CentsGauge: View {
    let cents: Double
    var body: some View {
        let value = cents.isFinite ? max(-50, min(50, cents)) : 0
        VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 8)
                GeometryReader { geo in
                    let w = geo.size.width
                    let pos = (value + 50) / 100.0
                    Capsule().fill(Color.accentColor).frame(width: max(8, w * pos), height: 8)
                }
            }.frame(height: 8)
            Text(cents.isFinite ? String(format: "%+.1f¢", cents) : "—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NextChip: View {
    let title: String, text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.headline.monospaced())
        }
        .padding(10)
        .background(.ultraThinMaterial) // small accent; not full glass
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: Control Cards
// MARK: Control Cards (compact root)
private struct RootCardCompact: View {
    @AppStorage(SettingsKeys.staffA4Hz)  private var concertA4Hz: Double = 440
    @AppStorage(SettingsKeys.noteNameA4Hz) private var noteNameA4Hz: Double = 440
    @AppStorage(SettingsKeys.tonicNameMode) private var tonicNameModeRaw: String = TonicNameMode.auto.rawValue
    @AppStorage(SettingsKeys.tonicE3) private var tonicE3: Int = 0
    @AppStorage(SettingsKeys.accidentalPreference) private var accidentalPreferenceRaw: String = AccidentalPreference.auto.rawValue
    @EnvironmentObject private var model: AppModel
    let ns: Namespace.ID
    @Binding var showSheet: Bool
    @State private var input: String = ""
    @State private var animateTick = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // Root chip (hero to modal)
                    Button {
                        showSheet = true
                    } label: {
                        let tonicDisplayName = currentTonicDisplayName(
                            modeRaw: tonicNameModeRaw,
                            manualE3: tonicE3,
                            rootHz: model.rootHz,
                            noteNameA4Hz: noteNameA4Hz,
                            accidentalPreferenceRaw: accidentalPreferenceRaw,
                            textStyle: .caption,
                            weight: .semibold
                        )
                        HStack(spacing: 6) {
                            Image(systemName: "tuningfork")
                                .imageScale(.medium)
                            Text(String(format: "%.1f", model.rootHz))
                                .font(.headline.monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                                .matchedGeometryEffect(id: "rootValue", in: ns)  // ← hero
                            Text(tonicDisplayName)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 34, alignment: .center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = String(format: "%.4f", model.rootHz)
                        }
                    }

                    // Inline evaluator (commit-on-return)
                    TextField("p/q×base (e.g. 16/9×220)", text: $input, onCommit: commitInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.done)
                        .font(.subheadline.monospaced())
                        .textFieldStyle(.roundedBorder)

                    Spacer(minLength: 4)

                    // Action chips — History, Favorites, Calculator
                    HStack(spacing: 8) {
                        IconChip("clock.arrow.circlepath") { open(.history) }
                        IconChip("star") { open(.favorites) }
                        IconChip("function") { open(.calculator) }
                    }
                }
            }
        }
        .onAppear { input = String(format: "%.1f", model.rootHz) }
        .onChange(of: model.rootHz) { v in
            input = String(format: "%.1f", v)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { animateTick.toggle() }
        }
    }

    private func open(_ tab: RootStudioTab) {
        showSheet = true
        if tab == .history {
            LearnEventBus.shared.send(.tunerPitchHistoryOpened)
        }
        NotificationCenter.default.post(name: .openRootStudioTab, object: tab.rawValue)
    }

    private func commitInput() {
        guard let v = parseHz(input) else { return }
        model.rootHz = v
        pushRootHistory(v)
        input = String(format: "%.1f", v)
    }
}

private struct IconChip: View {
    let symbol: String
    let action: () -> Void
    init(_ s: String, action: @escaping () -> Void) { symbol = s; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).imageScale(.medium)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// Accepts "415", "16/9", "16/9*415", "415*16/9" (spaces ok), clamps 20–2000 Hz.
    private func parseHz(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: " ", with: "")
        if t.isEmpty { return nil }
        func parseFrac(_ x: String) -> Double? {
            if let d = Double(x) { return d }
            let parts = x.split(separator: "/")
            if parts.count == 2, let p = Double(parts[0]), let q = Double(parts[1]), q != 0 {
                return p / q
            }
            return nil
        }
        // Try plain number or fraction first
        if let v = parseFrac(t) {
            let hz = min(2000.0, max(20.0, v))
            return hz.isFinite ? hz : nil
        }
        // Try product like a*b or b*a where a/b may be a fraction
        let mult = t.split(separator: "*")
        if mult.count == 2, let a = parseFrac(String(mult[0])), let b = parseFrac(String(mult[1])) {
            let hz = min(2000.0, max(20.0, a * b))
            return hz.isFinite ? hz : nil
        }
        return nil
    }
// ===== Root Studio (modal) ===================================================
fileprivate enum RootStudioTab: String, CaseIterable, Identifiable { case calculator, history, favorites, a4
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calculator: return "Calculator"
        case .history:    return "History"
        case .favorites:  return "Favorites"
        case .a4:         return "A4"
        }
    }
    var symbol: String {
        switch self {
        case .calculator: return "function"
        case .history:    return "clock.arrow.circlepath"
        case .favorites:  return "star"
        case .a4:         return "music.quarternote.3"
        }
    }
}

extension Notification.Name { static let openRootStudioTab = Notification.Name("tenney.open.root.studio.tab") }

private struct RootStudioSheet: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(SettingsKeys.a4Choice)   private var a4Choice = "440"
    @AppStorage(SettingsKeys.a4CustomHz) private var a4Custom: Double = 440
    @AppStorage(SettingsKeys.staffA4Hz)  private var concertA4Hz: Double = 440
    @AppStorage(SettingsKeys.noteNameA4Hz) private var noteNameA4Hz: Double = 440
    @AppStorage(SettingsKeys.tonicNameMode) private var tonicNameModeRaw: String = TonicNameMode.auto.rawValue
    @AppStorage(SettingsKeys.tonicE3) private var tonicE3: Int = 0
    @AppStorage(SettingsKeys.accidentalPreference) private var accidentalPreferenceRaw: String = AccidentalPreference.auto.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var tab: RootStudioTab
    let ns: Namespace.ID
    @State private var input = ""
    @State private var history: [Double] = RootHistory.load()
    @State private var favorites: [Double] = RootFavorites.load()
    @State private var highlight: RootStudioTab? = nil
    @State private var showReference = false
    @State private var referenceEmphasis = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            // Sticky header: tonic summary
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(effectiveTonicDisplayText(textStyle: .title3, weight: .semibold))
                                    HStack(spacing: 4) {
                                        Image(systemName: "tuningfork")
                                            .imageScale(.small)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.1f", model.rootHz))
                                            .font(.footnote.monospacedDigit().weight(.semibold))
                                            .matchedGeometryEffect(id: "rootValue", in: ns)
                                        Text("Hz")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
        
                            // Cards (compact, one row each on iPhone)
                            quickRootsCard
                                .id("quickRoots")
                                .overlay(cardHighlight(for: .history, or: .favorites))
        
                            calculatorBar
                                .id("calculator")
                                .overlay(cardHighlight(for: .calculator))

                            nameAsCard
        
                            a4Card
                                .id("a4")
                                .overlay(cardHighlight(for: .a4))

                            referenceHelpRow
                        }
                        .padding(16)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .openRootStudioTab)) { note in
                        guard let raw = note.object as? String, let t = RootStudioTab(rawValue: raw) else { return }
                        tab = t
                        let target = (t == .calculator ? "calculator" : (t == .a4 ? "a4" : "quickRoots"))
                        withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
                        highlight = t
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(.easeOut(duration: 0.25)) { highlight = nil } }
                    }
                }
#if targetEnvironment(macCatalyst)
            GlassDismissCircleButton { dismiss() }
                .padding(.top, 20)
                .padding(.trailing, 20)
#endif
        }
        .onAppear {
            input = String(format: "%.1f", model.rootHz)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRootStudioTab)) { note in
            if let raw = note.object as? String, let t = RootStudioTab(rawValue: raw) { tab = t }
        }
        .onChange(of: tonicNameModeRaw) { _, newValue in
            guard let mode = TonicNameMode(rawValue: newValue) else { return }
            if mode == .manual, let auto = autoSpelling {
                tonicE3 = auto.e3
            }
            pulseReferenceHelp()
        }
        .sheet(isPresented: $showReference) {
            NavigationStack {
                LearnTenneyHubView(entryPoint: .settings)
            }
        }
    }

    // Compact calculator (bar + tokens)
        private var calculatorBar: some View {
            glassCard("Calculator") {
                HStack(spacing: 8) {
                    Image(systemName: "function").imageScale(.medium).foregroundStyle(.secondary)
                    TextField("415  ·  16/9  ·  16/9×220", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.go)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commit)
                    Button("Set") { commit() }.buttonStyle(.borderedProminent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["×2","÷2","3/2","5/4","16/9","+5¢","−5¢"], id:\.self) { token in
                            Button(token) { applyToken(token) }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
    private func commit() {
        guard let v = parseHz(input) else { return }
        model.rootHz = v
        RootHistory.push(v); history = RootHistory.load()
        input = String(format: "%.1f", v)
    }
    private func applyToken(_ t: String) {
            var v = model.rootHz
            switch t {
            case "×2":   v *= 2
            case "÷2":   v /= 2
            case "3/2":  v *= 3.0/2.0
            case "5/4":  v *= 5.0/4.0
            case "16/9": v *= 16.0/9.0
            case "+5¢":  v *= pow(2,  5.0/1200.0)
            case "−5¢":  v *= pow(2, -5.0/1200.0)
            default: break
            }
            v = min(2000, max(20, v))
            model.rootHz = v
            RootHistory.push(v); history = RootHistory.load()
            input = String(format: "%.1f", v)
        }
    
        // MARK: Local glass card primitive (matches Settings look)
        @ViewBuilder private func glassCard(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                content()
            }
            .padding(14)
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    } else {
                       RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                    }
               }
            )
        }
    
        // Card highlight overlay for focus jumps
        private func cardHighlight(for first: RootStudioTab, or second: RootStudioTab? = nil) -> some View {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity((highlight == first || highlight == second) ? 0.35 : 0), lineWidth: 2)
                .animation(.easeOut(duration: 0.25), value: highlight)
        }

    // A4 card as theme-style tiles
        private var a4Card: some View {
            glassCard("Concert Pitch (A4)") {
                HStack(spacing: 12) {
                    GlassSelectTile(title: "440", isOn: a4Choice == "440") { a4Choice = "440" }
                    GlassSelectTile(title: "442", isOn: a4Choice == "442") { a4Choice = "442" }
                    GlassSelectTile(title: "Custom", isOn: a4Choice == "custom") { a4Choice = "custom" }
                }
                if a4Choice == "custom" {
                    HStack(spacing: 6) {
                        Text("A4").font(.caption2).foregroundStyle(.secondary)
                        TextField("Hz", value: $a4Custom, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Spacer()
                    }
                }
                Text("Used for concert pitch behaviors. Root naming stays independent.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: a4Choice) { _ in updateA4() }
            .onChange(of: a4Custom) { _ in updateA4() }
        }
    private func updateA4() {
        let chosen: Double = (a4Choice == "442" ? 442 : (a4Choice == "custom" ? max(200, min(1000, a4Custom)) : 440))
        concertA4Hz = chosen
        postSetting(SettingsKeys.staffA4Hz, chosen)
        pulseReferenceHelp()
    }

    private var tonicMode: TonicNameMode {
        TonicNameMode(rawValue: tonicNameModeRaw) ?? .auto
    }

    private var preference: AccidentalPreference {
        AccidentalPreference(rawValue: accidentalPreferenceRaw) ?? .auto
    }

    private var autoSpelling: TonicSpelling? {
        TonicSpelling.from(rootHz: model.rootHz, noteNameA4Hz: noteNameA4Hz, preference: preference)
    }

    private var effectiveTonicSpellingValue: TonicSpelling? {
        effectiveTonicSpelling(
            rootHz: model.rootHz,
            noteNameA4Hz: noteNameA4Hz,
            tonicNameModeRaw: tonicNameModeRaw,
            tonicE3: tonicE3,
            accidentalPreference: preference
        )
    }

    private func effectiveTonicDisplayText(
        textStyle: Font.TextStyle,
        weight: Font.Weight,
        design: Font.Design = .default
    ) -> AttributedString {
        guard let spelling = effectiveTonicSpellingValue else {
            var fallback = AttributedString("—")
            fallback.font = .system(size: Heji2FontRegistry.preferredPointSize(for: textStyle), weight: weight, design: design)
            return fallback
        }
        return spelling.attributedDisplayText(textStyle: textStyle, weight: weight, design: design)
    }

    private var manualLetterBinding: Binding<String> {
        Binding(
            get: {
                TonicSpelling(e3: tonicE3).letter
            },
            set: { newValue in
                let accidental = min(2, max(-2, TonicSpelling(e3: tonicE3).accidentalCount))
                let spelling = TonicSpelling.from(letter: newValue, accidental: accidental)
                tonicE3 = spelling.e3
                tonicNameModeRaw = TonicNameMode.manual.rawValue
            }
        )
    }

    private var manualAccidentalBinding: Binding<Int> {
        Binding(
            get: {
                let accidental = TonicSpelling(e3: tonicE3).accidentalCount
                return min(2, max(-2, accidental))
            },
            set: { newValue in
                let letter = TonicSpelling(e3: tonicE3).letter
                let accidental = min(2, max(-2, newValue))
                let spelling = TonicSpelling.from(letter: letter, accidental: accidental)
                tonicE3 = spelling.e3
                tonicNameModeRaw = TonicNameMode.manual.rawValue
            }
        )
    }

    private var suggestedSpellings: [TonicSpelling] {
        let sharp = TonicSpelling.from(rootHz: model.rootHz, noteNameA4Hz: noteNameA4Hz, preference: .preferSharps)
        let flat = TonicSpelling.from(rootHz: model.rootHz, noteNameA4Hz: noteNameA4Hz, preference: .preferFlats)
        return [sharp, flat].compactMap { $0 }.uniquedBy { $0.displayText }
    }

    // MARK: Reusable list
    // Quick Roots (favorites + recent) in one compact card
        private var quickRootsCard: some View {
            glassCard("Quick Roots") {
                VStack(alignment: .leading, spacing: 8) {
                    if !favorites.isEmpty {
                        HStack {
                            Text("Favorites").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Edit") { /* optional: present full list if desired */ }
                                .font(.caption)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(favorites, id: \.self) { v in
                                    RootChip(v, highlighted: abs(v - model.rootHz) < 0.001) {
                                        model.rootHz = v
                                    } trailing: {
                                        Image(systemName: "star.fill").imageScale(.small)
                                    }
                                }
                            }
                        }
                    }
                    if !history.isEmpty {
                        HStack {
                            Text("Recent").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") {
                                history.forEach { RootHistory.remove($0) }
                                history = RootHistory.load()
                            }.font(.caption)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(history, id: \.self) { v in
                                    RootChip(v, highlighted: abs(v - model.rootHz) < 0.001) {
                                        model.rootHz = v; RootHistory.push(v); history = RootHistory.load()
                                    } trailing: {
                                        Image(systemName: favorites.contains(v) ? "star.fill" : "star").imageScale(.small)
                                            .onTapGesture {
                                                RootFavorites.toggle(v); favorites = RootFavorites.load()
                                            }
                                    }
                                }
                            }
                        }
                    }
                    if favorites.isEmpty && history.isEmpty {
                        Text("No favorites or recents yet. Set a root to begin.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }

    private var nameAsCard: some View {
        glassCard("Name as") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Tonic naming", selection: $tonicNameModeRaw) {
                    Text("Auto").tag(TonicNameMode.auto.rawValue)
                    Text("Manual").tag(TonicNameMode.manual.rawValue)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Current")
                    Spacer()
                    Text(effectiveTonicDisplayText(textStyle: .title3, weight: .semibold, design: .monospaced))
                }

                Text(tonicMode == .auto ? "Auto (derived)" : "Manual (saved)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if tonicMode == .auto {
                    Text("Derived from root + naming A4.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !suggestedSpellings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Suggested").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                ForEach(suggestedSpellings, id: \.self) { spelling in
                                    let title = spelling.attributedDisplayText(
                                        textStyle: .title3,
                                        weight: .semibold,
                                        design: .default
                                    )
                                    GlassSelectTile(title: title, isOn: false) {
                                        tonicE3 = spelling.e3
                                        tonicNameModeRaw = TonicNameMode.manual.rawValue
                                    }
                                    .accessibilityLabel("Name tonic as \(spelling.displayText)")
                                }
                            }
                        }
                    }
                }

                if tonicMode == .manual {
                    Text("Choose a name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !suggestedSpellings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Suggested").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                ForEach(suggestedSpellings, id: \.self) { spelling in
                                    let title = spelling.attributedDisplayText(
                                        textStyle: .title3,
                                        weight: .semibold,
                                        design: .default
                                    )
                                    GlassSelectTile(title: title, isOn: tonicE3 == spelling.e3) {
                                        tonicE3 = spelling.e3
                                        tonicNameModeRaw = TonicNameMode.manual.rawValue
                                    }
                                    .accessibilityLabel("Name tonic as \(spelling.displayText)")
                                }
                            }
                        }
                    }
                    DisclosureGroup("Advanced…") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Letter", selection: manualLetterBinding) {
                                ForEach(["C", "D", "E", "F", "G", "A", "B"], id: \.self) { letter in
                                    Text(letter).tag(letter)
                                }
                            }
                            .pickerStyle(.menu)
                            Picker("Accidental", selection: manualAccidentalBinding) {
                                ForEach(-2...2, id: \.self) { value in
                                    Text(accidentalLabel(value)).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.top, 6)
                    }
                }

                Text("Names the tonic (1/1) used to spell intervals.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

        private var referenceHelpRow: some View {
            let emphasisOpacity = referenceEmphasis ? 0.9 : 0.0
            return glassCard("Reference") {
                Button {
                    LearnTenneyStateStore.shared.pendingModuleToOpen = .rootPitchTuningConfig
                    LearnTenneyStateStore.shared.pendingReferenceTopic = .rootTonicConcert
                    showReference = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Root, Tonic, Concert Pitch")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Why these are separate (and how to debug weird labels)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor.opacity(emphasisOpacity), lineWidth: 1.5)
                    )
                    .shadow(color: Color.accentColor.opacity(referenceEmphasis ? 0.15 : 0.0), radius: 6, x: 0, y: 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.01) : .easeOut(duration: 0.25), value: referenceEmphasis)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open reference: Root, Tonic, Concert Pitch")
            }
        }

        private func pulseReferenceHelp() {
            guard !reduceMotion else {
                referenceEmphasis = false
                return
            }
            referenceEmphasis = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                referenceEmphasis = false
            }
        }

    private func accidentalLabel(_ value: Int) -> AttributedString {
        if value == 0 {
            var label = AttributedString("Natural")
            label.font = .system(size: Heji2FontRegistry.preferredPointSize(for: .body), weight: .regular, design: .default)
            return label
        }
        let glyphs = Heji2Mapping.shared.glyphsForDiatonicAccidental(value).map(\.string).joined()
        var label = AttributedString(glyphs)
        let baseSize = Heji2FontRegistry.preferredPointSize(for: .body)
        label.font = Heji2FontRegistry.hejiTextFont(size: baseSize, relativeTo: .body)
        return label
    }
}

// MARK: History / Favorites persistence (simple arrays)
fileprivate enum RootHistory {
    private static let key = "tenney.root.history"
    static func load() -> [Double] { (UserDefaults.standard.array(forKey: key) as? [Double]) ?? [] }
    static func push(_ v: Double) {
        var arr = load().filter { abs($0 - v) > 0.0001 }
        arr.insert(v, at: 0); arr = Array(arr.prefix(20))
        UserDefaults.standard.set(arr, forKey: key)
    }
    static func remove(_ v: Double) {
        var arr = load()
                arr.removeAll { abs($0 - v) < 0.0001 }
                UserDefaults.standard.set(arr, forKey: key)
    }
}
fileprivate func pushRootHistory(_ v: Double) { RootHistory.push(v) }

fileprivate enum RootFavorites {
    private static let key = "tenney.root.favorites"
    static func load() -> [Double] { (UserDefaults.standard.array(forKey: key) as? [Double]) ?? [] }
    static func toggle(_ v: Double) {
        var arr = load()
        if let idx = arr.firstIndex(where: { abs($0 - v) < 0.0001 }) { arr.remove(at: idx) } else { arr.insert(v, at: 0) }
        UserDefaults.standard.set(arr, forKey: key)
    }
    static func remove(_ v: Double) {
        var arr = load(); arr.removeAll { abs($0 - v) < 0.0001 }; UserDefaults.standard.set(arr, forKey: key)
    }
}

private extension Array {
    func uniquedBy<T: Hashable>(_ key: (Element) -> T) -> [Element] {
        var seen: Set<T> = []
        return filter { element in
            let k = key(element)
            if seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
    }
}
private struct PrimeLimitCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Prime Limit").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach([3,5,7,11], id:\.self) { p in
                        let selected = (model.primeLimit == p)
                        Button(action: { model.primeLimit = p }) {
                            Text("\(p)")
                                .font(.footnote.weight(selected ? .semibold : .regular))
                                .foregroundStyle(
                                    selected
                                    ? (theme.isDark ? Color.white : Color.black)
                                    : Color.secondary
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selected
                                    ? AnyShapeStyle(.thinMaterial)
                                    : AnyShapeStyle(.ultraThinMaterial),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(
                                        selected
                                        ? accentStyle
                                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Prime limit \(p)")
                    }
                }
            }
        }
    }
}


private struct StrictnessCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Strictness").font(.caption).foregroundStyle(.secondary)
                Picker("Strictness", selection: $model.strictness) {
                    ForEach(Strictness.allCases) { s in Text(s.rawValue.capitalized).tag(s) }
                }.pickerStyle(.segmented)
            }
        }
    }
}

private struct TestToneCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Test Tone (sine)").font(.caption).foregroundStyle(.secondary)
                Toggle("Play test tone (matches Root)", isOn: $model.playTestTone)
                .onChange(of: model.rootHz) { _, new in
                    if model.playTestTone { /* frequency follows root automatically via start() */ }
                }
            }
        }
    }
}
// === Reusables for Root Studio =================================================
struct GlassSelectTile: View {
    let title: AttributedString
    let isOn: Bool
    let action: () -> Void

    init(title: String, isOn: Bool, action: @escaping () -> Void) {
        var label = AttributedString(title)
        label.font = .title3.monospacedDigit().weight(.semibold)
        self.title = label
        self.isOn = isOn
        self.action = action
    }

    init(title: AttributedString, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isOn = isOn
        self.action = action
    }

    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(title)
                    .foregroundStyle(
                        isOn
                        ? (theme.isDark ? Color.white : Color.black) // tile content is usually on light-ish glass
                        : Color.secondary
                    )
                    .frame(minWidth: 88, minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(12)

                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accentStyle)
                        .blendMode(theme.isDark ? .screen : .darken)
                        .padding(6)
                }
            }
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isOn
                        ? accentStyle
                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentTransition(.opacity)
    }
}


private struct RootChip<Trailing: View>: View {
    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let value: Double
    var highlighted: Bool = false
    let onTap: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }

    init(
        _ v: Double,
        highlighted: Bool = false,
        onTap: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.value = v
        self.highlighted = highlighted
        self.onTap = onTap
        self.trailing = trailing
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(String(format: "%.1f", value))
                    .font(.footnote.monospacedDigit().weight(.semibold))

                // Let the trailing view show its own icon; we tint the star when highlighted.
                trailing()
                    .foregroundStyle(
                        highlighted
                        ? accentStyle
                        : AnyShapeStyle(Color.secondary)
                    )
                    .blendMode(highlighted ? (theme.isDark ? .screen : .darken) : .normal)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(
                highlighted
                ? (theme.isDark ? Color.white : Color.black)
                : Color.secondary
            )
            .background(
                highlighted
                ? AnyShapeStyle(.thinMaterial)
                : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    highlighted
                    ? accentStyle
                    : AnyShapeStyle(Color.secondary.opacity(0.12)),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Key-window snapshot (used for frozen backdrop)
private func captureKeyWindowSnapshot(afterScreenUpdates: Bool = true) -> UIImage? {
    guard
        let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
    else { return nil }

    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
    return renderer.image { _ in
        // drawHierarchy provides a faithful capture including materials
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: afterScreenUpdates)
    }
}
// ===== First-run Wizard Footer =====
private struct WizardFooter: View {
    let tip: String
    let route: String
    let build: String
    let onSkip: () -> Void
    @State private var breathe = false
    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Skip (left) • Build stamp (right)
            HStack {
                Button(action: onSkip) {
                    Text("Skip setup")
                        .font(.caption)
                        .foregroundStyle(accentStyle)
                        .underline(false)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Text(build)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
            }

            // Row 2: Quiet tip (centered)
            Text(tip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // Row 3: Audio route chip + micro-links (centered)
            HStack(spacing: 10) {
                Text(route)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .lineLimit(1)
                Text("•").foregroundStyle(.secondary)
                Button("Help") { /* TODO: present Help */ }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                Text("•").foregroundStyle(.secondary)
                Button("Privacy") { /* TODO: present Privacy */ }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                Text("•").foregroundStyle(.secondary)
                Button("Terms") { /* TODO: present Terms */ }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Breathing line
            Rectangle()
                .fill(Color.primary.opacity(breathe ? 0.08 : 0.02))
                .frame(height: 1)
                .animation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true), value: breathe)
                .onAppear { breathe = true }
        }
        .padding(.vertical, 8)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
    }
}
private struct WizardFooterRail: View {
    let buildString: String
    let tips: [String]
    var onSkip: (() -> Void)? = nil      // ← add

    @State private var routeLabel: String = "Built-in Speaker • 48 kHz"
    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var accentStyle: AnyShapeStyle {
        ThemeAccent.shapeStyle(base: theme.accent, reduceTransparency: reduceTransparency)
    }

    var body: some View {
        VStack(spacing: 10) {
            BreathingDivider()

            HStack {
                Button {
                    onSkip?()
                } label: {
                    Label("Skip setup", systemImage: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accentStyle)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(accentStyle, lineWidth: 1)
                                .opacity(0.55)
                        )
                        .contentShape(Capsule())
                        .shadow(radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip setup")

                Spacer()
                Text(buildString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            TipTickerView(tips: tips).padding(.top, 2)

            HStack(spacing: 14) {
                Link("Help", destination: URL(string: "https://example.com/help")!)
                Link("Privacy", destination: URL(string: "https://example.com/privacy")!)
                Link("Terms", destination: URL(string: "https://example.com/terms")!)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.9))

            HStack {
                AudioRouteChip(label: routeLabel)
                Spacer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            routeLabel = AudioRouteChip.currentRouteSummary()
        }
        .onAppear { routeLabel = AudioRouteChip.currentRouteSummary() }
    }
}

// MARK: - Breathing divider (subtle glow pulse)
private struct BreathingDivider: View {
    @State private var t: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.10))
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.50))
                    .frame(height: 1)
                    .shadow(color: .white.opacity(0.35 + 0.25 * t), radius: 8 + 8 * t, y: 0)
                    .opacity(0.25 + 0.35 * t)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { t = 1 }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Tip ticker (crossfade every ~6s; marquee only if overflow)
private struct TipTickerView: View {
    let tips: [String]
    @State private var idx = 0
    @State private var show = true

    var body: some View {
        ZStack {
            TipMarquee(text: tips.isEmpty ? "" : tips[idx])
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(show ? 1 : 0)
                .animation(.easeInOut(duration: 0.45), value: show)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !tips.isEmpty else { return }
            while true {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                withAnimation { show = false }
                try? await Task.sleep(nanoseconds: 500_000_000)
                idx = (idx + 1) % tips.count
                withAnimation { show = true }
            }
        }
        .accessibilityLabel("Tip")
        .accessibilityValue(Text(tips.isEmpty ? "" : tips[idx]))
    }
}

private struct TipMarquee: View {
    let text: String
    @State private var contentW: CGFloat = 0
    @State private var clipW: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    @State private var started = false

    var body: some View {
        GeometryReader { clipGeo in
            let cw = clipGeo.size.width
            ZStack(alignment: .leading) {
                Text(text)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .onAppear {
                                    contentW = g.size.width
                                    clipW = cw
                                    startIfNeeded()
                                }
                                .onChange(of: g.size.width) { _ in
                                    contentW = g.size.width; clipW = cw; restart()
                                }
                        }
                    )
                    .offset(x: offsetX)
            }
            .clipped()
        }
        .frame(height: 18)
        .onChange(of: text) { _ in restart() }
        .onChange(of: clipW) { _ in restart() }
    }

    private func startIfNeeded() {
        guard contentW > clipW, !started else { return }
        started = true
        let travel = max(0, contentW - clipW + 24)
         let duration = max(6.0, Double(travel) / 30.0) // ~30pt/s
        withAnimation(.linear(duration: duration).delay(1).repeatForever(autoreverses: true)) {
            offsetX = -travel
        }
    }
    private func restart() {
        started = false
        withAnimation(.easeOut(duration: 0.2)) { offsetX = 0 }
        DispatchQueue.main.async { startIfNeeded() }
    }
}

// MARK: - Audio route chip + helper
private struct AudioRouteChip: View {
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill").imageScale(.small)
            Text(label).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: Capsule())
        .accessibilityLabel("Audio route")
        .accessibilityValue(Text(label))
    }

    static func currentRouteSummary() -> String {
        let session = AVAudioSession.sharedInstance()
        let name = session.currentRoute.outputs.first?.portName ?? "Built-in Speaker"
        let kHz = session.sampleRate / 1000.0
        let rate = (abs(kHz - 44.1) < 0.2) ? "44.1" : String(format: "%.0f", kHz)
        return "\(name) • \(rate) kHz"
    }
}

private struct VenueBanner: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 8, y: 4)
            .accessibilityLabel("Venue standard applied")
            .accessibilityValue(Text(text))
    }
}
