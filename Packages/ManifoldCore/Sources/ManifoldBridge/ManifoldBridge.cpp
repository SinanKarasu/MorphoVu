// ManifoldBridge.cpp
// ─────────────────────────────────────────────────────────────────────────────
// Implementation of ManifoldBridge.h.
//
// All manifold:: types stay in this .cpp file; none leak into the header.
// ─────────────────────────────────────────────────────────────────────────────

#include "ManifoldBridge.h"

#include <manifold/manifold.h>  // Manifold, MeshGL, Polygons, SimplePolygon, vec2

#include <cmath>
#include <stdexcept>

// ─── Pimpl ────────────────────────────────────────────────────────────────────

struct ManifoldShape::Pimpl {
    manifold::Manifold m;

    Pimpl() = default;
    explicit Pimpl(manifold::Manifold manifold) : m(std::move(manifold)) {}
};

// ─── Lifecycle ─────────────────────────────────────────────────────────────────

ManifoldShape::ManifoldShape()
    : d_(std::make_shared<Pimpl>()) {}

ManifoldShape::ManifoldShape(const ManifoldShape& other)
    : d_(other.d_) {}   // shared_ptr copy – cheap

ManifoldShape::ManifoldShape(ManifoldShape&& other) noexcept
    : d_(std::move(other.d_)) {}

ManifoldShape::~ManifoldShape() = default;

ManifoldShape& ManifoldShape::operator=(const ManifoldShape& other) {
    if (this != &other) d_ = other.d_;
    return *this;
}

ManifoldShape& ManifoldShape::operator=(ManifoldShape&& other) noexcept {
    d_ = std::move(other.d_);
    return *this;
}

ManifoldShape::ManifoldShape(std::shared_ptr<Pimpl> p)
    : d_(std::move(p)) {}

// ── Internal helper (member so it can call the private constructor) ──────────
// Called from all factory / boolean methods below.
static ManifoldShape makeShape(manifold::Manifold m) {
    // We build via the public default constructor then swap – OR we use a
    // local friend trick.  Simplest: route through the private shared_ptr ctor.
    // Because this .cpp file is the class's own translation unit we can access
    // private members through an explicit friend or static helper.
    // We declare it private in the header and call it here from member functions.
    //
    // *** Do NOT call this free function from non-member code. ***
    struct Accessor : ManifoldShape {
        explicit Accessor(manifold::Manifold mv)
            : ManifoldShape(std::make_shared<ManifoldShape::Pimpl>(std::move(mv))) {}
    };
    return Accessor(std::move(m));
}

// ─── Primitives ───────────────────────────────────────────────────────────────

ManifoldShape ManifoldShape::makeSphere(float radius, int circularSegments) {
    return makeShape(manifold::Manifold::Sphere(radius, circularSegments));
}

ManifoldShape ManifoldShape::makeCube(float sx, float sy, float sz, bool centered) {
    return makeShape(manifold::Manifold::Cube({sx, sy, sz}, centered));
}

ManifoldShape ManifoldShape::makeCylinder(float height, float radiusLow,
                                           float radiusHigh, int circularSegments,
                                           bool center) {
    // radiusHigh == -1 → same as radiusLow (perfect cylinder)
    float rHigh = (radiusHigh < 0.0f) ? radiusLow : radiusHigh;
    return makeShape(manifold::Manifold::Cylinder(height, radiusLow, rHigh,
                                                  circularSegments, center));
}

ManifoldShape ManifoldShape::makeCone(float height, float radius,
                                       int circularSegments) {
    return makeShape(manifold::Manifold::Cylinder(height, radius, 0.0f,
                                                  circularSegments, false));
}

ManifoldShape ManifoldShape::makeTorus(float majorRadius, float minorRadius,
                                        int toroidalSegments, int poloidalSegments) {
    // Build a torus by revolving a circle cross-section using Manifold::Revolve().
    // The cross-section is a circle of minorRadius centred at (majorRadius, 0).

    using namespace manifold;

    // Build a 2-D circle profile as a SimplePolygon (std::vector<vec2>).
    // vec2 = la::vec<double,2>.  Manifold::Revolve takes const Polygons& which
    // is std::vector<SimplePolygon>, so we wrap the circle in an outer vector.
    SimplePolygon circle;
    circle.reserve(static_cast<size_t>(poloidalSegments));
    for (int i = 0; i < poloidalSegments; ++i) {
        double angle = static_cast<double>(i) / static_cast<double>(poloidalSegments)
                       * 2.0 * 3.14159265358979323846;
        circle.push_back({
            static_cast<double>(majorRadius) + static_cast<double>(minorRadius) * std::cos(angle),
            static_cast<double>(minorRadius) * std::sin(angle)
        });
    }

    Polygons profile{circle};   // Polygons = std::vector<SimplePolygon>
    return makeShape(Manifold::Revolve(profile, toroidalSegments));
}

// ─── Boolean CSG ──────────────────────────────────────────────────────────────

ManifoldShape ManifoldShape::add(const ManifoldShape& other) const {
    return makeShape(d_->m + other.d_->m);
}

ManifoldShape ManifoldShape::subtract(const ManifoldShape& other) const {
    return makeShape(d_->m - other.d_->m);
}

