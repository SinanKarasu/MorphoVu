import SwiftUI

enum MorphoTheme {
    static let accent = Color(red: 0.37, green: 0.78, blue: 1.0)

    struct Palette {
        let shellTop: Color
        let shellBottom: Color
        let panel: Color
        let panelTint: Color
        let panelStroke: Color
        let panelTintStroke: Color
        let outputPanel: Color
        let sceneTop: Color
        let sceneBottom: Color
        let ink: Color
        let secondaryInk: Color
        let outputInk: Color
        let shadow: Color
    }

    static func palette(for colorScheme: ColorScheme) -> Palette {
        switch colorScheme {
        case .dark:
            Palette(
                shellTop: Color(red: 0.05, green: 0.07, blue: 0.12),
                shellBottom: Color(red: 0.02, green: 0.03, blue: 0.06),
                panel: Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.94),
                panelTint: Color(red: 0.11, green: 0.13, blue: 0.18).opacity(0.96),
                panelStroke: Color.white.opacity(0.10),
                panelTintStroke: Color.white.opacity(0.08),
                outputPanel: Color(red: 0.03, green: 0.05, blue: 0.08),
                sceneTop: Color(red: 0.03, green: 0.05, blue: 0.09),
                sceneBottom: Color(red: 0.07, green: 0.10, blue: 0.16),
                ink: Color(red: 0.95, green: 0.97, blue: 0.99),
                secondaryInk: Color(red: 0.62, green: 0.69, blue: 0.79),
                outputInk: Color(red: 0.88, green: 0.92, blue: 0.99),
                shadow: Color.black.opacity(0.34)
            )
        default:
            Palette(
                shellTop: Color(red: 0.93, green: 0.95, blue: 0.98),
                shellBottom: Color(red: 0.84, green: 0.88, blue: 0.93),
                panel: Color.white.opacity(0.9),
                panelTint: Color.white.opacity(0.72),
                panelStroke: Color.white.opacity(0.55),
                panelTintStroke: Color.white.opacity(0.45),
                outputPanel: Color(red: 0.12, green: 0.15, blue: 0.21),
                sceneTop: Color(red: 0.08, green: 0.11, blue: 0.16),
                sceneBottom: Color(red: 0.14, green: 0.18, blue: 0.24),
                ink: Color(red: 0.12, green: 0.14, blue: 0.19),
                secondaryInk: Color(red: 0.34, green: 0.39, blue: 0.47),
                outputInk: Color(red: 0.87, green: 0.91, blue: 0.98),
                shadow: Color.black.opacity(0.12)
            )
        }
    }
}
