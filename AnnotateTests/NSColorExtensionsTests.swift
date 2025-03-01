import XCTest

@testable import Annotate

final class NSColorExtensionsTests: XCTestCase {

    // Test that dark colors return white as the contrasting color
    func testDarkColorsReturnWhiteContrast() {
        let darkColors: [NSColor] = [
            .black,
            .systemBlue,
            .systemIndigo,
            .systemPurple,
            .systemRed,
            .darkGray,
            NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
        ]

        for color in darkColors {
            let contrastingColor = color.contrastingColor()
            XCTAssertEqual(
                contrastingColor, .white, "Dark color \(color) should return white as contrast")
        }
    }

    // Test that light colors return black as the contrasting color
    func testLightColorsReturnBlackContrast() {
        let lightColors: [NSColor] = [
            .white,
            .systemYellow,
            .systemOrange,
            .lightGray,
            NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),
        ]

        for color in lightColors {
            let contrastingColor = color.contrastingColor()
            XCTAssertEqual(
                contrastingColor, .black, "Light color \(color) should return black as contrast")
        }
    }

    // Test colors near the threshold (0.6 luminance)
    func testBorderlineColors() {
        let justBelowThreshold = NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        XCTAssertEqual(justBelowThreshold.contrastingColor(), .white)

        let justAboveThreshold = NSColor(calibratedRed: 0.7, green: 0.7, blue: 0.7, alpha: 1.0)
        XCTAssertEqual(justAboveThreshold.contrastingColor(), .black)
    }

    // Test that colors with different alpha values still calculate correct contrast
    func testColorsWithAlpha() {
        let transparentBlack = NSColor.black.withAlphaComponent(0.5)
        let transparentWhite = NSColor.white.withAlphaComponent(0.5)

        // Alpha shouldn't affect the luminance calculation for contrast
        XCTAssertEqual(transparentBlack.contrastingColor(), .white)
        XCTAssertEqual(transparentWhite.contrastingColor(), .black)
    }

    // Test that non-RGB color spaces are handled correctly
    func testNonRGBColorSpaces() {
        // Create a color in a different color space
        let hsbColor = NSColor(hue: 0.5, saturation: 0.8, brightness: 0.3, alpha: 1.0)

        // Should not crash and should return a valid contrasting color
        XCTAssertNoThrow(hsbColor.contrastingColor())
        XCTAssertNotNil(hsbColor.contrastingColor())
    }
}
