//
//  LearnTenneyModuleView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import SwiftUI

enum LearnTenneyTab: String, CaseIterable, Identifiable {
    case tour = "tour"
    case practice = "practice"
    case reference = "reference"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tour: return "Tour"
        case .practice: return "Practice"
        case .reference: return "Reference"
        }
    }
}

enum LearnPracticeFocus: Hashable, Sendable {
    case latticeTapSelect
    case latticeLongPress
    case latticeLimitChips
    case latticeAxisShift
    case tunerViewSwitch
    case tunerLockTarget
    case tunerConfidence
    case tunerPrimeLimit
    case tunerStageMode
    case tunerETvsJI
    case builderPads
    case builderOctaveStepping
    case builderExport
    case builderOscilloscope
}

struct LearnTenneyModuleView: View {
    let module: LearnTenneyModule

    @State private var tab: LearnTenneyTab = .tour
    @State private var practiceFocus: LearnPracticeFocus? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Top rail (segmented)
            VStack(spacing: 10) {
                Picker("", selection: $tab) {
                    Text("Tour").tag(LearnTenneyTab.tour)
                    Text("Practice").tag(LearnTenneyTab.practice)
                    Text("Reference").tag(LearnTenneyTab.reference)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)

            // Content (single scroll container per tab)
            Group {
                switch tab {
                case .tour:
                    LearnTenneyTourView(module: module)

                case .practice:
                    LearnTenneyPracticeView(module: module, focus: $practiceFocus)

                case .reference:
                    LearnTenneyReferenceListView(module: module) { focus in
                        practiceFocus = focus
                        tab = .practice
                    }
                }
            }
        }
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

