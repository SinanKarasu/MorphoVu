import SwiftUI

extension View {
    @ViewBuilder
    func pythonTextInputTraits() -> some View {
        #if os(macOS)
        self
        #else
        self
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
        #endif
    }

    @ViewBuilder
    func hidesEditorScrollBackgroundWhenSupported() -> some View {
        #if os(macOS)
        self
        #else
        self.scrollContentBackground(.hidden)
        #endif
    }
}
