//
//  Array+Assign.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

extension Array {
    mutating func assign<T: Collection>(from slice: T) where T.Element == Element {
        var i = 0
        for v in slice {
            if i >= self.count { break }
            self[i] = v
            i += 1
        }
    }
}
