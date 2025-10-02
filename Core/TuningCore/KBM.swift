//
//  KBM.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Minimal .kbm mapping (common fields). Forgiving reader/writer.
struct KeyboardMapping: Equatable, Codable {
    var mappingSize: Int                 // typically 12
    var firstMIDINote: Int               // e.g., 0
    var lastMIDINote: Int                // e.g., 127
    var middleNote: Int                  // e.g., 69
    var referenceFrequencyHz: Double     // e.g., 440.0
    var referenceDegreeIndex: Int        // 0-based index in scale (usually 0)
    var degreeOfNote: [Int]              // length mappingSize, entries -1 for unmapped

    static func parse(_ text: String) throws -> KeyboardMapping {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        lines = lines.compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if t.hasPrefix("!") { return nil }
            return t
        }
        func requireInt(_ idx: Int, _ name: String) throws -> Int {
            guard idx < lines.count, let v = Int(lines[idx].split(separator: " ").first ?? "") else {
                throw NSError(domain: "KBM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(name)"])
            }
            return v
        }
        func requireDouble(_ idx: Int, _ name: String) throws -> Double {
            guard idx < lines.count, let v = Double(lines[idx].split(separator: " ").first ?? "") else {
                throw NSError(domain: "KBM", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing \(name)"])
            }
            return v
        }

        let mappingSize = try requireInt(0, "mapping size")
        let firstMIDINote = try requireInt(1, "first MIDI note")
        let lastMIDINote = try requireInt(2, "last MIDI note")
        let middleNote = try requireInt(3, "middle note")
        let refDegree = try requireInt(4, "reference degree")
        let refFreq = try requireDouble(5, "reference frequency")
        var degreeOfNote: [Int] = []
        var idx = 6
        for _ in 0..<mappingSize {
            if idx >= lines.count { degreeOfNote.append(-1) } else {
                degreeOfNote.append(Int(lines[idx].split(separator: " ").first ?? "-1") ?? -1)
            }
            idx += 1
        }

        return KeyboardMapping(
            mappingSize: mappingSize,
            firstMIDINote: firstMIDINote,
            lastMIDINote: lastMIDINote,
            middleNote: middleNote,
            referenceFrequencyHz: refFreq,
            referenceDegreeIndex: refDegree,
            degreeOfNote: degreeOfNote
        )
    }

    func serialize() -> String {
        var out: [String] = []
        out.append("! Tenney .kbm")
        out.append("\(mappingSize)")
        out.append("\(firstMIDINote)")
        out.append("\(lastMIDINote)")
        out.append("\(middleNote)")
        out.append("\(referenceDegreeIndex)")
        out.append(String(format: "%.6f", referenceFrequencyHz))
        for d in degreeOfNote { out.append("\(d)") }
        return out.joined(separator: "\n")
    }
}
