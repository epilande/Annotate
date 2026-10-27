import SwiftUI

extension NSColor {
    /// Returns a contrasting color (black or white) based on the brightness of the original color
    /// - Returns: White for dark colors, black for light colors
    func contrastingColor() -> NSColor {
        luminance < 0.6 ? .white : .black
    }

    /// Brightness from 0 (black) to 1 (white), weighting the sRGB components by the standard
    /// coefficients from the WCAG 2.0 specification. A color that can't be converted to sRGB
    /// reads as 0, so it is treated as dark.
    var luminance: CGFloat {
        guard let rgbColor = self.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * rgbColor.redComponent + 0.7152 * rgbColor.greenComponent
            + 0.0722 * rgbColor.blueComponent
    }

    /// Compares two colors for approximate equality within a small tolerance
    func isClose(to other: NSColor) -> Bool {
        guard let c1 = self.usingColorSpace(.deviceRGB),
            let c2 = other.usingColorSpace(.deviceRGB)
        else { return false }
        return abs(c1.redComponent - c2.redComponent) < 0.01
            && abs(c1.greenComponent - c2.greenComponent) < 0.01
            && abs(c1.blueComponent - c2.blueComponent) < 0.01
    }
}
