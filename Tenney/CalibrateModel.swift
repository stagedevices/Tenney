//
//  CalibrateModel.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  CalibrateModel.swift
//  VenueCalibrator
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI
import Combine
import AVFAudio

final class CalibrateModel: ObservableObject {
    @Published var venueName: String = "This venue"
    @Published var a4Hz: Double = 440.0 { didSet { clampA4() } }
    @Published var rootHz: Double = 440.0
    @Published var playing: Bool = false
    @Published var accent: Accent = .system
    @Published var routeSummary: String = AudioRoute.summary() // “Built-in Speaker • 48 kHz”

    private let engine = TinyTone()
    private var bag = Set<AnyCancellable>()

    init() {
        rootHz = a4Hz
        observeRoute()
    }

    func applyParams(a4: Double?, name: String?, accent: String?, quick: Bool) {
        if let a4 = a4, a4.isFinite { a4Hz = a4 }
        rootHz = a4Hz
        if let n = name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            venueName = n
        } else {
            venueName = "This venue"
        }
        if let a = accent, let acc = Accent(rawValue: a.lowercased()) { self.accent = acc }
        if quick { play() }
    }

    // MARK: Controls

    func play() {
        engine.start()
        engine.setFrequency(rootHz)
        engine.setPlaying(true)
        playing = true
    }

    func stop() {
        engine.setPlaying(false)
        playing = false
    }

    func togglePlay() { playing ? stop() : play() }

    func octave(_ dir: Int) {                 // dir: -1 or +1
        let f = rootHz * (dir < 0 ? 0.5 : 2.0)
        setRoot(clamped(f))
    }

    func nudgeCents(_ cents: Double) {
        let f = rootHz * pow(2.0, cents / 1200.0)
        setRoot(clamped(f))
    }

    func setRoot(_ hz: Double) {
        rootHz = hz
        if playing { engine.setFrequency(rootHz) }
    }

    private func clampA4() { a4Hz = clamped(a4Hz) }
    private func clamped(_ f: Double) -> Double { min(2000.0, max(20.0, f)) }

    // MARK: Route

    private func observeRoute() {
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                self?.routeSummary = AudioRoute.summary()
                // Conservative: stop on route change to avoid surprises on stage
                self?.stop()
            }
            .store(in: &bag)
    }

    // MARK: Accent

    enum Accent: String, CaseIterable, Identifiable {
        case system, amber, red
        var id: String { rawValue }
        var colors: [Color] {
            switch self {
            case .system: return [ .accentColor, .accentColor.opacity(0.55) ]
            case .amber:  return [ .orange, .yellow ]
            case .red:    return [ .red, .pink ]
            }
        }
    }
}

// MARK: - Audio helpers

enum AudioRoute {
    static func summary() -> String {
        let s = AVAudioSession.sharedInstance()
        let name = s.currentRoute.outputs.first?.portName ?? "Built-in Speaker"
        let kHz = s.sampleRate / 1000.0
        let rate = (abs(kHz - 44.1) < 0.2) ? "44.1" : String(format: "%.0f", kHz)
        return "\(name) • \(rate) kHz"
    }
}