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

    static func glyphAvailable(_ glyph: String, fontName: String) -> Bool {
        guard let scalar = glyph.unicodeScalars.first else { return false }
        let font = CTFontCreateWithName(fontName as CFString, 16, nil)
        var character = UniChar(scalar.value)
        var glyphs = CGGlyph()
        return CTFontGetGlyphsForCharacters(font, &character, &glyphs, 1)
    }
}
