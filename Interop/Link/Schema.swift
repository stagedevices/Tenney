//
//  Schema.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Inbound state from SyncTimer (Tenney follows).
struct SyncTimerMessage: Codable {
    struct Payload: Codable {
        var rootHz: Double?
        var primeLimit: Int?
        var strictness: String?
        var presetId: String?
        var timer: [String: String]?
    }
    var v: Int
    var source: String
    var op: String
    var payload: Payload
}
