//
//  NextNodeSelectionTests.swift
//  TenneyTests
//

import CoreGraphics
import Testing
@testable import Tenney

struct NextNodeSelectionTests {
    @Test func picksVisibleOverOffscreenAtEqualDistance() async throws {
        let candidates = [
            NextNodeSelection.Candidate(
                id: "a",
                stableID: "a",
                position: CGPoint(x: 1, y: 0),
                isVisible: false,
                isGhost: false,
                opacityOrPriority: nil,
                complexity: 1.0
            ),
            NextNodeSelection.Candidate(
                id: "b",
                stableID: "b",
                position: CGPoint(x: 1, y: 0),
                isVisible: true,
                isGhost: false,
                opacityOrPriority: nil,
                complexity: 1.0
            )
        ]

        let pick = NextNodeSelection.pickNext(
            from: candidates,
            excluding: "none",
            referencePoint: .zero,
            preferVisibleSubset: true,
            priorDirection: nil,
            displayScale: 2
        )

        #expect(pick == "b")
    }

    @Test func picksNonGhostThenLowerComplexity() async throws {
        let candidates = [
            NextNodeSelection.Candidate(
                id: "ghost",
                stableID: "ghost",
                position: CGPoint(x: 1, y: 0),
                isVisible: true,
                isGhost: true,
                opacityOrPriority: nil,
                complexity: 1.0
            ),
            NextNodeSelection.Candidate(
                id: "plain",
                stableID: "plain",
                position: CGPoint(x: 1, y: 0),
                isVisible: true,
                isGhost: false,
                opacityOrPriority: nil,
                complexity: 9.0
            ),
            NextNodeSelection.Candidate(
                id: "simple",
                stableID: "simple",
                position: CGPoint(x: 1, y: 0),
                isVisible: true,
                isGhost: false,
                opacityOrPriority: nil,
                complexity: 2.0
            )
        ]

        let pick = NextNodeSelection.pickNext(
            from: candidates,
            excluding: "none",
            referencePoint: .zero,
            preferVisibleSubset: true,
            priorDirection: nil,
            displayScale: 2
        )

        #expect(pick == "simple")
    }

    @Test func breaksFullTieWithStableID() async throws {
        let candidates = [
            NextNodeSelection.Candidate(
                id: "b",
                stableID: "b",
                position: CGPoint(x: 1, y: 0),
                isVisible: true,
                isGhost: false,
                opacityOrPriority: nil,
                complexity: 1.0
            ),
            NextNodeSelection.Candidate(
                id: "a",
                stableID: "a",
                position: CGPoint(x: 1, y: 0),
                isVisible: true,
                isGhost: false,
                opacityOrPriority: nil,
                complexity: 1.0
            )
        ]

        let pick = NextNodeSelection.pickNext(
            from: candidates,
            excluding: "none",
            referencePoint: .zero,
            preferVisibleSubset: true,
            priorDirection: nil,
            displayScale: 2
        )

        #expect(pick == "a")
    }
}
