//
//  RatioTextParsing.swift
//  Tenney
//
//  Created by OpenAI on 2025-02-17.
//

import Foundation

/// Minimal ratio string → (p, q). Accepts "p/q" and trims whitespace.
func parseRatioTextPQ(_ s: String) -> (p: Int, q: Int)? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = t.split(separator: "/")
    guard parts.count == 2,
          let p = Int(parts[0].trimmingCharacters(in: .whitespaces)),
          let q = Int(parts[1].trimmingCharacters(in: .whitespaces)),
          p > 0, q > 0 else { return nil }
    return (p, q)
}

func ratioResultFromText(_ s: String, octave: Int = 0) -> RatioResult? {
    guard let pq = parseRatioTextPQ(s) else { return nil }
    return RatioResult(num: pq.p, den: pq.q, octave: octave)
}

func lockRecentString(_ ratio: RatioResult) -> String {
    "\(ratio.num)/\(ratio.den)|\(ratio.octave)"
}

func ratioResultFromLockRecent(_ s: String) -> RatioResult? {
    let parts = s.split(separator: "|")
    let ratioText = parts.first.map(String.init) ?? s
    let octave = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    guard let pq = parseRatioTextPQ(ratioText) else { return nil }
    return RatioResult(num: pq.p, den: pq.q, octave: octave)
}
