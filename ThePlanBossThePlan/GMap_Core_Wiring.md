# MorphuVu Integration Blueprint: Core to GMap Module Wiring
Target: Flat Index Lookup via Unified Memory Bus (macOS / visionOS)

## 1. Project Directory Structure
Use this mapping to resolve file cross-references during code generation:
- /Core
  ├── Index.swift              # Raw integer index wrappers
  ├── IndexAllocator.swift     # Flat storage slot reservation/freeing
  ├── Dart.swift               # DartIndex primitives
  ├── AttributeContainer.swift # Generic contiguous backing array
  └── Orbits.swift             # Combinatorial cell traversal logic
- /GMap
  ├── GMap.swift               # Core state wrapper
  ├── GMap+Darts.swift        # Low-level involution arrays
  ├── GMap+Remove.swift       # Cell deletion and pointer resetting
  └── GMap+Attributes.swift   # Topological-to-Geometric parameter bridge

## 2. Core Integration Specification

### 2.1 Wiring AttributeContainer to GMap
The implementation in `GMap+Attributes.swift` must directly instantiate or wrap `AttributeContainer` from the Core layer. 
When executing `mergeAttributes(_ dartA: DartIndex, _ dartB: DartIndex, dimension idim: Int)`, use the following pipeline pattern:
1. Query the corresponding `AttributeContainer` instance for the storage slots matching `dartA` and `dartB`.
2. Evaluate the blending math (e.g., metric tensor interpolation or coordinate snapping).
3. Update the tracking slot using the flat indexing system provided by `IndexAllocator.swift`.

### 2.2 Memory Isolation & Invalidation
Inside `GMap+Remove.swift` (specifically within `removeCell`), when a dart is isolated:
1. Cleanly update the alpha arrays inside `GMap+Darts.swift` to break the involution loops.
2. Call the deallocation method inside `IndexAllocator.swift` to immediately mark that integer index slot as reusable. 
3. Avoid leaving dangling references or un-invalidated indexes in the `AttributeContainer`.

## 3. Structural Constraints for Claudine / Codexine
- Do NOT inject classes or reference counting cycles (`ARC` overhead) into these extensions.
- Keep all operations constrained to flat arrays using the index primitives from `Index.swift`.
- Ensure all method signatures cleanly compile across both macOS and visionOS targets without requiring platform-specific forks.

