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
        !isListening
    }

    var isListeningPlaceholder: Bool { isListening }

    static let empty = TunerRailSnapshot(
        ratioText: "—",
        cents: 0,
        hz: 0,
        confidence: 0,
        lowerText: "",
        higherText: "",
        isListening: true,
        targetKey: "none"
    )
}

@MainActor
final class TunerRailClock: ObservableObject {
    @Published var snapshot: TunerRailSnapshot = .empty
    private var lastGoodSnapshot: TunerRailSnapshot = .empty
    private var hasGoodSnapshot = false

    private var cancellable: AnyCancellable?
    private static let listeningConfidenceThreshold = 0.6

    init(app: AppModel, hz: Double = 15.0) {
        let initialTargetKey = Self.targetKey(for: app.display)
        let initialSnapshot = TunerRailSnapshot(
            ratioText: app.display.ratioText,
            cents: app.display.cents,
            hz: app.display.hz,
            confidence: app.display.confidence,
            lowerText: app.display.lowerText,
            higherText: app.display.higherText,
            isListening: Self.isListening(
                display: app.display,
                targetKey: initialTargetKey,
                micPermission: app.micPermission
            ),
            targetKey: initialTargetKey
        )

        snapshot = initialSnapshot
        if !initialSnapshot.isListening {
            lastGoodSnapshot = initialSnapshot
            hasGoodSnapshot = true
        }

        let interval = max(0.05, min(0.5, 1.0 / hz))
        cancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let display = app.display
                let targetKey = Self.targetKey(for: display)
                let listening = Self.isListening(
                    display: display,
                    targetKey: targetKey,
                    micPermission: app.micPermission
                )

                let nextSnapshot = TunerRailSnapshot(
                    ratioText: display.ratioText,
                    cents: display.cents,
                    hz: display.hz,
                    confidence: display.confidence,
                    lowerText: display.lowerText,
                    higherText: display.higherText,
                    isListening: listening,
                    targetKey: targetKey
                )

                if listening {
                    let held = hasGoodSnapshot ? lastGoodSnapshot : snapshot
                    snapshot = held.withListening(true)
                } else {
                    lastGoodSnapshot = nextSnapshot.withListening(false)
                    hasGoodSnapshot = true
                    snapshot = nextSnapshot
                }
            }
    }

    private static func targetKey(for display: TunerDisplay) -> String {
        guard display.hz.isFinite, display.hz > 0 else { return "" }
        return "\(display.ratioText)|\(String(format: "%.0f", display.hz))"
    }

    private static func isListening(
        display: TunerDisplay,
        targetKey: String,
        micPermission: MicPermissionState
    ) -> Bool {
        let ratioMissing = display.ratioText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || display.ratioText == "—"
        let invalidHz = !display.hz.isFinite || display.hz <= 0
        return micPermission != .granted
        || ratioMissing
        || invalidHz
        || targetKey.isEmpty
        || display.confidence < listeningConfidenceThreshold
    }
}

private extension TunerRailSnapshot {
    func withListening(_ isListening: Bool) -> TunerRailSnapshot {
        var copy = self
        copy.isListening = isListening
        return copy
    }
}
