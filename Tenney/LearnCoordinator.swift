//
//  LearnCoordinator.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/30/25.
//


//  LearnCoordinator.swift
//  Tenney

import SwiftUI
import Combine

final class LearnCoordinator: ObservableObject {
    var stepCount: Int { steps.count }

    var currentStep: LearnStep? {
        guard !completed, !steps.isEmpty else { return nil }
        let i = min(max(0, currentStepIndex), steps.count - 1)
        return steps[i]
    }

    @Published var currentStepIndex: Int = 0
    @Published var gate: LearnGate = .init()
    @Published var completed = false


    private var cancellables = Set<AnyCancellable>()
    private let module: LearnTenneyModule
    private let steps: [LearnStep]
    private var builderStep4Pads: Set<Int> = []
    private var builderStep4TimerTask: Task<Void, Never>? = nil

    init(module: LearnTenneyModule, steps: [LearnStep]) {
        self.module = module
        self.steps = steps
        self.gate = steps.first?.gate ?? LearnGate()
        subscribe()
        enterStep(0)
    }

    deinit {
        resetBuilderStep4State()
    }

    private func subscribe() {
        LearnEventBus.shared.publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }
    
    func next() { advance() }

    func back() {
        guard currentStepIndex > 0 else { return }
        resetBuilderStep4State()
        currentStepIndex -= 1
        enterStep(currentStepIndex)
        persistState(stepIndex: currentStepIndex, completed: false)
    }

    func reset() {
        completed = false
        currentStepIndex = 0
        enterStep(0)
        persistState(stepIndex: 0, completed: false)
    }


    private func handle(_ event: LearnEvent) {
        guard currentStepIndex < steps.count else { return }
        handleBuilderStep4Event(event)
        let step = steps[currentStepIndex]
        let validated = step.validate(event)
#if DEBUG
        print("[LearnCoordinator] module=\(module) step \(currentStepIndex + 1)/\(steps.count) \"\(step.title)\" event=\(event) validated=\(validated)")
#endif
        if validated {
            advance()
        } else if gate.isActive, !isAttemptedDisallowedAction(event) {            LearnEventBus.shared.send(.attemptedDisallowedAction("\(event)"))
        }
    }
    
    private func isAttemptedDisallowedAction(_ event: LearnEvent) -> Bool {
            if case .attemptedDisallowedAction = event { return true }
            return false
        }

    private func enterStep(_ i: Int) {
        guard i < steps.count else { completed = true; return }
        resetBuilderStep4State()
        gate = steps[i].gate
    }

    private func advance() {
        let next = currentStepIndex + 1
        resetBuilderStep4State()
        if next < steps.count {
            currentStepIndex = next
            gate = steps[next].gate
            persistState(stepIndex: next, completed: false)
        } else {
            completed = true
            gate = LearnGate() // unlock everything
            persistState(stepIndex: steps.count, completed: true)
        }
    }

    private func persistState(stepIndex: Int, completed: Bool) {
        LearnTenneyPersistence.shared.saveState(module, stepIndex: stepIndex, completed: completed)
    }

    private func handleBuilderStep4Event(_ event: LearnEvent) {
        guard isBuilderStep4Active else { return }
        guard case let .builderPadTriggered(index) = event else { return }
        builderStep4Pads.insert(index)
#if DEBUG
        print("[LearnCoordinator] builder step 4 pad count=\(builderStep4Pads.count)")
#endif
        startBuilderStep4TimerIfNeeded()
    }

    private var isBuilderStep4Active: Bool {
        module == .builder && currentStepIndex == 3 && !completed
    }

    private func resetBuilderStep4State() {
        builderStep4Pads.removeAll()
        builderStep4TimerTask?.cancel()
        builderStep4TimerTask = nil
#if DEBUG
        if module == .builder {
            print("[LearnCoordinator] builder step 4 reset/cancel")
        }
#endif
    }

    private func startBuilderStep4TimerIfNeeded() {
        guard isBuilderStep4Active else { return }
        guard builderStep4Pads.count >= 2 else { return }
        guard builderStep4TimerTask == nil else { return }
#if DEBUG
        print("[LearnCoordinator] builder step 4 timer started")
#endif
        builderStep4TimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.isBuilderStep4Active, self.builderStep4Pads.count >= 2 else { return }
#if DEBUG
                print("[LearnCoordinator] builder step 4 timer satisfied")
#endif
                self.handle(.builderScopeTimedSatisfied)
            }
            await MainActor.run {
                if self.builderStep4TimerTask?.isCancelled == false {
                    self.builderStep4TimerTask = nil
                }
            }
        }
    }
}

struct LearnStep: Sendable {
    let title: String
    let bullets: [String]
    let instruction: String?
    let tryIt: String

    let gate: LearnGate
    let validate: @Sendable (LearnEvent) -> Bool

    // Bullets-style steps (Lattice / rich copy)
    init(
        title: String,
        bullets: [String],
        tryIt: String,
        gate: LearnGate = .init(),
        validate: @escaping @Sendable (LearnEvent) -> Bool
    ) {
        self.title = title
        self.bullets = bullets
        self.instruction = nil
        self.tryIt = tryIt
        self.gate = gate
        self.validate = validate
    }

    // Instruction-style steps (older Tuner/Builder)
    init(
        title: String,
        instruction: String,
        tryIt: String,
        gate: LearnGate = .init(),
        validate: @escaping @Sendable (LearnEvent) -> Bool
    ) {
        self.title = title
        self.bullets = []
        self.instruction = instruction
        self.tryIt = tryIt
        self.gate = gate
        self.validate = validate
    }

    // Back-compat (your original minimal init)
    init(
        gate: LearnGate,
        validate: @escaping @Sendable (LearnEvent) -> Bool
    ) {
        self.title = ""
        self.bullets = []
        self.instruction = nil
        self.tryIt = ""
        self.gate = gate
        self.validate = validate
    }
}



typealias LearnTenneyPersistence = TenneyPracticeSnapshot