ManifoldShape ManifoldShape::intersect(const ManifoldShape& other) const {
    return makeShape(d_->m ^ other.d_->m);
}

// ─── Transforms ───────────────────────────────────────────────────────────────

ManifoldShape ManifoldShape::translate(float x, float y, float z) const {
    return makeShape(d_->m.Translate({x, y, z}));
}

ManifoldShape ManifoldShape::scale(float sx, float sy, float sz) const {
    return makeShape(d_->m.Scale({sx, sy, sz}));
}

ManifoldShape ManifoldShape::rotate(float xDeg, float yDeg, float zDeg) const {
    return makeShape(d_->m.Rotate(xDeg, yDeg, zDeg));
}

ManifoldShape ManifoldShape::mirror(float nx, float ny, float nz) const {
    return makeShape(d_->m.Mirror({nx, ny, nz}));
}

// ─── Mesh extraction ──────────────────────────────────────────────────────────

MeshOutput ManifoldShape::getMesh() const {
    MeshOutput out;
    if (!d_ || d_->m.IsEmpty()) return out;

    manifold::MeshGL gl = d_->m.GetMeshGL();

    const int numProp = gl.numProp;  // typically 3 (x,y,z) or more if normals embedded
    const int numVerts = static_cast<int>(gl.vertProperties.size()) / numProp;

    // ── Vertex positions (always the first 3 properties) ──────────────────
    out.vertPos.reserve(static_cast<size_t>(numVerts * 3));
    for (int v = 0; v < numVerts; ++v) {
        out.vertPos.push_back(gl.vertProperties[v * numProp + 0]);
        out.vertPos.push_back(gl.vertProperties[v * numProp + 1]);
        out.vertPos.push_back(gl.vertProperties[v * numProp + 2]);
    }

    // ── Triangle indices ───────────────────────────────────────────────────
    out.triVerts.reserve(gl.triVerts.size());
    for (auto idx : gl.triVerts) {
        out.triVerts.push_back(static_cast<uint32_t>(idx));
    }

    // ── Per-face normals (computed on the fly) ─────────────────────────────
    // We compute smooth vertex normals by averaging adjacent face normals.
    const int numTris = static_cast<int>(out.triVerts.size()) / 3;
    out.vertNormal.assign(static_cast<size_t>(numVerts * 3), 0.0f);

    for (int t = 0; t < numTris; ++t) {
        uint32_t i0 = out.triVerts[t * 3 + 0];
        uint32_t i1 = out.triVerts[t * 3 + 1];
        uint32_t i2 = out.triVerts[t * 3 + 2];

        float ax = out.vertPos[i0 * 3], ay = out.vertPos[i0 * 3 + 1], az = out.vertPos[i0 * 3 + 2];
        float bx = out.vertPos[i1 * 3], by = out.vertPos[i1 * 3 + 1], bz = out.vertPos[i1 * 3 + 2];
        float cx = out.vertPos[i2 * 3], cy = out.vertPos[i2 * 3 + 1], cz = out.vertPos[i2 * 3 + 2];

        // Edge vectors
        float ex = bx - ax, ey = by - ay, ez = bz - az;
        float fx = cx - ax, fy = cy - ay, fz = cz - az;

        // Cross product (face normal, un-normalised = area-weighted)
        float nx = ey * fz - ez * fy;
        float ny = ez * fx - ex * fz;
        float nz = ex * fy - ey * fx;

        for (uint32_t idx : {i0, i1, i2}) {
            out.vertNormal[idx * 3 + 0] += nx;
            out.vertNormal[idx * 3 + 1] += ny;
            out.vertNormal[idx * 3 + 2] += nz;
        }
    }

    // Normalise
    for (int v = 0; v < numVerts; ++v) {
        float nx = out.vertNormal[v * 3];
        float ny = out.vertNormal[v * 3 + 1];
        float nz = out.vertNormal[v * 3 + 2];
        float len = std::sqrt(nx*nx + ny*ny + nz*nz);
        if (len > 1e-6f) {
            out.vertNormal[v * 3]     = nx / len;
            out.vertNormal[v * 3 + 1] = ny / len;
            out.vertNormal[v * 3 + 2] = nz / len;
        }
    }

    out.valid = true;
    return out;
}

// ─── Info ──────────────────────────────────────────────────────────────────────

int  ManifoldShape::numVerts()    const { return d_ ? d_->m.NumVert() : 0; }
int  ManifoldShape::numTris()     const { return d_ ? d_->m.NumTri()  : 0; }
bool ManifoldShape::isEmpty()     const { return !d_ || d_->m.IsEmpty(); }

bool ManifoldShape::isValid() const {
    if (!d_) return false;
    return d_->m.Status() == manifold::Manifold::Error::NoError;
}

float ManifoldShape::volume() const {
    if (!d_ || d_->m.IsEmpty()) return 0.0f;
    return static_cast<float>(d_->m.Volume());        // v3: Volume() replaces GetProperties().volume
}

float ManifoldShape::surfaceArea() const {
    if (!d_ || d_->m.IsEmpty()) return 0.0f;
    return static_cast<float>(d_->m.SurfaceArea());   // v3: SurfaceArea() replaces GetProperties().surfaceArea
}
