//
//  TunerRatioDisplayTests.swift
//  TenneyTests
//
//  Created by OpenAI on 2024-05-07.
//

import Testing
@testable import Tenney

struct TunerRatioDisplayTests {

    @Test func unfoldedRatioRefFormatting() async throws {
        let downTwo = RatioRef(p: 1, q: 1, octave: -2, monzo: [:])
        #expect(unfoldedRatioString(downTwo) == "1/4")

        let upOne = RatioRef(p: 5, q: 4, octave: 1, monzo: [:])
        #expect(unfoldedRatioString(upOne) == "5/2")
    }

    @Test func tunerDisplayUsesUnfoldedRatioResult() async throws {
        let result = RatioResult(num: 3, den: 2, octave: -1)
        #expect(tunerDisplayRatioString(result) == "3/4")
    }
}
