import Foundation
import CoreGraphics

struct LatticeNode: Identifiable, Hashable, Sendable {
    let id: UUID

    // “New” fields expected by LatticeView / LatticeLayout
    let coord: LatticeCoord
    let pos: CGPoint
    let tenneyHeight: Int

    // “Old” fields (keep compatibility)
    let ratio: Ratio?
    let monzo: [Int]?
    let tags: [String]

    // New initializer used by LatticeLayout.planeNodes(...)
    init(coord: LatticeCoord, pos: CGPoint, tenneyHeight: Int, id: UUID = UUID()) {
        self.id = id
        self.coord = coord
        self.pos = pos
        self.tenneyHeight = tenneyHeight
        self.ratio = nil
        self.monzo = nil
        self.tags = []
    }

    // Existing initializer shape used elsewhere
    init(ratio: Ratio, monzo: [Int], tags: [String], id: UUID = UUID()) {
        self.id = id
        self.ratio = ratio
        self.monzo = monzo
        self.tags = tags

        // Best-effort derivations so the rest of the UI can still draw.
        // Prime index map: 0→2, 1→3, 2→5, 3→7, 4→11, ...
        let primes: [Int] = [2,3,5,7,11,13,17,19,23,29,31]
        var d: [Int:Int] = [:]
        for (i, e) in monzo.enumerated() where i < primes.count && e != 0 {
            d[primes[i]] = e
        }

        let e3 = d[3] ?? 0
        let e5 = d[5] ?? 0
        self.coord = LatticeCoord(e3: e3, e5: e5)
        self.pos = LatticeLayout().position(monzo: d)

        // If you have a real TH function elsewhere, swap this later.
        self.tenneyHeight = 1
    }

    static func == (lhs: LatticeNode, rhs: LatticeNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
