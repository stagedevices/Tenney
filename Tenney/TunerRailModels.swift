//
//  TunerRailModels.swift
//  Tenney
//
//  Created by OpenAI on 2024-05-07.
//

import Foundation
import SwiftUI
import Combine

enum TunerRailCardID: String, CaseIterable, Identifiable, Codable {
    case nowTuning
    case intervalTape
    case miniLatticeFocus
    case nearestTargets
    case sessionCapture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowTuning:        return "Now Tuning"
        case .intervalTape:     return "Interval Tape"
        case .miniLatticeFocus: return "Mini Lattice Focus"
        case .nearestTargets:   return "Nearest Targets"
        case .sessionCapture:   return "Session Capture"
        }
    }

    var systemImage: String {
        switch self {
        case .nowTuning:        return "tuningfork"
        case .intervalTape:     return "timeline.selection"
        case .miniLatticeFocus: return "hexagon"
        case .nearestTargets:   return "list.bullet.rectangle"
        case .sessionCapture:   return "tray.and.arrow.down"
        }
    }
}

struct TunerRailPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var enabledOrderedCards: [TunerRailCardID]

    init(id: UUID = UUID(), name: String, enabledOrderedCards: [TunerRailCardID]) {
        self.id = id
        self.name = name
        self.enabledOrderedCards = enabledOrderedCards
    }
}

/// Simple persistence helper for the Mac-only tuner rail.
final class TunerRailStore: ObservableObject {
    @Published var presets: [TunerRailPreset] = []
    @Published var activePresetID: UUID
    @Published var enabledCards: [TunerRailCardID] = []
    @Published var showRail: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let seeded = Self.loadPresets(from: defaults)
        presets = seeded.presets
        activePresetID = seeded.activeID
        showRail = defaults.object(forKey: SettingsKeys.tunerRailShow) as? Bool ?? true
        enabledCards = presets.first(where: { $0.id == activePresetID })?.enabledOrderedCards
            ?? Self.defaultPreset.enabledOrderedCards
    }

    func setShowRail(_ show: Bool) {
        showRail = show
        defaults.set(show, forKey: SettingsKeys.tunerRailShow)
    }

    func applyPreset(id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        activePresetID = id
        enabledCards = preset.enabledOrderedCards
        persist()
    }

    func updateEnabledCards(_ cards: [TunerRailCardID]) {
        enabledCards = cards
        guard let idx = presets.firstIndex(where: { $0.id == activePresetID }) else { return }
        presets[idx].enabledOrderedCards = cards
        persist()
    }

    func toggleCard(_ card: TunerRailCardID) {
        var list = enabledCards
        if let idx = list.firstIndex(of: card) {
            list.remove(at: idx)
        } else {
            list.append(card)
        }
        updateEnabledCards(list)
    }

    func newPreset(named name: String) -> TunerRailPreset {
        let preset = TunerRailPreset(name: name, enabledOrderedCards: enabledCards.isEmpty ? Self.defaultPreset.enabledOrderedCards : enabledCards)
        presets.append(preset)
        activePresetID = preset.id
        persist()
        return preset
    }

    func duplicateActivePreset(as name: String) {
        guard let current = presets.first(where: { $0.id == activePresetID }) else { return }
        let dup = TunerRailPreset(name: name, enabledOrderedCards: current.enabledOrderedCards)
        presets.append(dup)
        activePresetID = dup.id
        enabledCards = dup.enabledOrderedCards
        persist()
    }

    func renameActivePreset(to name: String) {
        guard let idx = presets.firstIndex(where: { $0.id == activePresetID }) else { return }
        presets[idx].name = name
        persist()
    }

    func deletePreset(id: UUID) {
        let wasActive = (id == activePresetID)
        presets.removeAll { $0.id == id }
        if presets.isEmpty {
            presets = Self.defaultPresets
        }
        if wasActive {
            activePresetID = presets.first?.id ?? Self.defaultPreset.id
            enabledCards = presets.first(where: { $0.id == activePresetID })?.enabledOrderedCards ?? []
        }
        persist()
    }

    var defaultCards: [TunerRailCardID] { Self.defaultPreset.enabledOrderedCards }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(presets),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: SettingsKeys.tunerRailPresetsJSON)
        }
        defaults.set(activePresetID.uuidString, forKey: SettingsKeys.tunerRailActivePresetID)
        defaults.set(showRail, forKey: SettingsKeys.tunerRailShow)
    }

    private static func loadPresets(from defaults: UserDefaults) -> (presets: [TunerRailPreset], activeID: UUID) {
        let decoder = JSONDecoder()
        if let json = defaults.string(forKey: SettingsKeys.tunerRailPresetsJSON),
           let data = json.data(using: .utf8),
           let decoded = try? decoder.decode([TunerRailPreset].self, from: data),
           !decoded.isEmpty {
            let activeID = UUID(uuidString: defaults.string(forKey: SettingsKeys.tunerRailActivePresetID) ?? "") ?? decoded.first!.id
            return (decoded, activeID)
        }

        // Seed defaults
        let defaultsList = defaultPresets
        let active = defaultsList.first?.id ?? defaultPreset.id
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(defaultsList),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: SettingsKeys.tunerRailPresetsJSON)
            defaults.set(active.uuidString, forKey: SettingsKeys.tunerRailActivePresetID)
        }
        defaults.set(true, forKey: SettingsKeys.tunerRailShow)
        return (defaultsList, active)
    }

    static var defaultPreset: TunerRailPreset {
        TunerRailPreset(
            name: "Default",
            enabledOrderedCards: [.nowTuning, .nearestTargets, .miniLatticeFocus, .intervalTape, .sessionCapture]
        )
    }

    static var minimalPreset: TunerRailPreset {
        TunerRailPreset(
            name: "Minimal",
            enabledOrderedCards: [.nowTuning, .nearestTargets]
        )
    }

    static var defaultPresets: [TunerRailPreset] {
        [defaultPreset, minimalPreset]
    }

    var availableCards: [TunerRailCardID] {
        TunerRailCardID.allCases.filter { !enabledCards.contains($0) }
    }
}
