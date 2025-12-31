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
    @Published var gate = LearnGate()
    @Published var completed = false

    private var cancellables = Set<AnyCancellable>()
    private let module: LearnTenneyModule
    private let steps: [LearnStep]

    init(module: LearnTenneyModule, steps: [LearnStep]) {
        self.module = module
        self.steps = steps
        self.gate = steps.first?.gate ?? LearnGate()
        subscribe()
        enterStep(0)
    }

    private func subscribe() {
        LearnEventBus.shared.publisher
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }
    
    func next() { advance() }

    func back() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
        enterStep(currentStepIndex)
    }

    func reset() {
        completed = false
        currentStepIndex = 0
        enterStep(0)
    }


    private func handle(_ event: LearnEvent) {
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]
        if step.validate(event) {
            advance()
        } else if gate.isActive {
            LearnEventBus.shared.send(.attemptedDisallowedAction("\(event)"))
        }
    }

    private func enterStep(_ i: Int) {
        guard i < steps.count else { completed = true; return }
        gate = steps[i].gate
    }

    private func advance() {
        let next = currentStepIndex + 1
        if next < steps.count {
            currentStepIndex = next
            gate = steps[next].gate
        } else {
            completed = true
            gate = LearnGate() // unlock everything
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
