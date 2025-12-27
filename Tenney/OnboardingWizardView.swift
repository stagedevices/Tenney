//
//  OnboardingWizardView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  OnboardingWizardView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//

//
//  OnboardingWizardView.swift
//  Tenney
//
//  First-run setup wizard (liquid glass modal) with four steps:
//    1) Root pitch (JI root) with preview
//    2) Equal-Temperament Reference (A4) with preview
//    3) Appearance (Lattice Theme + Light/Dark/System override)
//    4) Default screen (Lattice or Tuner) + “white dip” flash to allow background swap
//

import SwiftUI
import UIKit

// OnboardingWizardView
// - Transparent root; one GLASS card per step floating above tuner
// - Underlying tuner is blurred & dimmed by ContentView; we add no fullscreen backgrounds here
// - Theme picker constrained so it never overflows on small devices

struct OnboardingWizardView: View {
    @Namespace private var animationNamespace
    var onRequireSwapFlash: () -> Void
    var onDone: () -> Void
    @EnvironmentObject private var app: AppModel
    @AppStorage(SettingsKeys.setupWizardDone) private var setupWizardDone: Bool = false
    @AppStorage(SettingsKeys.defaultView)    private var defaultView: String = "tuner" // "lattice" | "tuner"
    @AppStorage(SettingsKeys.staffA4Hz)      private var a4Staff: Double = 440

    // Steps: 0=Root, 1=A4, 2=Theme/Style, 3=Default Screen
    @State private var step: Int = 0

    // Step 1 — Root presets + custom
    private let rootPresets: [Double] = [392, 415, 440]
    @State private var rootPreset: Double? = 415
    @State private var rootCustomHz: Double = 415
    @State private var previewRootOn: Bool = false

