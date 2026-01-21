//
//  GlassWhiteCircle.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/20/26.
//

import Foundation
import SwiftUI
import UIKit

 
// Neutral / white glass circle for export button
 public struct GlassWhiteCircle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(
                                .regular,
                                in: Circle()
                            )
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay(
                Circle()
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
    }
}
