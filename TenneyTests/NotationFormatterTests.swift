//
//  NotationFormatterTests.swift
//  TenneyTests
//
//  Created by OpenAI on 2025-01-09.
//

import Testing
@testable import Tenney

struct NotationFormatterTests {

    @Test func closestHelmholtzLabelTracksFrequencyChanges() async throws {
        let labelLow = NotationFormatter.closestHelmholtzLabel(
            freqHz: 220.0 * (3.0 / 2.0),
            a4Hz: 440.0,
            preference: .auto
        )
        let labelHigh = NotationFormatter.closestHelmholtzLabel(
            freqHz: 440.0 * (3.0 / 2.0),
            a4Hz: 440.0,
            preference: .auto
        )
        #expect(labelLow == "e′")
        #expect(labelHigh == "e″")
    }

    @Test func closestHelmholtzLabelUsesA4Reference() async throws {
        let labelStandard = NotationFormatter.closestHelmholtzLabel(
            freqHz: 440.0,
            a4Hz: 440.0,
            preference: .preferSharps
        )
        let labelShifted = NotationFormatter.closestHelmholtzLabel(
            freqHz: 440.0,
            a4Hz: 256.0,
            preference: .preferSharps
        )
        #expect(labelStandard == "a′")
        #expect(labelShifted == "f♯″")
    }

    @Test func closestHelmholtzLabelKnownPitches() async throws {
        let a4 = NotationFormatter.closestHelmholtzLabel(
            freqHz: 440.0,
            a4Hz: 440.0,
            preference: .auto
        )
        let middleC = NotationFormatter.closestHelmholtzLabel(
            freqHz: 261.6256,
            a4Hz: 440.0,
            preference: .auto
        )
        #expect(a4 == "a′")
        #expect(middleC == "c′")
    }
}
