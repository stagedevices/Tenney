//
//  LatticeRenderNode.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/23/25.
//


import Foundation
import CoreGraphics

struct LatticeRenderNode: Hashable, Sendable {
    let coord: LatticeCoord
    let pos: CGPoint
    let tenneyHeight: Int
}
