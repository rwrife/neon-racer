import Foundation

struct RGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var relativeLuminance: Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red)
            + 0.7152 * linearize(green)
            + 0.0722 * linearize(blue)
    }

    func contrastRatio(with other: RGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

struct PaletteComponents: Equatable, Sendable {
    let background: RGBColor
    let panel: RGBColor
    let primary: RGBColor
    let secondary: RGBColor
    let text: RGBColor
    let warning: RGBColor

    static func resolve(_ choice: AccessibilityPalette, highContrast: Bool) -> Self {
        let background = highContrast
            ? RGBColor(red: 0, green: 0, blue: 0)
            : RGBColor(red: 0.015, green: 0.005, blue: 0.06)
        let panel = highContrast
            ? RGBColor(red: 0.04, green: 0.04, blue: 0.06)
            : RGBColor(red: 0.10, green: 0.02, blue: 0.18)

        switch choice {
        case .neon:
            return Self(
                background: background,
                panel: panel,
                primary: RGBColor(red: 0, green: 0.95, blue: 1),
                secondary: RGBColor(red: 1, green: 0.12, blue: 0.55),
                text: RGBColor(red: 1, green: 1, blue: 1),
                warning: RGBColor(red: 1, green: 0.72, blue: 0.12)
            )
        case .blueOrange:
            return Self(
                background: background,
                panel: panel,
                primary: RGBColor(red: 0.30, green: 0.78, blue: 1),
                secondary: RGBColor(red: 1, green: 0.58, blue: 0.16),
                text: RGBColor(red: 1, green: 1, blue: 1),
                warning: RGBColor(red: 1, green: 0.82, blue: 0.28)
            )
        case .magentaGreen:
            return Self(
                background: background,
                panel: panel,
                primary: RGBColor(red: 0.38, green: 1, blue: 0.56),
                secondary: RGBColor(red: 1, green: 0.32, blue: 0.78),
                text: RGBColor(red: 1, green: 1, blue: 1),
                warning: RGBColor(red: 1, green: 0.78, blue: 0.18)
            )
        }
    }
}
