//
//  ContentView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var vm: TunerViewModel

    var body: some View {
        AdaptiveRoot(
            stage: StageView(vm: vm),
            rail: RailControls(vm: vm),
            utility: UtilityBar()
        )
        #if DEBUG
        .devOverlay()
        #endif
    }
}

private struct StageView: View {
    @ObservedObject var vm: TunerViewModel

    var body: some View {
        VStack(spacing: 10) {
            Text("Tenney").font(TenneyTokens.Font.display(28))

            Text(vm.displayRatio)
                .font(TenneyTokens.Font.mono(64))
                .foregroundStyle(TenneyTokens.Color.prime5)

            Text(vm.centsText)
                .font(TenneyTokens.Font.body(18))
                .foregroundStyle(.secondary)

            Text(vm.hzText)
                .font(TenneyTokens.Font.body(14))
                .foregroundStyle(.secondary)

            if !vm.altRatios.isEmpty {
                HStack(spacing: 12) {
                    ForEach(vm.altRatios, id: \.self) { txt in
                        PrimeChip(title: txt, tint: .secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct RailControls: View {
    @ObservedObject var vm: TunerViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Root + Limit
            HStack {
                Stepper("Root \(Int(vm.rootHz)) Hz", value: Binding(
                    get: { Int(vm.rootHz) },
                    set: { vm.rootHz = Double($0) }
                ), in: 110...880, step: 1)
                .font(TenneyTokens.Font.body(16))

                Spacer()

                Menu {
                    ForEach(PrimeLimit.allCases, id: \.self) { lim in
                        Button(limLabel(lim)) { vm.primeLimit = lim }
                    }
                } label: {
                    Text("Limit: \(vm.primeLimit.rawValue)")
                }
            }

            // Strictness
            Picker("Strictness", selection: $vm.strictness) {
                Text("Loose").tag(Strictness.loose)
                Text("Performance").tag(Strictness.performance)
                Text("Strict").tag(Strictness.strict)
            }
            .pickerStyle(.segmented)

            // Meter + Mic state + Test tone
            VStack(spacing: 6) {
                HStack {
                    Text(vm.micGranted ? "Mic: On" : "Mic: Off")
                    Spacer()
                    Text(String(format: "RMS: %.3f", vm.inputRMS))
                        .foregroundStyle(.secondary)
                }
                MeterBar(level: vm.inputRMS)
                Toggle(isOn: $vm.useTestTone) {
                    Text("Test Tone 220 Hz")
                }
            }
        }
        .padding(.horizontal, TenneyTokens.Spacing.m)
        .padding(.vertical, TenneyTokens.Spacing.m)
    }

    private func limLabel(_ l: PrimeLimit) -> String {
        switch l {
        case .three: return "3-limit"
        case .five: return "5-limit"
        case .seven: return "7-limit"
        case .eleven: return "11-limit"
        case .thirteen: return "13-limit"
        }
    }
}

private struct UtilityBar: View {
    var body: some View {
        HStack {
            Text("Liquid Glass • iOS 26")
            Spacer()
            Button("Export") {}
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, TenneyTokens.Spacing.l)
        .padding(.vertical, 8)
        .modifier(GlassToolbarBackground())
    }
}

 struct GlassToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(TenneyTokens.Color.glassBorder, lineWidth: 0.5) }
        }
    }
}
