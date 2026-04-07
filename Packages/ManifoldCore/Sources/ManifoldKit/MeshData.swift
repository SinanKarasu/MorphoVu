// MeshData.swift – ManifoldKit
// ─────────────────────────────────────────────────────────────────────────────
// Converts the flat C++ MeshOutput into Swift-friendly value types ready
// for RealityKit's MeshDescriptor.
//
// We use the raw-pointer accessors on MeshOutput (vertPosPtr / triVertsPtr)
// rather than subscripting std::vector directly, because pointer access is
// unambiguous in Swift's C++ interop.
// ─────────────────────────────────────────────────────────────────────────────

import ManifoldBridge
import simd

// ─── Swift mesh representation ────────────────────────────────────────────────

/// A triangle mesh ready for RealityKit's MeshDescriptor.
public struct MeshData: Sendable, Equatable {
    public let positions:  [SIMD3<Float>]
    public let normals:    [SIMD3<Float>]
    public let indices:    [UInt32]

    public var vertexCount:   Int  { positions.count }
    public var triangleCount: Int  { indices.count / 3 }
    public var isEmpty:       Bool { positions.isEmpty }
}

// ─── Conversion from C++ MeshOutput ──────────────────────────────────────────

extension MeshData {
    static func from(_ out: MeshOutput) -> MeshData? {
        guard out.valid else { return nil }

        let vertCount  = Int(out.vertPosCount()) / 3
        let idxCount   = Int(out.triVertsCount())

        guard vertCount > 0, idxCount > 0 else { return nil }

        // ── Positions ──────────────────────────────────────────────────────
        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(vertCount)

        // vertPosPtr() returns an Optional UnsafePointer<Float> in Swift
        if let ptr = out.vertPosPtr() {
            let buf = UnsafeBufferPointer(start: ptr, count: vertCount * 3)
            var i = buf.startIndex
            while i < buf.endIndex {
                positions.append(SIMD3<Float>(buf[i], buf[i + 1], buf[i + 2]))
                i += 3
            }
        } else {
            return nil
        }

        // ── Normals ────────────────────────────────────────────────────────
        var normals = [SIMD3<Float>]()
        normals.reserveCapacity(vertCount)

        let normCount = Int(out.vertNormCount()) / 3
        if normCount == vertCount, let nptr = out.vertNormPtr() {
            let nbuf = UnsafeBufferPointer(start: nptr, count: vertCount * 3)
            var i = nbuf.startIndex
            while i < nbuf.endIndex {
                normals.append(SIMD3<Float>(nbuf[i], nbuf[i + 1], nbuf[i + 2]))
                i += 3
            }
        } else {
            normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: vertCount)
        }

        // ── Indices ────────────────────────────────────────────────────────
        var indices = [UInt32]()
        indices.reserveCapacity(idxCount)

        if let iptr = out.triVertsPtr() {
            let ibuf = UnsafeBufferPointer(start: iptr, count: idxCount)
            indices.append(contentsOf: ibuf)
        } else {
            return nil
        }

        return MeshData(positions: positions, normals: normals, indices: indices)
    }
}
