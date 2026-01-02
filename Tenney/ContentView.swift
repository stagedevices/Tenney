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

struct ContentView: View {
    @AppStorage(SettingsKeys.tenneyThemeID) private var tenneyThemeIDRaw: String = LatticeThemeID.classicBO.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixBasis) private var mixBasisRaw: String = TenneyMixBasis.complexityWeight.rawValue
    @AppStorage(SettingsKeys.tenneyThemeMixMode) private var mixModeRaw: String = TenneyMixMode.blend.rawValue
    @AppStorage(SettingsKeys.tenneyThemeScopeMode) private var scopeModeRaw: String = TenneyScopeColorMode.constant.rawValue

    @AppStorage(SettingsKeys.setupWizardDone) private var setupWizardDone: Bool = false
private let libraryStore = ScaleLibraryStore.shared
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(SettingsKeys.latticeThemeStyle) private var themeStyleRaw: String = "system"
    private var resolvedTheme: ResolvedTenneyTheme {
        TenneyThemeRegistry.resolvedCurrent(
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
        }
        .environment(\.tenneyTheme, resolvedTheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        .overlay { resolvedTheme.surfaceTint.ignoresSafeArea().allowsHitTesting(false) }

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
        }

        .onReceive(NotificationCenter.default.publisher(for: .venueCalibrated)) { note in
            guard let info = note.object as? VenueCalibrationInfo else { return }
            venueToast = info
            // Auto-hide after 2.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.25)) { venueToast = nil }
            }
        }
        .overlay(alignment: .top) {
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

        if isLandscape {
            HStack(spacing: 16) {
                tunerCardView
#if targetEnvironment(macCatalyst)
                if tunerRailStore.showRail {
                    TunerContextRailHost(
                        store: tunerRailStore,
                        app: app,
                        showSettings: $showSettings
                    ) {
                        requestedSettingsCategory = .tuner
                    }
                    .opacity(stageActive ? 0 : 1)
                    .allowsHitTesting(!stageActive)
                }
#else
                railView(in: geo, isLandscape: true)
#endif
            }
            .padding(16)
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
            .padding(.top, -20)
    }

    private var tunerCardView: some View {
        TunerCard(stageActive: $stageActive)
            .matchedGeometryEffect(id: "tunerHero", in: stageNS)
            .opacity(stageActive ? 0 : 1)
            .allowsHitTesting(!stageActive)   //  critical: don't let the invisible source eat taps
            .frame(maxWidth: .infinity)
    }

    private func railView(in geo: GeometryProxy, isLandscape: Bool) -> some View {
        RailView(showRootStudio: $showRootStudio, rootNS: rootNS)
            .frame(width: isLandscape ? min(400, geo.size.width * 0.34) : nil)
            .opacity(stageActive ? 0 : 1)
            .allowsHitTesting(!stageActive)
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
        app.setMicActive(mode == .tuner)
    }

    private func librarySheetDismiss() {
        app.setMicActive(mode == .tuner)
    }

    @ViewBuilder
    private func builderSheet<Payload>(payload: Payload, startInLibrary: Bool) -> some View {
        let store = ScaleBuilderStore(payload: payload)
        ScaleBuilderScreen(store: store)
            .environmentObject(libraryStore)
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

                TunerCard(stageActive: $stageActive)
                    .matchedGeometryEffect(id: "tunerHeroStage", in: stageNS)
                    .frame(maxWidth: min(520, proxy.size.width - 32))
                    .padding(16)
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
            .statusBar(hidden: stageHideStatus && stageActive)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onDisappear {
                requestedSettingsCategory = nil
            }
    }

    @ViewBuilder
    private func builderSheetContent(payload: Any, startInLibrary: Bool) -> some View {
        let store = ScaleBuilderStore(payload: payload)
        ScaleBuilderScreen(store: store)
            .environmentObject(libraryStore)
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
    }
    private var scaleLibraryDetent: some View {
        ScaleLibrarySheet()
            .environmentObject(libraryStore)
            .presentationDetents([.medium, .large], selection: .constant(.medium))
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .onAppear { app.setMicActive(false) }
    }
    private var rootStudioDetent: some View {
        RootStudioSheet(tab: $rootStudioTab, ns: rootNS)
            .environmentObject(app)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
    }

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
    @EnvironmentObject private var model: AppModel
    @StateObject private var store = TunerStore()
    private var liveHz: Double { model.display.hz }
    private var liveCents: Double { model.display.cents }
    private var liveConf: Double { model.display.confidence }
    private var liveNearest: RatioResult? { parseRatio(model.display.ratioText) }

    @StateObject private var hold = NeedleHoldState()
    @State private var currentNearest: RatioResult? = nil
    @Binding var stageActive: Bool

    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme

    private var pillGrad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                 farLabel: "Far"
             )

         case .chronoDial:
             ChronoDial(
                 cents: centsShown,
                 confidence: liveConf,
                 inTuneWindow: 5,
                 stageMode: store.stageMode,
                 accent: stageAccent
             )
             // add back in when ready to test phasescope
     //    case .phaseScope:
     //        PhaseScopeTunerView(vm: model, store: store)
         }
     }


    private func centsVsLocked(_ locked: RatioResult?, hz: Double, root: Double) -> Double {
        guard let t = locked, hz.isFinite else { return model.display.cents }
        let targetHz = root * pow(2.0, Double(t.octave)) * (Double(t.num)/Double(t.den))
        return 1200.0 * log2(hz / targetHz)
    }
     private var stageButton: some View {
         Button {
             withAnimation(.snappy) { stageActive.toggle() }
         } label: {
             HStack(spacing: 6) {
                 Image(systemName: stageActive ? "theatermasks.fill" : "theatermasks")
                     .font(.footnote.weight(.semibold))
                     .foregroundStyle(
                         stageActive
                         ? AnyShapeStyle(pillGrad)
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
                     ? AnyShapeStyle(pillGrad)
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
     }

    var body: some View {
        GlassCard(corner: 20) {
            VStack(spacing: 14) {

                // Header row: Mode glyph strip (left) • Style strip • Stage toggle (right)
                ViewThatFits(in: .horizontal) {

                    // ✅ Preferred (fits on wider devices)
                    HStack {
                        TunerModeStrip(mode: $store.mode)
                        TunerViewStyleStrip(
                            style: Binding(
                                get: { store.viewStyle },
                                set: { store.viewStyle = $0 }
                            )
                        )

                        Spacer()
                        stageButton
                    }

                    // ✅ Fallback (narrow widths): two-line header
                    VStack(spacing: 10) {
                        HStack {
                            TunerModeStrip(mode: $store.mode)
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
                            Spacer()
                        }
                    }
                }



                // Chrono dial (rectangular card contains it)
                let rawCents: Double = {
                    if let locked = store.lockedTarget {
                        return signedCents(actualHz: liveHz, rootHz: model.rootHz, target: locked)
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

                tunerDial(
                    centsShown: centsShown,
                    liveConf: liveConf,
                    stageAccent: stageAccent,
                    showFar: showFar,
                    held: held,
                    currentNearest: currentNearest,
                    liveNearest: liveNearest
                )
                .frame(maxWidth: .infinity)
                // add back in when ready to test phasescope
                          //      .frame(
                           //         minHeight: 260,
                             //       idealHeight: (store.viewStyle == .phaseScope ? 300 : 320),
                               //     maxHeight: (store.viewStyle == .phaseScope ? 360 : nil)
                              //  )
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.35) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    store.toggleLock(currentNearest: (currentNearest ?? liveNearest))
                }

                
                .overlay(alignment: .topTrailing) {
                    // Lock indicator chip (top-right of the dial area)
                    if let t = store.lockedTarget {
                        BadgeCapsule(text: "Current \(model.display.ratioText)", style: AnyShapeStyle(Color.secondary.opacity(0.15)))
                            .padding(6)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Complications (12/3/6/9 o’clock grammar)
                VStack(spacing: 8) {
                    // 12 o’clock: Ratio + prime badges
                    HStack(spacing: 10) {
                        Text(store.lockedTarget.map { "\($0.num)/\($0.den)" } ?? model.display.ratioText)
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        // tiny prime badge guesses from label (fast path; you already have NotationFormatter if needed)
                        let label = store.lockedTarget.map { "\($0.num)/\($0.den)" } ?? model.display.ratioText
                        let primes = label.split(separator: "/").flatMap { Int($0) }.flatMap { factors($0) }.filter { $0 > 2 }
                        HStack(spacing: 6) {
                                                    ForEach(Array(Set(primes)).sorted(), id: \.self) { p in
                                                        BadgeCapsule(text: "\(p)", style: AnyShapeStyle(theme.primeTint(p)))
                                                    }
                                                }
                        Spacer()
                    }

                    // 3 & 6 o’clock: ET cents and JI delta (mode-aware)
                    HStack(spacing: 12) {
                        StatTile(label: "ET", value: model.display.cents.isFinite ? String(format: "%+.1f¢", model.display.cents) : "—")
                        if store.mode == .live, store.lockedTarget == nil {
                            StatTile(label: "vs JI", value: String(format: "%+.1f¢", model.display.cents))
                        } else if let lock = store.lockedTarget {
                            StatTile(label: "vs \(lock.num)/\(lock.den)", value: String(format: "%+.1f¢", centsShown))

                        } // .strict hides the extra JI label by design
                        Spacer()
                        StatTile(label: "Hz", value: String(format: "%.1f", model.display.hz))
                        StatTile(label: "Conf", value: String(format: "%.0f%%", model.display.confidence*100))
                    }

                    // 9 o’clock: suggestions (tap to lock)
                    if store.lockedTarget == nil {
                        HStack {
                            NextChip(title: "Lower",  text: model.display.lowerText)
                                .onTapGesture { if let r = parseRatio(model.display.lowerText) { store.lockedTarget = r } }
                            Spacer(minLength: 12)
                            BadgeCapsule(text: "Current \(model.display.ratioText)", style: AnyShapeStyle(Color.secondary.opacity(0.15)))
                            Spacer(minLength: 12)
                            NextChip(title: "Higher", text: model.display.higherText)
                                .onTapGesture { if let r = parseRatio(model.display.higherText) { store.lockedTarget = r } }
                        }
                        .transition(.opacity)
                    } else {
                        // Tap to clear lock
                        Button("Clear Target") { withAnimation(.snappy) { store.lockedTarget = nil } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .onChange(of: model.display.ratioText) { txt in
                    currentNearest = parseRatio(txt) // for long-press locking
                }

                // Tuner-local prime limit chips (walled off)
                HStack(spacing: 8) {
                    Text("Limit").font(.caption).foregroundStyle(.secondary)
                    ForEach([3,5,7,11,13], id:\.self) { p in
                        let selected = (store.primeLimit == p)
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
                    Spacer()
                }
                .padding(.top, 4)
                .onChange(of: store.primeLimit) { model.tunerPrimeLimit = $0 }
                .onAppear { store.primeLimit = model.tunerPrimeLimit }

            }
        }

    }
}

// Tiny helpers (local to ContentView)
private func parseRatio(_ s: String) -> RatioResult? {
    let parts = s.split(separator: "/"); guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]) else { return nil }
    return RatioResult(num: n, den: d, octave: 0)
}
private func factors(_ n: Int) -> [Int] {
    var x = n, p = 2, out: [Int] = []
    while p*p <= x { while x % p == 0 { out.append(p); x /= p } ; p += 1 }
    if x > 1 { out.append(x) }
    return out
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
    @Binding var mode: AppScreenMode
    @Binding var showSettings: Bool
    @Binding var showRootStudio: Bool
    let rootNS: Namespace.ID
    /// Reorders the segmented picker so the user's default view appears on the **left**.
    let defaultView: String

    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme
    @Environment(\.tenneyPracticeActive) private var practiceActive

    private var pillGrad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                Picker("Mode", selection: $mode) {
                    if defaultView == "lattice" {
                        Text("Lattice").tag(AppScreenMode.lattice)
                        Text("Tuner").tag(AppScreenMode.tuner)
                    } else {
                        Text("Tuner").tag(AppScreenMode.tuner)
                        Text("Lattice").tag(AppScreenMode.lattice)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .padding(.trailing, 8)
            }


            // In lattice mode, show a clear, tappable Sound toggle for audition
            if mode == .lattice {
                Button {
                    app.latticeAuditionOn.toggle()
                } label: {
                    let on = app.latticeAuditionOn
                    HStack(spacing: 8) {
                        Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .imageScale(.large)
                            .foregroundStyle(
                                on
                                ? AnyShapeStyle(pillGrad)
                                : AnyShapeStyle(Color.secondary)
                            )
                            .blendMode(on ? (theme.isDark ? .screen : .darken) : .normal)
// MARK: - UTILITY BAR SOUND ON AND OFF TOGGLE
                        ZStack {
                            Text("Off").opacity(on ? 0 : 1)
                            Text("On").opacity(on ? 1 : 0)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            on
                            ? (theme.isDark ? Color.white : Color.black)
                            : Color.secondary
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        on
                        ? AnyShapeStyle(.thinMaterial)
                        : AnyShapeStyle(.ultraThinMaterial),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            on
                            ? AnyShapeStyle(pillGrad)
                            : AnyShapeStyle(Color.secondary.opacity(0.12)),
                            lineWidth: 1
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .tenneyChromaShadow(true)
                .accessibilityLabel(app.latticeAuditionOn ? "Audition sound on" : "Audition sound off")
            } else {
                            Image(systemName: "dot.radiowaves.left.and.right").imageScale(.large)
                            Text(app.micPermission == .granted ? "Tuner active" : "Initializing")
                                    }
            Spacer()

            // Only one matchedGeometry source should exist at a time.
                        // In Lattice: Utility Bar owns the hero → sheet.
                        // In Tuner: Root card owns the hero; Utility Bar shows a static label.
                        if mode == .lattice {
                            Button {
                                showRootStudio = true
                            } label: {
                                HStack(spacing: 6) {
                                    // ROOT PICKER IN FOOTER BAR
                                    Image(systemName: "tuningfork").imageScale(.medium)
                                    Text(String(format: "%.1f Hz", app.rootHz))
                                        .matchedGeometryEffect(id: "rootValue", in: rootNS)
                                        .font(.footnote.monospacedDigit())
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "tuningfork").imageScale(.medium)
                                Text(String(format: "%.1f Hz", app.rootHz))
                                    .font(.footnote.monospacedDigit())
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
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
    @EnvironmentObject private var model: AppModel
    let ns: Namespace.ID
    @Binding var showSheet: Bool
    @State private var input: String = ""
    @State private var animateTick = false

    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                // Root chip (hero to modal)
                Button {
                    showSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tuningfork")
                            .imageScale(.medium)
                        Text(String(format: "%.1f Hz", model.rootHz))
                            .font(.headline.monospacedDigit())
                            .matchedGeometryEffect(id: "rootValue", in: ns)  // ← hero
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
        .onAppear { input = String(format: "%.1f", model.rootHz) }
        .onChange(of: model.rootHz) { v in
            input = String(format: "%.1f", v)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { animateTick.toggle() }
        }
    }

    private func open(_ tab: RootStudioTab) { showSheet = true
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
    @AppStorage(SettingsKeys.staffA4Hz)  private var a4Staff: Double = 440

    @Binding var tab: RootStudioTab
    let ns: Namespace.ID
    @State private var input = ""
    @State private var history: [Double] = RootHistory.load()
    @State private var favorites: [Double] = RootFavorites.load()
    @State private var highlight: RootStudioTab? = nil

    var body: some View {
        ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            // Sticky header: hero chip
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "tuningfork").imageScale(.medium)
                                    Text(String(format: "%.1f Hz", model.rootHz))
                                        .font(.title3.monospacedDigit().weight(.semibold))
                                        .matchedGeometryEffect(id: "rootValue", in: ns)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                                Spacer()
                            }
        
                            // Cards (compact, one row each on iPhone)
                            quickRootsCard
                                .id("quickRoots")
                                .overlay(cardHighlight(for: .history, or: .favorites))
        
                            calculatorBar
                                .id("calculator")
                                .overlay(cardHighlight(for: .calculator))
        
                            a4Card
                                .id("a4")
                                .overlay(cardHighlight(for: .a4))
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
        .onAppear {
            input = String(format: "%.1f", model.rootHz)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRootStudioTab)) { note in
            if let raw = note.object as? String, let t = RootStudioTab(rawValue: raw) { tab = t }
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
                Text("Used for staff/ET reference. Root remains independent.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: a4Choice) { _ in updateA4() }
            .onChange(of: a4Custom) { _ in updateA4() }
        }
    private func updateA4() {
        let chosen: Double = (a4Choice == "442" ? 442 : (a4Choice == "custom" ? max(200, min(1000, a4Custom)) : 440))
        a4Staff = chosen
        postSetting(SettingsKeys.staffA4Hz, chosen)
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
private struct PrimeLimitCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme

    private var grad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                                        ? AnyShapeStyle(grad)
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
    let title: String
    let isOn: Bool
    let action: () -> Void

    @Environment(\.tenneyTheme) private var theme: ResolvedTenneyTheme

    private var grad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(title)
                    .font(.title3.monospacedDigit().weight(.semibold))
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
                        .foregroundStyle(AnyShapeStyle(grad))
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
                        ? AnyShapeStyle(grad)
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

    let value: Double
    var highlighted: Bool = false
    let onTap: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    private var grad: LinearGradient {
        LinearGradient(
            colors: [theme.e3, theme.e5],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                        ? AnyShapeStyle(grad)
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
                    ? AnyShapeStyle(grad)
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

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Skip (left) • Build stamp (right)
            HStack {
                Button(action: onSkip) {
                    Text("Skip setup")
                        .font(.caption)
                        .foregroundStyle(
                                .linearGradient(
                                    colors: [.red, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
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
    private let skipGrad = LinearGradient(
        colors: [.red, .orange],
        startPoint: .leading,
        endPoint: .trailing
    )

    let buildString: String
    let tips: [String]
    var onSkip: (() -> Void)? = nil      // ← add

    @State private var routeLabel: String = "Built-in Speaker • 48 kHz"

    var body: some View {
        VStack(spacing: 10) {
            BreathingDivider()

            HStack {
                Button {
                    onSkip?()
                } label: {
                    Label("Skip setup", systemImage: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(skipGrad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(skipGrad.opacity(0.55), lineWidth: 1)
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
