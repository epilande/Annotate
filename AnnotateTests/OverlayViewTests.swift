import XCTest

@testable import Annotate

@MainActor
final class OverlayViewTests: XCTestCase, Sendable {
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
        overlayView.paths = [DrawingPath(points: [], color: .red, lineWidth: 3.0)]
        overlayView.arrows = [Arrow(startPoint: .zero, endPoint: .zero, color: .blue, lineWidth: 3.0)]
        overlayView.lines = [Line(startPoint: .zero, endPoint: .zero, color: .red, lineWidth: 3.0)]
        overlayView.highlightPaths = [DrawingPath(points: [], color: .yellow, lineWidth: 3.0)]
        overlayView.rectangles = [Rectangle(startPoint: .zero, endPoint: .zero, color: .green, lineWidth: 3.0)]
        overlayView.circles = [Circle(startPoint: .zero, endPoint: .zero, color: .purple, lineWidth: 3.0)]
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
        let line = Line(startPoint: startPoint, endPoint: endPoint, color: .systemBlue, lineWidth: 3.0)
        
        // Add it to the view
        overlayView.lines.append(line)
        
        // Verify line was added
        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.lines[0].startPoint, startPoint)
        XCTAssertEqual(overlayView.lines[0].endPoint, endPoint)
        XCTAssertEqual(overlayView.lines[0].color, .systemBlue)
        XCTAssertEqual(overlayView.lines[0].lineWidth, 3.0)
        
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
            lineWidth: 3.0,
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
            lineWidth: 3.0,
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

    func testResetCounter() {
        overlayView.nextCounterNumber = 5
        overlayView.counterAnnotations = [
            CounterAnnotation(number: 1, position: .zero, color: .blue)
        ]

        overlayView.resetCounter()

        XCTAssertEqual(overlayView.nextCounterNumber, 1)
        XCTAssertEqual(overlayView.counterAnnotations.count, 1, "Existing counters should remain")
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

    // MARK: - Cursor Tests

    func testCursorIsIBeamInTextModeWithoutActiveTextField() {
        overlayView.currentTool = .text
        overlayView.activeTextField = nil

        XCTAssertEqual(overlayView.currentTool, .text)
        XCTAssertNil(overlayView.activeTextField)

        let shouldShowIBeam = overlayView.currentTool == .text && overlayView.activeTextField == nil
        XCTAssertTrue(shouldShowIBeam, "Should show I-beam cursor in text mode without active text field")
    }

    func testCursorIsNotIBeamWhenTextFieldIsActive() {
        overlayView.currentTool = .text
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "", width: 100)

        XCTAssertEqual(overlayView.currentTool, .text)
        XCTAssertNotNil(overlayView.activeTextField)

        let shouldShowIBeam = overlayView.currentTool == .text && overlayView.activeTextField == nil
        XCTAssertFalse(shouldShowIBeam, "Should not show I-beam cursor when text field is active")

        overlayView.activeTextField?.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    // MARK: - Text Field Positioning Tests

    func testCreateTextFieldForNewTextCentersVertically() {
        let clickPoint = NSPoint(x: 200, y: 300)
        overlayView.createTextField(at: clickPoint, withText: "", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        // For new text, Y offset should be -16 (half of 32px height) to center at click
        // X offset is -8 for left padding
        XCTAssertEqual(textField.frame.origin.x, clickPoint.x - 8, "X should offset by left padding")
        XCTAssertEqual(textField.frame.origin.y, clickPoint.y - 16, "Y should center text field at click point")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testCreateTextFieldForEditingAlignWithStoredPosition() {
        let storedPosition = NSPoint(x: 200, y: 300)
        overlayView.createTextField(at: storedPosition, withText: "Existing text", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        // For editing, Y offset should be -4 (top padding only) to align with drawn text
        // X offset is -8 for left padding
        XCTAssertEqual(textField.frame.origin.x, storedPosition.x - 8, "X should offset by left padding")
        XCTAssertEqual(textField.frame.origin.y, storedPosition.y - 4, "Y should offset by top padding for editing")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testFinalizeTextAnnotationAccountsForPadding() {
        let clickPoint = NSPoint(x: 200, y: 300)
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .red, fontSize: 18
        )
        overlayView.createTextField(at: clickPoint, withText: "", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        textField.stringValue = "Test text"
        overlayView.finalizeTextAnnotation(textField)

        XCTAssertEqual(overlayView.textAnnotations.count, 1, "Should have one text annotation")

        let annotation = overlayView.textAnnotations[0]
        // Finalized position should account for padding: frame.origin + (8, 4)
        let expectedX = clickPoint.x - 8 + 8  // -8 for field offset, +8 for padding = clickPoint.x
        let expectedY = clickPoint.y - 16 + 4  // -16 for field offset, +4 for padding
        XCTAssertEqual(annotation.position.x, expectedX, accuracy: 0.01, "Position X should account for padding")
        XCTAssertEqual(annotation.position.y, expectedY, accuracy: 0.01, "Position Y should account for padding")
    }
}
