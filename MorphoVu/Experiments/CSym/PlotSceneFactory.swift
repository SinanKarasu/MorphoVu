#if os(macOS)
import AppKit
import SceneKit
import simd

private typealias PlatformColor = NSColor

enum PlotSceneFactory {
    private static let axisRange: Float = 12
    private static let gridStep: Float = 1
    private static let lineLiftZ: Double = 3.5
    private static let groundZ: Double = 0
    private static let plotLineRadius: CGFloat = 0.07
    private static let shadowLineRadius: CGFloat = 0.045
    private static let axisLineRadius: CGFloat = 0.035
    private static let stemLineRadius: CGFloat = 0.02

    private struct ScenePalette {
        let background: PlatformColor
        let groundDiffuse: PlatformColor
        let groundEmission: PlatformColor
        let grid: PlatformColor
        let majorGridOpacity: CGFloat
        let minorGridOpacity: CGFloat
        let xAxis: PlatformColor
        let yAxis: PlatformColor
        let zAxis: PlatformColor
        let plotLine: PlatformColor
        let shadowLine: PlatformColor
        let stemLine: PlatformColor
    }

    static func makeInitialScene(
        isDark: Bool,
        gridOpacity: CGFloat = 1,
        pointOfView: SCNNode? = nil
    ) -> SCNScene {
        let palette = palette(isDark: isDark)
        let scene = SCNScene()
        scene.background.contents = palette.background
        configureCamera(in: scene, pointOfView: pointOfView)
        addGroundPlane(to: scene, palette: palette, planeOpacity: gridOpacity)
        addGrid(to: scene, palette: palette, gridOpacity: gridOpacity)
        addAxes(to: scene, palette: palette)
        return scene
    }

    static func makeScene(
        from plot: LinePlotData,
        isDark: Bool,
        gridOpacity: CGFloat = 1,
        pointOfView: SCNNode? = nil
    ) -> SCNScene {
        let palette = palette(isDark: isDark)
        let scene = SCNScene()
        scene.background.contents = palette.background
        configureCamera(in: scene, pointOfView: pointOfView)
        addGroundPlane(to: scene, palette: palette, planeOpacity: gridOpacity)
        addGrid(to: scene, palette: palette, gridOpacity: gridOpacity)
        addAxes(to: scene, palette: palette)

        let lifted = plot.points.map {
            PlotPointN(x: $0.x, y: $0.y, z: lineLiftZ, t: $0.t, w: $0.w)
        }
        let shadow = lifted.map {
            PlotPointN(x: $0.x, y: $0.y, z: groundZ, t: $0.t, w: $0.w)
        }

        addTubeLine(shadow, color: palette.shadowLine, to: scene, opacity: 0.75, radius: shadowLineRadius)
        addTubeLine(lifted, color: palette.plotLine, to: scene, opacity: 1, radius: plotLineRadius)
        addProjectionStems(lifted: lifted, shadow: shadow, to: scene, palette: palette)

        return scene
    }

    static func updateScene(
        _ scene: SCNScene,
        with plot: LinePlotData?,
        isDark: Bool,
        gridOpacity: CGFloat = 1,
        pointOfView: SCNNode
    ) {
        let sourceScene: SCNScene
        if let plot {
            sourceScene = makeScene(from: plot, isDark: isDark, gridOpacity: gridOpacity)
        } else {
            sourceScene = makeInitialScene(isDark: isDark, gridOpacity: gridOpacity)
        }

        scene.background.contents = sourceScene.background.contents
        attachCamera(pointOfView, to: scene)

        for node in scene.rootNode.childNodes where node !== pointOfView && node.camera == nil {
            node.removeFromParentNode()
        }

        for node in sourceScene.rootNode.childNodes where node.camera == nil {
            scene.rootNode.addChildNode(node)
        }
    }

