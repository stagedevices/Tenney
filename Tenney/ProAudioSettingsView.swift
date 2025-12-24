//
//  ProAudioSettingsView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  ProAudioSettingsView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/18/25.
//
import Foundation
import SwiftUI
import AVFAudio


@ViewBuilder
private func glassCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.headline)
        content()
    }
    .padding(14)
    .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
    )
}


public struct ProAudioSettingsView: View {

    // State properties to manage settings
    @State private var availableInputs: [AVAudioSessionPortDescription] = []
    @State private var selectedInput: AVAudioSessionPortDescription?
    @State private var preferredSampleRate: Double = 48000  // Default sample rate
    @State private var preferredBufferFrames: Int = 256  // Default buffer size
    @State private var preferredChannelMode: Int = 1  // Mono (0), Stereo (1), Multi-Channel (2)
    @State private var monitorInput: Bool = false

    init() {
        fetchAvailableInputs()
    }
    
    // Fetch available inputs from AVAudioSession
    private func fetchAvailableInputs() {
        let session = AVAudioSession.sharedInstance()
        availableInputs = session.availableInputs ?? []
        if let firstInput = availableInputs.first {
            selectedInput = firstInput
        }
    }

    // Save user settings to UserDefaults
    private func saveToUserDefaults() {
        UserDefaults.standard.set(preferredSampleRate, forKey: SettingsKeys.audioPreferredSampleRate)
        UserDefaults.standard.set(preferredBufferFrames, forKey: SettingsKeys.audioPreferredBufferFrames)
    }
    
    // Validate audio settings (check against known good values)
    private func validateAudioSettings() {
        // Validate sample rate
        let supportedSampleRates: [Double] = [44100.0, 48000.0, 96000.0]
        if !supportedSampleRates.contains(preferredSampleRate) {
            preferredSampleRate = 48000.0  // Default to 48 kHz
        }
        
        // Validate buffer size
        let supportedBufferSizes: [Int] = [128, 256, 512, 1024]
        if !supportedBufferSizes.contains(preferredBufferFrames) {
            preferredBufferFrames = 256  // Default to 256
        }

        // Optionally save changes to UserDefaults
        UserDefaults.standard.set(preferredSampleRate, forKey: SettingsKeys.audioPreferredSampleRate)
        UserDefaults.standard.set(preferredBufferFrames, forKey: SettingsKeys.audioPreferredBufferFrames)
    }
    
    // Main View Body
    public var body: some View {
        glassCard("Pro Audio Input") {
            VStack(alignment: .leading, spacing: 12) {
                // Input Device Picker
                Text("Input Device")
                    .font(.headline)
                HStack {
                    ForEach(availableInputs, id: \.uid) { input in
                        let isSelected = selectedInput?.uid == input.uid
                        Button(action: {
                            withAnimation { selectedInput = input }
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .imageScale(.large)
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                Text(input.portName)
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                            .padding()
                            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                
                // Channel Mode Picker
                Text("Channel Mode")
                    .font(.headline)
                HStack {
                    ChannelModeButton(title: "Mono", isSelected: preferredChannelMode == 0, action: { preferredChannelMode = 0 })
                    ChannelModeButton(title: "Stereo", isSelected: preferredChannelMode == 1, action: { preferredChannelMode = 1 })
                    ChannelModeButton(title: "Multi-Channel", isSelected: preferredChannelMode == 2, action: { preferredChannelMode = 2 })
                }

                // Sample Rate Picker
                Text("Sample Rate")
                    .font(.headline)
                HStack {
                    RateOptionButton(title: "44.1 kHz", rate: 44100.0, preferredSampleRate: $preferredSampleRate, validateAudioSettings: validateAudioSettings)
                    RateOptionButton(title: "48 kHz", rate: 48000.0, preferredSampleRate: $preferredSampleRate, validateAudioSettings: validateAudioSettings)
                    RateOptionButton(title: "96 kHz", rate: 96000.0, preferredSampleRate: $preferredSampleRate, validateAudioSettings: validateAudioSettings)
                }

                // Buffer Size Picker
                Text("Buffer Size")
                    .font(.headline)
                HStack {
                    BufferOptionButton(size: 128, preferredBufferFrames: $preferredBufferFrames, validateAudioSettings: validateAudioSettings)
                    BufferOptionButton(size: 256, preferredBufferFrames: $preferredBufferFrames, validateAudioSettings: validateAudioSettings)
                    BufferOptionButton(size: 512, preferredBufferFrames: $preferredBufferFrames, validateAudioSettings: validateAudioSettings)
                    BufferOptionButton(size: 1024, preferredBufferFrames: $preferredBufferFrames, validateAudioSettings: validateAudioSettings)
                }

                // Monitor Input Toggle
                Toggle("Monitor Input", isOn: $monitorInput)
                    .padding(.top, 10)
                    .onChange(of: monitorInput) { _ in manageInputMonitoring() }

                if monitorInput {
                    Text("Input monitoring is active. Make sure output is safe from feedback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear {
            // Save to UserDefaults when the view disappears
            saveToUserDefaults()
        }
    }
    
    private func manageInputMonitoring() {
        // Add logic for preventing feedback
    }

    // Custom Views for each setting
    private struct ChannelModeButton: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .padding(10)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private struct RateOptionButton: View {
        let title: String
        let rate: Double
        @Binding var preferredSampleRate: Double
        let validateAudioSettings: () -> Void

        var body: some View {
            Button {
                preferredSampleRate = rate
                validateAudioSettings()  // Call validation function
            } label: {
                VStack {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(preferredSampleRate == rate ? .primary : .secondary)
                    Image(systemName: preferredSampleRate == rate ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                        .foregroundColor(preferredSampleRate == rate ? .accentColor : .secondary)
                }
                .padding(10)
                .background(preferredSampleRate == rate ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private struct BufferOptionButton: View {
        let size: Int
        @Binding var preferredBufferFrames: Int
        let validateAudioSettings: () -> Void

        var body: some View {
            Button {
                preferredBufferFrames = size
                validateAudioSettings()  // Call validation function
            } label: {
                VStack {
                    Text("\(size)")
                        .font(.footnote)
                        .foregroundStyle(preferredBufferFrames == size ? .primary : .secondary)
                    Image(systemName: preferredBufferFrames == size ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                        .foregroundColor(preferredBufferFrames == size ? .accentColor : .secondary)
                }
                .padding(10)
                .background(preferredBufferFrames == size ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

}
