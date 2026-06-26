import SwiftUI

#if os(macOS)
import SceneKit

struct CSymExperimentView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var input = "y = a x + b"
    @State private var aValue = 1.0
    @State private var bValue = 0.0
    @State private var gridOpacity = 1.0
    @State private var cameraNode: SCNNode
    @State private var scene: SCNScene
    @State private var status = ""

    init() {
        let cameraNode = PlotSceneFactory.makeCameraNode()
        let initialScene = PlotSceneFactory.makeInitialScene(
            isDark: false,
            gridOpacity: 1,
            pointOfView: cameraNode
        )
        _cameraNode = State(initialValue: cameraNode)
        _scene = State(initialValue: initialScene)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CSym Experiment")
                .font(.title2)
                .fontWeight(.semibold)

            Text("AmbientAtlas’ line-expression playground, transplanted into MorphoVu as a staging area for symbolic geometry work.")
                .foregroundStyle(.secondary)

            TextField("Line expression", text: $input)
                .textFieldStyle(.roundedBorder)
                .pythonTextInputTraits()

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("a = \(aValue.formatted(.number.precision(.fractionLength(2))))")
                    Slider(value: $aValue, in: -10...10, step: 0.1)
                }

                VStack(alignment: .leading) {
                    Text("b = \(bValue.formatted(.number.precision(.fractionLength(2))))")
                    Slider(value: $bValue, in: -10...10, step: 0.1)
                }
            }

            VStack(alignment: .leading) {
                Text("grid = \(Int((gridOpacity * 100).rounded()))%")
                Slider(value: $gridOpacity, in: 0...1, step: 0.01)
            }

            HStack {
                Button("Plot 3D") {
                    replot()
                }
                .keyboardShortcut(.defaultAction)

                Text(status)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            SceneView(
                scene: scene,
                pointOfView: cameraNode,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .frame(minWidth: 900, minHeight: 560)
            .background(sceneContainerBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 740)
        .onAppear {
            replot()
        }
        .onChange(of: aValue) { _, _ in
            replot()
        }
        .onChange(of: bValue) { _, _ in
            replot()
        }
        .onChange(of: gridOpacity) { _, _ in
            replot()
        }
        .onChange(of: colorScheme) { _, _ in
            replot()
        }
    }

    private func replot() {
        let isDark = colorScheme == .dark
        do {
            let model = try LineExpressionModel.parse(input)
            let plot = try model.sampleLine3D(a: aValue, b: bValue, xMin: -10, xMax: 10, sampleCount: 180)
            PlotSceneFactory.updateScene(
                scene,
                with: plot,
                isDark: isDark,
                gridOpacity: CGFloat(gridOpacity),
                pointOfView: cameraNode
            )
            status = statusText(for: plot)
        } catch {
            PlotSceneFactory.updateScene(
                scene,
                with: nil,
                isDark: isDark,
                gridOpacity: CGFloat(gridOpacity),
                pointOfView: cameraNode
            )
            status = "Error: \(error)"
        }
    }

    private var sceneContainerBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private func statusText(for plot: LinePlotData) -> String {
        if let derivative = plot.symbolicDerivative {
            let symbols = plot.freeSymbols.isEmpty ? "none" : plot.freeSymbols.joined(separator: ", ")
            return "\(plot.backend) | d/dx = \(derivative) | free: \(symbols)"
        }

        return String(
            format: "%@ | line: y = %.3fx + %.3f | points: %d",
            plot.backend,
            plot.estimatedSlope,
            plot.estimatedIntercept,
            plot.points.count
        )
    }
}

#elseif os(visionOS)

struct CSymExperimentView: View {
    @State private var input       = "y = \\sin(x)"
    @State private var aValue      = 1.0
    @State private var bValue      = 0.0
    @State private var gridOpacity = 1.0
    @State private var status      = ""
    @State private var parseError: String? = nil
    @State private var plotData: LinePlotData? = nil
    @State private var plotGeneration = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            controlPanel
                .frame(width: 290)
                .padding(20)
            Divider()
            CSymPlotView(
                plot: plotData,
                plotGeneration: plotGeneration,
                gridOpacity: Float(gridOpacity)
            )
        }
        .onAppear { replot() }
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CSym Experiment")
                .font(.title2.bold())
            Text("GPU-accelerated math on Metal · drag to orbit")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Expression  e.g. y = \\sin(x)", text: $input)
                .textFieldStyle(.roundedBorder)
                .pythonTextInputTraits()
                .onSubmit { replot() }

            paramSlider("a", value: $aValue, range: -10...10, step: 0.1)
            paramSlider("b", value: $bValue, range: -10...10, step: 0.1)
            paramSlider("grid", value: $gridOpacity, range: 0...1, step: 0.01)

            Button("Plot") { replot() }
                .keyboardShortcut(.defaultAction)

            Group {
                if let error = parseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                } else if !status.isEmpty {
                    Text(status)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func paramSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label) = \(value.wrappedValue, format: .number.precision(.fractionLength(2)))")
                .font(.system(.caption, design: .monospaced))
            // onEditingChanged fires once when the finger lifts, not on every tick.
            // This prevents flooding the GPU with hundreds of DrJit evaluations
            // while dragging and avoids memory pressure from rebuilding 400+ entities.
            Slider(value: value, in: range, step: step) { editing in
                if !editing { replot() }
            }
        }
    }

    // MARK: - Evaluation

    private func replot() {
        do {
            let model = try LineExpressionModel.parse(input)
            let data  = try model.sampleLine3D(
                a: aValue, b: bValue,
                xMin: -10, xMax: 10, sampleCount: 180
            )
            plotData   = data
            parseError = nil
            status     = statusText(for: data)
            plotGeneration += 1
        } catch {
            plotData   = nil
            parseError = error.localizedDescription
            status     = ""
            plotGeneration += 1
        }
    }

    private func statusText(for plot: LinePlotData) -> String {
        String(
            format: "%@ | y ≈ %.3fx + %.3f | %d pts",
            plot.backend,
            plot.estimatedSlope,
            plot.estimatedIntercept,
            plot.points.count
        )
    }
}

#else

struct CSymExperimentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CSym Experiment")
                .font(.title2.bold())
            Text("Available on macOS and visionOS.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}

#endif

#Preview {
    CSymExperimentView()
}
