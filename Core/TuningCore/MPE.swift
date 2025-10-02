//
//  MPE.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

enum MPE {
    /// Convert cents to 14-bit pitch bend value for a given bend range in semitones.
    /// Returns (LSB, MSB) bytes for a MIDI Pitch Bend message (0xE0 channel, LSB, MSB).
    @inlinable static func bend14bit(cents: Double, bendRangeSemitones: Double) -> (UInt8, UInt8) {
        let semis = cents / 100.0
        let val = 8192.0 + (semis / bendRangeSemitones) * 8192.0
        let clamped = Int(max(0.0, min(16383.0, round(val))))
        let lsb = UInt8(clamped & 0x7F)
        let msb = UInt8((clamped >> 7) & 0x7F)
        return (lsb, msb)
    }

    /// Build a 3-byte Pitch Bend event for a MIDI channel [0..15].
    @inlinable static func pitchBendMessage(channel: UInt8, cents: Double, bendRangeSemitones: Double) -> [UInt8] {
        let (lsb, msb) = bend14bit(cents: cents, bendRangeSemitones: bendRangeSemitones)
        let status: UInt8 = 0xE0 | (channel & 0x0F)
        return [status, lsb, msb]
    }

    /// RPN messages to set Pitch Bend Range (semitones, cents) on a channel.
    /// Use channel-wide setup for MPE zones as needed.
    static func setPitchBendRangeMessages(channel: UInt8, semitones: UInt8, cents: UInt8 = 0) -> [[UInt8]] {
        let statusCC: UInt8 = 0xB0 | (channel & 0x0F)
        return [
            [statusCC, 101, 0],      // RPN MSB
            [statusCC, 100, 0],      // RPN LSB  (0,0 = Pitch Bend Range)
            [statusCC, 6, semitones],// Data Entry MSB (semitones)
            [statusCC, 38, cents],   // Data Entry LSB (cents)
            [statusCC, 101, 127],    // RPN null
            [statusCC, 100, 127]
        ]
    }
}
