//
//  HejiGlyphs.swift
//  Tenney
//

import Foundation
import CoreText

enum HejiGlyphs {
    static let gClef = "\u{E050}"
    static let fClef = "\u{E062}"
    static let noteheadBlack = "\u{E0A4}"

    static func standardAccidental(for count: Int) -> String {
        if count == 0 { return "" }
        if count > 0 {
            return String(repeating: "\u{E262}", count: count)
        } else {
            return String(repeating: "\u{E260}", count: abs(count))
        }
    }

    static func microtonalGlyph(for component: HejiMicrotonalComponent) -> String {
        switch component {
        case .syntonic(let up):
            return up ? "\u{E2C7}" : "\u{E2C2}"
        case .septimal(let up):
            return up ? "\u{E2DF}" : "\u{E2DE}"
        case .undecimal(let up):
            return up ? "\u{E2E3}" : "\u{E2E2}"
        case .tridecimal(let up):
            return up ? "\u{E2E7}" : "\u{E2E6}"
        }
    }

    static func glyphAvailable(_ glyph: String, fontName: String) -> Bool {
        guard let scalar = glyph.unicodeScalars.first else { return false }
        let font = CTFontCreateWithName(fontName as CFString, 16, nil)
        var character = UniChar(scalar.value)
        var glyphs = CGGlyph()
        return CTFontGetGlyphsForCharacters(font, &character, &glyphs, 1)
    }
}

