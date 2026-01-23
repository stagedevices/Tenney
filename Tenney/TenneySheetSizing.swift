//
//  TenneySheetSizing.swift
//  Tenney
//
//  Created by OpenAI on 3/5/25.
//

import SwiftUI
import UIKit

private struct TenneySheetSizing: ViewModifier {
    private var shouldApplySizing: Bool {
#if targetEnvironment(macCatalyst)
        return true
#else
        return UIDevice.current.userInterfaceIdiom != .phone
#endif
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if shouldApplySizing {
            if #available(iOS 16.0, *) {
                content
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .frame(
                        minWidth: 700,
                        idealWidth: 860,
                        maxWidth: .infinity,
                        minHeight: 720,
                        idealHeight: 900,
                        maxHeight: .infinity
                    )
            } else {
                content
                    .frame(
                        minWidth: 700,
                        idealWidth: 860,
                        maxWidth: .infinity,
                        minHeight: 720,
                        idealHeight: 900,
                        maxHeight: .infinity
                    )
            }
        } else {
            content
        }
    }
}

extension View {
    func tenneySheetSizing() -> some View {
        modifier(TenneySheetSizing())
    }
}
