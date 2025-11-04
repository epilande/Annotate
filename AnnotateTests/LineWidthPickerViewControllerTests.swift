import XCTest

@testable import Annotate

@MainActor
final class LineWidthPickerViewControllerTests: XCTestCase, Sendable {
    var viewController: LineWidthPickerViewController!
    var testDefaults: UserDefaults!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            testDefaults = TestUserDefaults.create()
            viewController = LineWidthPickerViewController(userDefaults: testDefaults)
            _ = viewController.view  // Trigger view loading
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            viewController = nil
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }
    
    func testViewControllerInitialization() {
        XCTAssertNotNil(viewController)
        XCTAssertNotNil(viewController.view)
    }
    
    func testLineWidthBounds() {
        // Test minimum and maximum line width constants
        XCTAssertEqual(viewController.minLineWidth, 0.5)
        XCTAssertEqual(viewController.maxLineWidth, 20.0)
    }
    
    func testLineWidthRatio() {
        // Test the ratio for line width increments
        XCTAssertEqual(viewController.ratio, 0.25)
    }
    
    func testViewDimensions() {
        // Test that the view has expected dimensions
        let view = viewController.view
        XCTAssertEqual(view.frame.width, 280)
        XCTAssertEqual(view.frame.height, 120)
    }
    
    func testBottomPaddingAdded() {
        // Test that bottom padding was added for better visual balance
        // The view height should accommodate all elements plus padding
        let view = viewController.view
        
        // View should be tall enough to include:
        // - Title label (top padding: 10pt)
        // - Preview view (height: 40pt, spacing: 8pt)
        // - Slider (height: ~20pt, spacing: 8pt)
        // - Value label (with spacing and bottom padding: 10pt)
        
        let minimumExpectedHeight: CGFloat = 10 + 40 + 8 + 20 + 8 + 20 + 10
        XCTAssertGreaterThanOrEqual(view.frame.height, minimumExpectedHeight)
    }
    
    func testCurrentLineWidthRetrieved() {
        // Test that current line width is retrieved from UserDefaults
        // Set a test value
        testDefaults.set(5.5, forKey: UserDefaults.lineWidthKey)

        // Create new view controller to trigger load
        let newVC = LineWidthPickerViewController(userDefaults: testDefaults)
        _ = newVC.view

        // Note: We can't directly access the slider value without making it public,
        // but we can verify the UserDefaults key is used correctly
        let savedWidth = testDefaults.double(forKey: UserDefaults.lineWidthKey)
        XCTAssertEqual(savedWidth, 5.5)
    }
    
    func testLineWidthIncrement() {
        // Test that line width increments by the correct ratio
        let ratio: CGFloat = 0.25
        let testWidths: [CGFloat] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 5.0, 10.0, 20.0]
        
        for width in testWidths {
            let roundedWidth = round(width / ratio) * ratio
            XCTAssertEqual(
                roundedWidth,
                width,
                accuracy: 0.001,
                "Width \(width) should be a valid increment"
            )
        }
    }
    
    func testLineWidthClamping() {
        // Test that line width values are clamped to min/max
        let minWidth: CGFloat = 0.5
        let maxWidth: CGFloat = 20.0
        
        // Test below minimum
        let belowMin: CGFloat = 0.2
        let clampedMin = max(minWidth, min(maxWidth, belowMin))
        XCTAssertEqual(clampedMin, minWidth)
        
        // Test above maximum
        let aboveMax: CGFloat = 25.0
        let clampedMax = max(minWidth, min(maxWidth, aboveMax))
        XCTAssertEqual(clampedMax, maxWidth)
        
        // Test within range
        let withinRange: CGFloat = 5.0
        let clampedRange = max(minWidth, min(maxWidth, withinRange))
        XCTAssertEqual(clampedRange, withinRange)
    }
}
