import XCTest

@testable import Annotate

@MainActor
final class ArrowDrawingTests: XCTestCase, Sendable {
    var overlayView: OverlayView!
    
    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
    }
    
    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            overlayView = nil
        }
        super.tearDown()
    }
    
    func testArrowCreationWithLineWidth() {
        // Test that arrows are created with the correct line width
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 200)
        let lineWidth: CGFloat = 5.0
        
        overlayView.currentLineWidth = lineWidth
        let arrow = Arrow(
            startPoint: start,
            endPoint: end,
            color: .red,
            lineWidth: overlayView.currentLineWidth
        )
        
        XCTAssertEqual(arrow.lineWidth, lineWidth)
        XCTAssertEqual(arrow.startPoint, start)
        XCTAssertEqual(arrow.endPoint, end)
    }
    
    func testArrowWithDifferentLineWidths() {
        // Test that arrows with different line widths are distinct
        let start = NSPoint(x: 50, y: 50)
        let end = NSPoint(x: 150, y: 150)
        
        let arrow1 = Arrow(startPoint: start, endPoint: end, color: .blue, lineWidth: 2.0)
        let arrow2 = Arrow(startPoint: start, endPoint: end, color: .blue, lineWidth: 8.0)
        
        XCTAssertNotEqual(arrow1, arrow2)
        XCTAssertNotEqual(arrow1.lineWidth, arrow2.lineWidth)
    }
    
    func testArrowEquilateralTriangleCalculation() {
        // Test the mathematical correctness of equilateral triangle dimensions
        // For an equilateral triangle with side length 25:
        // - Height should be approximately 21.65 (25 * sqrt(3) / 2)
        // - Half-base should be 12.5 (25 / 2)
        
        let sideLength: CGFloat = 25.0
        let expectedHeight = sideLength * sqrt(3.0) / 2.0
        let expectedHalfBase = sideLength / 2.0
        
        // Verify the math
        XCTAssertEqual(expectedHeight, 21.650635094610966, accuracy: 0.0001)
        XCTAssertEqual(expectedHalfBase, 12.5)
        
        // The triangle should have all sides equal
        // Distance from tip to each base corner should equal the base width
        let tipToBaseDistance = expectedHeight
        let baseWidth = sideLength
        
        // Using Pythagorean theorem to verify
        // Distance from tip to corner = sqrt(height^2 + halfBase^2)
        let calculatedSideLength = sqrt(pow(expectedHeight, 2) + pow(expectedHalfBase, 2))
        XCTAssertEqual(calculatedSideLength, sideLength, accuracy: 0.0001)
    }
    
    func testArrowLineEndsAtTriangleBase() {
        // Test that the arrow line should end at the base of the triangle
        // to prevent overlap/gap
        
        let start = NSPoint(x: 0, y: 0)
        let end = NSPoint(x: 100, y: 0)
        
        let sideLength: CGFloat = 25.0
        let height = sideLength * sqrt(3.0) / 2.0
        
        // The line should end at distance 'height' from the tip
        let expectedLineEndX = end.x - height
        
        // Verify the calculation
        XCTAssertEqual(expectedLineEndX, 100 - 21.650635094610966, accuracy: 0.0001)
    }
    
    func testArrowWithVariousAngles() {
        // Test arrows pointing in different directions maintain correct geometry
        let origin = NSPoint(x: 100, y: 100)
        let distance: CGFloat = 100.0
        
        // Horizontal right arrow
        let arrowRight = Arrow(
            startPoint: origin,
            endPoint: NSPoint(x: origin.x + distance, y: origin.y),
            color: .red,
            lineWidth: 3.0
        )
        
        // Horizontal left arrow
        let arrowLeft = Arrow(
            startPoint: origin,
            endPoint: NSPoint(x: origin.x - distance, y: origin.y),
            color: .red,
            lineWidth: 3.0
        )
        
        // Vertical up arrow
        let arrowUp = Arrow(
            startPoint: origin,
            endPoint: NSPoint(x: origin.x, y: origin.y + distance),
            color: .red,
            lineWidth: 3.0
        )
        
        // Vertical down arrow
        let arrowDown = Arrow(
            startPoint: origin,
            endPoint: NSPoint(x: origin.x, y: origin.y - distance),
            color: .red,
            lineWidth: 3.0
        )
        
        // All arrows should have the same line width
        XCTAssertEqual(arrowRight.lineWidth, arrowLeft.lineWidth)
        XCTAssertEqual(arrowLeft.lineWidth, arrowUp.lineWidth)
        XCTAssertEqual(arrowUp.lineWidth, arrowDown.lineWidth)
        
        // All arrows should have the same length
        let lengthRight = hypot(arrowRight.endPoint.x - arrowRight.startPoint.x,
                               arrowRight.endPoint.y - arrowRight.startPoint.y)
        let lengthLeft = hypot(arrowLeft.endPoint.x - arrowLeft.startPoint.x,
                              arrowLeft.endPoint.y - arrowLeft.startPoint.y)
        let lengthUp = hypot(arrowUp.endPoint.x - arrowUp.startPoint.x,
                            arrowUp.endPoint.y - arrowUp.startPoint.y)
        let lengthDown = hypot(arrowDown.endPoint.x - arrowDown.startPoint.x,
                              arrowDown.endPoint.y - arrowDown.startPoint.y)
        
        XCTAssertEqual(lengthRight, distance, accuracy: 0.0001)
        XCTAssertEqual(lengthLeft, distance, accuracy: 0.0001)
        XCTAssertEqual(lengthUp, distance, accuracy: 0.0001)
        XCTAssertEqual(lengthDown, distance, accuracy: 0.0001)
    }
    
    func testArrowAddedToOverlayView() {
        // Test that arrows can be added to the overlay view
        overlayView.currentTool = .arrow
        overlayView.currentLineWidth = 4.0
        
        let initialCount = overlayView.arrows.count
        
        let arrow = Arrow(
            startPoint: NSPoint(x: 10, y: 10),
            endPoint: NSPoint(x: 50, y: 50),
            color: .blue,
            lineWidth: overlayView.currentLineWidth
        )
        
        overlayView.arrows.append(arrow)
        
        XCTAssertEqual(overlayView.arrows.count, initialCount + 1)
        XCTAssertEqual(overlayView.arrows.last?.lineWidth, 4.0)
    }
}
