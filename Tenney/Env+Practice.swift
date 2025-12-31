//
//  Env+Practice.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/30/25.
//


import SwiftUI

private struct TenneyPracticeActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var tenneyPracticeActive: Bool {
        get { self[TenneyPracticeActiveKey.self] }
        set { self[TenneyPracticeActiveKey.self] = newValue }
    }
}
