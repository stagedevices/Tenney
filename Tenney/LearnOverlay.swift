//
//  LearnOverlay.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/30/25.
//


//  LearnOverlay.swift
//  Tenney
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LearnOverlay: View {
    let module: LearnTenneyModule?
    let stepIndex: Int
    let totalSteps: Int
    let step: LearnStep?
    let completed: Bool

    let onBack: () -> Void
    let onNext: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void
    let onContinue: () -> Void
    let nextEnabled: Bool

    // Back-compat init (old callers)
    init(currentStep: Int, completed: Bool) {
        self.module = nil
        self.stepIndex = currentStep
        self.totalSteps = 0
        self.step = nil
        self.completed = completed
        self.onBack = {}
        self.onNext = {}
        self.onReset = {}
        self.onDone = {}
        self.onContinue = {}
        self.nextEnabled = true
    }

    init(
        module: LearnTenneyModule? = nil,
        stepIndex: Int,
        totalSteps: Int,
        step: LearnStep?,
        completed: Bool,
        nextEnabled: Bool = true,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onContinue: @escaping () -> Void = {}
    ) {
        self.module = module
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.step = step
        self.completed = completed
        self.onBack = onBack
        self.onNext = onNext
        self.onReset = onReset
        self.onDone = onDone
        self.onContinue = onContinue
        self.nextEnabled = nextEnabled
    }

    var body: some View {
        Group {
            if completed, let module {
                LearnCompletionView(
                    module: module,
                    onPracticeAgain: onReset,
                    onDone: onDone,
                    onContinue: onContinue
                )
            } else {
                // Header
                LearnOverlayCardContent(
                    titleText: titleText,
                    counterText: counterText,
                    bulletLines: bulletLines,
                    step: step,
                    stepIndex: stepIndex,
                    isLastStep: isLastStep,
                    nextEnabled: nextEnabled,
                    onBack: onBack,
                    onReset: onReset,
                    onNext: onNext
                )
            }
        }
    }

    private var titleText: String {
        if let s = step, !s.title.isEmpty { return s.title }
        return "Step \(stepIndex + 1)"
    }

    private var counterText: String {
        if totalSteps > 0 { return "\(stepIndex + 1)/\(totalSteps)" }
        return "Step \(stepIndex + 1)"
    }

    private var bulletLines: [String] {
        guard let s = step else { return [] }
        if !s.bullets.isEmpty { return s.bullets }
        if let i = s.instruction, !i.isEmpty { return [i] }
        return []
    }

    private var isLastStep: Bool {
        totalSteps > 0 && stepIndex >= (totalSteps - 1)
    }
}

private struct LearnOverlayCardContent: View {
    let titleText: String
    let counterText: String
    let bulletLines: [String]
    let step: LearnStep?
    let stepIndex: Int
    let isLastStep: Bool
    let nextEnabled: Bool
    let onBack: () -> Void
    let onReset: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(counterText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }

