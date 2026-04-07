// ManifoldKit.swift
// ─────────────────────────────────────────────────────────────────────────────
// Module entry point – re-exports the public API surface.
//
// Import this module from your SwiftUI app:
//   import ManifoldKit
//
// Then use:
//   let s = Shape.sphere(radius: 1)
//   let c = Shape.cube(size: .one)
//   let result = s - c          // difference
//   let mesh = result.meshData()
// ─────────────────────────────────────────────────────────────────────────────

// Everything public in Shape.swift, MeshData.swift is automatically part of
// the ManifoldKit module – this file exists as a conventional entry point and
// for any cross-cutting documentation or module-level symbols.

/// ManifoldKit version (tracks Manifold tag in setup.sh)
public let manifoldKitVersion = "3.1.0"
