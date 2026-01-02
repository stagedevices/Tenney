//
//  TunerDesktopPane.swift
//  Tenney
//
//  Two-column tuner layout for macOS/Catalyst.
//

import SwiftUI

struct TunerDesktopPane: View {
    @StateObject private var store = TunerStore()
    @Binding var stageActive: Bool

    private let railThreshold: CGFloat = 1020

    var body: some View {
        GeometryReader { geo in
            let showRail = geo.size.width >= railThreshold
            HStack(alignment: .top, spacing: showRail ? 16 : 0) {
                TunerCard(stageActive: $stageActive, store: store)
                    .frame(maxWidth: .infinity, alignment: .top)

                if showRail {
                    TunerContextRail(store: store, availableHeight: geo.size.height)
                        .frame(width: min(320, geo.size.width * 0.36), alignment: .top)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.snappy, value: showRail)
            .padding(.vertical, 8)
        }
    }
}
