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

            KeyboardLabView()
                .tabItem {
                    Label("Keyboard Lab", systemImage: "keyboard")
                }

            PythonWorkbenchView()
                .tabItem {
                    Label("Python", systemImage: "chevron.left.slash.chevron.right")
                }

            CSymExperimentView()
                .tabItem {
                    Label("CSym", systemImage: "function")
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
