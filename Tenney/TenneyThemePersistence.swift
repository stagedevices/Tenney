//
//  TenneyThemePersistence.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  TenneyThemePersistence.swift
//  Tenney
//
//  Custom themes stored locally (no import/export, no sharing).
//

import Foundation

enum TenneyThemePersistence {
    static let schemaVersion: Int = 1

    struct CustomTheme: Codable, Hashable, Identifiable {
        let id: UUID
        var name: String

        // prime -> hex (only themed primes)
        var paletteHex: [Int: String]

        var mixBasis: String
        var mixMode: String

        // surface tint (light/dark)
        var lightTintHex: String
        var lightStrength: Double
        var darkTintHex: String
        var darkStrength: Double

        // tuner
        var tunerNeedleHex: String
        var tunerTicksHex: String
        var tunerTickOpacity: Double
        var tunerInTuneNeutralHex: String
        var tunerInTuneStrength: Double

        // scope
        var scopeTraceHex: String
        var scopeMode: String
    }

    static func loadAll() -> [CustomTheme] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.tenneyCustomThemes) else { return [] }
        do {
            return try JSONDecoder().decode([CustomTheme].self, from: data)
        } catch {
            return []
        }
    }

    static func saveAll(_ themes: [CustomTheme]) {
        guard let data = try? JSONEncoder().encode(themes) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKeys.tenneyCustomThemes)
    }
}
