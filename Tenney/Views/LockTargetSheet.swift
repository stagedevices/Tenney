//
//  LockTargetSheet.swift
//  Tenney
//
//  Created by OpenAI on 2025-02-17.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LockTargetSheet: View {
    @Binding var numeratorText: String
    @Binding var denominatorText: String
    @Binding var octave: Int

    let lockedTarget: RatioResult?
    let currentNearest: RatioResult?
    let lowerText: String
    let higherText: String
    let recents: [TunerLockRecent]
    let rootHz: Double
    let liveHz: Double
    let tint: Color
    let matchedGeometry: LockFieldMatchedGeometry?
    let onCancel: () -> Void
    let onUnlock: () -> Void
    let onSet: (RatioResult) -> Void
    let onCommit: (RatioResult) -> Void
    let onRemoveRecent: (RatioResult) -> Void
    let onClearRecents: () -> Void

    @FocusState private var focusedField: Field?
    @State private var showKeypad: Bool = false

    private enum Field {
        case numerator
        case denominator
    }

    private var ratioText: String {
        guard !numeratorText.isEmpty || !denominatorText.isEmpty else { return "" }
        return "\(numeratorText)/\(denominatorText)"
    }

    private var lockPreview: RatioResult? {
        ratioResultFromText(ratioText, octave: octave)
    }

    private var validationMessage: String? {
        if denominatorText == "0" { return "Denominator can’t be 0" }
        if numeratorText.isEmpty || denominatorText.isEmpty { return "Enter ratio like 5/4" }
        if lockPreview == nil { return "Enter ratio like 5/4" }
        return nil
    }

    private var displayRatioText: String? {
        ratioText.isEmpty ? nil : ratioText
    }

    private var isPhone: Bool {
#if targetEnvironment(macCatalyst)
        return false
#elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
#else
        return false
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    sectionLayout
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .navigationTitle("Lock Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .modifier(GlassBlueCircle())
                    .accessibilityLabel("Done")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            LockFieldPill(
                size: .large,
                isLocked: lockedTarget != nil,
                displayText: displayRatioText,
                tint: tint,
                matchedGeometry: matchedGeometry
            )
            HStack(spacing: 12) {
                Text("Lock Target")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if lockedTarget != nil {
                    glassActionButton(
                        title: "Unlock",
                        systemImage: "lock.open",
                        isDestructive: true,
                        minHeight: 32,
                        horizontalPadding: 12,
                        fillsWidth: false,
                        action: onUnlock
                    )
                }
            }
        }
    }

    private var sectionLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                enterSection
                pickSection
            }
            .frame(minWidth: 680)

            VStack(alignment: .leading, spacing: 16) {
                enterSection
                pickSection
            }
        }
    }

    private var enterSection: some View {
        GlassCard(corner: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ratioEntryRow
                octaveControl
                previewSection

                if isPhone {
                    if focusedField != nil {
                        keypad
                    }
                } else {
                    Toggle("Keypad", isOn: $showKeypad)
                        .toggleStyle(.switch)
                        .font(.footnote.weight(.semibold))
                    if showKeypad {
                        keypad
                    }
                }
            }
        }
    }

    private var ratioEntryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ratioEntryCell(
                label: "Numerator",
                text: $numeratorText,
                field: .numerator,
                onIncrement: { adjustValue(&numeratorText, delta: 1) },
                onDecrement: { adjustValue(&numeratorText, delta: -1) }
            )

            Text("/")
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            ratioEntryCell(
                label: "Denominator",
                text: $denominatorText,
                field: .denominator,
                onIncrement: { adjustValue(&denominatorText, delta: 1) },
                onDecrement: { adjustValue(&denominatorText, delta: -1) }
            )
        }
    }

    private func ratioEntryCell(
        label: String,
        text: Binding<String>,
        field: Field,
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("0", text: text)
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($focusedField, equals: field)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            focusedField == field
                                ? tint.opacity(0.8)
                                : Color.white.opacity(0.08),
                            lineWidth: focusedField == field ? 1.6 : 1
                        )
                )
                .accessibilityLabel(label)
                .onChange(of: text.wrappedValue) { newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        text.wrappedValue = filtered
                    }
                }

            HStack(spacing: 8) {
                HoldNudgeButton(systemName: "minus", action: onDecrement)
                HoldNudgeButton(systemName: "plus", action: onIncrement)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var octaveControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Octave")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Octave", selection: $octave) {
                ForEach(-2...2, id: \.self) { value in
                    Text(value >= 0 ? "+\(value)" : "\(value)")
                        .tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Octave")
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = validationMessage {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            } else if let preview = lockPreview {
                let targetHz = preview.targetHz(rootHz: rootHz)
                let cents = signedCents(actualHz: liveHz, rootHz: rootHz, target: preview)

                Text("Locks to: \(tunerDisplayRatioString(preview))")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Target Hz: \(targetHz.isFinite ? String(format: "%.2f", targetHz) : "—")")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("At current pitch: \(cents.isFinite ? String(format: "%+.1f¢", cents) : "—")")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pickSection: some View {
        GlassCard(corner: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                let picks = pickItems
                if picks.isEmpty {
                    Text("No targets available yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(picks) { item in
                            Button {
                                applyRatio(item.ratio)
                            } label: {
                                LockPickChip(title: item.title, ratio: tunerDisplayRatioString(item.ratio))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recents")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                            ForEach(recents.prefix(12)) { recent in
                                Button {
                                    applyRatio(recent.ratio)
                                } label: {
                                    LockRecentChip(ratio: tunerDisplayRatioString(recent.ratio))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onRemoveRecent(recent.ratio)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    Button(role: .destructive) {
                                        onClearRecents()
                                    } label: {
                                        Label("Clear All", systemImage: "trash.slash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        let isValid = lockPreview != nil
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                glassActionButton(title: "Cancel", systemImage: "xmark", action: onCancel)

                glassActionButton(title: "Set", systemImage: "checkmark.circle", action: {
                    guard let preview = lockPreview else { return }
                    onSet(preview)
                })
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.6)

                glassActionButton(
                    title: "Lock",
                    systemImage: "lock.fill",
                    usesRedStyle: true,
                    action: {
                    guard let preview = lockPreview else { return }
                    onCommit(preview)
#if os(iOS) && !targetEnvironment(macCatalyst)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                    }
                )
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.6)
            }
            .padding()
            .background(.thinMaterial)
        }
    }

    private func adjustValue(_ text: inout String, delta: Int) {
        let value = Int(text) ?? 0
        let next = max(1, value + delta)
        text = "\(next)"
    }

    private func applyRatio(_ ratio: RatioResult) {
        numeratorText = "\(ratio.num)"
        denominatorText = "\(ratio.den)"
        octave = ratio.octave
        focusedField = nil
    }

    private var pickItems: [LockPickItem] {
        var items: [LockPickItem] = []
        var seen: Set<String> = []

        if let currentNearest {
            let key = lockRecentString(currentNearest)
            items.append(LockPickItem(title: "Nearest", ratio: currentNearest))
            seen.insert(key)
        }

        if let lower = ratioResultFromText(lowerText), !seen.contains(lockRecentString(lower)) {
            items.append(LockPickItem(title: "Lower", ratio: lower))
            seen.insert(lockRecentString(lower))
        }

        if let higher = ratioResultFromText(higherText), !seen.contains(lockRecentString(higher)) {
            items.append(LockPickItem(title: "Higher", ratio: higher))
            seen.insert(lockRecentString(higher))
        }

        return items
    }

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(["1","2","3","4","5","6","7","8","9"], id: \.self) { digit in
                KeypadButton(title: digit) { appendDigit(digit) }
            }
            KeypadButton(system: "delete.left") { backspace() }
            KeypadButton(title: "0") { appendDigit("0") }
            KeypadButton(title: "Next") { switchField() }
        }
        .padding(.top, 6)
    }

    private func appendDigit(_ digit: String) {
        if focusedField == nil {
            focusedField = .numerator
        }
        switch focusedField {
        case .numerator:
            numeratorText.append(digit)
        case .denominator:
            denominatorText.append(digit)
        case .none:
            break
        }
    }

    private func backspace() {
        switch focusedField {
        case .numerator:
            _ = numeratorText.popLast()
        case .denominator:
            _ = denominatorText.popLast()
        case .none:
            break
        }
    }

    private func switchField() {
        if focusedField == .numerator {
            focusedField = .denominator
        } else {
            focusedField = .numerator
        }
    }
}

private struct LockPickItem: Identifiable {
    let title: String
    let ratio: RatioResult
    var id: String { "\(title)-\(ratio.num)-\(ratio.den)-\(ratio.octave)" }
}

private struct LockPickChip: View {
    let title: String
    let ratio: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(ratio)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct LockRecentChip: View {
    let ratio: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ratio)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private extension LockTargetSheet {
    func glassActionButton(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        isDestructive: Bool = false,
        usesRedStyle: Bool = false,
        minHeight: CGFloat = 44,
        horizontalPadding: CGFloat = 14,
        fillsWidth: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            let corner: CGFloat = 12
            let redStyle = isDestructive || usesRedStyle
            let label = HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
            .padding(.horizontal, horizontalPadding)
            .foregroundStyle(redStyle ? .white : (tint ?? .primary))

            Group {
                if redStyle {
                    label.modifier(GlassRedRoundedRect(corner: corner))
                } else {
                    label.modifier(GlassRoundedRect(corner: corner))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(GlassPressFeedback())
    }
}

private struct KeypadButton: View {
    let title: String?
    let system: String?
    let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.system = nil
        self.action = action
    }

    init(system: String, action: @escaping () -> Void) {
        self.title = nil
        self.system = system
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                        .font(.headline.weight(.semibold))
                } else if let system {
                    Image(systemName: system)
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HoldNudgeButton: View {
    let systemName: String
    let action: () -> Void

    @State private var isHolding = false
    @State private var tickCount = 0
    @State private var timer: Timer?

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.thinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHolding else { return }
                    startHolding()
                }
                .onEnded { _ in
                    stopHolding()
                }
        )
        .onDisappear { stopHolding() }
    }

    private func startHolding() {
        isHolding = true
        tickCount = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { _ in
            tickCount += 1
            action()
            if tickCount > 8 {
                action()
            }
        }
    }

    private func stopHolding() {
        isHolding = false
        timer?.invalidate()
        timer = nil
    }
}
