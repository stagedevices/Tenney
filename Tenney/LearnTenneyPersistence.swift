//
//  LearnTenneyPersistence.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import Foundation

/// Snapshot + restore UserDefaults keys (scoped by prefix) so Practice never persists.
struct TenneyPracticeSnapshot {
    private let captured: [String: Any]
    private let removedKeys: Set<String>
    private let prefixes: [String]

    init(prefixes: [String] = ["Tenney.", "tenney."]) {
        self.prefixes = prefixes
        let all = UserDefaults.standard.dictionaryRepresentation()
        let scoped = all.filter { k, _ in prefixes.contains(where: { k.hasPrefix($0) }) }
        self.captured = scoped
        self.removedKeys = []
    }

    private init(prefixes: [String], captured: [String: Any], removedKeys: Set<String>) {
        self.prefixes = prefixes
        self.captured = captured
        self.removedKeys = removedKeys
    }

    /// Capture again, but also track any keys created during practice so we can remove them on restore.
    func trackingNewKeys(since baseline: TenneyPracticeSnapshot) -> TenneyPracticeSnapshot {
        let nowAll = UserDefaults.standard.dictionaryRepresentation()
        let nowScopedKeys = Set(nowAll.keys.filter { k in prefixes.contains(where: { k.hasPrefix($0) }) })
        let baseScopedKeys = Set(baseline.captured.keys)
        let newKeys = nowScopedKeys.subtracting(baseScopedKeys)
        return TenneyPracticeSnapshot(prefixes: prefixes, captured: captured, removedKeys: newKeys)
    }

    func restore() {
        // Remove any keys created during practice.
        for k in removedKeys {
            UserDefaults.standard.removeObject(forKey: k)
        }
        // Restore baseline values.
        let current = UserDefaults.standard.dictionaryRepresentation()
        let currentScoped = current.keys.filter { k in prefixes.contains(where: { k.hasPrefix($0) }) }
        let currentScopedSet = Set(currentScoped)
        let capturedKeys = Set(captured.keys)

        // Remove keys that existed at baseline but are now missing? (restore handles by set)
        // Remove keys that exist now but didn't exist at baseline (covered by removedKeys if tracked).
        // Set all captured values.
        for (k, v) in captured {
            UserDefaults.standard.set(v, forKey: k)
        }
        // If something was present now but not in captured, and we didn't explicitly track it,
        // keep it (non-destructive) — trackingNewKeys handles the strict case.
        _ = currentScopedSet.subtracting(capturedKeys)
    }
}

extension Date {
    /// Local day stamp used for “max ~1/day” gating.
    var tenneyDayStamp: String {
        let cal = Calendar.current
        let y = cal.component(.year, from: self)
        let m = cal.component(.month, from: self)
        let d = cal.component(.day, from: self)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

extension TenneyPracticeSnapshot {
    static let shared = TenneyPracticeSnapshot()

    struct ModuleState: Equatable {
        let stepIndex: Int
        let completed: Bool
    }

    func markCompleted(_ module: LearnTenneyModule) {
        let state = ModuleState(stepIndex: loadCurrentStep(module), completed: true)
        UserDefaults.standard.set(true, forKey: "learn.\(module.rawValue).completed")
        LearnTenneyStateStore.shared.updateState(module, state: state)
    }

    func isCompleted(_ module: LearnTenneyModule) -> Bool {
        let key = "learn.\(module.rawValue).completed"
        return UserDefaults.standard.bool(forKey: key)
    }

    func saveCurrentStep(_ module: LearnTenneyModule, index: Int) {
        UserDefaults.standard.set(index, forKey: "learn.\(module.rawValue).step")
        let state = ModuleState(stepIndex: index, completed: isCompleted(module))
        LearnTenneyStateStore.shared.updateState(module, state: state)
    }

    func loadCurrentStep(_ module: LearnTenneyModule) -> Int {
        UserDefaults.standard.integer(forKey: "learn.\(module.rawValue).step")
    }

    func loadState(_ module: LearnTenneyModule) -> ModuleState {
        ModuleState(stepIndex: loadCurrentStep(module), completed: isCompleted(module))
    }

    func saveState(_ module: LearnTenneyModule, stepIndex: Int, completed: Bool) {
        UserDefaults.standard.set(stepIndex, forKey: "learn.\(module.rawValue).step")
        UserDefaults.standard.set(completed, forKey: "learn.\(module.rawValue).completed")
        let state = ModuleState(stepIndex: stepIndex, completed: completed)
        LearnTenneyStateStore.shared.updateState(module, state: state)
    }

    func resetState(_ module: LearnTenneyModule) {
        saveState(module, stepIndex: 0, completed: false)
    }
}

final class LearnTenneyStateStore: ObservableObject {
    static let shared = LearnTenneyStateStore()

    @Published private(set) var states: [LearnTenneyModule: TenneyPracticeSnapshot.ModuleState]
    @Published var pendingModuleToOpen: LearnTenneyModule? = nil

    private init() {
        var initial: [LearnTenneyModule: TenneyPracticeSnapshot.ModuleState] = [:]
        for module in LearnTenneyModule.allCases {
            initial[module] = TenneyPracticeSnapshot.shared.loadState(module)
        }
        self.states = initial
    }

    func updateState(_ module: LearnTenneyModule, state: TenneyPracticeSnapshot.ModuleState) {
        states[module] = state
    }
}
