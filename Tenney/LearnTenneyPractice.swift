import SwiftUI
import Combine

struct LearnTenneyPracticeView: View {
    let module: LearnTenneyModule
    @Binding var focus: LearnPracticeFocus?

    private let steps: [LearnStep]
    @StateObject private var coordinator: LearnCoordinator
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppModel
    @State private var auditionToggledOnce = false
    @State private var primeLimitTapCount = 0
    @State private var focusTarget: String? = nil
    @State private var practiceRestartID = UUID()

    init(module: LearnTenneyModule, focus: Binding<LearnPracticeFocus?>) {
        self.module = module
        self._focus = focus

        let s = LearnStepFactory.steps(for: module)
        self.steps = s
        _coordinator = StateObject(wrappedValue: LearnCoordinator(module: module, steps: s))
    }
    private var nextEnabledForStep: Bool {
        switch coordinator.currentStepIndex {
        case 1:  return auditionToggledOnce          // Step 2
        case 2:  return primeLimitTapCount >= 1      // Step 3
        case 3:  return primeLimitTapCount >= 2      // Step 4
        default: return true
        }
    }
    private func overlayStep(for idx: Int) -> LearnStep? {
        guard steps.indices.contains(idx) else { return nil }
        return steps[idx]
    }

    private func finishPractice() {
        focus = nil
        dismiss()
    }

    private func resetPractice() {
        coordinator.reset()
        LearnTenneyPersistence.shared.resetState(module)
        auditionToggledOnce = false
        primeLimitTapCount = 0
        focusTarget = learnTargetID(for: focus)
        practiceRestartID = UUID()
    }

    private func continueToNextModule() {
        guard let next = module.nextModule else {
            finishPractice()
            return
        }
        LearnTenneyStateStore.shared.pendingModuleToOpen = next
        finishPractice()
    }

    private func learnTargetID(for focus: LearnPracticeFocus?) -> String? {
        switch focus {
        case .builderPads:
            return "builder_pad"
        case .builderAddRoot:
            return "builder_add_root"
        case .builderOscilloscope:
            return "builder_scope"
        default:
            return nil
        }
    }

    private func handleLearnEvent(_ e: LearnEvent) {
        switch e {
        case .latticeAuditionEnabledChanged:
            if coordinator.currentStepIndex == 1 { auditionToggledOnce = true }

        case .latticeAuditionToggled:
            if coordinator.currentStepIndex == 1 { auditionToggledOnce = true }

        case .latticePrimeChipToggled:
            if coordinator.currentStepIndex == 2 || coordinator.currentStepIndex == 3 {
                primeLimitTapCount += 1
            }

        case .latticePrimeChipTapped:
            if coordinator.currentStepIndex == 2 || coordinator.currentStepIndex == 3 {
                primeLimitTapCount += 1
            }

        default:
            break
        }
    }

