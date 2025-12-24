//
//  VenueCalibrationInfo.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


//
//  VenueCalibrationInfo.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//

import Foundation

struct VenueCalibrationInfo: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var a4: Double
    var timestamp: Date = Date()

    init(name: String, a4: Double, timestamp: Date = Date()) {
        self.name = name
        self.a4 = a4
        self.timestamp = timestamp
    }
}
