//
//  GlassChip.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  GlassChip.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/3/25.
//

import Foundation
import SwiftUI



private struct GlassChipBackground: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                // Use the chip’s shape; tint the glass (keeps it subtle & adaptive)
                .glassEffect(.regular.tint(color), in: Capsule())
        } else {
            // Fallback for simulators / older OS
            content
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}
