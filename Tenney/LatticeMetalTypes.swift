//
//  LatticeMetalTypes.swift
//  Tenney
//
//  Shared Swift/Metal layout types for lattice rendering.
//

import Foundation
import CoreGraphics
import simd
import SwiftUI

struct LatticeMetalNode {
    var worldPosition: SIMD2<Float>
    var tenneyHeight: Float
    var color: SIMD4<Float>
    var nodeID: UInt32
    var flags: UInt32
    var complexity: Float
    var octaveOffset: Float
}

struct LatticeMetalLink {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var color: SIMD4<Float>
    var width: Float
    var pad: SIMD3<Float> = .zero
}

struct LatticeMetalUniforms {
    var viewportSize: SIMD2<Float>
    var translation: SIMD2<Float>
    var scale: Float
    var baseRadius: Float
    var time: Float
    var audioAmplitude: Float
    var audioPhase: Float
    var debugFlags: UInt32
    var linkAlpha: Float
    var hoverLift: Float
}

struct LatticeMetalPickRequest: Equatable {
    enum Kind: UInt32 {
        case hover = 0
        case tap = 1
        case longPress = 2
    }

    var point: SIMD2<Float>
    var kind: Kind
    var token: UInt32
}

struct LatticeMetalPickResult {
    var nodeID: UInt32
    var distanceSquared: UInt32
    var kind: LatticeMetalPickRequest.Kind
    var token: UInt32

    var isValid: Bool { nodeID != UInt32.max }
}

struct LatticeMetalSnapshot {
    var nodes: [LatticeMetalNode]
    var links: [LatticeMetalLink]
    var camera: LatticeCamera
    var viewSize: CGSize
    var baseRadius: Float
    var time: Double
    var audioAmplitude: Float
    var audioPhase: Float
    var debugFlags: UInt32
    var linkAlpha: Float
    var hoverLift: Float
    var useMetalFX: Bool
}

struct LatticeMetalNodeInfo {
    var nodeID: UInt32
    var pos: CGPoint
    var isPlane: Bool
    var coord: LatticeCoord?
    var prime: Int?
    var e3: Int
    var e5: Int
    var eP: Int
    var p: Int
    var q: Int
}

extension Color {
    func metalRGBA() -> SIMD4<Float> {
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
#else
        return SIMD4(1, 1, 1, 1)
#endif
    }
}
