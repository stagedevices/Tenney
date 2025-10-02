//
//  Resolver.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

final class RatioResolver {
    struct State {
        var current: Ratio = Ratio(1,1)
        var currentCentsError: Double = 0
        var lastSwitchMonotonic: Double = 0
    }

    private(set) var state = State()
    var rootHz: Double = 220.0
    var limit: PrimeLimit = .eleven
    var strictness: Strictness = .performance

    func reset(rootHz: Double? = nil) {
        if let r = rootHz { self.rootHz = r }
        state = State()
    }

    /// Returns (primary, cents, alternatives[up to 2])
    func resolve(frequencyHz: Double, monotonicTime: Double) -> (Ratio, Double, [Ratio]) {
        // Safe guardrails
        guard frequencyHz.isFinite, frequencyHz > 0, rootHz.isFinite, rootHz > 0 else {
            return (state.current, state.currentCentsError, [])
        }

        // 1) Real ratio vs root
        let x = frequencyHz / rootHz
        let best = RatioApproximator.approximate(x, options: .init(primeLimit: limit, maxDenominator: 4096, maxCentsError: 60))
        // Use the pure analytic cents error; no temporary Ratio needed.
        let centsError = 1200.0 * log2(x / best.value)

        // 2) Hysteresis + dwell
        let shouldSwitch: Bool = {
            if state.current == Ratio(1,1) { return true }
            if best == state.current { return false }
            let band = strictness.hysteresisCents
            let currentTargetHz = rootHz * state.current.value
            let currentCents = 1200.0 * log2(frequencyHz / currentTargetHz)
            if abs(currentCents) <= band { return false }
            let elapsed = (monotonicTime - state.lastSwitchMonotonic) * 1000.0
            return elapsed >= Double(strictness.minDwellMs)
        }()

        if shouldSwitch {
            state.current = best
            state.lastSwitchMonotonic = monotonicTime
        }
        state.currentCentsError = centsError

        // 3) Alternatives
        let alts = alternativeRatios(around: x, exclude: state.current, limit: limit, maxCount: 2)
        return (state.current, centsError, alts)
    }

    private func alternativeRatios(around x: Double, exclude: Ratio, limit: PrimeLimit, maxCount: Int) -> [Ratio] {
        let best = RatioApproximator.approximate(x, options: .init(primeLimit: limit, maxDenominator: 4096, maxCentsError: 120))
        var set = Set<Ratio>(); set.insert(best)
        var candidates: [Ratio] = []
        func consider(_ r: Ratio) {
            if r == exclude || set.contains(r) { return }
            guard let _ = r.toMonzoIfWithin13() else { return }
            set.insert(r); candidates.append(r)
        }
        for dn in [-2,-1,1,2] { consider(Ratio(best.n + dn, best.d)) }
        for dd in [-2,-1,1,2] {
            let d = best.d + dd
            if d > 0 { consider(Ratio(best.n, d)) }
        }
        let scored = candidates.map { r -> (Ratio, Double, Double) in
            let c = abs(1200.0 * log2(r.value / x))
            let h = r.toMonzoIfWithin13()?.tenneyHeight ?? 1e9
            return (r, c, h)
        }.sorted { a, b in abs(a.1 - b.1) > 1e-9 ? a.1 < b.1 : a.2 < b.2 }
        return Array(scored.prefix(maxCount)).map { $0.0 }
    }
}