    static func makeCameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 1000

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(14, 9, 24)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        return cameraNode
    }

    private static func configureCamera(in scene: SCNScene, pointOfView: SCNNode?) {
        if let pointOfView {
            attachCamera(pointOfView, to: scene)
            return
        }
        attachCamera(makeCameraNode(), to: scene)
    }

    private static func attachCamera(_ cameraNode: SCNNode, to scene: SCNScene) {
        if cameraNode.camera == nil {
            let camera = SCNCamera()
            camera.zNear = 0.1
            camera.zFar = 1000
            cameraNode.camera = camera
        }
        if cameraNode.parent === scene.rootNode {
            return
        }
        if cameraNode.parent != nil {
            cameraNode.removeFromParentNode()
        }
        scene.rootNode.addChildNode(cameraNode)
    }

    private static func addGroundPlane(to scene: SCNScene, palette: ScenePalette, planeOpacity: CGFloat) {
        let side = CGFloat(axisRange * 2)
        let plane = SCNPlane(width: side, height: side)
        let opacity = max(0, min(1, planeOpacity))
        let material = SCNMaterial()
        material.diffuse.contents = palette.groundDiffuse
        material.emission.contents = palette.groundEmission
        material.transparency = opacity
        material.isDoubleSided = true
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 0, groundZ)
        scene.rootNode.addChildNode(node)
    }

    private static func addGrid(to scene: SCNScene, palette: ScenePalette, gridOpacity: CGFloat) {
        let minV = -axisRange
        let maxV = axisRange
        let step = Int(gridStep)
        guard step > 0 else { return }
        let opacityScale = max(0, min(1, gridOpacity))

        for i in stride(from: Int(minV), through: Int(maxV), by: step) {
            let value = Double(i)

            let vertical = [
                PlotPointN(x: value, y: Double(minV), z: groundZ, t: 0, w: 1),
                PlotPointN(x: value, y: Double(maxV), z: groundZ, t: 0, w: 1)
            ]
            let horizontal = [
                PlotPointN(x: Double(minV), y: value, z: groundZ, t: 0, w: 1),
                PlotPointN(x: Double(maxV), y: value, z: groundZ, t: 0, w: 1)
            ]

            let opacity = (i == 0 ? palette.majorGridOpacity : palette.minorGridOpacity) * opacityScale
            addLine(vertical, color: palette.grid, to: scene, opacity: opacity)
            addLine(horizontal, color: palette.grid, to: scene, opacity: opacity)
        }
    }

    private static func addAxes(to scene: SCNScene, palette: ScenePalette) {
        let xAxis = [
            PlotPointN(x: -Double(axisRange), y: 0, z: 0, t: 0, w: 1),
            PlotPointN(x: Double(axisRange), y: 0, z: 0, t: 0, w: 1)
        ]
        let yAxis = [
            PlotPointN(x: 0, y: -Double(axisRange), z: 0, t: 0, w: 1),
            PlotPointN(x: 0, y: Double(axisRange), z: 0, t: 0, w: 1)
        ]
        let zAxis = [
            PlotPointN(x: 0, y: 0, z: -Double(axisRange), t: 0, w: 1),
            PlotPointN(x: 0, y: 0, z: Double(axisRange), t: 0, w: 1)
        ]

        addTubeLine(xAxis, color: palette.xAxis, to: scene, opacity: 1, radius: axisLineRadius)
        addTubeLine(yAxis, color: palette.yAxis, to: scene, opacity: 1, radius: axisLineRadius)
        addTubeLine(zAxis, color: palette.zAxis, to: scene, opacity: 1, radius: axisLineRadius)
    }

    private static func addProjectionStems(
        lifted: [PlotPointN],
        shadow: [PlotPointN],
        to scene: SCNScene,
        palette: ScenePalette
    ) {
        let count = min(lifted.count, shadow.count)
        guard count >= 2 else { return }

        for index in stride(from: 0, to: count, by: 12) {
            let segment = [shadow[index], lifted[index]]
            addTubeLine(segment, color: palette.stemLine, to: scene, opacity: 0.45, radius: stemLineRadius)
        }
    }

    private static func addLine(_ points: [PlotPointN], color: PlatformColor, to scene: SCNScene, opacity: CGFloat) {
        guard points.count >= 2 else { return }

        let vectors = points.map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: vectors)

        var indices: [UInt32] = []
        indices.reserveCapacity((vectors.count - 1) * 2)
        for i in 0..<(vectors.count - 1) {
            indices.append(UInt32(i))
            indices.append(UInt32(i + 1))
        }

        let data = indices.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }

        let element = SCNGeometryElement(
            data: data,
            primitiveType: .line,
            primitiveCount: indices.count / 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.transparency = opacity
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
    }

    private static func addTubeLine(
        _ points: [PlotPointN],
        color: PlatformColor,
        to scene: SCNScene,
        opacity: CGFloat,
        radius: CGFloat
    ) {
        guard points.count >= 2 else { return }

        for i in 0..<(points.count - 1) {
            let start = SIMD3<Float>(Float(points[i].x), Float(points[i].y), Float(points[i].z))
            let end = SIMD3<Float>(Float(points[i + 1].x), Float(points[i + 1].y), Float(points[i + 1].z))
            let delta = end - start
            let length = simd_length(delta)
            if length <= 1e-6 { continue }

            let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color
            material.transparency = opacity
            material.lightingModel = .constant
            cylinder.materials = [material]

            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (start + end) * 0.5
            node.simdOrientation = orientationFromYAxis(to: delta)
            scene.rootNode.addChildNode(node)
        }
    }

    private static func orientationFromYAxis(to direction: SIMD3<Float>) -> simd_quatf {
        let up = SIMD3<Float>(0, 1, 0)
        let unit = simd_normalize(direction)
        let dot = simd_dot(up, unit)

        if dot > 0.9999 {
            return simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
        }
        if dot < -0.9999 {
            return simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }

        let axis = simd_normalize(simd_cross(up, unit))
        let angle = acos(max(-1, min(1, dot)))
        return simd_quatf(angle: angle, axis: axis)
    }

    private static func palette(isDark: Bool) -> ScenePalette {
        if isDark {
            return ScenePalette(
                background: grayscaleColor(0.08, alpha: 1),
                groundDiffuse: PlatformColor.white.withAlphaComponent(0.07),
                groundEmission: PlatformColor.white.withAlphaComponent(0.02),
                grid: grayscaleColor(0.84, alpha: 1),
                majorGridOpacity: 0.30,
                minorGridOpacity: 0.14,
                xAxis: .systemRed,
                yAxis: .systemGreen,
                zAxis: .systemBlue,
                plotLine: .systemOrange,
                shadowLine: .systemGray,
                stemLine: .systemGray
            )
        }

        return ScenePalette(
            background: grayscaleColor(0.95, alpha: 1),
            groundDiffuse: PlatformColor.white.withAlphaComponent(0.25),
            groundEmission: PlatformColor.white.withAlphaComponent(0.03),
            grid: grayscaleColor(0.60, alpha: 1),
            majorGridOpacity: 0.28,
            minorGridOpacity: 0.14,
            xAxis: .systemRed,
            yAxis: .systemGreen,
            zAxis: .systemBlue,
            plotLine: .systemOrange,
            shadowLine: .systemGray,
            stemLine: .systemGray
        )
    }

    private static func grayscaleColor(_ white: CGFloat, alpha: CGFloat) -> PlatformColor {
        return PlatformColor(calibratedWhite: white, alpha: alpha)
    }
}
#endif
