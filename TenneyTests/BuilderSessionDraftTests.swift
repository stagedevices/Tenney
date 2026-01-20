//
//  BuilderSessionDraftTests.swift
//  TenneyTests
//
//  Created by Sebastian Suarez-Solis on 10/6/25.
//

import Testing
@testable import Tenney

struct BuilderSessionDraftTests {
    @Test @MainActor func draftAppendsAcrossAddCycles() {
        let app = AppModel()
        let base = TenneyScale(
            name: "Base",
            degrees: [
                RatioRef(p: 1, q: 1),
                RatioRef(p: 3, q: 2)
            ],
            referenceHz: 440.0
        )
        app.builderLoadedScale = base

        #expect(app.builderSession.draftInitialized)
        #expect(app.builderSession.draftDegrees == base.degrees)

        let batchA = [RatioRef(p: 5, q: 4)]
        app.appendBuilderDraftRefs(batchA)
        #expect(app.builderSession.draftDegrees.count == base.degrees.count + batchA.count)

        let batchB = [RatioRef(p: 7, q: 4)]
        app.appendBuilderDraftRefs(batchB)
        #expect(
            app.builderSession.draftDegrees.count ==
                base.degrees.count + batchA.count + batchB.count
        )
        #expect(app.builderSession.draftDegrees.suffix(2) == [batchA[0], batchB[0]])
    }
}
