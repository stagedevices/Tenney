//
//  LearnTenneyModuleView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import SwiftUI

enum LearnTenneyTab: String, CaseIterable, Identifiable {
    case practice, reference
    var id: String { rawValue }
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
    case builderAddRoot
    case builderOscilloscope
}

struct LearnTenneyModuleView: View {
    let module: LearnTenneyModule

    @State private var tab: LearnTenneyTab = .practice
    @State private var practiceFocus: LearnPracticeFocus? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Top rail (segmented)
            VStack(spacing: 10) {
                Picker("", selection: $tab) {
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
    private struct LearnTenneyTourView: View {
        let module: LearnTenneyModule
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tour").font(.title2.weight(.semibold))
                    Text("Tour content goes here.")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }

}
