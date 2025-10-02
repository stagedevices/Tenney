//
//  Scala.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

/// Scala scale representation (relative to 1/1)
struct ScalaScale: Equatable, Codable {
    var description: String
    /// Each entry is either cents or a ratio string; we store as Ratio for exactness when possible, otherwise as cents
    var entries: [Entry]

    enum Entry: Equatable, Codable {
        case ratio(Ratio)
        case cents(Double)

        var centsValue: Double {
            switch self {
            case .ratio(let r): return r.cents
            case .cents(let c): return c
            }
        }
    }

    // MARK: Parsing

    /// Parse .scl text (forgiving: skips '!' comments, blank lines).
    static func parse(_ text: String) throws -> ScalaScale {
        var lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        // Strip comments and trim
        lines = lines.compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if t.hasPrefix("!") { return nil }
            return t
        }
        guard !lines.isEmpty else { throw NSError(domain: "Scala", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty .scl"]) }
        let description = lines.removeFirst()
        guard !lines.isEmpty else { throw NSError(domain: "Scala", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing count line"]) }

        // Count line may include comments; extract first integer
        let countLine = lines.removeFirst()
        let scanner = Scanner(string: countLine)
        var count: Int = 0
        if !scanner.scanInt(&count) { throw NSError(domain: "Scala", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid count line"]) }

        var entries: [Entry] = []
        for line in lines {
            if entries.count >= count { break }
            let t = line.split(separator: " ").first.map(String.init) ?? line
            if t.contains("/") {
                // ratio n/d
                let parts = t.split(separator: "/").map { String($0) }
                if parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]), d != 0 {
                    entries.append(.ratio(Ratio(n,d)))
                } else {
                    // malformed ratio -> try cents
                    if let c = Double(t) { entries.append(.cents(c)) }
                }
            } else if let c = Double(t) {
                entries.append(.cents(c))
            }
        }
        return ScalaScale(description: description, entries: entries)
    }

    /// Serialize to .scl text (cents for generic entries; ratio for exacts).
    func serialize() -> String {
        var out: [String] = []
        out.append("! \(description)")
        out.append("\(entries.count)")
        out.append("!")
        for e in entries {
            switch e {
            case .ratio(let r): out.append("\(r.n)/\(r.d)")
            case .cents(let c): out.append(String(format: "%.5f", c))
            }
        }
        return out.joined(separator: "\n")
    }
}
