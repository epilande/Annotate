import XCTest

@testable import Annotate

@MainActor
final class ColorPickerViewControllerTests: XCTestCase, Sendable {
    var colorPicker: ColorPickerViewController!
    var mockAppDelegate: MockAppDelegate!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            colorPicker = ColorPickerViewController()
            mockAppDelegate = MockAppDelegate()
            AppDelegate.shared = mockAppDelegate

            _ = colorPicker.view
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            colorPicker = nil
            mockAppDelegate = nil
            AppDelegate.shared = nil
        }
        super.tearDown()
    }

    func testColorPaletteInitialization() {
        XCTAssertEqual(colorPalette.count, 9)
        XCTAssertEqual(colorPalette[0], .systemRed)
        XCTAssertEqual(colorPalette[1], .systemOrange)
        XCTAssertEqual(colorPalette[2], .systemYellow)
        XCTAssertEqual(colorPalette[3], .systemGreen)
        XCTAssertEqual(colorPalette[4], .cyan)
        XCTAssertEqual(colorPalette[5], .systemIndigo)
        XCTAssertEqual(colorPalette[6], .magenta)
        XCTAssertEqual(colorPalette[7], .white)
        XCTAssertEqual(colorPalette[8], .black)
    }

    func testViewSetup() {
        // Verify container view setup
        XCTAssertEqual(colorPicker.view.frame.size, NSSize(width: 150, height: 100))

        // Find the main vertical stack view
        let mainStackView = colorPicker.view.subviews.first as? NSStackView
        XCTAssertNotNil(mainStackView)
        XCTAssertEqual(mainStackView?.orientation, .vertical)
        XCTAssertEqual(mainStackView?.alignment, .leading)
        XCTAssertEqual(mainStackView?.distribution, .fillEqually)

        // Check row stack views
        let rowStackViews = mainStackView?.arrangedSubviews.compactMap { $0 as? NSStackView }
        XCTAssertEqual(rowStackViews?.count, 3)  // Should have 3 rows

        // Check color swatch buttons
        var totalButtons = 0
        rowStackViews?.forEach { stackView in
            let buttons = stackView.arrangedSubviews.compactMap { $0 as? ColorSwatchButton }
            totalButtons += buttons.count
        }
        XCTAssertEqual(totalButtons, colorPalette.count)
    }

    func testColorSelection() {
        // Find the main stack view
        guard let mainStackView = colorPicker.view.subviews.first as? NSStackView,
            let firstRowStack = mainStackView.arrangedSubviews.first as? NSStackView,
            let firstButton = firstRowStack.arrangedSubviews.first as? ColorSwatchButton
        else {
            XCTFail("Failed to find first color swatch button")
            return
        }

        // Verify button color
        XCTAssertEqual(firstButton.swatchColor, .systemRed)

        // Simulate button click
        colorPicker.colorSwatchClicked(firstButton)

        // Verify color was updated in AppDelegate
        XCTAssertEqual(mockAppDelegate.currentColor, .systemRed)
        XCTAssertTrue(mockAppDelegate.updateStatusBarIconCalled)
    }
}

// Mock AppDelegate for testing
class MockAppDelegate: AppDelegate {
    var updateStatusBarIconCalled = false
    override var currentColor: NSColor {
        didSet {
            // Track color changes
        }
    }

    override func updateStatusBarIcon(with color: NSColor) {
        updateStatusBarIconCalled = true
        currentColor = color
    }
}
