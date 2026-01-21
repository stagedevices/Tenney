import Foundation

enum ScalePlaybackMode: String, CaseIterable, Identifiable {
    case arp
    case chord
    case drone

    var id: String { rawValue }
    var title: String {
        switch self {
        case .arp: return "Arp"
        case .chord: return "Chord"
        case .drone: return "Drone"
        }
    }
}

final class ScalePreviewPlayer {
    private var activeVoiceIDs: [Int] = []
    private var token = UUID()
    private var droneActive = false

    func play(mode: ScalePlaybackMode, scale: TenneyScale, degrees: [RatioRef], focus: RatioRef?, safeAmp: Double) {
        stop()
        let newToken = UUID()
        token = newToken

        let rootHz = RatioMath.foldToAudible(scale.referenceHz)
        let selected = focus ?? degrees.first
        let amp = Float(safeAmp)

        func startTone(_ freq: Double) -> Int {
            let ownerKey = "scaleLibrary:\(scale.id.uuidString):\(UUID().uuidString)"
            return ToneOutputEngine.shared.sustain(
                freq: freq,
                amp: amp,
                owner: .other,
                ownerKey: ownerKey,
                attackMs: 6,
                releaseMs: 120
            )
        }

        func scheduleRelease(id: Int, after seconds: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, self.token == newToken else { return }
                ToneOutputEngine.shared.release(id: id, seconds: 0.06)
                self.activeVoiceIDs.removeAll { $0 == id }
            }
        }

        switch mode {
        case .arp:
            for (index, ratio) in degrees.enumerated() {
                let delay = Double(index) * 0.18
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.token == newToken else { return }
                    let hz = RatioMath.hz(rootHz: scale.referenceHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: true)
                    let id = startTone(hz)
                    self.activeVoiceIDs.append(id)
                    scheduleRelease(id: id, after: 0.22)
                }
            }
        case .chord:
            for ratio in degrees {
                let hz = RatioMath.hz(rootHz: scale.referenceHz, p: ratio.p, q: ratio.q, octave: ratio.octave, fold: true)
                let id = startTone(hz)
                activeVoiceIDs.append(id)
                scheduleRelease(id: id, after: 0.38)
            }
        case .drone:
            let rootID = startTone(rootHz)
            activeVoiceIDs.append(rootID)
            scheduleRelease(id: rootID, after: 0.48)
            if let selected {
                let hz = RatioMath.hz(rootHz: scale.referenceHz, p: selected.p, q: selected.q, octave: selected.octave, fold: true)
                let id = startTone(hz)
                activeVoiceIDs.append(id)
                scheduleRelease(id: id, after: 0.48)
            }
        }
    }

    func stop() {
        droneActive = false
        token = UUID()
        for id in activeVoiceIDs {
            ToneOutputEngine.shared.release(id: id, seconds: 0.0)
        }
        activeVoiceIDs.removeAll()
    }

    func toggleDrone(rootHz: Double, focusHz: Double, safeAmp: Double) -> Bool {
        if droneActive {
            stop()
            droneActive = false
            return false
        }

        stop()
        droneActive = true

        let amp = Float(safeAmp)
        func startTone(_ freq: Double) -> Int {
            let ownerKey = "scaleLibrary:drone:\(UUID().uuidString)"
            return ToneOutputEngine.shared.sustain(
                freq: freq,
                amp: amp,
                owner: .other,
                ownerKey: ownerKey,
                attackMs: 6,
                releaseMs: 120
            )
        }

        let a = startTone(rootHz)
        let b = startTone(focusHz)
        activeVoiceIDs = [a, b]
        return true
    }
}
