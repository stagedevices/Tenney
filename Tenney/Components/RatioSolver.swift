//
//  RatioResult.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


import Foundation

 struct RatioCandidate: Identifiable, Hashable {
     let ref: RatioRef
     let hz: Double
     let cents: Double
     let tenneyHeight: Int

     var id: String { ref.id }
     var ratioText: String { RatioMath.unitLabel(ref.p, ref.q) }

     init(ref: RatioRef, hz: Double, cents: Double) {
        self.ref = ref
        self.hz = hz
        self.cents = cents
        self.tenneyHeight = RatioMath.tenneyHeight(p: ref.p, q: ref.q)
    }
}

public struct RatioResult: Hashable {
    public let num: Int
    public let den: Int
    public let octave: Int
    public let centsError: Int

    public init(num: Int, den: Int, octave: Int) {
        self.num = max(1, num)
        self.den = max(1, den)
        self.octave = octave
        self.centsError = 0
    }

    /// Unit-octave ratio string (octave is intentionally separate).
    public var ratioString: String { "\(num)/\(den)" }

    public func targetHz(rootHz: Double) -> Double {
        RatioMath.ratioToHz(p: num, q: den, octave: octave, rootHz: rootHz, centsError: centsError)
    }
}

public struct RatioNeighborPack: Hashable {
    public let main: RatioResult
    public let lower: RatioResult
    public let higher: RatioResult
}

public final class RatioSolver {
    
    
    public struct Config: Sendable {
        /// Max denominator considered when generating unit-octave ratios (1 ≤ num/den < 2).
        public var maxDen: Int = 256
        /// Hard cap on how many unit ratios we keep per prime-limit (after sorting by “simplicity”).
        public var maxUnitRatios: Int = 4096

        public init() {}
    }

    private struct UnitRatio {
        let num: Int
        let den: Int
        let value: Double
        let complexity: Int
    }

    private let config: Config

    // Cache: primeLimit -> unit ratios
    private var cache: [Int: [UnitRatio]] = [:]
    private let lock = NSLock()

    private static let shared = RatioSolver()

    public init(config: Config = .init()) {
        self.config = config
    }

    /// Main API expected by your pitch pipeline. :contentReference[oaicite:2]{index=2}
    public func nearestWithNeighbors(for hz: Double, rootHz: Double, primeLimit: Int) -> RatioNeighborPack {
        guard hz.isFinite, hz > 0, rootHz.isFinite, rootHz > 0 else {
            let r = RatioResult(num: 1, den: 1, octave: 0)
            return .init(main: r, lower: r, higher: r)
        }

        let r = hz / rootHz
        let units = unitRatios(for: max(2, primeLimit))
        if units.isEmpty {
            let rr = RatioResult(num: 1, den: 1, octave: 0)
            return .init(main: rr, lower: rr, higher: rr)
        }

        var best: (res: RatioResult, absCents: Double, hz: Double)? = nil

        var lower1: (res: RatioResult, hz: Double)? = nil
        var lower2: (res: RatioResult, hz: Double)? = nil
        var higher1: (res: RatioResult, hz: Double)? = nil
        var higher2: (res: RatioResult, hz: Double)? = nil

        for u in units {
            // Pick octave that minimizes error for this unit ratio.
            let k = Int(round(log2(r / u.value)))
            let candHz = ldexp(rootHz * u.value, k) // rootHz * u * 2^k
            if !(candHz.isFinite && candHz > 0) { continue }

            let cents = 1200.0 * log2(hz / candHz)
            let absCents = abs(cents)

            let cand = RatioResult(num: u.num, den: u.den, octave: k)

            if best == nil || absCents < best!.absCents {
                best = (cand, absCents, candHz)
            }

            if candHz <= hz {
                if lower1 == nil || candHz > lower1!.hz {
                    lower2 = lower1
                    lower1 = (cand, candHz)
                } else if lower2 == nil || candHz > lower2!.hz {
                    lower2 = (cand, candHz)
                }
            } else {
                if higher1 == nil || candHz < higher1!.hz {
                    higher2 = higher1
                    higher1 = (cand, candHz)
                } else if higher2 == nil || candHz < higher2!.hz {
                    higher2 = (cand, candHz)
                }
            }
        }

        let fallback = RatioResult(num: 1, den: 1, octave: 0)
        let main = best?.res ?? fallback

        // Ensure lower/higher exist and (ideally) differ from main.
        let lowerPick: RatioResult = {
            if let l1 = lower1?.res, l1 != main { return l1 }
            if let l2 = lower2?.res, l2 != main { return l2 }
            // If we never found <=hz, use nearest >=hz as “lower” fallback (rare at extremes)
            if let h1 = higher1?.res, h1 != main { return h1 }
            return main
        }()

        let higherPick: RatioResult = {
            if let h1 = higher1?.res, h1 != main { return h1 }
            if let h2 = higher2?.res, h2 != main { return h2 }
            // If we never found >=hz, use nearest <=hz as “higher” fallback (rare at extremes)
            if let l1 = lower1?.res, l1 != main { return l1 }
            return main
        }()

        return .init(main: main, lower: lowerPick, higher: higherPick)
    }

