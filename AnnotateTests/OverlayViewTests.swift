import XCTest

@testable import Annotate

final class OverlayViewTests: XCTestCase {

    var overlayView: OverlayView!

    override func setUp() {
        super.setUp()
        overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    override func tearDown() {
        overlayView = nil
        super.tearDown()
    }

    func testOverlayViewInitialization() {
        XCTAssertEqual(overlayView.currentColor, .systemRed)
        XCTAssertEqual(overlayView.currentTool, .pen)
        XCTAssertTrue(overlayView.fadeMode)
        XCTAssertEqual(overlayView.fadeDuration, 1.25)

        // Test empty collections
        XCTAssertTrue(overlayView.paths.isEmpty)
        XCTAssertTrue(overlayView.arrows.isEmpty)
        XCTAssertTrue(overlayView.lines.isEmpty)
        XCTAssertTrue(overlayView.highlightPaths.isEmpty)
        XCTAssertTrue(overlayView.rectangles.isEmpty)
        XCTAssertTrue(overlayView.circles.isEmpty)
        XCTAssertTrue(overlayView.textAnnotations.isEmpty)

        // Test nil values
        XCTAssertNil(overlayView.currentPath)
        XCTAssertNil(overlayView.currentArrow)
        XCTAssertNil(overlayView.currentLine)
        XCTAssertNil(overlayView.currentHighlight)
        XCTAssertNil(overlayView.currentRectangle)
        XCTAssertNil(overlayView.currentCircle)
        XCTAssertNil(overlayView.currentTextAnnotation)
    }

    func testToolSwitching() {
        // Test all tool types
        overlayView.currentTool = .pen
        XCTAssertEqual(overlayView.currentTool, .pen)

        overlayView.currentTool = .arrow
        XCTAssertEqual(overlayView.currentTool, .arrow)
        
        overlayView.currentTool = .line
        XCTAssertEqual(overlayView.currentTool, .line)

        overlayView.currentTool = .highlighter
        XCTAssertEqual(overlayView.currentTool, .highlighter)

        overlayView.currentTool = .rectangle
        XCTAssertEqual(overlayView.currentTool, .rectangle)

        overlayView.currentTool = .circle
        XCTAssertEqual(overlayView.currentTool, .circle)

        overlayView.currentTool = .text
        XCTAssertEqual(overlayView.currentTool, .text)
    }

    func testClearAll() {
        // Add some test data
        overlayView.paths = [DrawingPath(points: [], color: .red)]
        overlayView.arrows = [Arrow(startPoint: .zero, endPoint: .zero, color: .blue)]
        overlayView.lines = [Line(startPoint: .zero, endPoint: .zero, color: .red)]
        overlayView.highlightPaths = [DrawingPath(points: [], color: .yellow)]
        overlayView.rectangles = [Rectangle(startPoint: .zero, endPoint: .zero, color: .green)]
        overlayView.circles = [Circle(startPoint: .zero, endPoint: .zero, color: .purple)]
        overlayView.textAnnotations = [
            TextAnnotation(text: "Test", position: .zero, color: .black, fontSize: 12)
        ]

        // Clear all
        overlayView.clearAll()

        // Verify everything is cleared
        XCTAssertTrue(overlayView.paths.isEmpty)
        XCTAssertTrue(overlayView.arrows.isEmpty)
        XCTAssertTrue(overlayView.lines.isEmpty)
        XCTAssertTrue(overlayView.highlightPaths.isEmpty)
        XCTAssertTrue(overlayView.rectangles.isEmpty)
        XCTAssertTrue(overlayView.circles.isEmpty)
        XCTAssertTrue(overlayView.textAnnotations.isEmpty)
    }
    
    func testDrawLine() {
        // Create a new line
        let startPoint = NSPoint(x: 100, y: 100)
        let endPoint = NSPoint(x: 200, y: 200)
        let line = Line(startPoint: startPoint, endPoint: endPoint, color: .systemBlue)
        
        // Add it to the view
        overlayView.lines.append(line)
        
        // Verify line was added
        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.lines[0].startPoint, startPoint)
        XCTAssertEqual(overlayView.lines[0].endPoint, endPoint)
        XCTAssertEqual(overlayView.lines[0].color, .systemBlue)
        
        // Test delete last item when tool is line
        overlayView.currentTool = .line
        overlayView.deleteLastItem()
        XCTAssertTrue(overlayView.lines.isEmpty)
    }
    
    func testLineFade() {
        // Create a line with a creation time
        let now = CACurrentMediaTime()
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .systemBlue,
            creationTime: now
        )
        
        overlayView.lines.append(line)
        
        // Test line with recent creation time should be visible
        overlayView.fadeMode = true
        XCTAssertEqual(overlayView.lines.count, 1)
        
        // Add a line with an old creation time
        let oldLine = Line(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .systemRed,
            creationTime: now - 10.0 // Way beyond fade duration
        )
        
        overlayView.lines.append(oldLine)
        XCTAssertEqual(overlayView.lines.count, 2)
        
        // Note: We can't directly test the drawing behavior since it's done
        // in the draw method that interacts with the graphics context
    }

    func testCounterAnnotations() {
        XCTAssertTrue(overlayView.counterAnnotations.isEmpty)
        XCTAssertEqual(overlayView.nextCounterNumber, 1)

        let counter = CounterAnnotation(
            number: 1,
            position: NSPoint(x: 100, y: 100),
            color: .systemBlue
        )
        overlayView.counterAnnotations.append(counter)
        overlayView.nextCounterNumber = 2

        // Verify counter was added
        XCTAssertEqual(overlayView.counterAnnotations.count, 1)
        XCTAssertEqual(overlayView.counterAnnotations[0].number, 1)
        XCTAssertEqual(overlayView.nextCounterNumber, 2)

        // Test clearing counters
        overlayView.clearAll()
        XCTAssertTrue(overlayView.counterAnnotations.isEmpty)
        XCTAssertEqual(overlayView.nextCounterNumber, 1)
    }

    func testCounterToolSelection() {
        overlayView.currentTool = .counter
        XCTAssertEqual(overlayView.currentTool, .counter)
    }

    func testDeleteLastCounter() {
        // Add two counters
        let counter1 = CounterAnnotation(
            number: 1,
            position: NSPoint(x: 100, y: 100),
            color: .systemBlue
        )
        let counter2 = CounterAnnotation(
            number: 2,
            position: NSPoint(x: 200, y: 200),
            color: .systemRed
        )

        overlayView.counterAnnotations = [counter1, counter2]
        overlayView.nextCounterNumber = 3
        overlayView.currentTool = .counter

        // Delete last counter
        overlayView.deleteLastItem()

        // Verify only counter1 remains
        XCTAssertEqual(overlayView.counterAnnotations.count, 1)
        XCTAssertEqual(overlayView.counterAnnotations[0].number, 1)
        XCTAssertEqual(overlayView.nextCounterNumber, 2)
    }

    func testUpdateAdaptColors() {
        overlayView.updateAdaptColors(boardEnabled: true)
        XCTAssertTrue(
            overlayView.adaptColorsToBoardType, "adaptColorsToBoardType should be true when enabled"
        )

        overlayView.updateAdaptColors(boardEnabled: false)
        XCTAssertFalse(
            overlayView.adaptColorsToBoardType,
            "adaptColorsToBoardType should be false when disabled")
    }
}
