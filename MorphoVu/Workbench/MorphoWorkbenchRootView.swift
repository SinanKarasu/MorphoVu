import SwiftUI
import ManifoldKit

struct MorphoWorkbenchRootView: View {
    @Environment(MorphoWorkbenchState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
#if os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif

    var body: some View {
#if os(macOS)
        macOSLayout
#else
        visionOSLayout
#endif
    }

    private var palette: MorphoTheme.Palette {
        MorphoTheme.palette(for: colorScheme)
    }

#if os(macOS)
    private var macOSLayout: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)

            VStack(spacing: 18) {
                scenePanel
                bottomPanelRow
            }
            .frame(minWidth: 640)
        }
        .padding(18)
        .background(shellBackground)
    }

    private var bottomPanelRow: some View {
        HStack(alignment: .top, spacing: 18) {
            statsPanel
                .frame(maxWidth: 320)
            structurePanel
        }
    }
#endif

    private var visionOSLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                sceneLaunchPanel
                presetPanel
                statsPanel
                structurePanel
            }
            .padding(20)
        }
        .background(shellBackground)
    }

    private var shellBackground: some View {
        LinearGradient(
            colors: [palette.shellTop, palette.shellBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MorphoVu Workbench")
                .font(.largeTitle.bold())
            Text("A clean scene host for manifold geometry now, with room for a later runtime bridge from PyDE-style tooling.")
                .foregroundStyle(palette.secondaryInk)
            Text("The geometry engine now lives inside MorphoVu, and the render path is intentionally closer to ManifoldWorkbench than the old embedded PyDE card preview.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(panelBackground)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerCard
            presetPanel
        }
    }

    private var presetPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shapes")
                .font(.title3.bold())

            List(selection: selectedPresetBinding) {
                ForEach(state.groupedPresets, id: \.0.id) { group, presets in
                    Section(group.title) {
                        ForEach(presets, id: \.id) { preset in
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.title)
                                    Text(preset.summary)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryInk)
                                }
                                .padding(.vertical, 4)
                            } icon: {
                                Image(systemName: preset.symbolName)
                            }
                            .tag(preset)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .padding(20)
        .background(panelTintBackground)
    }

    private var scenePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(state.selectedPreset.title) Scene")
                        .font(.title3.bold())
                    Text("Drag to orbit and use the mouse wheel to zoom.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryInk)
                }

                Spacer()

                buildStatusBadge
            }

            MorphoSceneRenderView(state: state)
                .frame(minHeight: 520)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(22)
        .background(panelBackground)
    }

    private var sceneLaunchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scene Window")
                .font(.title3.bold())
            Text("On visionOS, keep the controls flat and the geometry in its own dedicated volumetric window.")
                .foregroundStyle(palette.secondaryInk)

#if os(visionOS)
            Button {
                openWindow(id: MorphoSceneWindowID.scene3D)
            } label: {
                Label("Open 3-D Scene", systemImage: "visionpro")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MorphoTheme.accent)
#else
            Text("The shared scene window is only used on visionOS. On macOS the scene stays docked in the workbench.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryInk)
#endif
        }
        .padding(20)
        .background(panelBackground)
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mesh Stats")
                .font(.title3.bold())

            statRow("Preset", value: state.selectedPreset.title)
            statRow("Vertices", value: "\(state.solid.vertexCount)")
            statRow("Triangles", value: "\(state.solid.triangleCount)")
            statRow("Volume", value: String(format: "%.4f", state.solid.volume))
            statRow("Surface", value: String(format: "%.4f", state.solid.surfaceArea))
            statRow("Valid", value: state.solid.isValid ? "Yes" : "No")
            statRow("Revision", value: "\(state.buildRevision)")

            if let lastError = state.lastError {
                Divider()
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(panelBackground)
    }

    private var structurePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shared Structure")
                .font(.title3.bold())
            Text("This is the seed contract for future runtime integration: a stable shape/preset/mesh summary that MorphoVu can later accept from Python or another authoring layer.")
                .foregroundStyle(palette.secondaryInk)

            ScrollView {
                Text(state.contractText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(palette.outputInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .frame(minHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.outputPanel)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(panelBackground)
    }

    private var buildStatusBadge: some View {
        Text(state.isBuilding ? "Building" : "Ready")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(state.isBuilding ? Color.orange : MorphoTheme.accent)
            )
    }

    private var selectedPresetBinding: Binding<MorphoPreset?> {
        Binding(
            get: { state.selectedPreset },
            set: { newValue in
                if let newValue {
                    state.selectedPreset = newValue
                }
            }
        )
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(palette.secondaryInk)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(palette.ink)
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(palette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(palette.panelStroke, lineWidth: 1)
            )
            .shadow(color: palette.shadow, radius: 14, y: 8)
    }

    private var panelTintBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(palette.panelTint)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(palette.panelTintStroke, lineWidth: 1)
            )
            .shadow(color: palette.shadow, radius: 10, y: 5)
    }
}

#if os(visionOS)
struct MorphoSceneWindowView: View {
    @Environment(MorphoWorkbenchState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(state.selectedPreset.title)
                    .font(.headline)
                Spacer()
                Text("\(state.solid.triangleCount) tris")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            MorphoSceneRenderView(state: state, showsProgress: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(12)
    }
}
#endif
