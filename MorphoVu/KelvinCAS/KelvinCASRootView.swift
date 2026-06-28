//
//  KelvinCASRootView.swift
//  MorphoVu
//
//  Created by Codex on 6/28/26.
//

import SwiftUI
import KelvinGUI

struct KelvinCASRootView: View {
    @State private var vm = KelvinViewModel()

    var body: some View {
        KelvinMasterView()
            .environment(vm)
#if os(macOS)
            .frame(minWidth: 900, minHeight: 600)
#endif
    }
}

#Preview {
    KelvinCASRootView()
}

