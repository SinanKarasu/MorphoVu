# MorphuVu Integration Blueprint: Attribute Engine & G-Map Memory
Target Architectures: macOS 17+, visionOS 4+ (Unified Apple Silicon Bus)

## 1. System Philosophy
This document establishes the symbol table interface linking our topological Generalized Map (Swift/Rust port) with Emmett Lalish's `manifold` geometry kernel and our C++ CSym metric tensor engine. Memory must remain flat, utilizing contiguously allocated index arrays rather than reference pointers to guarantee 90Hz–120Hz rendering performance.

## 2. Mathematical State Matrix
Each active topological i-cell must map to a localized coordinate state space governed by the spacetime metric tensor $g_{\mu\nu}$. 

```latex
\[ds^2 = \sum_{\mu=0}^{3} \sum_{\nu=0}^{3} g_{\mu\nu} dx^\mu dx^\nu\]
```

## 3. Swift Implementation Spec: `GMap+Attributes.swift`

### 3.1 Requirements
1. Implement a generic, index-allocated `AttributeStorage<T>` layout to eliminate heap fragmentation.
2. Provide the implementation framework for the following critical topology-to-geometry bridging method:

```swift
public extension GMap {
    /// Merges structural data attributes following an i-cell contraction or removal.
    /// Bridges the topological link between surviving boundary elements.
    func mergeAttributes(_ dartA: DartIndex, _ dartB: DartIndex, dimension idim: Int) -> Bool
}
```

### 3.2 Allocation Constraints
- Do NOT use classes or reference cycles for Dart tracking.
- Attributes must resolve via a flat lookup table indexed directly by a 32-bit integer (`Int32` or explicit `DartIndex`).
- When cell contractions trigger `removeCell`, attributes must cleanly blend rather than dropping out of scope.

## 4. Memory Reclamation Spec: `GMap+Remove.swift`
Ensure that `removeIsolatedDart(_ di: DartIndex)` executes complete structural index invalidation. When a dart is detached, its corresponding entries inside the alpha involution arrays ($\alpha_0, \alpha_1, \alpha_2$) must be reset to an explicit sentinel state (`0` or `-1`) to prevent memory leaks on the Apple Silicon Unified Memory bus.

