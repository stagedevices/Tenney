//
//  LearnTenneyTips.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import SwiftUI

/// Minimal gating scaffold (Mode A now; Mode B later).
struct LearnTipGate {
    static func canShowTipToday() -> Bool {
        let today = Date().tenneyDayStamp
        let last = UserDefaults.standard.string(forKey: SettingsKeys.learnLastTipDayStamp) ?? ""
        return last != today
    }

    static func markTipShownToday() {
        UserDefaults.standard.set(Date().tenneyDayStamp, forKey: SettingsKeys.learnLastTipDayStamp)
    }

    static func tipsMode() -> String {
        UserDefaults.standard.string(forKey: SettingsKeys.learnTipsMode) ?? "learnOnly"
    }
}
