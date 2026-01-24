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
    private let primeComponents: [Int: Heji2DirectionalGlyphs]

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
            guard let glyphs = primeComponents[component.prime] else { continue }
            out.append(contentsOf: component.up ? glyphs.up : glyphs.down)
        }
        return out
    }
}

private struct Heji2MappingPayload: Decodable {
    let fonts: Heji2FontNames?
    let diatonicAccidentals: [String: [Heji2Glyph]]
    let primeComponents: [String: Heji2DirectionalGlyphs]
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
