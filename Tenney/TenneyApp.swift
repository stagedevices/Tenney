//
//  TenneyApp.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import SwiftUI

@main
struct TenneyApp: App {
    @StateObject private var tuner = TunerViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tuner)
        }
    }
}
