//
//  ScreenShell.swift
//  Tenney
//
//  Created by OpenAI on 2/27/25.
//

import SwiftUI

struct ScreenShell<Background: View>: ViewModifier {
    let background: Background

    func body(content: Content) -> some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            background
                .ignoresSafeArea()
            content
        }
        .overlay(ScreenShellDebugOverlay())
    }
}

extension View {
    func screenShell<Background: View>(@ViewBuilder background: () -> Background = { EmptyView() }) -> some View {
        modifier(ScreenShell(background: background()))
    }
}

#if DEBUG
private struct ScreenShellDebugOverlay: View {
    static let enabled = false

    var body: some View {
        if Self.enabled {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Color.red.opacity(0.2)
                        .frame(height: proxy.safeAreaInsets.top)
                    Spacer(minLength: 0)
                    Color.blue.opacity(0.2)
                        .frame(height: proxy.safeAreaInsets.bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
#else
private struct ScreenShellDebugOverlay: View {
    var body: some View {
        EmptyView()
    }
}
#endif
