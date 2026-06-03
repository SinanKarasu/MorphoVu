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

#else

struct CSymExperimentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CSym Experiment")
                .font(.title2.bold())

            Text("The AmbientAtlas SceneKit experiment is available on macOS first. The view is parked here so the tab structure is ready while we decide how to port it to the spatial renderer.")
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
