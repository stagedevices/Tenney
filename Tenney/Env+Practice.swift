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

private struct LearnPracticeCompletedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct TenneyPracticeChromeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var tenneyPracticeActive: Bool {
        get { self[TenneyPracticeActiveKey.self] }
        set { self[TenneyPracticeActiveKey.self] = newValue }
    }

    var learnPracticeCompleted: Bool {
        get { self[LearnPracticeCompletedKey.self] }
        set { self[LearnPracticeCompletedKey.self] = newValue }
    }

    var tenneyPracticeChrome: Bool {
        get { self[TenneyPracticeChromeKey.self] }
        set { self[TenneyPracticeChromeKey.self] = newValue }
    }
}
