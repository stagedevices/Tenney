//
//  Tokens.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import SwiftUI

enum TenneyTokens {
    enum Color {
        // Use asset colors if you add them; these provide safe fallbacks now.
        static let prime3: SwiftUI.Color  = SwiftUI.Color(red: 0.22, green: 0.55, blue: 0.98)
        static let prime5: SwiftUI.Color  = SwiftUI.Color(red: 0.98, green: 0.65, blue: 0.12)
        static let prime7: SwiftUI.Color  = SwiftUI.Color(red: 0.90, green: 0.30, blue: 0.72)
        static let prime11: SwiftUI.Color = SwiftUI.Color(red: 0.10, green: 0.76, blue: 0.55)
        static let prime13: SwiftUI.Color = SwiftUI.Color(red: 0.60, green: 0.45, blue: 0.95)

        static let stageBackground: SwiftUI.Color = SwiftUI.Color(.systemBackground)
        static let glassForeground: SwiftUI.Color = SwiftUI.Color.primary
        static let glassBorder: SwiftUI.Color     = SwiftUI.Color.primary.opacity(0.08)
    }

    enum Spacing {
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 16
        static let chip: CGFloat = 12
    }

    enum Font {
        static func body(_ size: CGFloat = 16) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .default)
        }
        static func display(_ size: CGFloat = 28) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func mono(_ size: CGFloat = 48) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .monospaced)
        }
    }
}
