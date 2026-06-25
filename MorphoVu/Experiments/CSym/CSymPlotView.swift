// CSymPlotView.swift
// ─────────────────────────────────────────────────────────────────────────────
// RealityKit 3D plot for the CSym experiment (visionOS).
//
// Mirrors the geometry produced by PlotSceneFactory on macOS:
//   • X (red), Y (green), Z (blue) axes as cylinders
//   • Grid on the Z = 0 plane
//   • Plot line lifted to Z = lineLiftZ, shadow at Z = 0, stem connectors
//
// All scene geometry is in "scene units" (-12 … +12 on X/Y).  The entire
// pivotEntity is scaled by sceneScale so it fits comfortably in a visionOS
// window (~0.6 m across).  Orbit is done by rotating pivotEntity around its
// own Z (up) and X (tilt) axes in response to a drag gesture.
// ─────────────────────────────────────────────────────────────────────────────

#if os(visionOS)
import RealityKit
import SwiftUI
import simd

struct CSymPlotView: View {
    let plot: LinePlotData?
    let gridOpacity: Float

    // Orbit state
    @State private var yaw: Float = 0.5
    @State private var pitch: Float = 0.42
    @State private var dragAnchorYaw: Float = 0
    @State private var dragAnchorPitch: Float = 0
    @State private var isDragging = false

    // Entities (created once, content swapped on change)
    @State private var pivotEntity = Entity()
    @State private var baseEntity  = Entity()   // axes + grid
    @State private var plotEntity  = Entity()   // orange line + shadow + stems

    // Dirty flags — revision counters are @State (trigger update:); rendered
    // tracking uses a reference type so mutations don't cause a second re-render.
    @State private var baseRevision: Int = 0
    @State private var plotRevision: Int = 0
    @State private var rendered = _RenderRevisions()

    // ── Scene constants (scene-space units; applied before sceneScale) ────────
    private static let sceneScale: Float  = 0.025    // 1 scene unit → 25 mm
    private static let axisRange: Float   = 12
    private static let lineLiftZ: Float   = 3.5      // plot line elevation
    private static let plotRadius: Float  = 0.18
    private static let shadowRadius: Float = 0.11
    private static let axisRadius: Float  = 0.13
    private static let stemRadius: Float  = 0.08
    private static let gridRadius: Float  = 0.055

