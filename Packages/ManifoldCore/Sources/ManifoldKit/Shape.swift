// Shape.swift – ManifoldKit
// ─────────────────────────────────────────────────────────────────────────────
// Idiomatic Swift wrapper around the C++ ManifoldShape.
//
// Because this target has .interoperabilityMode(.Cxx) in Package.swift, the
// compiler can see ManifoldBridge's C++ types directly.  Solid just adds:
//   • Swift-style argument labels and default parameters
//   • SIMD types at the boundary
//   • @discardableResult transform chaining
//
// Named "Solid" (not "Shape") to avoid ambiguity with SwiftUI.Shape.
// ─────────────────────────────────────────────────────────────────────────────

import ManifoldBridge
import simd

// ─── Solid ────────────────────────────────────────────────────────────────────

/// A water-tight solid geometry, computed by Manifold.
///
/// `Solid` is a value type – copies are cheap (shared reference to the
/// underlying C++ object).  All operations return a *new* Solid.
public struct Solid: @unchecked Sendable {

    // The underlying C++ object (imported via C++ interop)
    internal let native: ManifoldShape

    internal init(_ native: ManifoldShape) {
        self.native = native
    }

    // ── Primitives ────────────────────────────────────────────────────────

    public static func sphere(radius: Float = 1.0, segments: Int = 32) -> Solid {
        Solid(ManifoldShape.makeSphere(radius, Int32(segments)))
    }

    public static func cube(size: SIMD3<Float> = .one, centered: Bool = true) -> Solid {
        Solid(ManifoldShape.makeCube(size.x, size.y, size.z, centered))
    }

    public static func cylinder(
        height: Float = 1.0,
        radius: Float = 0.5,
        segments: Int = 32,
        center: Bool = false
    ) -> Solid {
        Solid(ManifoldShape.makeCylinder(height, radius, -1.0, Int32(segments), center))
    }

    public static func cone(
        height: Float = 1.0,
        radius: Float = 0.5,
        segments: Int = 32
    ) -> Solid {
        Solid(ManifoldShape.makeCone(height, radius, Int32(segments)))
    }

    public static func torus(
        majorRadius: Float = 1.0,
        minorRadius: Float = 0.3,
        toroidalSegments: Int = 64,
        poloidalSegments: Int = 16
    ) -> Solid {
        Solid(ManifoldShape.makeTorus(
            majorRadius, minorRadius,
            Int32(toroidalSegments), Int32(poloidalSegments)
        ))
    }

    // ── Boolean CSG ───────────────────────────────────────────────────────

    /// Union – A ∪ B
    public func union(with other: Solid) -> Solid {
        Solid(native.add(other.native))
    }

    /// Difference – A − B
    public func difference(from other: Solid) -> Solid {
        Solid(native.subtract(other.native))
    }

    /// Intersection – A ∩ B
    public func intersection(with other: Solid) -> Solid {
        Solid(native.intersect(other.native))
    }

    // ── Transforms ────────────────────────────────────────────────────────

    @discardableResult
    public func translated(by v: SIMD3<Float>) -> Solid {
        Solid(native.translate(v.x, v.y, v.z))
    }

    @discardableResult
    public func scaled(by v: SIMD3<Float>) -> Solid {
        Solid(native.scale(v.x, v.y, v.z))
    }

    @discardableResult
    public func scaled(uniformly s: Float) -> Solid {
        Solid(native.scale(s, s, s))
    }

    @discardableResult
    public func rotated(x xDeg: Float = 0, y yDeg: Float = 0, z zDeg: Float = 0) -> Solid {
        Solid(native.rotate(xDeg, yDeg, zDeg))
    }

    @discardableResult
    public func mirrored(normal: SIMD3<Float>) -> Solid {
        Solid(native.mirror(normal.x, normal.y, normal.z))
    }

    // ── Mesh output ───────────────────────────────────────────────────────

    public func meshData() -> MeshData? {
        MeshData.from(native.getMesh())
    }

    // ── Info ──────────────────────────────────────────────────────────────

    public var vertexCount:   Int   { Int(native.numVerts()) }
    public var triangleCount: Int   { Int(native.numTris()) }
    public var isEmpty:       Bool  { native.isEmpty() }
    public var isValid:       Bool  { native.isValid() }
    public var volume:        Float { native.volume() }
    public var surfaceArea:   Float { native.surfaceArea() }
}

// ─── Operator aliases ─────────────────────────────────────────────────────────

extension Solid {
    /// Union  (same as `union(with:)`)
    public static func + (lhs: Solid, rhs: Solid) -> Solid { lhs.union(with: rhs) }
    /// Difference  (same as `difference(from:)`)
    public static func - (lhs: Solid, rhs: Solid) -> Solid { lhs.difference(from: rhs) }
    /// Intersection  (same as `intersection(with:)`)
    public static func ^ (lhs: Solid, rhs: Solid) -> Solid { lhs.intersection(with: rhs) }
}

// ─── Preset examples ──────────────────────────────────────────────────────────

extension Solid {
    /// Sphere with a cubic hole drilled through the centre (difference demo)
    public static var sphereWithCube: Solid {
        let s = Solid.sphere(radius: 1.0, segments: 64)
        let c = Solid.cube(size: SIMD3(0.8, 0.8, 0.8))
        return s - c
    }

    /// Two overlapping spheres, union
    public static var twinSpheres: Solid {
        let a = Solid.sphere(radius: 0.8).translated(by: SIMD3(-0.5, 0, 0))
        let b = Solid.sphere(radius: 0.8).translated(by: SIMD3( 0.5, 0, 0))
        return a + b
    }

    /// Sphere intersected with a cube
    public static var sphereCubeIntersection: Solid {
        Solid.sphere(radius: 1.2) ^ Solid.cube(size: SIMD3(1.4, 1.4, 1.4))
    }
}
