//
//  ContentView.swift
//  MorphoVu
//
//  Created by Sinan Karasu on 3/30/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            MorphoWorkbenchRootView()
                .tabItem {
                    Label("Workbench", systemImage: "cube.transparent")
                }

            LispPadDevRootView()
                .tabItem {
                    Label("Runtime Lab", systemImage: "terminal")
                }
        }
        .tint(MorphoTheme.accent)
    }
}

#Preview {
    ContentView()
        .environment(MorphoWorkbenchState())
}
