//
//  LatticePreviewModeKey.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


// // TenneyEnvironmentKeys.swift // Tenney // // Created by Sebastian Suarez-Solis on 12/23/25. //

import SwiftUI

// MARK: - Lattice preview flags
private struct LatticePreviewModeKey: EnvironmentKey {
static let defaultValue: Bool = false
}

private struct LatticePreviewHideChipsKey: EnvironmentKey {
static let defaultValue: Bool = false
}

extension EnvironmentValues {
/// When true, lattice renders in a lightweight "preview" context (no heavy UI / interactions).
var latticePreviewMode: Bool {
get { self[LatticePreviewModeKey.self] }
set { self[LatticePreviewModeKey.self] = newValue }
}

/// When true, lattice preview hides overlay chips (used in tutorial/preview cards).
var latticePreviewHideChips: Bool {
    get { self[LatticePreviewHideChipsKey.self] }
    set { self[LatticePreviewHideChipsKey.self] = newValue }
}


}