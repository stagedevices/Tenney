//
//  BravuraFontRegistrar.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/22/26.
//


import Foundation
import CoreText

enum BravuraFontRegistrar {
    static func registerIfNeeded() {
        register("Bravura", ext: "otf")
        register("BravuraText", ext: "otf")
    }

    private static func register(_ name: String, ext: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
