//
//  TunerRailClock.swift
//  Tenney
//
//  Created by OpenAI on 2024-05-07.
//

import Foundation
import Combine

struct TunerRailSnapshot: Equatable {
    var ratioText: String
    var cents: Double
    var hz: Double
    var confidence: Double
    var lowerText: String
    var higherText: String
    var isListening: Bool
    var targetKey: String

    var hasLivePitch: Bool {
        isListening && hz.isFinite && hz > 0 && confidence >= 0.3
    }

    var isListeningPlaceholder: Bool { !hasLivePitch }

    static let empty = TunerRailSnapshot(
        ratioText: "—",
        cents: 0,
        hz: 0,
        confidence: 0,
        lowerText: "",
        higherText: "",
        isListening: false,
        targetKey: "none"
    )
}

@MainActor
final class TunerRailClock: ObservableObject {
    @Published var snapshot: TunerRailSnapshot = .empty

    private var cancellable: AnyCancellable?

    init(app: AppModel, hz: Double = 15.0) {
        let interval = max(0.05, min(0.5, 1.0 / hz))
        cancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let display = app.display
                let targetKey = "\(display.ratioText)|\(String(format: "%.0f", display.hz))"
                snapshot = TunerRailSnapshot(
                    ratioText: display.ratioText,
                    cents: display.cents,
                    hz: display.hz,
                    confidence: display.confidence,
                    lowerText: display.lowerText,
                    higherText: display.higherText,
                    isListening: app.micPermission == .granted,
                    targetKey: targetKey
                )
            }
    }
}