    var body: some View {
        let idx = coordinator.currentStepIndex

        let content = ZStack(alignment: .top) {
            PracticeContent(module: module, stepIndex: idx)
                .id(practiceRestartID)
                .environment(\.learnGate, coordinator.gate)
                .overlayPreferenceValue(LearnTargetAnchorKey.self) { targets in
                    GeometryReader { proxy in
                        if let target = focusTarget, let anchor = targets[target] {
                            let rect = proxy[anchor]
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.9), lineWidth: 2)
                                .frame(width: rect.width + 10, height: rect.height + 10)
                                .position(x: rect.midX, y: rect.midY)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 6)
                                .allowsHitTesting(false)
                                .animation(.snappy(duration: 0.25), value: rect)
                        }
                    }
                }

            // Top-right + pushed DOWN so top-left prime chips stay visible/tappable
            let overlay = LearnOverlay(
                module: module,
                stepIndex: idx,
                totalSteps: steps.count,
                step: overlayStep(for: idx),
                completed: coordinator.completed,
                nextEnabled: nextEnabledForStep,
                onBack: coordinator.back,
                onNext: coordinator.next,
                onReset: resetPractice,
                onDone: finishPractice,
                onContinue: continueToNextModule
            )

            if coordinator.completed {
                overlay
            } else {
                overlay
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(.top, 72)
                    .padding(.horizontal, 12)
            }
        }
        .onReceive(LearnEventBus.shared.publisher) { (e: LearnEvent) in
            handleLearnEvent(e)
        }
        .onAppear {
            focusTarget = learnTargetID(for: focus)
        }
        .onChange(of: focus) { newValue in
            focusTarget = learnTargetID(for: newValue)
        }
        .environment(\.learnPracticeCompleted, coordinator.completed)

        Group {
            if module == .lattice {
                content
            } else {
                content
                    .navigationTitle("Practice")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct PracticeContent: View {
    let module: LearnTenneyModule
    let stepIndex: Int

    var body: some View {
        Group {
            switch module {
            case .lattice:
                LatticePracticeHost(stepIndex: stepIndex)

            case .tuner:
                TunerPracticeHost()

            case .builder:
                BuilderPracticeHost()
            }
        }
    }
}

private struct LatticePracticeHost: View {
    let stepIndex: Int
    @EnvironmentObject private var latticeStore: LatticeStore
    @State private var practiceSnapshot: TenneyPracticeSnapshot? = nil
    @State private var didSeed = false
    @State private var baselineVisiblePrimes: Set<Int> = []

    private var overlayPrimes: [Int] {
        PrimeConfig.primes.filter { $0 != 2 && $0 != 3 && $0 != 5 }
    }

    private func applyOverlayPrimeState(_ visible: Set<Int>) {
        for p in overlayPrimes {
            latticeStore.setPrimeVisible(p, visible.contains(p), animated: false)
        }
    }

    var body: some View {
        ZStack {
            // ✅ Always keep the real sandbox mounted (this is where your UtilityBar comes from)
            ContentView()
                .environment(\.tenneyPracticeActive, true)
                .environment(\.tenneyPracticeChrome, true)
                .toolbar(.hidden, for: .tabBar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ✅ Step-specific visuals ONLY (never replace the sandbox)
            latticeStepOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(10)
        }
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            baselineVisiblePrimes = latticeStore.visiblePrimes
            let baseline = TenneyPracticeSnapshot()
            practiceSnapshot = baseline.trackingNewKeys(since: baseline)
            UserDefaults.standard.set(false, forKey: SettingsKeys.latticeRememberLastView)
            UserDefaults.standard.set(false, forKey: SettingsKeys.overlay7)
            UserDefaults.standard.set(false, forKey: SettingsKeys.overlay11)
            applyOverlayPrimeState(Set<Int>())
        }
        .onDisappear {
            guard didSeed else { return }
            applyOverlayPrimeState(baselineVisiblePrimes)
            practiceSnapshot?.restore()
        }
    }

    @ViewBuilder
    private var latticeStepOverlay: some View {
        switch stepIndex {
        case 0:
            Color.clear
        case 1:
            // step 2: keep it NON-OPAQUE so the lattice remains visible
            Color.clear
        default:
            Color.clear
        }
    }
}


private struct TunerPracticeHost: View {
    @State private var stageActive = false
    @StateObject private var tunerStore = TunerStore()
    @EnvironmentObject private var app: AppModel
    var body: some View {
        TunerCard(store: tunerStore, stageActive: $stageActive)
            .onAppear {
                app.setPipelineActive(true, reason: "learn_practice_tuner")
            }
            .onDisappear {
                app.setPipelineActive(false, reason: "learn_practice_tuner")
            }
    }
}

private struct BuilderPracticeHost: View {
    @StateObject private var store = ScaleBuilderStore(
        payload: ScaleBuilderPayload(rootHz: 440.0, primeLimit: 5, items: [])
    )
    @EnvironmentObject private var app: AppModel
    @State private var practiceSnapshot: TenneyPracticeSnapshot? = nil
    @State private var didSeed = false
    @State private var baselineBuilderSession: AppModel.BuilderSessionState? = nil
    @State private var baselineBuilderPayload: ScaleBuilderPayload? = nil

    private func seedBuilderPractice() {
        let seed: [RatioRef] = [
            RatioRef(p: 9, q: 8, octave: 0, monzo: [:]),
            RatioRef(p: 5, q: 4, octave: 0, monzo: [:]),
            RatioRef(p: 4, q: 3, octave: 0, monzo: [:]),
            RatioRef(p: 3, q: 2, octave: 0, monzo: [:]),
            RatioRef(p: 5, q: 3, octave: 0, monzo: [:]),
            RatioRef(p: 15, q: 8, octave: 0, monzo: [:])
        ]
        store.payload.items = []
        seed.forEach { store.add($0) }
    }

    var body: some View {
        ScaleBuilderScreen(store: store)
            .environment(\.tenneyPracticeActive, true)
            .onAppear {
                guard !didSeed else { return }
                didSeed = true
                baselineBuilderSession = app.builderSession
                baselineBuilderPayload = app.builderSessionPayload
                app.builderSession = .init()
                app.builderSessionPayload = nil
                let baseline = TenneyPracticeSnapshot()
                seedBuilderPractice()
                practiceSnapshot = baseline.trackingNewKeys(since: baseline)
            }
            .onDisappear {
                practiceSnapshot?.restore()
                if let baselineBuilderSession {
                    app.builderSession = baselineBuilderSession
                }
                app.builderSessionPayload = baselineBuilderPayload
            }
    }
}
  
