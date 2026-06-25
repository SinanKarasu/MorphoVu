# MorphoVu — Architecture & Design Notes

**Author:** Sinan Karasu  
**Platform:** macOS 26+ (development), visionOS 2+ (immersive target)  
**Language:** Swift 6.4, C++ interop (SymEngine, Manifold, Dr.Jit)  
**Status:** Active development, June 2026

---

## What This Is

MorphoVu is a differential geometry workbench for Apple Vision Pro. The
immediate aim is to let someone type an expression like

```
y = \frac{x}{a} + b
```

via a mathematical keyboard, have it symbolically analyzed, JIT-compiled for
fast evaluation, turned into a mesh by a geometry kernel, and displayed as an
immersive three-dimensional object.

The longer aim is n-dimensional manifolds: for n > 3, MorphoVu slices or
projects the manifold down to three displayable dimensions while preserving its
combinatorial and topological structure. The combinatorial tracking is done with
Generalized Maps (G-maps in the sense of Damiand & Lienhardt), the geometry
by Emmett Lalish's Manifold kernel, and the display by RealityKit ImmersiveView
on visionOS.

This is not a casual 3-D viewer. The intent is to tie three strands of serious
mathematics — symbolic algebra, JIT numerical evaluation, and combinatorial
topology — into a single interactive environment running on spatial computing
hardware.

---

## The Pipeline

```
Math keyboard
      │
      ▼  LaTeX / MathML expression string
   TektonParsers  (ANTLR4-based LaTeX parser, macOS-only in full form)
      │
      ▼  expression AST
   CSym / SymEngine  (symbolic manipulation: differentiate, simplify, free vars)
      │
      ▼  simplified expression, named free symbols
   Dr.Jit  (JIT compilation → native kernel for fast point evaluation)
      │
      ▼  evaluated point cloud  (R^n samples)
   GMap  (combinatorial tracking of cell structure in the sample mesh)
      │
      ▼  i-cell incidence data
   Manifold  (geometry kernel: boolean CSG, mesh refinement, watertight output)
      │
      ▼  MeshData  (positions, normals, UInt32 indices)
   ManifoldKit → RealityKit MeshDescriptor
      │
      ▼  ModelEntity in ImmersiveSpace
   visionOS  (Vision Pro display, immersed mode)
```

Each stage has a clearly bounded API. The stages can be swapped, replaced, or
short-circuited for experimentation:  for instance, the Keyboard Lab tab
exercises the math keyboard and ANTLR parser alone; the CSym tab exercises
SymEngine evaluation directly; the Runtime Lab runs LispPad (macOS only) to
explore SCMUtils-style symbolic computation.

---

## Package Ecosystem

### ManifoldCore  (ready, macOS 14+ / visionOS 1+)

