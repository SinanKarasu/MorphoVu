import Observation
import ManifoldKit
import SwiftUI
import simd

enum MorphoPresetGroup: String, CaseIterable, Identifiable, Codable, Sendable {
    case primitives
    case csg

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .primitives:
            return "Primitives"
        case .csg:
            return "CSG Presets"
        }
    }
}

enum MorphoPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case sphere
    case cube
    case cylinder
    case cone
    case torus
    case sphereMinusCube
    case twinSpheres
    case sphereCubeIntersection

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .sphere:
            return "Sphere"
        case .cube:
            return "Cube"
        case .cylinder:
            return "Cylinder"
        case .cone:
            return "Cone"
        case .torus:
            return "Torus"
        case .sphereMinusCube:
            return "Sphere - Cube"
        case .twinSpheres:
            return "Twin Spheres"
        case .sphereCubeIntersection:
            return "Sphere Intersect Cube"
        }
    }

    nonisolated var summary: String {
        switch self {
        case .sphere:
            return "High-resolution sphere for baseline shading and navigation."
        case .cube:
            return "Simple box primitive to sanity-check axes and lighting."
        case .cylinder:
            return "Round wall shape useful for testing smooth normals."
        case .cone:
            return "Single-tip primitive for sharper lighting transitions."
        case .torus:
            return "Closed ring with richer curvature than the basic primitives."
        case .sphereMinusCube:
            return "Difference example showing a boolean cut through a sphere."
        case .twinSpheres:
            return "Union example with overlapping curved solids."
        case .sphereCubeIntersection:
            return "Intersection example with a compact combined volume."
        }
    }

    nonisolated var symbolName: String {
        switch self {
        case .sphere:
            return "circle.fill"
        case .cube:
            return "cube.fill"
        case .cylinder:
            return "cylinder.fill"
        case .cone:
            return "pyramid.fill"
        case .torus:
            return "circle.dotted"
        case .sphereMinusCube:
            return "minus.circle"
        case .twinSpheres:
            return "plus.circle"
        case .sphereCubeIntersection:
            return "scope"
        }
    }

    nonisolated var group: MorphoPresetGroup {
        switch self {
        case .sphere, .cube, .cylinder, .cone, .torus:
            return .primitives
        case .sphereMinusCube, .twinSpheres, .sphereCubeIntersection:
            return .csg
        }
    }

    nonisolated func makeSolid() -> Solid {
        switch self {
        case .sphere:
            return .sphere(radius: 1.0, segments: 64)
        case .cube:
            return .cube(size: SIMD3(1.4, 1.4, 1.4))
        case .cylinder:
            return .cylinder(height: 1.7, radius: 0.72, segments: 64)
        case .cone:
            return .cone(height: 1.7, radius: 0.82, segments: 64)
        case .torus:
            return .torus(majorRadius: 1.0, minorRadius: 0.32, toroidalSegments: 72, poloidalSegments: 24)
        case .sphereMinusCube:
            return .sphereWithCube
        case .twinSpheres:
            return .twinSpheres
        case .sphereCubeIntersection:
            return .sphereCubeIntersection
        }
    }
}

@MainActor
@Observable
final class MorphoWorkbenchState {
    var selectedPreset: MorphoPreset = .sphere {
        didSet {
            rebuildShape()
        }
    }

    private(set) var solid: Solid = .sphere()
    private(set) var meshData: MeshData?
    private(set) var isBuilding = false
    private(set) var buildRevision = 0
    private(set) var lastError: String?

    init() {
        rebuildShape()
    }

    var geometryEnvelope: MorphoGeometryEnvelope {
        MorphoGeometryEnvelope(
            preset: selectedPreset,
            meshRevision: buildRevision,
            vertexCount: solid.vertexCount,
            triangleCount: solid.triangleCount,
            isValid: solid.isValid,
            volume: solid.volume,
            surfaceArea: solid.surfaceArea
        )
    }

    var contractText: String {
        MorphoJSON.prettyString(geometryEnvelope)
    }

    var groupedPresets: [(MorphoPresetGroup, [MorphoPreset])] {
        MorphoPresetGroup.allCases.map { group in
            (group, MorphoPreset.allCases.filter { $0.group == group })
        }
    }

    func rebuildShape() {
        isBuilding = true
        lastError = nil

        let preset = selectedPreset
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                let solid = preset.makeSolid()
                let mesh = solid.meshData()
                return (solid, mesh)
            }.value

            guard let self else { return }
            solid = result.0
            meshData = result.1
            buildRevision += 1
            isBuilding = false

            if result.1 == nil {
                lastError = "Mesh extraction returned no data for \(preset.title)."
            }
        }
    }
}
