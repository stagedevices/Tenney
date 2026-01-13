//
//  LatticeStorePersistTests.swift
//  TenneyTests
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Testing
@testable import Tenney

struct LatticeStorePersistTests {
    @Test func persistBlobRoundTripWithGhosts() throws {
        let ghostA = LatticeStore.GhostMonzo(e3: 1, e5: -1, p: 7, eP: 2)
        let ghostB = LatticeStore.GhostMonzo(e3: -2, e5: 1, p: 11, eP: -1)
        let ghostC = LatticeStore.GhostMonzo(e3: 0, e5: 0, p: 13, eP: 3)

        let blob = LatticeStore.PersistBlob(
            camera: .init(tx: 1.25, ty: -2.5, scale: 1.4),
            pivot: .init(e3: 2, e5: -3),
            visiblePrimes: [7, 11, 13],
            axisShift: [3: 1, 5: 0, 7: -1],
            mode: LatticeStore.LatticeMode.select.rawValue,
            selected: [
                .init(e3: 0, e5: 0),
                .init(e3: 1, e5: 2)
            ],
            selectedGhosts: [
                .init(from: ghostA),
                .init(from: ghostB),
                .init(from: ghostC)
            ],
            selectionOrderGhosts: [
                .init(from: ghostB),
                .init(from: ghostA),
                .init(from: ghostC)
            ],
            octaveOffsets: [
                .init(ghost: .init(from: ghostA), offset: 1),
                .init(ghost: .init(from: ghostB), offset: -2)
            ],
            guidesOn: true,
            labelMode: JILabelMode.ratio.rawValue,
            audition: false
        )

        let data = try JSONEncoder().encode(blob)
        let decoded = try JSONDecoder().decode(LatticeStore.PersistBlob.self, from: data)

        #expect(decoded.camera.tx == blob.camera.tx)
        #expect(decoded.camera.ty == blob.camera.ty)
        #expect(decoded.camera.scale == blob.camera.scale)
        #expect(decoded.pivot.e3 == blob.pivot.e3)
        #expect(decoded.pivot.e5 == blob.pivot.e5)
        #expect(decoded.visiblePrimes == blob.visiblePrimes)
        #expect(decoded.axisShift == blob.axisShift)
        #expect(decoded.mode == blob.mode)
        #expect(decoded.guidesOn == blob.guidesOn)
        #expect(decoded.labelMode == blob.labelMode)
        #expect(decoded.audition == blob.audition)

        let decodedPlane = decoded.selected.map { ($0.e3, $0.e5) }
        let expectedPlane = blob.selected.map { ($0.e3, $0.e5) }
        #expect(decodedPlane == expectedPlane)

        let decodedGhosts = Set((decoded.selectedGhosts ?? []).map { ($0.e3, $0.e5, $0.p, $0.eP) })
        let expectedGhosts = Set((blob.selectedGhosts ?? []).map { ($0.e3, $0.e5, $0.p, $0.eP) })
        #expect(decodedGhosts == expectedGhosts)

        let decodedGhostOrder = (decoded.selectionOrderGhosts ?? []).map { ($0.e3, $0.e5, $0.p, $0.eP) }
        let expectedGhostOrder = (blob.selectionOrderGhosts ?? []).map { ($0.e3, $0.e5, $0.p, $0.eP) }
        #expect(decodedGhostOrder == expectedGhostOrder)

        let decodedOffsets = Dictionary(
            uniqueKeysWithValues: (decoded.octaveOffsets ?? []).map { ($0.ghost, $0.offset) }
        )
        let expectedOffsets = Dictionary(
            uniqueKeysWithValues: (blob.octaveOffsets ?? []).map { ($0.ghost, $0.offset) }
        )
        #expect(decodedOffsets == expectedOffsets)
    }
}