Three-layer Swift package wrapping Emmett Lalish's
[Manifold](https://github.com/elalish/manifold) C++ geometry kernel:

```
ManifoldKit   (Swift, .interoperabilityMode(.Cxx))
  └─ ManifoldBridge   (C++ PIMPL wrapper, compiled by SPM)
       └─ ManifoldBinary   (prebuilt static XCFramework, vendored)
```

The Swift API in `ManifoldKit` exposes:

- `Solid` — a watertight solid geometry value type with CSG operators
  (`+` union, `-` difference, `^` intersection), transforms, and
  `meshData() -> MeshData?`
- `MeshData` — flat `[SIMD3<Float>]` positions, normals, and `[UInt32]` indices,
  ready for `RealityKit.MeshDescriptor`

Bootstrap: `make bootstrap` or `Scripts/bootstrap-manifold.sh` builds upstream
Manifold and stages the XCFramework into `vendor/`.

*This is the geometry backend. Dr.Jit feeds it point samples; it returns
meshes.*

---

### GeneralizedMap  (ready, macOS 26+, Swift 6.4)

Value-generic Swift 6.4 package: `GMap<let N: Int, let NA: Int, let NL: Int>`.

```
N   — number of alpha involutions  (dimension + 1)
NA  — number of attribute slots per dart
NL  — number of weak link slots per dart
```

Common aliases: `GMap3_1_0` (3-G-map, 1 attribute), `GMap4_1_0` (4-G-map with
attributes), `GMap6_1_1` (6 involutions, 1 attribute, 1 weak link).

**What this does:** a G-map is the combinatorial skeleton of a cell complex —
it tracks which darts belong to the same vertex / edge / face / ... cell
without carrying any geometry. When MorphoVu evaluates an n-dimensional
manifold and triangulates it, the GMap layer records the incidence structure
(which triangles share an edge, which edges meet at a vertex) while the
geometry floats in the attribute layer. This makes operations like slicing,
projection, and unfolding algebraically clean.

Extension files: `GMap+Sew`, `GMap+Unsew`, `GMap+Shapes` (standard shapes),
`GMap+Extrude`, `GMap+Chamfer`, `GMap+Insert`, `GMap+Contract`,
`GMap+CloseBoundary`, `GMap+Attributes`, `GMap+Marks`, `GMap+Iteration`,
`GMap+Stats`.

---

### SymEngineSwift / CSym  (ready, macOS; visionOS untested)

`CPPSymEngine` wraps the
[SymEngine](https://github.com/symengine/symengine) C++ symbolic math library
via a Swift system library target (`pkgConfig: "symengine"`).  The Swift layer
in `MorphoVu` lives in:

- `LineExpressionModel` — holds the parsed expression root and token text
- `LineExpressionModel+SymEngine` — builds a SymEngine expression tree from
  the ANTLR4 AST, calls `.differentiated(by:)`, `.expanded()`, `.freeSymbolNames()`
- `PlotSceneFactory` — bridges SymEngine evaluation to RealityKit scene nodes

The `CSymExperimentView` tab exercises this layer directly in the app.

*Limitation:* SymEngine links against a system-installed dylib. Its availability
on visionOS is untested; it may need to be compiled as a static XCFramework
(same strategy as ManifoldCore) for the Vision Pro target.

---

### Dr.Jit  (not yet integrated)

[Dr.Jit](https://github.com/mitsuba-renderer/drjit) (Wenzel Jakob, EPFL / MIT)
is a JIT compilation framework designed for differentiable and vectorized
computation in C++ and Python. It is the missing piece between CSym and Manifold:
SymEngine simplifies the expression symbolically; Dr.Jit compiles the simplified
form to a native kernel that can evaluate ten thousand sample points as fast as
a single function call.

**visionOS entitlement:** visionOS prohibits JIT-compiled code by default.
The entitlement `com.apple.developer.cs.allow-jit` may permit it; this has not
yet been tested on a real device. If the entitlement is unavailable:

1. Pre-evaluate on macOS, transfer mesh via SharePlay / CloudKit.
2. Fork Dr.Jit and replace its JIT backend with ahead-of-time Metal kernels.
3. Use a Metal compute shader directly, compiling the kernel string to a
   `MTLFunction` (Metal itself handles the compilation step, which may or may
   not count as JIT under the entitlement rules).

*This is the next major integration task.*

---

### LispPad / SCMUtils  (macOS only — GPL)

LispPad Core embeds an MIT-licensed Scheme (R7RS) interpreter, and through it,
MIT's SCMUtils library for symbolic mechanics. SCMUtils is GPL. It cannot be
included in a visionOS app binary without making the entire app GPL.

LispPad is available in MorphoVu's "Runtime Lab" tab on macOS for exploration
and prototyping. It is excluded from the visionOS target via conditional
compilation.  If a specific SCMUtils algorithm is needed in the final pipeline,
it will need to be reimplemented in Swift using SymEngineSwift instead.

---

## App Structure

MorphoVu is a five-tab `TabView` (`ContentView.swift`), tinted with
`MorphoTheme.accent`:

| Tab | View | Purpose |
|-----|------|---------|
| Workbench | `MorphoWorkbenchRootView` | Main manifold display |
| Keyboard Lab | `KeyboardLabView` | Math keyboard + ANTLR LaTeX parser |
| Python | `PythonWorkbenchView` | Python / scripting bridge |
| CSym | `CSymExperimentView` | SymEngine symbolic experiments |
| Runtime Lab | `LispPadDevRootView` | LispPad / SCMUtils (macOS only) |

`MorphoWorkbenchState` is an `@Observable` object shared across the Workbench.

### MorphoGeometry Envelope

`MorphoGeometryEnvelope` in `Workbench/MorphoGeometry.swift` is the typed
payload that flows from the pipeline into the renderer:

```swift
struct MorphoGeometryEnvelope: Codable {
    let schema  = "org.bozuk.morphovu.geometry-envelope.v1"
    let source  = "ManifoldKit"
    var preset:  String?          // named preset (e.g. "sphereWithCube")
    var mesh:    MeshPayload?     // raw triangle mesh
    var solid:   SolidPayload?    // Manifold CSG spec (reconstructable)
}
```

`MorphoSceneRenderView` consumes this envelope. The Workbench state machine
drives the pipeline: expression string → envelope → rendered entity.

---

## The Immersive View

The immersive display pattern follows `DStarSwift/DStarImmersiveView.swift`,
which demonstrates the complete `BSP → MeshAccumulator → MeshDescriptor →
MeshResource → ModelEntity` pipeline for RealityKit on visionOS. MorphoVu will
follow the same pattern:

```
MeshData (from ManifoldKit)
  │  positions: [SIMD3<Float>]
  │  normals:   [SIMD3<Float>]
  │  indices:   [UInt32]
  ▼
var desc = MeshDescriptor()
desc.positions  = MeshBuffer(positions)
desc.normals    = MeshBuffer(normals)
desc.primitives = .triangles(indices)
let resource = try MeshResource.generate(from: [desc])
let entity   = ModelEntity(mesh: resource, materials: [material])
```

The `ImmersiveSpace` with `.immersionStyle(.full)` is `#if os(visionOS)` gated.
On macOS the Workbench tab shows the same geometry in a SceneKit or SwiftUI 3-D
preview view.

---

## n-Dimensional Projection and Slicing

For manifolds of dimension n > 3, two strategies are planned:

**Slicing:** fix the values of the extra n−3 coordinates at chosen levels.
The result is a family of 3-D cross-sections, each one a valid submanifold.
The GMap layer makes this clean: a (n−k)-G-map slice is obtained by fixing
k coordinates and retaining only the darts whose attribute values land on the
selected level set. No geometry code is required for the slicing itself — only
GMap orbit traversal.

**Projection:** apply a linear or curved map π: R^n → R^3. For smooth
manifolds the projection pushes forward the metric; for discrete meshes it is
simply a matrix multiply on each vertex position. The Manifold kernel can then
re-mesh the projected point cloud if needed.

The progress field concept from Sailing (see below) generalizes directly: a
smooth scalar `s: M → [0,1]` partitions an n-manifold into level sets, each
being an (n−1)-submanifold. Successive slices at s=0, s=Δ, s=2Δ, ... form
the natural animation sweep.

---

## Mathematical Lineage: Sailing → MorphoVu

The mathematical foundation for MorphoVu was worked out concretely in an earlier
project: **Sailing** (`/Users/sinan/Developer/Sailing`), a tacking-corridor
optimizer for sailboats.

The Sailing project encodes tacking paths as a 2-G-map:

- Each strip of the tacking corridor contributes one quadrilateral face → 8 darts.
- α₀: swap vertex along the same edge.
- α₁: swap edge at the same vertex within a face.
- α₂: swap face across a shared edge (glue adjacent strips).
- When two adjacent strips carry opposite tacks, the α₂ gluing is
  *orientation-reversing* — flagged as `isReflective`. This is the tack reversal.

The **progress field** `s: Ω → [0,1]` is a smooth scalar on the corridor
such that `s = const` level curves are strip boundaries. Extracting the level
set at each integer step gives the strip decomposition; the G-map encodes how
the strips fit together.

The **unfolding** operation: reflect alternating strips across their shared
boundary edge, straightening the zig-zag into a line. In combinatorial terms:
for each `isReflective` α₂ edge, apply the corresponding reflection isometry
to all darts on one side. The result is a valid G-map with all α₂ edges
non-reflective — a flat development of the original strip complex.

This is exactly the operation MorphoVu needs for n > 3: pick n−3 "extra"
dimensions, treat their level sets as G-map boundaries, unfold (project) across
those boundaries, and display the 3-D development on Vision Pro.

```
Sailing  (2-G-map, tacking strips, reflective unfolding, progress field)
    ↓   generalized to arbitrary dimension
GeneralizedMap  (GMap<N,NA,NL>, value-generic Swift 6.4)
    ↓   numerical evaluation of expression over sample grid
Dr.Jit  (JIT-compiled evaluation kernel)
    ↓   meshed by geometry kernel
ManifoldCore  (Solid, MeshData)
    ↓   combinatorial skeleton tracked in parallel
GMap layer  (i-cell incidence, slice / project operations)
    ↓   displayed as
RealityKit ImmersiveView  (Vision Pro, immersed mode)
```

The `CombinatorialMap.swift` 2-G-map in Sailing (`GMap2` class, Damiand-
Lienhardt style) is the direct conceptual ancestor of the `GMap<N,NA,NL>`
value-generic package in `Packages/GeneralizedMap`. The Euler characteristic
computation, orbit traversal, and `fromTackPath()` factory in `GMap2` all have
direct analogues in the full package.

---

## Build Notes

- **GeneralizedMap** requires Swift 6.4 (macOS 26 SDK). It cannot be compiled
  against earlier toolchains.
- **ManifoldCore** requires `make bootstrap` before the first build to stage
  the vendored XCFramework. Targets macOS 14+ and visionOS 1+.
- **SymEngineSwift** requires `brew install symengine` on macOS; the system
  library target uses `pkgConfig: "symengine"`. Not yet bootstrapped for visionOS.
- **Dr.Jit** is not yet in the package graph. When added, it will need a
  C++ interop bridge similar to ManifoldBridge.
- **LispPad** is conditionally compiled out of the visionOS target
  (`#if os(macOS)`).
- The Linux sandbox (available via Cowork) lacks an iOS/macOS SDK and cannot
  build any of these packages. All builds must be done on the Mac.

---

## Experimental Strategy

The 1990s approach to a system like this: start with CSym, build the pipeline
incrementally, and tweak. With symbolic math already working (CSym tab) and
geometry already working (ManifoldCore), the shortcut is:

1. Wire CSym → a naive Swift evaluator (no JIT) → Manifold → ImmersiveView.
   This gives a working end-to-end pipeline, slow for dense meshes but correct.

2. Replace the Swift evaluator with Dr.Jit when the entitlement question is
   resolved. The pipeline interface doesn't change — Dr.Jit is a drop-in
   accelerator at the evaluation step.

3. Add GMap tracking alongside the Manifold mesh. GMap carries the i-cell
   incidence; Manifold carries the geometry. Together they support slice / project
   UI.

4. Add the Math keyboard front end and connect it to step 1.

Step 1 can be completed now, without Dr.Jit, without the entitlement
investigation, and without the n > 3 projection math. It produces a working
Vision Pro immersive display of user-entered expressions.

---

## Historical Note

MorphoVu is being built by Sinan Karasu in 2026, approaching 80, to close
a circle that opened in the mid-1990s: the Atlas626Interpreter, timer14, and
the ARINC 626-3 work were all test-system infrastructure. MorphoVu is
mathematics for its own sake — a differential geometry workbench on hardware
that didn't exist when the ideas were first on the table.

The GeneralizedMap package preserves work done collaboratively with Claude
(Anthropic) on the Sailing tacking optimizer, which itself drew on
Damiand & Lienhardt's combinatorial map theory. That collaboration is the
geometric thread running from compass-and-rudder optimization to n-dimensional
manifold visualization on spatial computing hardware.

The vision: someone — a student, a geometer, a curious person — types an
expression and immediately inhabits the shape it describes.

---

*This document written June 2026 with assistance from Claude (Anthropic),
based on source code exploration and conversation with the original author.*
