//
//  LearnEvents.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/30/25.
//


//  LearnEvents.swift
//  Tenney

import Combine
import Foundation

enum LearnEvent: Equatable, Sendable {
    // Lattice
    case latticeAuditionEnabledChanged(Bool)
    case latticePrimeChipToggled(Int, Bool)
    case latticePrimeChipHiToggle(Bool)
    case latticeNodeSelected(String)
    case latticeNodeAuditioned(String)
    case latticePinPaletteOpened
    case latticeCameraChanged(pan: Double, zoom: Double)
    case latticeEdgeLabelsChanged(Double)
    case latticePlaneOrLevelChanged(Double)
    case latticeFocusSet
    case latticeFocusCleared

    // Tuner
    case tunerTargetPicked(String)
    case tunerLockToggled(Bool)
    case tunerRootChanged(Double)
    case tunerPitchHistoryOpened
    case tunerPitchHistoryClosed
    case tunerConfidenceGateChanged(Double)
    case tunerOutputEnabledChanged(Bool)
    case tunerOutputWaveChanged(String)

    // Builder
    case builderPadTriggered(Int)
    case builderPadOctaveChanged(Int, Int)
    case builderSelectionChanged(Int)
    case builderSelectionCleared
    case builderExportOpened
    case builderOscilloscopeObserved

    // Meta
    case attemptedDisallowedAction(String)
}

final class LearnEventBus {
    static let shared = LearnEventBus()
    private let subject = PassthroughSubject<LearnEvent, Never>()
    var publisher: AnyPublisher<LearnEvent, Never> { subject.eraseToAnyPublisher() }

    func send(_ event: LearnEvent) { subject.send(event) }
}
