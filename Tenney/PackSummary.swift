//
//  PackSummary.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/6/25.
//

import Foundation

struct PackSummary: Identifiable, Hashable {
    enum Kind: Hashable {
        case favorites
        case recents
        case communitySuperFolder
        case loose
        case realPack(PackRef)
    }

    var id: String
    var title: String
    var subtitle: String?
    var count: Int
    var source: PackRef.Source?
    var packRef: PackRef?
    var kind: Kind
}
