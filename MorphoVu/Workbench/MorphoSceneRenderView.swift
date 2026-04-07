import RealityKit
import SwiftUI
import ManifoldKit
import simd

struct MorphoSceneRenderView: View {
    let state: MorphoWorkbenchState
    var showsProgress: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    @State private var yaw: Float = 0.35
    @State private var pitch: Float = 0.28
    @State private var distance: Float = 4.1
    @State private var dragStartOrbit: OrbitState?
    @State private var pivotEntity = Entity()
    @State private var modelEntity: ModelEntity?
    @State private var didSetupScene = false
    @State private var renderedRevision = -1

    private var palette: MorphoTheme.Palette {
        MorphoTheme.palette(for: colorScheme)
    }

    var body: some View {
        RealityView { content in
#if !os(visionOS)
            content.camera = .virtual
#endif
            setupScene(content: content)
        } update: { _ in
            syncMesh()
            syncCamera()
        }
        .onAppear {
            syncMesh()
            syncCamera()
        }
        .onChange(of: state.buildRevision) { _, _ in
            syncMesh()
        }
        .gesture(orbitGesture)
#if os(macOS)
        .onScrollWheel { event in
            adjustDistance(by: Float(event.deltaY) * 0.08)
        }
#endif
        .background(sceneBackground)
        .overlay(alignment: .topTrailing) {
            if showsProgress && state.isBuilding {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding()
            }
        }
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartOrbit == nil {
                    dragStartOrbit = OrbitState(yaw: yaw, pitch: pitch)
                }
                guard let dragStartOrbit else { return }
                yaw = dragStartOrbit.yaw + Float(value.translation.width) * 0.008
                pitch = dragStartOrbit.pitch + Float(value.translation.height) * 0.008
                pitch = max(-Float.pi / 2 + 0.08, min(Float.pi / 2 - 0.08, pitch))
                syncCamera()
            }
            .onEnded { _ in
                dragStartOrbit = nil
            }
    }

    private var sceneBackground: some View {
        LinearGradient(
            colors: [
                palette.sceneTop,
                palette.sceneBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func setupScene(content: some RealityViewContentProtocol) {
        guard !didSetupScene else { return }
        content.add(makeAmbientLight())
        content.add(makeDirectionalLight())
        content.add(makeFillLight())
        content.add(pivotEntity)
        didSetupScene = true
        syncMesh()
        syncCamera()
    }

    @MainActor
    private func syncMesh() {
        guard renderedRevision != state.buildRevision else { return }
        guard let mesh = state.meshData, !mesh.isEmpty else { return }
        guard let meshResource = try? makeMeshResource(from: mesh) else { return }

        if let modelEntity {
            modelEntity.model?.mesh = meshResource
        } else {
            let entity = ModelEntity(mesh: meshResource, materials: [makeMaterial()])
            pivotEntity.addChild(entity)
            self.modelEntity = entity
        }

        renderedRevision = state.buildRevision
    }

    @MainActor
    private func syncCamera() {
        let rotX = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        let rotY = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        pivotEntity.orientation = rotY * rotX
        pivotEntity.position = SIMD3(0, 0, -distance)
    }

    private func adjustDistance(by delta: Float) {
        distance = max(1.4, min(14.0, distance - delta))
        syncCamera()
    }
}

private struct OrbitState {
    let yaw: Float
    let pitch: Float
}

private func makeMeshResource(from mesh: MeshData) throws -> MeshResource {
    var descriptor = MeshDescriptor(name: "morphovu.manifold")
    descriptor.positions = MeshBuffer(mesh.positions)
    if !mesh.normals.isEmpty {
        descriptor.normals = MeshBuffer(mesh.normals)
    }
    descriptor.primitives = .triangles(mesh.indices)
    return try MeshResource.generate(from: [descriptor])
}

private func makeMaterial() -> RealityKit.Material {
    var material = PhysicallyBasedMaterial()
#if os(macOS)
    let tint = NSColor(red: 0.39, green: 0.68, blue: 0.98, alpha: 1.0)
#else
    let tint = UIColor(red: 0.39, green: 0.68, blue: 0.98, alpha: 1.0)
#endif
    material.baseColor = .init(tint: tint)
    material.roughness = .init(floatLiteral: 0.28)
    material.metallic = .init(floatLiteral: 0.08)
    return material
}

private func makeDirectionalLight() -> Entity {
    let light = Entity()
    var component = DirectionalLightComponent()
    component.color = .white
    component.intensity = 3200
    light.components.set(component)
    light.look(at: .zero, from: SIMD3(3.2, 5.2, 4.1), relativeTo: nil)
    return light
}

private func makeAmbientLight() -> Entity {
    let light = Entity()
    var component = DirectionalLightComponent()
    component.color = .init(red: 0.66, green: 0.76, blue: 0.96, alpha: 1.0)
    component.intensity = 480
    light.components.set(component)
    light.look(at: .zero, from: SIMD3(-2.4, -1.2, -3.4), relativeTo: nil)
    return light
}

private func makeFillLight() -> Entity {
    let light = Entity()
    var component = DirectionalLightComponent()
    component.color = .init(red: 1.0, green: 0.86, blue: 0.72, alpha: 1.0)
    component.intensity = 720
    light.components.set(component)
    light.look(at: .zero, from: SIMD3(-3.0, 2.2, 2.6), relativeTo: nil)
    return light
}

#if os(macOS)
import AppKit

private extension View {
    func onScrollWheel(perform action: @escaping (NSEvent) -> Void) -> some View {
        background(ScrollWheelReader(action: action))
    }
}

private struct ScrollWheelReader: NSViewRepresentable {
    let action: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScrollCaptureView {
        ScrollCaptureView(action: action)
    }

    func updateNSView(_ nsView: ScrollCaptureView, context: Context) {
        nsView.action = action
    }

    final class ScrollCaptureView: NSView {
        var action: (NSEvent) -> Void
        private var monitor: Any?

        init(action: @escaping (NSEvent) -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self, event.window === self.window else { return event }
                    self.action(event)
                    return event
                }
            } else {
                removeMonitor()
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
#endif
