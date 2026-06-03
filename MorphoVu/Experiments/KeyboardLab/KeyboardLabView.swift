import SwiftUI

private enum KeyPresentationMode: String, CaseIterable, Identifiable {
    case symbol
    case stacked
    case physical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbol:
            "Symbol"
        case .stacked:
            "Stacked"
        case .physical:
            "Physical"
        }
    }
}

struct KeyboardLabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = MathKeyboardStore()
    @State private var selectedLayerID = "option"
    @State private var query = ""
    @State private var keyScale = 1.16
    @State private var presentationMode: KeyPresentationMode = .stacked
    @State private var showDeadKeys = true
    @State private var emphasizeDeadKeys = true

    private var palette: LabTheme.Palette {
        LabTheme.palette(for: colorScheme)
    }

    var body: some View {
        Group {
            if let layout = store.layout {
                keyboardLab(layout)
                    .onAppear {
                        if layout.layers.contains(where: { $0.id == selectedLayerID }) == false {
                            selectedLayerID = layout.defaultLayerID
                        }
                    }
            } else if let errorMessage = store.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 42))
                        .foregroundStyle(palette.accent)
                    Text("Keyboard Lab Unavailable")
                        .font(.title2.bold())
                    Text(errorMessage)
                        .foregroundStyle(palette.secondaryInk)
                        .multilineTextAlignment(.center)
                    Button("Reload Layout") {
                        store.load()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
                .padding(32)
                .foregroundStyle(palette.ink)
            } else {
                ProgressView("Loading MathUnicode layout...")
                    .padding(32)
                    .tint(palette.accent)
            }
        }
    }

    private func keyboardLab(_ layout: MathKeyboardLayout) -> some View {
        let currentLayer = layout.layers.first(where: { $0.id == selectedLayerID }) ?? layout.layers[0]
        let visibleSymbols = symbols(for: currentLayer)

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(layout)
                controls(layout)
                symbolShelf(symbols: visibleSymbols)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        keyboardCard(layer: currentLayer)
                        if showDeadKeys {
                            deadKeysCard(layout.deadKeys)
                                .frame(maxWidth: 340)
                        }
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        keyboardCard(layer: currentLayer)
                        if showDeadKeys {
                            deadKeysCard(layout.deadKeys)
                        }
                    }
                }
            }
            .padding(24)
        }
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .background(
            LinearGradient(
                colors: [
                    palette.shellStart,
                    palette.shellEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func header(_ layout: MathKeyboardLayout) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image("MathUnicodeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(layout.name) Lab")
                    .font(.largeTitle.bold())

                Text("A SwiftUI playground for trying keyboard geometry and modifier layers before you lock in a VisionOS layout.")
                    .foregroundStyle(palette.secondaryInk)

                Text("Start with the published MathUnicode layout, then use this as a staging point for a VisionOS-first design.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryInk)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(palette.panelStroke, lineWidth: 1)
        )
        .shadow(color: palette.softShadow, radius: 14, y: 8)
    }

    private func controls(_ layout: MathKeyboardLayout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Controls")
                .font(.title3.bold())

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    layerPicker(layout)
                    presentationControls
                    searchControls
                }

                VStack(alignment: .leading, spacing: 16) {
                    layerPicker(layout)
                    presentationControls
                    searchControls
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.panelTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.panelTintStroke, lineWidth: 1)
        )
        .shadow(color: palette.softShadow, radius: 12, y: 6)
    }

    private func layerPicker(_ layout: MathKeyboardLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Layer")
                .font(.headline)
            Picker("Layer", selection: $selectedLayerID) {
                ForEach(layout.layers) { layer in
                    Text(layer.title).tag(layer.id)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
        }
    }

    private var presentationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presentation")
                .font(.headline)

            Picker("Mode", selection: $presentationMode) {
                ForEach(KeyPresentationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Key Scale")
                Slider(value: $keyScale, in: 0.82...1.4)
                Text("\(keyScale, format: .number.precision(.fractionLength(2)))x")
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryInk)
                    .frame(width: 52, alignment: .trailing)
            }

            Toggle("Show dead-key notes", isOn: $showDeadKeys)
            Toggle("Emphasize dead keys on the board", isOn: $emphasizeDeadKeys)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter")
                .font(.headline)
            TextField("Search symbol or physical key", text: $query)
                .pythonTextInputTraits()
                .textFieldStyle(.roundedBorder)

            Text("Search keeps the keyboard shape intact and just dims non-matching keys.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryInk)
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func symbolShelf(symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Layer Snapshot")
                .font(.title3.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(symbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(palette.accentStrong)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(palette.accentSoft)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(palette.panelStroke, lineWidth: 1)
                            )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.panelTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.panelTintStroke, lineWidth: 1)
        )
        .shadow(color: palette.softShadow, radius: 12, y: 6)
    }

    private func keyboardCard(layer: MathKeyboardLayer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(layer.title)
                .font(.title3.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(layer.rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                                KeyTileView(
                                    key: key,
                                    scale: keyScale,
                                    presentationMode: presentationMode,
                                    highlightDeadKeys: emphasizeDeadKeys,
                                    matchesQuery: keyMatchesQuery(key)
                                )
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(palette.panelStroke, lineWidth: 1)
        )
        .shadow(color: palette.softShadow, radius: 14, y: 8)
    }

    private func deadKeysCard(_ deadKeys: [MathDeadKey]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dead Keys")
                .font(.title3.bold())

            ForEach(deadKeys) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(item.shortcut)
                            .font(.headline)
                        Text(item.display)
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(palette.accentSoft)
                            )
                    }

                    Text(item.description)
                        .foregroundStyle(palette.secondaryInk)

                    if item.examples.isEmpty == false {
                        Text(item.examples)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(palette.panelElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(palette.panelStroke, lineWidth: 1)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.panelTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.panelTintStroke, lineWidth: 1)
        )
        .shadow(color: palette.softShadow, radius: 12, y: 6)
    }

    private func symbols(for layer: MathKeyboardLayer) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        for row in layer.rows {
            for key in row {
                guard key.isFixed == false else { continue }
                guard let output = key.output, output.isEmpty == false else { continue }
                guard output.count <= 2 else { continue }
                guard seen.insert(output).inserted else { continue }
                ordered.append(output)
            }
        }

        return ordered
    }

    private func keyMatchesQuery(_ key: MathKeyboardKey) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return true
        }

        let haystack = [
            key.label,
            key.defaultLegend,
            key.shiftLegend,
            key.output,
            key.note,
            key.deadState
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return haystack.contains(trimmed.lowercased())
    }
}

