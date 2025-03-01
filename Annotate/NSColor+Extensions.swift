import SwiftUI

extension NSColor {
    /// Returns a contrasting color (black or white) based on the brightness of the original color
    /// - Returns: White for dark colors, black for light colors
    func contrastingColor() -> NSColor {
        guard let rgbColor = self.usingColorSpace(.sRGB) else {
            return .white
        }

        // Calculate luminance to determine if color is light or dark
        // based on standard coefficients from the WCAG 2.0 specification
        let luminance =
            0.2126 * rgbColor.redComponent + 0.7152 * rgbColor.greenComponent + 0.0722
            * rgbColor.blueComponent

        return luminance < 0.6 ? .white : .black
    }
}