    // Step 2 — A4 presets + custom
    private let a4Presets: [Double] = [425, 440, 442, 444]
    @State private var a4Preset: Double? = 440
    @State private var a4CustomHz: Double = 440
    @State private var previewA4On: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            progressPips
            glassStepCard
            controls
        }
        .padding(8)
        .background(.clear) // absolutely no extra background between wizard and tuner
        
        .onAppear {
            // Seed from current app state
            rootCustomHz = app.rootHz
            if let m = rootPresets.first(where: { abs($0 - app.rootHz) < 0.01 }) {
                rootPreset = m
            } else { rootPreset = nil }

            a4CustomHz = a4Staff
            if let m = a4Presets.first(where: { abs($0 - a4Staff) < 0.01 }) {
                a4Preset = m
            } else { a4Preset = nil }
        }
        .onDisappear { stopTone() } // ensure tone off
    }

    // MARK: - Header progress
    private var progressPips: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Circle()
                    .fill(i == step ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Step card (GLASS)
    private var glassStepCard: some View {
        GlassCard {
            switch step {
            case 0: stepRoot
            case 1: stepA4
            case 2: stepTheme
            default: stepDefaultView
            }
        }
    }

    // MARK: - Step 1: Root pitch
    private var stepRoot: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Initial Root Pitch")
                .font(.headline)
            // tiles
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)], spacing: 12) {
                ForEach(rootPresets, id: \.self) { hz in
                    SelectTile(label: "\(Int(hz)) Hz", selected: rootPreset == hz)
                        .onTapGesture { selectRoot(hz) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SelectTile(label: "Custom", selected: rootPreset == nil)
                        .onTapGesture { withAnimation(.snappy) { rootPreset = nil } }
                    if rootPreset == nil {
                        HStack {
                            Text("Root")
                            Spacer()
                            TextField("Hz", value: $rootCustomHz, format: .number.precision(.fractionLength(1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .onChange(of: rootCustomHz) { _ in commitRootCustom() }
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            Toggle("Preview tone", isOn: $previewRootOn)
                .toggleStyle(.switch)
                .onChange(of: previewRootOn) { on in
                    let hz = currentRootHz
                    if on { startTone(hz) } else { stopTone() }
                }
            Text("This is your Just Intonation root (used in Lattice & Tuner).")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear {
            // ensure current values reflect app state
            rootCustomHz = app.rootHz
        }
    }
    private var currentRootHz: Double { rootPreset ?? max(20, min(5000, rootCustomHz)) }
    private func selectRoot(_ hz: Double) {
        withAnimation(.snappy) { rootPreset = hz }
        app.rootHz = hz
        postSetting(SettingsKeys.rootHz, hz) // broadcast; favorites model (if any) can listen
        if previewRootOn { setTone(hz) }
    }
    private func commitRootCustom() {
        let hz = currentRootHz
        app.rootHz = hz
        postSetting(SettingsKeys.rootHz, hz)
        if previewRootOn { setTone(hz) }
    }

    // MARK: - Step 2: Equal-Temperament Reference (A4)
    private var stepA4: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equal-Temperament Reference (A4)")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)], spacing: 12) {
                ForEach(a4Presets, id: \.self) { hz in
                    SelectTile(label: "\(Int(hz)) Hz", selected: a4Preset == hz)
                        .onTapGesture { selectA4(hz) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SelectTile(label: "Custom", selected: a4Preset == nil)
                        .onTapGesture { withAnimation(.snappy) { a4Preset = nil } }
                    if a4Preset == nil {
                        HStack {
                            Text("A4")
                            Spacer()
                            TextField("Hz", value: $a4CustomHz, format: .number.precision(.fractionLength(1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .onChange(of: a4CustomHz) { _ in commitA4Custom() }
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            Toggle("Preview tone", isOn: $previewA4On)
                .toggleStyle(.switch)
                .onChange(of: previewA4On) { on in
                    if on { startTone(currentA4Hz) } else { stopTone() }
                }
            Text("Used for staff names & ET cents. Independent from your JI root.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var currentA4Hz: Double { a4Preset ?? max(200, min(1000, a4CustomHz)) }
    private func selectA4(_ hz: Double) {
        withAnimation(.snappy) { a4Preset = hz; a4Staff = hz }
        postSetting(SettingsKeys.staffA4Hz, hz)
        if previewA4On { setTone(hz) }
    }
    private func commitA4Custom() {
        let hz = currentA4Hz
        a4Staff = hz
        postSetting(SettingsKeys.staffA4Hz, hz)
        if previewA4On { setTone(hz) }
    }

    // MARK: - Step 3: Theme & Style (fits; never overflows)
    private var stepTheme: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance & Theme")
                .font(.headline)
            // Constrain height so this never pushes out of the card; allow internal scrolling if needed.
            ScrollView {
                SettingsThemePickerView()
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: 360) // clamps on small phones; expands on iPad
        }
    }

    // MARK: - Step 4: Default screen (swap under full white dip)
    private var stepDefaultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Screen at Launch")
                .font(.headline)
            HStack(spacing: 12) {
                GlassSelectTile(title: "Lattice", isOn: defaultView == "lattice") {
                    selectDefaultView("lattice")
                }
                GlassSelectTile(title: "Tuner", isOn: defaultView == "tuner") {
                    selectDefaultView("tuner")
                }
            }
            Text("We’ll briefly fade to white while applying your choice.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func selectDefaultView(_ v: String) {
        guard v != defaultView else { return }
        defaultView = v
        onRequireSwapFlash() // brief white dip handled by ContentView
    }
    
   
    struct BackButton: View { let ns: Namespace.ID; var action: () -> Void
      
        
        var body: some View {
            Button(action: action) {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 200)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Material.thin)
                        
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    )
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16)
                    .matchedGeometryEffect(id: "backButton", in: ns)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    struct ContinueButton: View { let ns: Namespace.ID; var action: () -> Void

        var body: some View {
            Button(action: action) {
                Label("Continue", systemImage: "chevron.right.circle.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 200)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Material.thin)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    )
                    .contentShape(Rectangle())
                    .matchedGeometryEffect(id: "continueButton", in: ns)
            }
            .buttonStyle(PlainButtonStyle())
            .animation(.spring(), value: ns)
        }
    }

    struct DoneButton: View { let ns: Namespace.ID; var action: () -> Void
        var body: some View {
            Button(action: action) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 200)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Material.thin)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    )
                    .contentShape(Rectangle())
                    .matchedGeometryEffect(id: "doneButton", in: ns)
            }
            .buttonStyle(PlainButtonStyle())
            .animation(.easeInOut, value: ns)
        }
    }

    // MARK: - Controls
    private var controls: some View {
        HStack {
            if step > 0 {
                BackButton(ns: animationNamespace, action: {
                    withAnimation {
                        step -= 1
                    }
                })
            }
            
            Spacer()

            if step < 3 {
                ContinueButton(ns: animationNamespace, action: {
                    withAnimation {
                        step += 1
                    }
                })
            } else {
                DoneButton(ns: animationNamespace, action: {
                    withAnimation {
                        onDone()
                    }
                })
            }
        }
        .padding(.top, 16)
    }
    
}




private struct SelectTile: View {
    let label: String
    let selected: Bool
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(label)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(minWidth: 88, minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(12)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.small)
                    .symbolRenderingMode(.hierarchical)
                    .padding(6)
            }
        }
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .contentTransition(.opacity)
    }
}


// MARK: - Tone preview helpers
private func startTone(_ hz: Double) { _ = ToneOutputEngine.shared.start(frequency: hz) }
private func setTone(_ hz: Double)   { ToneOutputEngine.shared.setFrequency(hz) }
private func stopTone()               { ToneOutputEngine.shared.stop() }

// MARK: - Broadcast helper
private func postSetting(_ key: String, _ value: Any) {
    NotificationCenter.default.post(name: .settingsChanged, object: nil, userInfo: [key: value])
}