private struct KeyTileView: View {
    @Environment(\.colorScheme) private var colorScheme
    let key: MathKeyboardKey
    let scale: Double
    let presentationMode: KeyPresentationMode
    let highlightDeadKeys: Bool
    let matchesQuery: Bool

    private var palette: LabTheme.Palette {
        LabTheme.palette(for: colorScheme)
    }

    var body: some View {
        Group {
            if key.isFixed {
                fixedKey
            } else {
                mappedKey
            }
        }
        .opacity(matchesQuery ? 1.0 : 0.28)
        .animation(.easeInOut(duration: 0.15), value: matchesQuery)
    }

    private var fixedKey: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(palette.fixedKeyFill)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.fixedKeyStroke, lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                Text(key.label ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .padding(12)
            }
            .shadow(color: palette.softShadow.opacity(0.7), radius: 6, y: 3)
            .frame(
                width: 64 * key.width * scale,
                height: 72 * scale
            )
    }

    private var mappedKey: some View {
        let deadKeyAccent = highlightDeadKeys && key.isDeadKey
        let fillColor = deadKeyAccent ? palette.deadKeyFill : palette.keyFill
        let borderColor = deadKeyAccent ? palette.deadKeyBorder : palette.keyBorder

        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: deadKeyAccent ? 1.6 : 1)
            )
            .overlay(alignment: .topLeading) {
                if presentationMode != .symbol {
                    Text(key.defaultLegend ?? "")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryInk)
                        .padding(10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if presentationMode == .stacked {
                    Text(key.shiftLegend ?? "")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryInk)
                        .padding(10)
                }
            }
            .overlay {
                VStack(spacing: 4) {
                    Text(centerText)
                        .font(centerFont)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.ink)
                        .minimumScaleFactor(0.55)
                    if presentationMode == .physical {
                        Text(key.shiftLegend ?? "")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
                .padding(.horizontal, 8)
            }
            .overlay(alignment: .bottomLeading) {
                if let note = key.note, note.isEmpty == false {
                    Text(note.uppercased())
                        .font(.caption2)
                        .foregroundStyle(deadKeyAccent ? palette.accentStrong : palette.secondaryInk)
                        .padding(10)
                }
            }
            .shadow(color: palette.softShadow.opacity(0.7), radius: 6, y: 3)
            .frame(
                width: 64 * key.width * scale,
                height: 72 * scale
            )
    }

    private var centerText: String {
        switch presentationMode {
        case .symbol, .stacked:
            key.output ?? ""
        case .physical:
            key.defaultLegend ?? ""
        }
    }

    private var centerFont: Font {
        let size = CGFloat(scale)
        switch presentationMode {
        case .symbol:
            return Font.system(size: 24 * size, weight: .bold, design: .rounded)
        case .stacked:
            return Font.system(size: 22 * size, weight: .bold, design: .rounded)
        case .physical:
            return Font.system(size: 17 * size, weight: .bold, design: .rounded)
        }
    }
}

#Preview {
    KeyboardLabView()
}
