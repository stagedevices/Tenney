//
//  LearnCoordinatorTests.swift
//  TenneyTests
//
//  Created by Sebastian Suarez-Solis on 1/2/26.
//

import Testing
@testable import Tenney

@MainActor
struct LearnCoordinatorTests {
    @Test func tunerAdvancesOnExpectedEvents() async {
        let steps = LearnStepFactory.steps(for: .tuner)
        let coordinator = LearnCoordinator(module: .tuner, steps: steps)

        #expect(coordinator.currentStepIndex == 0)
        LearnEventBus.shared.send(.tunerTargetPicked("3/2"))
        await Task.yield()
        #expect(coordinator.currentStepIndex == 1)

        LearnEventBus.shared.send(.tunerLockToggled(true))
        await Task.yield()
        #expect(coordinator.currentStepIndex == 2)
    }

    @Test func latticeAdvancesOnExpectedEvents() async {
        let steps = LearnStepFactory.steps(for: .lattice)
        let coordinator = LearnCoordinator(module: .lattice, steps: steps)

        #expect(coordinator.currentStepIndex == 0)
        LearnEventBus.shared.send(.latticeNodeSelected("1/1"))
        await Task.yield()
        #expect(coordinator.currentStepIndex == 1)

        LearnEventBus.shared.send(.latticeAuditionEnabledChanged(true))
        await Task.yield()
        #expect(coordinator.currentStepIndex == 2)
    }
}
