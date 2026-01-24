//
//  TonicSpelling.swift
//  Tenney
//
//  Root-name utilities for HEJI spelling.
//

import Foundation
import SwiftUI

enum TonicNameMode: String, CaseIterable, Identifiable {
    case auto
    case manual

    var id: String { rawValue }
}

struct TonicSpelling: Hashable {
    var e3: Int

    var letter: String { letterInfo.letter }
    var accidentalCount: Int { letterInfo.accidentalCount }

    var displayText: String {
        letter + accidentalGlyph(accidentalCount)
    }

    func attributedDisplayText(
        textStyle: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        basePointSize: CGFloat? = nil
    ) -> AttributedString {
        let baseSize = basePointSize ?? Heji2FontRegistry.preferredPointSize(for: textStyle)
        let baseFont = Font.system(size: baseSize, weight: weight, design: design)
        var out = AttributedString(letter)
        out.font = baseFont
        let accidental = accidentalGlyph(accidentalCount)
        if !accidental.isEmpty {
            var acc = AttributedString(accidental)
            acc.font = Heji2FontRegistry.hejiTextFont(size: baseSize, relativeTo: textStyle)
            out += acc
        }
        return out
    }

    private var letterInfo: (letter: String, accidentalCount: Int) {
        let idx = ((e3 % 7) + 7) % 7
        let base = Self.baseFifth[idx]
        let accidental = (e3 - base) / 7
        return (Self.fifthLetters[idx], accidental)
    }

    static func from(rootHz: Double, noteNameA4Hz: Double, preference: AccidentalPreference) -> TonicSpelling? {
        guard rootHz.isFinite, rootHz > 0, noteNameA4Hz.isFinite, noteNameA4Hz > 0 else { return nil }
        let midiFloat = 69.0 + 12.0 * log2(rootHz / noteNameA4Hz)
        let midi = Int(midiFloat.rounded())
        let idx = ((midi % 12) + 12) % 12
        let spelling = spelledNote(forSemitone: idx, preference: preference)
        return from(letter: spelling.letter, accidental: spelling.accidentalCount)
    }

    static func from(letter: String, accidental: Int) -> TonicSpelling {
        let base = naturalFifths(letter)
        return TonicSpelling(e3: base + (7 * accidental))
    }

    static func resolvedTonicE3(
        mode: TonicNameMode,
        manualE3: Int,
        rootHz: Double,
        noteNameA4Hz: Double,
        preference: AccidentalPreference
    ) -> Int? {
        switch mode {
        case .manual:
            return manualE3
        case .auto:
            return TonicSpelling.from(rootHz: rootHz, noteNameA4Hz: noteNameA4Hz, preference: preference)?.e3
        }
    }

    static func resolvedNoteNameA4Hz(defaults: UserDefaults = .standard) -> Double {
        if defaults.object(forKey: SettingsKeys.noteNameA4Hz) != nil {
            let value = defaults.double(forKey: SettingsKeys.noteNameA4Hz)
            return value > 0 ? value : 440.0
        }
        let legacy = defaults.double(forKey: SettingsKeys.staffA4Hz)
        return legacy > 0 ? legacy : 440.0
    }

    private static let fifthLetters = ["C", "G", "D", "A", "E", "B", "F"]
    private static let baseFifth = [0, 1, 2, 3, 4, 5, -1]

    private static func naturalFifths(_ letter: String) -> Int {
        switch letter.uppercased() {
        case "C": return 0
        case "G": return 1
        case "D": return 2
        case "A": return 3
        case "E": return 4
        case "B": return 5
        case "F": return -1
        default: return 0
        }
    }

    private static func spelledNote(forSemitone idx: Int, preference: AccidentalPreference) -> (letter: String, accidentalCount: Int) {
        let sharps: [(String, Int)] = [
            ("C", 0), ("C", 1), ("D", 0), ("D", 1),
            ("E", 0), ("F", 0), ("F", 1), ("G", 0),
            ("G", 1), ("A", 0), ("A", 1), ("B", 0)
        ]
        let flats: [(String, Int)] = [
            ("C", 0), ("D", -1), ("D", 0), ("E", -1),
            ("E", 0), ("F", 0), ("G", -1), ("G", 0),
            ("A", -1), ("A", 0), ("B", -1), ("B", 0)
        ]
        switch preference {
        case .preferFlats:
            return flats[idx]
        case .preferSharps, .auto:
            return sharps[idx]
        }
    }

}

func effectiveTonicSpelling(
    rootHz: Double,
    noteNameA4Hz: Double,
    tonicNameModeRaw: String,
    tonicE3: Int,
    accidentalPreference: AccidentalPreference
) -> TonicSpelling? {
    let mode = TonicNameMode(rawValue: tonicNameModeRaw) ?? .auto
    switch mode {
    case .auto:
        return TonicSpelling.from(rootHz: rootHz, noteNameA4Hz: noteNameA4Hz, preference: accidentalPreference)
    case .manual:
        return TonicSpelling(e3: tonicE3)
    }
}

func accidentalGlyph(_ count: Int, showNatural: Bool = false) -> String {
    guard count != 0 else { return "" }
    let glyphs = Heji2Mapping.shared.glyphsForDiatonicAccidental(count)
    if !glyphs.isEmpty {
        return glyphs.map(\.string).joined()
    }
    return ""
}
