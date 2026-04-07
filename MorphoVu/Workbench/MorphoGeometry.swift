import Foundation

struct MorphoGeometryEnvelope: Codable {
    let schema: String
    let source: String
    let preset: MorphoPresetPayload
    let mesh: MorphoMeshPayload
    let solid: MorphoSolidPayload

    init(
        preset: MorphoPreset,
        meshRevision: Int,
        vertexCount: Int,
        triangleCount: Int,
        isValid: Bool,
        volume: Float,
        surfaceArea: Float
    ) {
        self.schema = "org.bozuk.morphovu.geometry-envelope.v1"
        self.source = "ManifoldKit"
        self.preset = MorphoPresetPayload(
            id: preset.id,
            title: preset.title,
            group: preset.group.title,
            summary: preset.summary
        )
        self.mesh = MorphoMeshPayload(
            revision: meshRevision,
            vertexCount: vertexCount,
            triangleCount: triangleCount
        )
        self.solid = MorphoSolidPayload(
            isValid: isValid,
            volume: volume,
            surfaceArea: surfaceArea
        )
    }
}

struct MorphoPresetPayload: Codable {
    let id: String
    let title: String
    let group: String
    let summary: String
}

struct MorphoMeshPayload: Codable {
    let revision: Int
    let vertexCount: Int
    let triangleCount: Int
}

struct MorphoSolidPayload: Codable {
    let isValid: Bool
    let volume: Float
    let surfaceArea: Float
}

enum MorphoJSON {
    static func prettyString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{\n  \"error\": \"Unable to encode MorphoVu geometry contract\"\n}"
        }

        return text
    }
}
