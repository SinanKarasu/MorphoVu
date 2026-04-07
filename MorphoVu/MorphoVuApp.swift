//
//  MorphoVuApp.swift
//  MorphoVu
//
//  Created by Sinan Karasu on 3/30/26.
//

import SwiftUI

enum MorphoSceneWindowID {
    static let scene3D = "scene3d"
}

@main
struct MorphoVuApp: App {
    @State private var workbenchState = MorphoWorkbenchState()

    var body: some Scene {
        WindowGroup("MorphoVu") {
            ContentView()
                .environment(workbenchState)
        }
#if os(macOS)
        .defaultSize(width: 1240, height: 820)
#endif

#if os(visionOS)
        WindowGroup("3-D Scene", id: MorphoSceneWindowID.scene3D) {
            MorphoSceneWindowView()
                .environment(workbenchState)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.75, height: 0.75, depth: 0.75, in: .meters)
#endif
    }
}
