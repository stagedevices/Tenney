//
//  AdaptiveRoot.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import SwiftUI


/// 3-zone adaptive skeleton: Stage (content), Rail (controls), Utility (bottom bar).
struct AdaptiveRoot<Stage: View, Rail: View, Utility: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    let stage: Stage
    let rail: Rail
    let utility: Utility

    private var isWide: Bool {
        if let h = hSize, let v = vSize {
            return h == .regular && (v == .compact || v == .regular)
        }
        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    var body: some View {
        ZStack {
            TenneyTokens.Color.stageBackground.ignoresSafeArea()

            AnyLayout(isWide ? AnyLayout(HStackLayout(spacing: TenneyTokens.Spacing.l))
                             : AnyLayout(VStackLayout(spacing: TenneyTokens.Spacing.l))) {
                stage

                // IMPORTANT: no container-level glass here; rail controls decide their own chrome.
                rail
                    .frame(maxWidth: isWide ? 420 : .infinity)
            }
            .padding(.horizontal, TenneyTokens.Spacing.l)
            .padding(.top, TenneyTokens.Spacing.l)
        }
        .safeAreaInset(edge: .bottom) { utility }
    }
}

