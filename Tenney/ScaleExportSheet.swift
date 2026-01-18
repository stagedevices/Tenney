import SwiftUI

struct ExportFormat: OptionSet {
    let rawValue: Int

    static let scl     = ExportFormat(rawValue: 1 << 0)
    static let kbm     = ExportFormat(rawValue: 1 << 1)
    static let freqs   = ExportFormat(rawValue: 1 << 2)
    static let cents   = ExportFormat(rawValue: 1 << 3)
    static let ableton = ExportFormat(rawValue: 1 << 4) // Ableton .ascl (Scala-based stub)

    static let `default`: ExportFormat = [.scl, .kbm]
}

enum ExportA4Mode: String, CaseIterable, Identifiable {
    case appDefault
    case hz440
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appDefault: return "App default"
        case .hz440:      return "440 Hz"
        case .custom:     return "Custom"
        }
    }
}

struct ScaleExportSheet: View {
    let title: String
    let builderRootSummary: String
    let exportSummaryText: String
    let exportFormats: ExportFormat
    let exportErrorMessage: String?
    let onToggleFormat: (ExportFormat) -> Void
    let onExport: () -> Void
    let onDone: () -> Void
    @Binding var exportA4Mode: ExportA4Mode
    @Binding var customA4Hz: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text("Export “\(title)”")
                        .font(.headline)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }

                Spacer()

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            Text("Choose formats to export and share this tuning to other apps and devices.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Formats")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("For synths & DAWs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        exportFormatRow(
                            format: .scl,
                            title: "Scala scale (.scl)",
                            subtitle: "Ratio-based tuning for Scala-compatible synths."
                        )
                        exportFormatRow(
                            format: .kbm,
                            title: "Scala keyboard mapping (.kbm)",
                            subtitle: "Maps the scale to a MIDI note and reference frequency."
                        )
                        exportFormatRow(
                            format: .ableton,
                            title: "Ableton scale (.ascl)",
                            subtitle: "Live 12 tuning (Scala-compatible stub)."
                        )
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("For documentation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        exportFormatRow(
                            format: .freqs,
                            title: "Plain text frequencies (freqs.txt)",
                            subtitle: "One frequency per line in Hz."
                        )
                        exportFormatRow(
                            format: .cents,
                            title: "Plain text cents (cents.txt)",
                            subtitle: "One offset per line in cents from unison."
                        )
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("A4 reference")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Picker("A4 reference", selection: $exportA4Mode) {
                    ForEach(ExportA4Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if exportA4Mode == .custom {
                    HStack {
                        Text("Custom A4 (Hz)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("440", value: $customA4Hz, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Builder root")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(builderRootSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(exportSummaryText)
                .font(.footnote)
                .foregroundStyle(exportFormats.isEmpty ? .secondary : .primary)

            Button {
                onExport()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up.on.square")
                    Text("Export Selected")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(exportFormats.isEmpty)

            if let message = exportErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 6)
    }

    private func exportFormatRow(format: ExportFormat, title: String, subtitle: String) -> some View {
        let isOn = exportFormats.contains(format)

        return Button {
            onToggleFormat(format)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                        .background(
                            (isOn ? Color.accentColor.opacity(0.08) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        )
                        .frame(width: 24, height: 24)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
