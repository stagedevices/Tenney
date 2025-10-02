//
//  PrimeLimit.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

enum PrimeLimit: Int, CaseIterable, Codable {
    case three = 3, five = 5, seven = 7, eleven = 11, thirteen = 13

    var primes: [Int] {
        switch self {
        case .three: return [2,3]
        case .five:  return [2,3,5]
        case .seven: return [2,3,5,7]
        case .eleven:return [2,3,5,7,11]
        case .thirteen:return [2,3,5,7,11,13]
        }
    }
}
