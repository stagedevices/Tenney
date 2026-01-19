import SwiftUI


enum TagChipSize {
    case small
    case regular

    var font: Font {
        switch self {
        case .small: return .caption2.weight(.semibold).monospaced()
        case .regular: return .caption.weight(.semibold).monospaced()
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 8
        case .regular: return 10
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small: return 4
        case .regular: return 6
        }
    }
}

struct TagChip: View {
    let tag: TagRef
    var size: TagChipSize = .regular
    var isSelected: Bool = false
    var showsRemove: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = tag.sfSymbolName {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
            }
            Text(tag.name)
                .font(size.font)
            if showsRemove {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag")
            }
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(tagBackground)
        .overlay(
            Capsule()
                .stroke(tag.color.color.opacity(isSelected ? 0.8 : 0.45), lineWidth: isSelected ? 1.4 : 1)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var tagBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(tag.color.color.opacity(isSelected ? 0.5 : 0.28)), in: Capsule())
        } else {
            Color.clear
                .background(.thinMaterial)
                .overlay(
                    Capsule()
                        .fill(tag.color.color.opacity(isSelected ? 0.22 : 0.14))
                )
        }
    }
}

struct TagChipRow: View {
    let tags: [TagRef]
    var maxCount: Int = 3

    var body: some View {
        let limited = tags.prefix(maxCount)
        let extra = max(0, tags.count - limited.count)
        HStack(spacing: 6) {
            ForEach(limited) { tag in
                TagChip(tag: tag, size: .small)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            }
        }
    }
}

struct TagIconPicker: View {
    @Binding var selection: String?
    @State private var searchText = ""

    private var filteredIcons: [String] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TagIconPicker.iconCatalog
        }
        return TagIconPicker.iconCatalog.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search icons", text: $searchText)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                Button {
                    selection = nil
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "nosign")
                            .font(.headline)
                        Text("None")
                            .font(.caption2.monospaced())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(iconBackground(isSelected: selection == nil))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                ForEach(filteredIcons, id: \.self) { symbol in
                    Button {
                        selection = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.headline)
                            .frame(width: 34, height: 34)
                            .padding(8)
                            .background(iconBackground(isSelected: selection == symbol))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func iconBackground(isSelected: Bool) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15)), in: .rect(cornerRadius: 10))
        } else {
            Color.clear
                .background(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((isSelected ? Color.accentColor : Color.secondary).opacity(0.16))
                )
        }
    }

    static let iconCatalog: [String] = [
        "tag.fill",
        "tag",
        "tuningfork",
        "music.note",
        "music.note.list",
        "pianokeys",
        "guitars",
        "metronome",
        "waveform",
        "slider.horizontal.3",
        "slider.horizontal.below.rectangle",
        "sparkles",
        "sparkle",
        "sun.max",
        "moon.stars",
        "bolt",
        "flame",
        "drop",
        "leaf",
        "snowflake",
        "mountain.2",
        "globe",
        "circle.grid.cross",
        "hexagon",
        "triangle",
        "circle",
        "square",
        "asterisk",
        "number",
        "function",
        "waveform.path",
        "radiowaves.left",
        "gauge",
        "tortoise",
        "hare",
        "seal",
        "star",
        "heart",
        "bell"
    ]
}

struct TagColorPalette: View {
    let selection: TagColor
    let onSelect: (TagColor) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(TagColor.allCases) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(selection == color ? 0.9 : 0.4), lineWidth: selection == color ? 2 : 1)
                        )
                        .background(
                            Circle()
                                .fill(.thinMaterial)
                                .opacity(selection == color ? 0.5 : 0.2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.label)
            }
        }
    }
}

struct GlassDismissButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(glassBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var glassBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
        } else {
            Color.clear
                .background(.thinMaterial)
        }
    }
}