    var body: some View {
        RealityView { content in
            pivotEntity.scale = SIMD3(repeating: Self.sceneScale)
            pivotEntity.addChild(baseEntity)
            pivotEntity.addChild(plotEntity)
            content.add(pivotEntity)
            content.add(makeLights())
            syncCamera()
        } update: { _ in
            // Use rendered (class) so mutations here don't schedule another update.
            if rendered.base != baseRevision {
                rendered.base = baseRevision
                rebuildBase()
            }
            if rendered.plot != plotRevision {
                rendered.plot = plotRevision
                rebuildPlot()
            }
        }
        // On visionOS the RealityKit input system consumes touches before SwiftUI
        // gestures see them. A Color.clear overlay with an explicit contentShape
        // sits above the 3D content and reliably captures the drag for orbit.
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if !isDragging {
                                dragAnchorYaw   = yaw
                                dragAnchorPitch = pitch
                                isDragging      = true
                            }
                            yaw   = dragAnchorYaw + Float(value.translation.width)  * 0.008
                            pitch = clampf(
                                dragAnchorPitch + Float(value.translation.height) * 0.008,
                                lo: -Float.pi / 2 + 0.08,
                                hi:  Float.pi / 2 - 0.08
                            )
                            syncCamera()
                        }
                        .onEnded { _ in isDragging = false }
                )
        }
        .onAppear {
            baseRevision = 1
            plotRevision = 1
        }
        .onChange(of: gridOpacity) { _, _ in baseRevision += 1 }
        .onChange(of: plot?.points.count) { _, _ in plotRevision += 1 }
    }

    // MARK: - Camera

    private func syncCamera() {
        // Orbit: yaw around scene Z (up axis), pitch around X (tilt)
        let rotZ = simd_quatf(angle: yaw,   axis: SIMD3<Float>(0, 0, 1))
        let rotX = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        pivotEntity.orientation = rotZ * rotX
    }

    // MARK: - Base scene (axes + grid) ─────────────────────────────────────────

    private func rebuildBase() {
        removeChildren(of: baseEntity)

        let r = Self.axisRange

        // Axes
        addTube(from3: (-r, 0, 0), to3: (r, 0, 0),   color: .systemRed,   radius: Self.axisRadius, parent: baseEntity)
        addTube(from3: (0, -r, 0), to3: (0, r, 0),   color: .systemGreen, radius: Self.axisRadius, parent: baseEntity)
        addTube(from3: (0, 0, -r), to3: (0, 0, r),   color: .systemBlue,  radius: Self.axisRadius, parent: baseEntity)

        // Grid at Z = 0
        let majorAlpha = CGFloat(0.30 * gridOpacity)
        let minorAlpha = CGFloat(0.14 * gridOpacity)
        guard majorAlpha > 0.01 else { return }

        for i in Int(-r)...Int(r) {
            let v = Float(i)
            let alpha = (i == 0) ? majorAlpha : minorAlpha
            guard alpha > 0.01 else { continue }
            let c = UIColor.white.withAlphaComponent(alpha)
            // Lines parallel to Y (vertical in top-down view)
            addTube(from3: (v, -r, 0), to3: (v, r, 0), color: c, radius: Self.gridRadius, parent: baseEntity)
            // Lines parallel to X (horizontal in top-down view)
            addTube(from3: (-r, v, 0), to3: (r, v, 0), color: c, radius: Self.gridRadius, parent: baseEntity)
        }
    }

    // MARK: - Plot line (rebuilt when plot changes) ────────────────────────────

    private func rebuildPlot() {
        removeChildren(of: plotEntity)
        guard let plot, !plot.points.isEmpty else { return }

        let pts = plot.points
        let liftZ   = Self.lineLiftZ
        let groundZ: Float = 0

        let lifted = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), liftZ) }
        let shadow = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), groundZ) }

        // Shadow line (gray, ground projection)
        for i in 0..<(shadow.count - 1) {
            addTube(from: shadow[i], to: shadow[i + 1],
                    color: UIColor.systemGray.withAlphaComponent(0.55),
                    radius: Self.shadowRadius, parent: plotEntity)
        }

        // Plot line (orange, lifted)
        for i in 0..<(lifted.count - 1) {
            addTube(from: lifted[i], to: lifted[i + 1],
                    color: .systemOrange,
                    radius: Self.plotRadius, parent: plotEntity)
        }

        // Vertical stems every 12 samples
        for i in stride(from: 0, to: pts.count, by: 12) {
            addTube(from: shadow[i], to: lifted[i],
                    color: UIColor.systemGray.withAlphaComponent(0.35),
                    radius: Self.stemRadius, parent: plotEntity)
        }
    }

    // MARK: - Geometry helpers ─────────────────────────────────────────────────

    /// Convenience overload using a tuple so call sites stay concise.
    private func addTube(
        from3 a: (Float, Float, Float),
        to3   b: (Float, Float, Float),
        color: UIColor,
        radius: Float,
        parent: Entity
    ) {
        addTube(
            from: SIMD3<Float>(a.0, a.1, a.2),
            to:   SIMD3<Float>(b.0, b.1, b.2),
            color: color, radius: radius, parent: parent
        )
    }

    private func addTube(
        from start: SIMD3<Float>,
        to   end:   SIMD3<Float>,
        color:  UIColor,
        radius: Float,
        parent: Entity
    ) {
        let delta  = end - start
        let length = simd_length(delta)
        guard length > 1e-6 else { return }

        let mesh = MeshResource.generateCylinder(height: length, radius: radius)
        var mat  = UnlitMaterial()
        mat.color = .init(tint: color)

        let entity = ModelEntity(mesh: mesh, materials: [mat])
        entity.position    = (start + end) * 0.5
        entity.orientation = quaternionFromY(to: delta / length)
        parent.addChild(entity)
    }

    /// Quaternion that rotates the RealityKit +Y axis to point along `unit`.
    private func quaternionFromY(to unit: SIMD3<Float>) -> simd_quatf {
        let up = SIMD3<Float>(0, 1, 0)
        let d  = simd_dot(up, unit)
        if d >  0.9999 { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
        if d < -0.9999 { return simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)) }
        let axis = simd_normalize(simd_cross(up, unit))
        return simd_quatf(angle: acos(max(-1, min(1, d))), axis: axis)
    }

    private func removeChildren(of entity: Entity) {
        let children = Array(entity.children)
        children.forEach { $0.removeFromParent() }
    }

    // MARK: - Lighting ─────────────────────────────────────────────────────────

    private func makeLights() -> Entity {
        let container = Entity()

        func add(intensity: Float, color: UIColor, from pos: SIMD3<Float>) {
            let e = Entity()
            var c = DirectionalLightComponent()
            c.intensity = intensity
            c.color     = color
            e.components.set(c)
            e.look(at: .zero, from: pos, relativeTo: nil)
            container.addChild(e)
        }

        add(intensity: 3500, color: .white,
            from: SIMD3( 3,  5,  4))
        add(intensity: 550,  color: UIColor(red: 0.72, green: 0.82, blue: 1.0, alpha: 1),
            from: SIMD3(-2, -1, -3))
        add(intensity: 700,  color: UIColor(red: 1.0,  green: 0.90, blue: 0.75, alpha: 1),
            from: SIMD3(-3,  2,  3))

        return container
    }
}

// MARK: - Helpers

private func clampf(_ x: Float, lo: Float, hi: Float) -> Float {
    max(lo, min(hi, x))
}

/// Reference-type revision tracker stored in @State.
/// Mutating its properties does NOT trigger a SwiftUI re-render because
/// the @State value (the reference itself) never changes.
private final class _RenderRevisions {
    var base: Int = -1
    var plot: Int = -1
}

#endif
