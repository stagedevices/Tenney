//
//  Heji2Mapping.swift
//  Tenney
//

import Foundation

struct Heji2Glyph: Hashable, Decodable {
    let glyph: String
    let staffOffset: Heji2Offset?
    let textOffset: Heji2Offset?
    let advance: Double?
    let staffAdvance: Double?
    let textAdvance: Double?

    var string: String { glyph }
}

struct Heji2Offset: Hashable, Decodable {
    let x: Double
    let y: Double
}

final class Heji2Mapping {
    static let shared = Heji2Mapping()

    let textFontName: String?
    let musicFontName: String?

    private let diatonicAccidentals: [Int: [Heji2Glyph]]
    /// prime -> steps -> directional glyphs (supports step-aware rendering: 3 => 2+1, etc)
    private let primeComponents: [Int: [Int: Heji2DirectionalGlyphs]]

    private init() {
        let bundles = [Bundle.main, Bundle(for: Heji2Mapping.self)]
        let url = bundles.compactMap { $0.url(forResource: "heji2_mapping", withExtension: "json") }.first
        guard let resourceUrl = url,
              let data = try? Data(contentsOf: resourceUrl),
              let decoded = try? JSONDecoder().decode(Heji2MappingPayload.self, from: data) else {
            textFontName = nil
            musicFontName = nil
            diatonicAccidentals = [:]
            primeComponents = [:]
            return
        }
        textFontName = decoded.fonts?.text
        musicFontName = decoded.fonts?.music
        diatonicAccidentals = decoded.diatonicAccidentals.decodeIntKeyedGlyphs()
        primeComponents = decoded.primeComponents.decodeIntKeyedComponents()
    }

    var supportedPrimes: Set<Int> {
        Set(primeComponents.keys)
    }
    
    func availableSteps(forPrime prime: Int) -> [Int] {
           guard let steps = primeComponents[prime]?.keys, !steps.isEmpty else { return [1] }
           let sorted = Array(steps).sorted(by: >)
           return sorted.contains(1) ? sorted : (sorted + [1])
       }

    func glyphsForDiatonicAccidental(_ n: Int) -> [Heji2Glyph] {
        guard n != 0 else { return [] }
        if let direct = diatonicAccidentals[n] {
            return direct
        }
        if n > 0, let unit = diatonicAccidentals[1] {
            return Array(repeating: unit, count: n).flatMap { $0 }
        }
        if n < 0, let unit = diatonicAccidentals[-1] {
            return Array(repeating: unit, count: abs(n)).flatMap { $0 }
        }
        return []
    }

    func glyphsForPrimeComponents(_ components: [HejiMicrotonalComponent]) -> [Heji2Glyph] {
        var out: [Heji2Glyph] = []
        for component in components {
            guard let stepsMap = primeComponents[component.prime] else { continue }
                        let resolved = stepsMap[component.steps] ?? stepsMap[1] ?? stepsMap.values.first
                        guard let glyphs = resolved else { continue }
                        out.append(contentsOf: component.up ? glyphs.up : glyphs.down)
        }
        return out
    }
}

private struct Heji2MappingPayload: Decodable {
    let fonts: Heji2FontNames?
    let diatonicAccidentals: [String: [Heji2Glyph]]
    /// Supports BOTH:
    ///  - legacy:  { "5": { "up":[...], "down":[...] } }
    ///  - stepped: { "5": { "1": {...}, "2": {...} } }
    let primeComponents: [String: [String: Heji2DirectionalGlyphs]]

    enum CodingKeys: String, CodingKey { case fonts, diatonicAccidentals, primeComponents }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fonts = try? c.decode(Heji2FontNames.self, forKey: .fonts)
        diatonicAccidentals = try c.decode([String: [Heji2Glyph]].self, forKey: .diatonicAccidentals)

        if let stepped = try? c.decode([String: [String: Heji2DirectionalGlyphs]].self, forKey: .primeComponents) {
            primeComponents = stepped
            return
        }
        let legacy = try c.decode([String: Heji2DirectionalGlyphs].self, forKey: .primeComponents)
        var wrapped: [String: [String: Heji2DirectionalGlyphs]] = [:]
        for (k, v) in legacy { wrapped[k] = ["1": v] }
        primeComponents = wrapped
    }
}

private struct Heji2FontNames: Decodable {
    let text: String?
    let music: String?
}

struct Heji2DirectionalGlyphs: Hashable, Decodable {
    let up: [Heji2Glyph]
    let down: [Heji2Glyph]
}

private extension Dictionary where Key == String, Value == [Heji2Glyph] {
    func decodeIntKeyedGlyphs() -> [Int: [Heji2Glyph]] {
        var out: [Int: [Heji2Glyph]] = [:]
        for (key, value) in self {
            if let intKey = Int(key) {
                out[intKey] = value
            }
        }
        return out
    }
}

private extension Dictionary where Key == String, Value == Heji2DirectionalGlyphs {
    func decodeIntKeyedComponents() -> [Int: Heji2DirectionalGlyphs] {
        var out: [Int: Heji2DirectionalGlyphs] = [:]
        for (key, value) in self {
            if let intKey = Int(key) {
                out[intKey] = value
            }
        }
        return out
    }
}
private extension Dictionary where Key == String, Value == [String: Heji2DirectionalGlyphs] {
    func decodeIntKeyedComponents() -> [Int: [Int: Heji2DirectionalGlyphs]] {
        var out: [Int: [Int: Heji2DirectionalGlyphs]] = [:]
        for (primeKey, stepMap) in self {
            guard let prime = Int(primeKey) else { continue }
            var steps: [Int: Heji2DirectionalGlyphs] = [:]
            for (stepKey, glyphs) in stepMap {
                if let step = Int(stepKey) { steps[step] = glyphs }
            }
            if !steps.isEmpty { out[prime] = steps }
        }
        return out
    }
}
