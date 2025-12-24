//
//  AppModelLocator.swift
//  Tenney
//

import Foundation

/// Minimal surface used by LatticeStore without importing your full AppModel type.
protocol AppModelProtocol: AnyObject {
    var rootHz: Double { get }
    var playTestTone: Bool { get set }
}
