//
//  LearnGate.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/30/25.
//


//  LearnGate.swift
//  Tenney

import SwiftUI

struct LearnGate: Equatable, Sendable {
    var allowedTargets: Set<String> = []
    var allowedGestures: Set<String> = []
    var isActive: Bool = false

    func allows(_ id: String) -> Bool {
        guard isActive else { return true }
        return allowedTargets.contains(id) || allowedGestures.contains(id)
    }
}

private struct LearnGateKey: EnvironmentKey {
    static let defaultValue = LearnGate()
}

extension EnvironmentValues {
    var learnGate: LearnGate {
        get { self[LearnGateKey.self] }
        set { self[LearnGateKey.self] = newValue }
    }
}

extension View {
    func learnTarget(id: String) -> some View {
        self.modifier(LearnTargetModifier(id: id))
    }

    func gated(_ id: String, gate: LearnGate) -> some View {
        self.allowsHitTesting(gate.allows(id))
    }
}

private struct LearnTargetModifier: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content.anchorPreference(key: LearnTargetAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

private struct LearnTargetAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
