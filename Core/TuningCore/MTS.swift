//
//  MTS.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Generic Universal SysEx builder + helpers for MIDI Tuning Standard envelopes.
/// NOTE: MTS sub-IDs are provided as arguments so you can choose real-time vs non-real-time and specific message types at call sites.
/// This keeps the encoder compile-safe now; verify sub-ID usage when integrating devices/hosts.
enum SysEx {
    /// Build a Universal SysEx message:
    /// start (0xF0), 0x7E (non-RT) or 0x7F (RT), deviceID (0x7F = all),
    /// subID1, subID2, payload..., end (0xF7).
    static func universal(realTime: Bool = false,
                          deviceID: UInt8 = 0x7F,
                          subID1: UInt8,
                          subID2: UInt8,
                          payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(payload.count + 8)
        bytes.append(0xF0)
        bytes.append(realTime ? 0x7F : 0x7E)
        bytes.append(deviceID & 0x7F)
        bytes.append(subID1 & 0x7F)
        bytes.append(subID2 & 0x7F)
        bytes.append(contentsOf: payload.map { $0 & 0x7F })
        bytes.append(0xF7)
        return bytes
    }
}

enum MTS {
    // Common Sub-ID constants (refer to spec during integration)
    // Sub-ID #1 for Tuning = 0x08
    static let subID1_tuning: UInt8 = 0x08

    // Some Sub-ID #2 values commonly used in MTS (verify per device):
    // 0x01: Bulk Tuning Dump (Single)
    // 0x02: Bulk Tuning Dump (Request)
    // 0x09: Scale/Octave Tuning 1-byte form (Real Time)
    // 0x0B: Single Note Tuning Change (Real Time)
    // Provide helpers for two common cases below.

    /// Build a Scale/Octave Tuning (12-note) real-time SysEx payload.
    /// `cents[0...11]` are offsets in cents relative to 12-TET steps (range typically -100..+100).
    static func scaleOctaveTuningRT(deviceID: UInt8 = 0x7F, cents: [Double]) -> [UInt8] {
        precondition(cents.count == 12, "Need 12 entries")
        // Convert cents to 7-bit values per 100-cent semitone:
        // Spec encodes 12 bytes each = 7-bit signed-ish offset (implementation-dependent across devices);
        // We map [-100, +100] → [27, 100] around 64 center. Clamp for safety.
        let encoded: [UInt8] = cents.map { c in
            let v = Int(round(c / 100.0 * 32.0)) // ~32 steps per semitone
            return UInt8(clamping: 64 + v)
        }
        return SysEx.universal(realTime: true,
                               deviceID: deviceID,
                               subID1: subID1_tuning,
                               subID2: 0x09,
                               payload: encoded)
    }

    /// Build a Bulk Tuning Dump (Single) non-real-time SysEx frame.
    /// `frequencies` length should be 128 (per MIDI note), in Hz. Encoded here as 14-bit coarse/fine pairs per spec family (clamped 7-bit chunks).
    static func bulkTuningDumpSingle(deviceID: UInt8 = 0x7F,
                                     name: String = "Tenney",
                                     frequencies: [Double]) -> [UInt8] {
        precondition(frequencies.count == 128, "Expected 128 frequencies")
        // Name is 16 bytes, 7-bit clean
        var nameBytes = Array(name.prefix(16).utf8).map { $0 & 0x7F }
        if nameBytes.count < 16 { nameBytes.append(contentsOf: repeatElement(0, count: 16 - nameBytes.count)) }

        // Encode each frequency as 2 bytes coarse/fine (device-dependent; use placeholder splitting into 14 bits total)
        // This provides a sane 7-bit-clean transport; exact mapping to Hz is device-specific and will be calibrated during Sprint 5 integration.
        var payload: [UInt8] = nameBytes
        payload.reserveCapacity(16 + 128 * 2)
        for f in frequencies {
            let scaled = max(0.0, min(f, 16383.0)) // clamp
            let v = Int(round(scaled)) & 0x3FFF
            let coarse = UInt8((v >> 7) & 0x7F)
            let fine   = UInt8(v & 0x7F)
            payload.append(coarse); payload.append(fine)
        }

        return SysEx.universal(realTime: false,
                               deviceID: deviceID,
                               subID1: subID1_tuning,
                               subID2: 0x01,
                               payload: payload)
    }
}
