import SwiftUI

enum LabTheme {
    struct Palette {
        let ink: Color
        let secondaryInk: Color
        let accent: Color
        let accentStrong: Color
        let accentSoft: Color
        let shellStart: Color
        let shellEnd: Color
        let panel: Color
        let panelElevated: Color
        let panelTint: Color
        let panelStroke: Color
        let panelTintStroke: Color
        let keyFill: Color
        let fixedKeyFill: Color
        let fixedKeyStroke: Color
        let keyBorder: Color
        let deadKeyFill: Color
        let deadKeyBorder: Color
        let outputPanel: Color
        let outputInk: Color
        let softShadow: Color
    }

    static func palette(for colorScheme: ColorScheme) -> Palette {
        switch colorScheme {
        case .dark:
            Palette(
                ink: Color(red: 0.95, green: 0.97, blue: 0.99),
                secondaryInk: Color(red: 0.66, green: 0.72, blue: 0.81),
                accent: Color(red: 0.28, green: 0.76, blue: 0.72),
                accentStrong: Color(red: 0.62, green: 0.95, blue: 0.89),
                accentSoft: Color(red: 0.11, green: 0.25, blue: 0.23),
                shellStart: Color(red: 0.05, green: 0.07, blue: 0.11),
                shellEnd: Color(red: 0.02, green: 0.04, blue: 0.07),
                panel: Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.94),
                panelElevated: Color(red: 0.11, green: 0.13, blue: 0.18).opacity(0.97),
                panelTint: Color(red: 0.10, green: 0.12, blue: 0.17).opacity(0.96),
                panelStroke: Color.white.opacity(0.10),
                panelTintStroke: Color.white.opacity(0.08),
                keyFill: Color(red: 0.14, green: 0.16, blue: 0.22).opacity(0.98),
                fixedKeyFill: Color(red: 0.20, green: 0.22, blue: 0.28),
                fixedKeyStroke: Color.white.opacity(0.12),
                keyBorder: Color.white.opacity(0.14),
                deadKeyFill: Color(red: 0.40, green: 0.25, blue: 0.10).opacity(0.95),
                deadKeyBorder: Color(red: 0.95, green: 0.67, blue: 0.31),
                outputPanel: Color(red: 0.04, green: 0.05, blue: 0.09).opacity(0.98),
                outputInk: Color(red: 0.91, green: 0.94, blue: 0.99),
                softShadow: Color.black.opacity(0.36)
            )
        default:
            Palette(
                ink: Color(red: 0.17, green: 0.16, blue: 0.14),
                secondaryInk: Color(red: 0.38, green: 0.35, blue: 0.31),
                accent: Color(red: 0.09, green: 0.47, blue: 0.43),
                accentStrong: Color(red: 0.03, green: 0.34, blue: 0.31),
                accentSoft: Color(red: 0.78, green: 0.90, blue: 0.86),
                shellStart: Color(red: 0.94, green: 0.90, blue: 0.82),
                shellEnd: Color(red: 0.78, green: 0.85, blue: 0.89),
                panel: Color(red: 0.98, green: 0.97, blue: 0.95).opacity(0.96),
                panelElevated: Color.white.opacity(0.95),
                panelTint: Color(red: 0.92, green: 0.94, blue: 0.96).opacity(0.96),
                panelStroke: Color.white.opacity(0.55),
                panelTintStroke: Color.white.opacity(0.45),
                keyFill: Color(red: 0.99, green: 0.98, blue: 0.96).opacity(0.98),
                fixedKeyFill: Color(red: 0.84, green: 0.81, blue: 0.76),
                fixedKeyStroke: Color.white.opacity(0.35),
                keyBorder: Color.black.opacity(0.16),
                deadKeyFill: Color(red: 0.97, green: 0.82, blue: 0.66),
                deadKeyBorder: Color(red: 0.78, green: 0.48, blue: 0.19),
                outputPanel: Color(red: 0.21, green: 0.24, blue: 0.29).opacity(0.96),
                outputInk: Color(red: 0.95, green: 0.96, blue: 0.98),
                softShadow: Color.black.opacity(0.09)
            )
        }
    }
}
