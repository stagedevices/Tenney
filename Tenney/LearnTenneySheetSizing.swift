//
//  LearnTenneySheetSizing.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/1/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private let learnTenneySheetMinWidth: CGFloat = 620
private let learnTenneySheetIdealWidth: CGFloat = 820
private let learnTenneySheetMinHeight: CGFloat = 760
private let learnTenneySheetIdealHeight: CGFloat = 920

extension View {
    @ViewBuilder
    func learnTenneySheetPresentation() -> some View {
        if #available(iOS 16.4, macOS 13.3, *) {
            self.presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        } else if #available(iOS 16.0, macOS 13.0, *) {
            self.presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    @ViewBuilder
    func learnTenneySheetSizing(enabled: Bool) -> some View {
        if enabled {
            self.frame(
                minWidth: learnTenneySheetMinWidth,
                idealWidth: learnTenneySheetIdealWidth,
                maxWidth: .infinity,
                minHeight: learnTenneySheetMinHeight,
                idealHeight: learnTenneySheetIdealHeight,
                maxHeight: .infinity
            )
        } else {
            self
        }
    }
}

func shouldApplyLearnTenneySheetSizing(sizeClass: UserInterfaceSizeClass?) -> Bool {
    if sizeClass == .regular { return true }
    #if canImport(UIKit)
    return UIDevice.current.userInterfaceIdiom != .phone
    #else
    return true
    #endif
}
