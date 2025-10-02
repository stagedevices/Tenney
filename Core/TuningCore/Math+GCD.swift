//
//  Math+GCD.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation

@inlinable func gcd(_ a: Int, _ b: Int) -> Int {
    var x = abs(a), y = abs(b)
    while y != 0 { (x, y) = (y, x % y) }
    return x
}

@inlinable func lcm(_ a: Int, _ b: Int) -> Int {
    let g = gcd(a,b)
    return g == 0 ? 0 : abs(a / g * b)
}