            if !bulletLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bulletLines, id: \.self) { b in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(b).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let s = step, !s.tryIt.isEmpty {
                Divider().opacity(0.7)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try it")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(s.tryIt)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                    .disabled(stepIndex == 0)

                Button("Reset", action: onReset)
                    .buttonStyle(.bordered)

                Spacer()

                Button(isLastStep ? "Finish" : "Next", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .disabled(!nextEnabled)
                    .opacity(nextEnabled ? 1 : 0.55)
            }
        }
        .padding(12)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct LearnCompletionView: View {
    let module: LearnTenneyModule
    let onPracticeAgain: () -> Void
    let onDone: () -> Void
    let onContinue: () -> Void

    @StateObject private var store = LearnTenneyStateStore.shared
    @State private var didHaptic = false
    @State private var animateIn = false
    @State private var sweep = false

    @Environment(\.tenneyTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            TenneySceneBackground(
                isDark: colorScheme == .dark,
                preset: theme.sceneBackgroundPreset,
                tintA: theme.primeTint(3),
                tintB: theme.primeTint(5)
            )
            .overlay(vignetteOverlay)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    heroPuck
                        .scaleEffect(animateIn ? 1.0 : (reduceMotion ? 1.0 : 0.92))
                        .opacity(animateIn ? 1.0 : (reduceMotion ? 1.0 : 0.0))

                    VStack(spacing: 6) {
                        Text("Module complete")
                            .font(.title2.weight(.semibold))
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .scaleEffect(animateIn ? 1.0 : (reduceMotion ? 1.0 : 0.96))
                    .opacity(animateIn ? 1.0 : (reduceMotion ? 1.0 : 0.0))

                    bulletsView

                    actionCard

                    progressView
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 22)
                .padding(.top, 32)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if !didHaptic {
#if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                didHaptic = true
            }
            if reduceMotion {
                animateIn = true
            } else {
                withAnimation(.easeOut(duration: 0.28)) {
                    animateIn = true
                }
                withAnimation(.easeOut(duration: 0.34)) {
                    sweep = true
                }
            }
        }
    }

    private var tint: Color {
        theme.primeTint(3)._tenneyInterpolate(to: theme.primeTint(5), t: 0.5)
    }

    private var subtitle: String {
        switch module {
        case .lattice: return "Lattice is ready."
        case .tuner: return "Tuner is ready."
        case .builder: return "Builder is ready."
        case .libraryPacks: return "Library & Packs is ready."
        case .rootPitchTuningConfig: return "Reference is ready."
        }
    }

    private var bullets: [String] {
        switch module {
        case .lattice:
            return ["Select ratios", "Audition quickly", "Use prime limits"]
        case .tuner:
            return ["Switch views", "Use lock", "Use stage mode"]
        case .builder:
            return ["Play pads", "Add root", "Hear blends"]
        case .libraryPacks:
            return ["Open your library", "Browse packs", "Learn community packs"]
        case .rootPitchTuningConfig:
            return ["Review root vs tonic", "Check concert pitch", "Debug labels"]
        }
    }

    private var hasNextModule: Bool {
        module.nextModule != nil
    }

    private var completedCount: Int {
        LearnTenneyModule.allCases.filter { store.states[$0]?.completed == true }.count
    }

    private var totalModules: Int {
        LearnTenneyModule.allCases.count
    }

    private var heroPuck: some View {
        let tintOpacity = colorScheme == .dark ? 0.30 : 0.22

        // Choose a single concrete ShapeStyle type for the fill.
        let backgroundStyle: AnyShapeStyle = {
            if reduceTransparency {
                return AnyShapeStyle(tint.opacity(tintOpacity))
            } else {
                return AnyShapeStyle(.ultraThinMaterial)
            }
        }()

        return ZStack {
            Circle()
                .fill(backgroundStyle)
                .overlay(
                    Circle()
                        .fill(tint.opacity(tintOpacity))
                )
                .overlay(puckSweep)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.25), radius: 6, x: 0, y: 4)
        }
        .frame(width: 92, height: 92)
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }


    private var puckSweep: some View {
        Group {
            if !reduceMotion {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(-20))
                    .offset(x: sweep ? width * 0.8 : -width * 0.8)
                }
                .mask(Circle())
                .opacity(0.5)
            }
        }
    }

    private var bulletsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(tint.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(bullet)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            if hasNextModule {
                Button("Continue to next module", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
            Button("Practice again", action: onPracticeAgain)
                .buttonStyle(.bordered)

            Button("Done", action: onDone)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(completedCount) of \(totalModules) modules completed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = totalModules > 0 ? Double(completedCount) / Double(totalModules) : 0
                Capsule()
                    .fill(tint.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.65))
                            .frame(width: width * progress)
                    }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }

    private var cardBackground: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(
                Color(uiColor: .systemBackground).opacity(0.92)
            )
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var vignetteOverlay: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color.clear,
                Color.black.opacity(colorScheme == .dark ? 0.55 : 0.12)
            ]),
            center: .center,
            startRadius: 60,
            endRadius: 460
        )
        .opacity(reduceTransparency ? 0.35 : 0.6)
    }
}

// Manual test checklist:
// - Complete a module: full-screen completion view + single haptic.
// - Reduce Motion on: no sweep, no animated scale.
// - Practice again: resets progress and restarts practice.
// - Done / Continue to next module: returns to hub.





private struct LearnOverlayCard: View {
    let currentStep: Int
    let totalSteps: Int
    let step: LearnStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Step \(currentStep + 1)/\(max(totalSteps, 1))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())

                if let title = step?.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer()
            }

            if let bullets = step?.bullets, !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bullets, id: \.self) { b in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(b).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                    }
                }
            }

            if let tryIt = step?.tryIt, !tryIt.isEmpty {
                Divider().opacity(0.7)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Try it")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(tryIt)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
