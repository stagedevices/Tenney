//
//  Heji2FontRegistry.swift
//  Tenney
//

import Foundation
import CoreText
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum Heji2FontRegistry {
    private static var didRegister = false

    static var hejiTextFontName: String {
        Heji2Mapping.shared.textFontName ?? "HEJI2Text"
    }

    static var hejiMusicFontName: String {
        Heji2Mapping.shared.musicFontName ?? "HEJI2Music"
    }

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        register(fontName: "HEJI2Text", ext: "otf")
        register(fontName: "HEJI2Music", ext: "otf")
        register(fontName: "HEJI2", ext: "otf")
    }

    static func preferredPointSize(for textStyle: Font.TextStyle) -> CGFloat {
#if canImport(UIKit)
        return UIFont.preferredFont(forTextStyle: textStyle.uiTextStyle).pointSize
#elseif canImport(AppKit)
        return NSFont.preferredFont(forTextStyle: textStyle.nsTextStyle).pointSize
#else
        return 16
#endif
    }

    static func hejiTextFont(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        Font.custom(hejiTextFontName, size: size, relativeTo: textStyle)
    }

    private static func register(fontName: String, ext: String) {
        guard let url = Bundle.main.url(forResource: fontName, withExtension: ext) else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

#if canImport(UIKit)
private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
#elseif canImport(AppKit)
private extension Font.TextStyle {
    var nsTextStyle: NSFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
#endif
