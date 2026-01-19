import Foundation
import SwiftUI


typealias TagID = UUID

struct TagRef: Identifiable, Codable, Hashable, Sendable {
    var id: TagID
    var name: String
    var sfSymbolName: String?
    var color: TagColor
    var customHex: String?
}

enum TagColor: String, Codable, CaseIterable, Identifiable {
    case slate
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .slate: return Color.gray
        case .blue: return Color.blue
        case .indigo: return Color.indigo
        case .purple: return Color.purple
        case .pink: return Color.pink
        case .red: return Color.red
        case .orange: return Color.orange
        case .yellow: return Color.yellow
        case .green: return Color.green
        case .teal: return Color.teal
        }
    }

    var label: String {
        rawValue.uppercased()
    }

    var hexValue: String {
        switch self {
        case .slate: return "#6B7280"
        case .blue: return "#3B82F6"
        case .indigo: return "#6366F1"
        case .purple: return "#A855F7"
        case .pink: return "#EC4899"
        case .red: return "#EF4444"
        case .orange: return "#F97316"
        case .yellow: return "#EAB308"
        case .green: return "#22C55E"
        case .teal: return "#14B8A6"
        }
    }

    static var `default`: TagColor { .slate }
}

extension TagRef {
    var resolvedColor: Color {
        if let customHex {
            return Color(hex: customHex)
        }
        return color.color
    }

    var resolvedHex: String {
        customHex ?? color.hexValue
    }
}

enum TagNameNormalizer {
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let letters = CharacterSet.letters
        var out = ""
        out.reserveCapacity(collapsed.count)
        for scalar in collapsed.unicodeScalars {
            if letters.contains(scalar) {
                out.append(String(scalar).uppercased())
            } else {
                out.append(String(scalar))
            }
        }
        return out
    }
}
