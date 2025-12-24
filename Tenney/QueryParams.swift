//
//  QueryParams.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  QueryParams.swift
//  VenueCalibrator
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation

struct QueryParams {
    private let items: [URLQueryItem]
    init(_ items: [URLQueryItem]) { self.items = items }

    func string(_ key: String) -> String? {
        items.first { $0.name.lowercased() == key.lowercased() }?.value
    }
    func double(_ key: String) -> Double? {
        guard let s = string(key), let d = Double(s) else { return nil }
        return d
    }
    func bool(_ key: String) -> Bool {
        // accepts 1/true/yes
        (string(key)?.lowercased()).map { ["1","true","yes"].contains($0) } ?? false
    }
    func has(_ key: String) -> Bool {
        items.contains { $0.name.lowercased() == key.lowercased() }
    }
}