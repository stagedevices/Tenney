//
//  LearnOverlay.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/30/25.
//


//  LearnOverlay.swift
//  Tenney
import SwiftUI

struct LearnOverlay: View {
    let stepIndex: Int
    let totalSteps: Int
    let step: LearnStep?
    let completed: Bool

    let onBack: () -> Void
    let onNext: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void
    let nextEnabled: Bool

    // Back-compat init (old callers)
    init(currentStep: Int, completed: Bool) {
        self.stepIndex = currentStep
        self.totalSteps = 0
        self.step = nil
        self.completed = completed
        self.onBack = {}
        self.onNext = {}
        self.onReset = {}
        self.onDone = {}
        self.nextEnabled = true
    }

    init(
        stepIndex: Int,
        totalSteps: Int,
        step: LearnStep?,
        completed: Bool,
        nextEnabled: Bool = true,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.step = step
        self.completed = completed
        self.onBack = onBack
        self.onNext = onNext
        self.onReset = onReset
        self.onDone = onDone
        self.nextEnabled = nextEnabled
    }

    var body: some View {
        VStack(spacing: 10) {
            if completed {
                HStack(spacing: 10) {
                    Text("🎉 Practice Complete")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                // Header
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

                // Bullets / instruction
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

                // Try it
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

                // Controls
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
