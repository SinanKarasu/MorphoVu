// ManifoldBridge.h
// ─────────────────────────────────────────────────────────────────────────────
// A template-free C++ API over manifold::Manifold that Swift 5.9+ can import
// directly via C++ interoperability (no bridging header required).
//
// Design principles
//   • No Manifold public types (e.g. glm::vec3) in the API boundary –
//     all geometry is passed as plain floats / ints.
//   • All classes have copy + move constructors → imported as Swift value types.
//   • PIMPL hides all manifold internals; std::unique_ptr is behind the impl
//     boundary and is never exposed to Swift.
//   • Output mesh uses std::vector<float> + std::vector<uint32_t> which Swift
//     can iterate as UnsafeBufferPointer via C++ interop.
// ─────────────────────────────────────────────────────────────────────────────
#pragma once

#include <memory>
#include <vector>
#include <cstdint>
#include <string>

// SWIFT_RETURNS_INDEPENDENT_VALUE tells Swift's C++ importer that a method
// returning a raw pointer does NOT return a pointer into the object's own
// storage – so Swift is allowed to use it as UnsafePointer<T>.
// The header is provided by the Swift toolchain when C++ interop is active.
#if __has_include(<swift/bridging>)
#  include <swift/bridging>
#else
#  define SWIFT_RETURNS_INDEPENDENT_VALUE
#endif

// ─── Mesh output ──────────────────────────────────────────────────────────────

/// Flat triangle mesh returned by getMesh().
///
/// vertPos:    [x₀,y₀,z₀,  x₁,y₁,z₁, …]  – 3 floats per vertex
/// vertNormal: [nx₀,ny₀,nz₀, …]            – 3 floats per vertex (may be empty)
/// triVerts:   [i₀,i₁,i₂,  i₃,i₄,i₅, …]   – 3 uint32 indices per triangle
struct MeshOutput {
    std::vector<float>    vertPos;
    std::vector<float>    vertNormal;
    std::vector<uint32_t> triVerts;
    bool valid = false;

    // Raw pointer accessors used by Swift's C++ interop.
    // SWIFT_RETURNS_INDEPENDENT_VALUE is required so Swift's importer treats
    // the returned pointer as usable (not an interior/dangling pointer).
    const float*    vertPosPtr()     const SWIFT_RETURNS_INDEPENDENT_VALUE { return vertPos.data(); }
    std::size_t     vertPosCount()   const { return vertPos.size(); }

    const float*    vertNormPtr()    const SWIFT_RETURNS_INDEPENDENT_VALUE { return vertNormal.data(); }
    std::size_t     vertNormCount()  const { return vertNormal.size(); }

    const uint32_t* triVertsPtr()    const SWIFT_RETURNS_INDEPENDENT_VALUE { return triVerts.data(); }
    std::size_t     triVertsCount()  const { return triVerts.size(); }
};

// ─── ManifoldShape ────────────────────────────────────────────────────────────

/// Opaque value-type wrapper around manifold::Manifold.
///
/// From Swift (with .interoperabilityMode(.Cxx)) you can call:
///
///   let sphere = ManifoldShape.makeSphere(1.0, 32)
///   let cube   = ManifoldShape.makeCube(1, 1, 1, true)
///   let result = sphere.add(cube)
///   let mesh   = result.getMesh()
///
class ManifoldShape {
public:
    // ── Lifecycle (required for Swift value-type import) ───────────────────
    ManifoldShape();
    ManifoldShape(const ManifoldShape& other);
    ManifoldShape(ManifoldShape&& other) noexcept;
    ~ManifoldShape();
    ManifoldShape& operator=(const ManifoldShape& other);
    ManifoldShape& operator=(ManifoldShape&& other) noexcept;

    // ── Primitives ─────────────────────────────────────────────────────────
    static ManifoldShape makeSphere(float radius, int circularSegments = 32);

    /// size{x,y,z} as three separate floats; centered = true centres on origin
    static ManifoldShape makeCube(float sx, float sy, float sz,
                                   bool centered = true);

    /// Standard cylinder.  radiusHigh ≥ 0 → truncated cone; –1 → same as radiusLow
    static ManifoldShape makeCylinder(float height,
                                       float radiusLow,
                                       float radiusHigh = -1.0f,
                                       int   circularSegments = 32,
                                       bool  center = false);

    /// Cone (cylinder with radiusHigh = 0)
    static ManifoldShape makeCone(float height, float radius,
                                   int circularSegments = 32);

    /// Torus – swept circle of minorRadius around a ring of majorRadius
    static ManifoldShape makeTorus(float majorRadius, float minorRadius,
                                    int toroidalSegments = 64,
                                    int poloidalSegments = 16);

    // ── Boolean CSG ────────────────────────────────────────────────────────

    /// Union (A ∪ B)
    ManifoldShape add(const ManifoldShape& other) const;

    /// Difference (A − B)
    ManifoldShape subtract(const ManifoldShape& other) const;

    /// Intersection (A ∩ B)
    ManifoldShape intersect(const ManifoldShape& other) const;

    // ── Rigid / affine transforms ──────────────────────────────────────────

    ManifoldShape translate(float x, float y, float z) const;
    ManifoldShape scale(float sx, float sy, float sz) const;

    /// Euler-angle rotation in degrees (applied x → y → z)
    ManifoldShape rotate(float xDeg, float yDeg, float zDeg) const;

    /// Mirror about the plane with the given normal (does not need to be unit length)
    ManifoldShape mirror(float nx, float ny, float nz) const;

    // ── Mesh extraction ────────────────────────────────────────────────────

    MeshOutput getMesh() const;

    // ── Info ───────────────────────────────────────────────────────────────

    int   numVerts()     const;
    int   numTris()      const;
    bool  isEmpty()      const;
    bool  isValid()      const;   ///< No topological errors
    float volume()       const;
    float surfaceArea()  const;

protected:
    // Forward-declare Pimpl here (protected) so the local Accessor subclass in
    // ManifoldBridge.cpp can refer to ManifoldShape::Pimpl when calling this ctor.
    // Swift's C++ importer treats protected as internal – not exposed to Swift.
    struct Pimpl;
    explicit ManifoldShape(std::shared_ptr<Pimpl> p);

private:
    // shared_ptr → ManifoldShape is copyable; copies share the manifold::Manifold.
    std::shared_ptr<Pimpl> d_;
};