     static func candidates(aroundHz hz: Double,
                                  rootHz: Double,
                                  primeLimit: Int,
                                  axisShift: [Int:Int],
                                  count: Int) -> [RatioCandidate] {
        shared.candidates(aroundHz: hz, rootHz: rootHz, primeLimit: primeLimit, axisShift: axisShift, count: count)
    }

     func candidates(aroundHz hz: Double,
                           rootHz: Double,
                           primeLimit: Int,
                           axisShift: [Int:Int],
                           count: Int) -> [RatioCandidate] {
        guard hz.isFinite, hz > 0, rootHz.isFinite, rootHz > 0, count > 0 else { return [] }

        let units = unitRatios(for: max(2, primeLimit))
        if units.isEmpty { return [] }

        let targetRatio = hz / rootHz

        func applyAxisShift(num: Int, den: Int) -> (Int, Int) {
            var n = num
            var d = den
            for (prime, exp) in axisShift {
                guard prime > 1, exp != 0 else { continue }
                if exp > 0 {
                    n = RatioMath.powMul(n, base: prime, exp: exp)
                } else {
                    d = RatioMath.powMul(d, base: prime, exp: -exp)
                }
            }
            return RatioMath.canonicalPQUnit(n, d)
        }

        var seen = Set<String>()
        var out: [(cand: RatioCandidate, absCents: Double)] = []
        out.reserveCapacity(min(count * 2, 64))

        for u in units {
            let (pAdj, qAdj) = applyAxisShift(num: u.num, den: u.den)
            let baseValue = Double(pAdj) / Double(qAdj)
            guard baseValue.isFinite, baseValue > 0 else { continue }

            let octave = Int(round(log2(targetRatio / baseValue)))
            let candHz = ldexp(rootHz * baseValue, octave)
            guard candHz.isFinite, candHz > 0 else { continue }

            let cents = 1200.0 * log2(hz / candHz)
            let key = "\(pAdj)/\(qAdj)@\(octave)"
            if seen.contains(key) { continue }
            seen.insert(key)

            let ref = RatioRef(p: pAdj, q: qAdj, octave: octave)
            let cand = RatioCandidate(ref: ref, hz: candHz, cents: cents)
            out.append((cand, abs(cents)))
        }

        out.sort {
            if $0.absCents != $1.absCents { return $0.absCents < $1.absCents }
            return $0.cand.tenneyHeight < $1.cand.tenneyHeight
        }

        return out.prefix(count).map { $0.cand }
    }

    // MARK: - Unit ratio generation

    private func unitRatios(for primeLimit: Int) -> [UnitRatio] {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[primeLimit] { return existing }

        let primes = primesUpTo(primeLimit)
        let maxDen = max(1, config.maxDen)

        var seen = Set<UInt64>()
        var out: [UnitRatio] = []
        out.reserveCapacity(min(config.maxUnitRatios, 2048))

        for den in 1...maxDen {
            // unit octave: 1 <= num/den < 2  =>  den <= num <= 2*den-1
            let numLo = den
            let numHi = (2 * den) - 1
            for num in numLo...numHi {
                let g = RatioMath.gcd(num, den)
                let n = num / g
                let d = den / g

                if !isSmooth(n, primes: primes) { continue }
                if !isSmooth(d, primes: primes) { continue }

                let key = (UInt64(n) << 32) | UInt64(d)
                if seen.contains(key) { continue }
                seen.insert(key)

                let v = Double(n) / Double(d)
                if !(v.isFinite && v >= 1.0 && v < 2.0) { continue }

                // “Simplicity” heuristic: low height tends to read well in UI.
                let complexity = n + d

                out.append(.init(num: n, den: d, value: v, complexity: complexity))
            }
        }

        // Keep the simplest ratios first, then ordered by value.
        out.sort {
            if $0.complexity != $1.complexity { return $0.complexity < $1.complexity }
            if $0.num != $1.num { return $0.num < $1.num }
            return $0.den < $1.den
        }

        if out.count > config.maxUnitRatios {
            out = Array(out.prefix(config.maxUnitRatios))
        }

        cache[primeLimit] = out
        return out
    }

    private func isSmooth(_ n: Int, primes: [Int]) -> Bool {
        if n == 1 { return true }
        var x = n
        for p in primes {
            while x % p == 0 { x /= p }
            if x == 1 { return true }
        }
        return x == 1
    }

    private func primesUpTo(_ max: Int) -> [Int] {
        if max < 2 { return [2] }
        if max == 2 { return [2] }

        var isPrime = [Bool](repeating: true, count: max + 1)
        isPrime[0] = false
        isPrime[1] = false

        let r = Int(Double(max).squareRoot())
        if r >= 2 {
            for p in 2...r where isPrime[p] {
                var m = p * p
                while m <= max {
                    isPrime[m] = false
                    m += p
                }
            }
        }

        var ps: [Int] = []
        ps.reserveCapacity(32)
        for i in 2...max where isPrime[i] {
            ps.append(i)
        }
        return ps
    }
}
