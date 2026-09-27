import SwiftUI

enum NeonPalette {
    static let midnight = Color(red: 0.015, green: 0.005, blue: 0.06)
    static let purple = Color(red: 0.31, green: 0.02, blue: 0.52)
    static let magenta = Color(red: 1, green: 0.03, blue: 0.48)
    static let cyan = Color(red: 0, green: 0.95, blue: 1)

    static func colors(for settings: AccessibilitySettings) -> PaletteComponents {
        .resolve(settings.palette, highContrast: settings.highContrast)
    }
}

extension RGBColor {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}
