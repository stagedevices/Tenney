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

