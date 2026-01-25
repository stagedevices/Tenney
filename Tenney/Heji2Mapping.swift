//
//  Heji2Mapping.swift
//  Tenney
//

import Foundation
#if canImport(CoreText)
import CoreText
#endif

struct Heji2Glyph: Hashable, Decodable {
    let glyph: String
    let staffOffset: Heji2Offset?
    let textOffset: Heji2Offset?
    let advance: Double?
    let staffAdvance: Double?
    let textAdvance: Double?

    var string: String { glyph }
}

enum HejiFontKind {
    case music
    case text
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
    private var glyphExistenceCache: [String: Bool] = [:]
    private var glyphFontCache: [String: HejiFontKind] = [:]
#if canImport(CoreText)
    private var ctFontCache: [String: CTFont] = [:]
#endif

    private init() {
        guard let decoded = Heji2MappingPayload.loadFromBundle() else {
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
#if DEBUG
        verifyGlyphsExist()
#endif
    }

    var supportedPrimes: Set<Int> {
        Set(primeComponents.keys)
    }
    
    func availableSteps(forPrime prime: Int) -> [Int] {
        // IMPORTANT: if a prime is not present in the mapping, return [] (not [1]).
                  // Returning [1] makes unsupported primes look supported and causes “missing glyph” bugs.
        guard let steps = primeComponents[prime]?.keys, !steps.isEmpty else { return [] }
        let sorted = Array(steps).sorted(by: >)
           return sorted.contains(1) ? sorted : (sorted + [1])
       }
    func supportsPrime(_ prime: Int) -> Bool {
            primeComponents[prime] != nil
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

    func glyphsForPrimeComponents(
            _ components: [HejiMicrotonalComponent],
            absorbDiatonicIntoPrime5 diatonicAccidental: Int = 0
        ) -> [Heji2Glyph] {
        var out: [Heji2Glyph] = []
        for component in components {
            guard let stepsMap = primeComponents[component.prime] else { continue }
            if let exact = stepsMap[component.steps] {
                let chosen = component.up ? exact.up : exact.down
                out.append(contentsOf: applyPrime5VariantIfNeeded(
                    chosen,
                    prime: component.prime,
                    diatonicAccidental: diatonicAccidental
                ))
                continue
            }
            guard let baseGlyphs = stepsMap[1] ?? stepsMap.values.first else { continue }
            let chosen = component.up ? baseGlyphs.up : baseGlyphs.down
            if component.steps > 1 {
                for _ in 0..<component.steps {
                    out.append(contentsOf: applyPrime5VariantIfNeeded(
                                            chosen,
                                            prime: component.prime,
                                            diatonicAccidental: diatonicAccidental
                                        ))
                }
            } else {
                out.append(contentsOf: applyPrime5VariantIfNeeded(
                                    chosen,
                                    prime: component.prime,
                                    diatonicAccidental: diatonicAccidental
                                ))
            }
        }
        return out
    }

    func glyphExists(_ s: String, fontName: String) -> Bool {
        let key = "\(fontName)|\(s)"
        if let cached = glyphExistenceCache[key] { return cached }
#if canImport(CoreText)
        let font = ctFont(forName: fontName)
        let ok = s.unicodeScalars.allSatisfy { scalar in
            var ch = UniChar(scalar.value)
            var glyph: CGGlyph = 0
            return CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1) && glyph != 0
        }
        glyphExistenceCache[key] = ok
        return ok
#else
        glyphExistenceCache[key] = true
        return true
#endif
    }

    func preferredFontForGlyph(_ s: String) -> HejiFontKind {
        if let cached = glyphFontCache[s] { return cached }
        let musicName = musicFontName ?? "HEJI2Music"
        let textName = textFontName ?? "HEJI2Text"
        let preferred: HejiFontKind
        if glyphExists(s, fontName: musicName) {
            preferred = .music
        } else if glyphExists(s, fontName: textName) {
            preferred = .text
        } else {
            preferred = .music
        }
        glyphFontCache[s] = preferred
        return preferred
    }

    func allGlyphMetadata() -> [Heji2GlyphMetadata] {
        var out: [Heji2GlyphMetadata] = []
        for (accidental, glyphs) in diatonicAccidentals {
            for glyph in glyphs {
                out.append(Heji2GlyphMetadata(
                    glyph: glyph.string,
                    prime: 0,
                    step: 0,
                    direction: "diatonic(\(accidental))"
                ))
            }
        }
        for (prime, steps) in primeComponents {
            for (step, directional) in steps {
                for glyph in directional.up {
                    out.append(Heji2GlyphMetadata(
                        glyph: glyph.string,
                        prime: prime,
                        step: step,
                        direction: "up"
                    ))
                }
                for glyph in directional.down {
                    out.append(Heji2GlyphMetadata(
                        glyph: glyph.string,
                        prime: prime,
                        step: step,
                        direction: "down"
                    ))
                }
            }
        }
        return out
    }
/// Prime-5 in your JSON is currently the “natural+arrows” glyph family.
    /// If the note is actually sharp/flat, we must shift to the sharp/flat variant glyphs and
    /// *not* render the separate diatonic accidental.
    private func applyPrime5VariantIfNeeded(
        _ glyphs: [Heji2Glyph],
        prime: Int,
        diatonicAccidental: Int
    ) -> [Heji2Glyph] {
        guard prime == 5 else { return glyphs }
        guard abs(diatonicAccidental) == 1 else { return glyphs } // keep this tight/safe

        // Attempt to shift each glyph by ±1 codepoint (SMuFL flat/natural/sharp grouping).
        return glyphs.map { g in
            guard let s = g.string.unicodeScalars.first else { return g }
            let v = s.value
            let shifted = diatonicAccidental < 0 ? (v &- 1) : (v &+ 1)
            guard let ns = UnicodeScalar(shifted) else { return g }

            // Don’t risk tofu: verify the shifted scalar is present in the HEJI2 font at runtime.
            // If verification is not available on this platform, we still return the shifted glyph;
            // worst case you’ll see tofu and we can pin exact codepoints then.
            #if canImport(CoreText)
            let fontName = Heji2FontRegistry.hejiTextFontName as CFString
            let ct = CTFontCreateWithName(fontName, 16, nil)
            var ch: UniChar = UniChar(shifted)
            var cg: CGGlyph = 0
            let ok = CTFontGetGlyphsForCharacters(ct, &ch, &cg, 1)
            guard ok, cg != 0 else { return g }
            #endif

            return Heji2Glyph(
                glyph: String(ns),
                staffOffset: g.staffOffset,
                textOffset: g.textOffset,
                advance: g.advance,
                staffAdvance: g.staffAdvance,
                textAdvance: g.textAdvance
            )
        }
    }

#if canImport(CoreText)
    private func ctFont(forName name: String) -> CTFont {
        if let cached = ctFontCache[name] { return cached }
        let ct = CTFontCreateWithName(name as CFString, 16, nil)
        ctFontCache[name] = ct
        return ct
    }
#endif

#if DEBUG
    private func verifyGlyphsExist() {
        let musicName = musicFontName ?? "HEJI2Music"
        let textName = textFontName ?? "HEJI2Text"
        for glyph in allGlyphMetadata() {
            let hasMusic = glyphExists(glyph.glyph, fontName: musicName)
            let hasText = hasMusic ? true : glyphExists(glyph.glyph, fontName: textName)
            if !hasMusic && !hasText {
                logMissingGlyph(glyph: glyph.glyph, prime: glyph.prime, step: glyph.step, direction: glyph.direction)
            }
        }
    }

    private func logMissingGlyph(glyph: String, prime: Int, step: Int, direction: String) {
        let scalar = glyph.unicodeScalars.first?.value ?? 0
        let codepoint = String(format: "U+%04X", scalar)
        print("[HEJI2_GLYPH_MISSING] \(codepoint) prime=\(prime) step=\(step) dir=\(direction) glyph=\"\(glyph)\"")
    }
#endif
}

private struct Heji2MappingPayload: Decodable {
    let fonts: Heji2FontNames?
    let diatonicAccidentals: [String: [Heji2Glyph]]
    /// Supports BOTH:
    ///  - legacy:  { "5": { "up":[...], "down":[...] } }
    ///  - stepped: { "5": { "1": {...}, "2": {...} } }
    let primeComponents: [String: [String: Heji2DirectionalGlyphs]]

    enum CodingKeys: String, CodingKey { case fonts, diatonicAccidentals, primeComponents }

    static func loadFromBundle() -> Heji2MappingPayload? {
        let bundles = [Bundle.main, Bundle(for: Heji2Mapping.self)]
        for bundle in bundles {
            guard let url = bundle.url(forResource: "heji2_mapping", withExtension: "json") else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let decoded = try? JSONDecoder().decode(Heji2MappingPayload.self, from: data) else { continue }
#if DEBUG
            let bundleLabel = bundle == Bundle.main ? "Bundle.main" : "Bundle(for: Heji2Mapping.self)"
            let primes = decoded.primeComponents.keys.compactMap(Int.init).sorted()
            print("[HEJI2_MAPPING] loaded=\(url.path) bundle=\(bundleLabel)")
            print("[HEJI2_MAPPING] primes=\(primes)")
#endif
            return decoded
        }
        return nil
    }

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

struct Heji2GlyphMetadata: Hashable {
    let glyph: String
    let prime: Int
    let step: Int
    let direction: String
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
