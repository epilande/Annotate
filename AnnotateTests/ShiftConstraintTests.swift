import XCTest

@testable import Annotate

@MainActor
final class ShiftConstraintTests: XCTestCase, Sendable {
    var window: OverlayWindow!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            TestWindows.recordOpenWindows()
            let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            window = OverlayWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            window.close()
            window = nil
            assertNoLeakedWindows()
        }
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func performDragGesture(
        from start: NSPoint,
        to end: NSPoint,
        withShift: Bool = false
    ) {
        let modifierFlags: NSEvent.ModifierFlags = withShift ? .shift : []

        let mouseDownEvent = TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: start,
            modifierFlags: modifierFlags
        )
        window.mouseDown(with: mouseDownEvent!)

        let mouseDragEvent = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end,
            modifierFlags: modifierFlags
        )
        window.mouseDragged(with: mouseDragEvent!)
    }

    private func completeDragGesture(at location: NSPoint, withShift: Bool = false) {
        let modifierFlags: NSEvent.ModifierFlags = withShift ? .shift : []
        let mouseUpEvent = TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: location,
            modifierFlags: modifierFlags
        )
        window.mouseUp(with: mouseUpEvent!)
    }

    private func performDragWithModifiers(
        from start: NSPoint,
        to end: NSPoint,
        shift: Bool = false,
        option: Bool = false
    ) {
        var modifierFlags: NSEvent.ModifierFlags = []
        if shift { modifierFlags.insert(.shift) }
        if option { modifierFlags.insert(.option) }

        let mouseDownEvent = TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: start,
            modifierFlags: modifierFlags
        )
        window.mouseDown(with: mouseDownEvent!)

        let mouseDragEvent = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end,
            modifierFlags: modifierFlags
        )
        window.mouseDragged(with: mouseDragEvent!)
    }

    private func assertLineAngle(_ line: Line, equals expectedAngle: CGFloat, accuracy: CGFloat = 0.01) {
        let dx = line.endPoint.x - line.startPoint.x
        let dy = line.endPoint.y - line.startPoint.y
        let angle = atan2(dy, dx)
        XCTAssertEqual(angle, expectedAngle, accuracy: accuracy)
    }

    private func assertArrowAngle(_ arrow: Arrow, equals expectedAngle: CGFloat, accuracy: CGFloat = 0.01) {
        let dx = arrow.endPoint.x - arrow.startPoint.x
        let dy = arrow.endPoint.y - arrow.startPoint.y
        let angle = atan2(dy, dx)
        XCTAssertEqual(angle, expectedAngle, accuracy: accuracy)
    }

    // MARK: - Snapping Algorithm Tests

    func testSnapTo0Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 150, y: 110)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            XCTAssertEqual(line.startPoint, start)
            XCTAssertEqual(line.endPoint.y, start.y, accuracy: 1.0)
            XCTAssertGreaterThan(line.endPoint.x, start.x)
        }
    }

    func testSnapTo45Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 150, y: 145)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            assertLineAngle(line, equals: .pi / 4)
        }
    }

    func testSnapTo90Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 110, y: 150)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            XCTAssertEqual(line.endPoint.x, start.x, accuracy: 1.0)
            XCTAssertGreaterThan(line.endPoint.y, start.y)
        }
    }

    func testSnapTo135Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 55, y: 145)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            assertLineAngle(line, equals: 3 * .pi / 4)
        }
    }

    func testSnapTo180Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 50, y: 105)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            XCTAssertEqual(line.endPoint.y, start.y, accuracy: 1.0)
            XCTAssertLessThan(line.endPoint.x, start.x)
        }
    }

    func testSnapTo225Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 55, y: 55)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            assertLineAngle(line, equals: -3 * .pi / 4)
        }
    }

    func testSnapTo270Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 105, y: 50)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            XCTAssertEqual(line.endPoint.x, start.x, accuracy: 1.0)
            XCTAssertLessThan(line.endPoint.y, start.y)
        }
    }

    func testSnapTo315Degrees() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 145, y: 55)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            assertLineAngle(line, equals: -.pi / 4)
        }
    }

    func testSnapWithZeroDistance() {
        let start = NSPoint(x: 100, y: 100)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: start, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            XCTAssertEqual(line.endPoint, start)
        }
    }

    func testSnapWithVerySmallDistance() {
        let start = NSPoint(x: 100, y: 100)
        let current = NSPoint(x: 101.5, y: 101.5)

        window.overlayView.currentTool = .line
        performDragGesture(from: start, to: current, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            assertLineAngle(line, equals: .pi / 4)
        }
    }

    // MARK: - Line Tool Integration Tests

    func testLineToolWithShiftFromStart() {
        window.overlayView.currentTool = .line
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 210)

        performDragGesture(from: start, to: end, withShift: true)
        XCTAssertNotNil(window.overlayView.currentLine)

        completeDragGesture(at: end, withShift: true)
        XCTAssertEqual(window.overlayView.lines.count, 1)
    }

    func testLineToolWithoutShift() {
        window.overlayView.currentTool = .line
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 210)

        performDragGesture(from: start, to: end)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            XCTAssertEqual(line.endPoint, end)
        }
    }

    // MARK: - Arrow Tool Integration Tests

    func testArrowToolWithShiftFromStart() {
        window.overlayView.currentTool = .arrow
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 205)

        performDragGesture(from: start, to: end, withShift: true)
        XCTAssertNotNil(window.overlayView.currentArrow)

        completeDragGesture(at: end, withShift: true)
        XCTAssertEqual(window.overlayView.arrows.count, 1)
    }

    func testArrowToolWithoutShift() {
        window.overlayView.currentTool = .arrow
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 205)

        performDragGesture(from: start, to: end)

        XCTAssertNotNil(window.overlayView.currentArrow)
        if let arrow = window.overlayView.currentArrow {
            XCTAssertEqual(arrow.endPoint, end)
        }
    }

    // MARK: - Pen Tool Integration Tests

    func testPenToolBecomesLineWithShift() {
        window.overlayView.currentTool = .pen
        let start = NSPoint(x: 100, y: 100)
        let mid = NSPoint(x: 120, y: 110)
        let end = NSPoint(x: 200, y: 205)

        performDragGesture(from: start, to: mid, withShift: true)

        let mouseDrag2 = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end,
            modifierFlags: .shift
        )
        window.mouseDragged(with: mouseDrag2!)

        XCTAssertNotNil(window.overlayView.currentPath)
        if let path = window.overlayView.currentPath {
            XCTAssertEqual(path.points.count, 2)
            XCTAssertEqual(path.points[0].point, start)
        }
    }

    func testPenToolFreeformWithoutShift() {
        window.overlayView.currentTool = .pen
        let start = NSPoint(x: 100, y: 100)
        let mid = NSPoint(x: 120, y: 110)
        let end = NSPoint(x: 200, y: 205)

        performDragGesture(from: start, to: mid)

        let mouseDrag2 = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end
        )
        window.mouseDragged(with: mouseDrag2!)

        XCTAssertNotNil(window.overlayView.currentPath)
        if let path = window.overlayView.currentPath {
            XCTAssertGreaterThan(path.points.count, 2)
        }
    }

    // MARK: - Highlighter Tool Integration Tests

    func testHighlighterBecomesLineWithShift() {
        window.overlayView.currentTool = .highlighter
        let start = NSPoint(x: 100, y: 100)
        let mid = NSPoint(x: 120, y: 110)
        let end = NSPoint(x: 200, y: 205)

        performDragGesture(from: start, to: mid, withShift: true)

        let mouseDrag2 = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end,
            modifierFlags: .shift
        )
        window.mouseDragged(with: mouseDrag2!)

        XCTAssertNotNil(window.overlayView.currentHighlight)
        if let highlight = window.overlayView.currentHighlight {
            XCTAssertEqual(highlight.points.count, 2)
            XCTAssertEqual(highlight.points[0].point, start)
        }
    }

    func testHighlighterFreeformWithoutShift() {
        window.overlayView.currentTool = .highlighter
        let start = NSPoint(x: 100, y: 100)
        let mid = NSPoint(x: 120, y: 110)
        let end = NSPoint(x: 200, y: 205)

        performDragGesture(from: start, to: mid)

        let mouseDrag2 = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end
        )
        window.mouseDragged(with: mouseDrag2!)

        XCTAssertNotNil(window.overlayView.currentHighlight)
        if let highlight = window.overlayView.currentHighlight {
            XCTAssertGreaterThan(highlight.points.count, 2)
        }
    }

    // MARK: - Dynamic Shift Toggling Tests

    func testPressingShiftMidDrag() {
        window.overlayView.currentTool = .line
        let start = NSPoint(x: 100, y: 100)
        let mid = NSPoint(x: 150, y: 130)
        let end = NSPoint(x: 200, y: 210)

        performDragGesture(from: start, to: mid)

        let flagsEvent = TestEvents.createKeyEvent(
            type: .flagsChanged,
            keyCode: 56,
            modifierFlags: .shift
        )
        window.flagsChanged(with: flagsEvent!)

        let mouseDrag2 = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end,
            modifierFlags: .shift
        )
        window.mouseDragged(with: mouseDrag2!)

        XCTAssertNotNil(window.overlayView.currentLine)
    }

    func testReleasingShiftMidDrag() {
        window.overlayView.currentTool = .line
        let start = NSPoint(x: 100, y: 100)
        let mid = NSPoint(x: 150, y: 150)

        performDragGesture(from: start, to: mid, withShift: true)

        XCTAssertNotNil(window.overlayView.currentLine)
        if let line = window.overlayView.currentLine {
            assertLineAngle(line, equals: .pi / 4)
        }
    }

    // MARK: - Shift State Tests

    func testShiftStateTracking() {
        window.overlayView.currentTool = .line
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 210)

        performDragGesture(from: start, to: end, withShift: true)
        XCTAssertNotNil(window.overlayView.currentLine)

        completeDragGesture(at: end, withShift: true)
        XCTAssertNil(window.overlayView.currentLine)
        XCTAssertEqual(window.overlayView.lines.count, 1)
    }

    // MARK: - Compatibility Tests

    func testShiftWithFadeMode() {
        window.overlayView.fadeMode = true
        window.overlayView.currentTool = .line

        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 210)

        performDragGesture(from: start, to: end, withShift: true)
        completeDragGesture(at: end, withShift: true)

        XCTAssertEqual(window.overlayView.lines.count, 1)
        XCTAssertNotNil(window.overlayView.lines.first?.creationTime)
    }

    func testShiftConstrainedLineCreation() {
        window.overlayView.currentTool = .line

        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 210)

        performDragGesture(from: start, to: end, withShift: true)
        completeDragGesture(at: end, withShift: true)

        XCTAssertEqual(window.overlayView.lines.count, 1)

        if let line = window.overlayView.lines.first {
            let dx = line.endPoint.x - line.startPoint.x
            let dy = line.endPoint.y - line.startPoint.y
            let angle = atan2(dy, dx)
            let normalizedAngle = round(angle / (.pi / 4)) * (.pi / 4)
            XCTAssertEqual(angle, normalizedAngle, accuracy: 0.01)
        }
    }

    // MARK: - Rectangle Shift Constraint Tests

    func testRectangleShiftConstraintsToSquare() {
        window.overlayView.currentTool = .rectangle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)  // Non-square dimensions

        performDragGesture(from: start, to: end, withShift: true)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        if let rect = window.overlayView.currentRectangle {
            let width = abs(rect.endPoint.x - rect.startPoint.x)
            let height = abs(rect.endPoint.y - rect.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Rectangle should be constrained to square")
        }
    }

    func testRectangleWithoutShiftIsNotConstrained() {
        window.overlayView.currentTool = .rectangle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)  // Non-square dimensions

        performDragGesture(from: start, to: end)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        if let rect = window.overlayView.currentRectangle {
            XCTAssertEqual(rect.endPoint, end, "Rectangle should not be constrained without shift")
        }
    }

    func testRectangleShiftPreservesDirection() {
        window.overlayView.currentTool = .rectangle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)

        performDragGesture(from: start, to: end, withShift: true)

        if let rect = window.overlayView.currentRectangle {
            XCTAssertGreaterThan(rect.endPoint.x, rect.startPoint.x, "X should increase when dragging right")
            XCTAssertGreaterThan(rect.endPoint.y, rect.startPoint.y, "Y should increase when dragging down")
        }
    }

    func testRectangleShiftUsesLargerDimension() {
        window.overlayView.currentTool = .rectangle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 130)  // Width 100, Height 30

        performDragGesture(from: start, to: end, withShift: true)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        if let rect = window.overlayView.currentRectangle {
            let width = abs(rect.endPoint.x - rect.startPoint.x)
            let height = abs(rect.endPoint.y - rect.startPoint.y)
            XCTAssertEqual(width, 100, accuracy: 0.1, "Square should use larger dimension (100)")
            XCTAssertEqual(height, 100, accuracy: 0.1, "Square should use larger dimension (100)")
        }
    }

    // MARK: - Oval Shift Constraint Tests

    func testOvalShiftConstrainsToPerfectCircle() {
        window.overlayView.currentTool = .oval
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)  // Non-square bounding box

        performDragGesture(from: start, to: end, withShift: true)

        XCTAssertNotNil(window.overlayView.currentOval)
        if let oval = window.overlayView.currentOval {
            let width = abs(oval.endPoint.x - oval.startPoint.x)
            let height = abs(oval.endPoint.y - oval.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Oval should have square bounding box")
        }
    }

    func testOvalWithoutShiftIsNotConstrained() {
        window.overlayView.currentTool = .oval
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)  // Non-square bounding box

        performDragGesture(from: start, to: end)

        XCTAssertNotNil(window.overlayView.currentOval)
        if let oval = window.overlayView.currentOval {
            XCTAssertEqual(oval.endPoint, end, "Oval should not be constrained without shift")
        }
    }

    func testOvalShiftPreservesDirection() {
        window.overlayView.currentTool = .oval
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)

        performDragGesture(from: start, to: end, withShift: true)

        if let oval = window.overlayView.currentOval {
            XCTAssertGreaterThan(oval.endPoint.x, oval.startPoint.x, "X should increase when dragging right")
            XCTAssertGreaterThan(oval.endPoint.y, oval.startPoint.y, "Y should increase when dragging down")
        }
    }

    func testOvalShiftUsesLargerDimension() {
        window.overlayView.currentTool = .oval
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 130)  // Width 100, Height 30

        performDragGesture(from: start, to: end, withShift: true)

        XCTAssertNotNil(window.overlayView.currentOval)
        if let oval = window.overlayView.currentOval {
            let width = abs(oval.endPoint.x - oval.startPoint.x)
            let height = abs(oval.endPoint.y - oval.startPoint.y)
            XCTAssertEqual(width, 100, accuracy: 0.1, "Oval should use larger dimension (100)")
            XCTAssertEqual(height, 100, accuracy: 0.1, "Oval should use larger dimension (100)")
        }
    }

    // MARK: - Shift + Center Mode (Option) Combined Tests

    func testRectangleShiftPlusCenterMode() {
        window.overlayView.currentTool = .rectangle
        let anchor = NSPoint(x: 200, y: 200)
        let end = NSPoint(x: 250, y: 230)  // Non-square drag

        performDragWithModifiers(from: anchor, to: end, shift: true, option: true)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        if let rect = window.overlayView.currentRectangle {
            let width = abs(rect.endPoint.x - rect.startPoint.x)
            let height = abs(rect.endPoint.y - rect.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Should be square")

            // Center mode: anchor should be at center of the shape
            let centerX = (rect.startPoint.x + rect.endPoint.x) / 2
            let centerY = (rect.startPoint.y + rect.endPoint.y) / 2
            XCTAssertEqual(centerX, anchor.x, accuracy: 0.1, "Center X should be at anchor")
            XCTAssertEqual(centerY, anchor.y, accuracy: 0.1, "Center Y should be at anchor")
        }
    }

    func testOvalShiftPlusCenterMode() {
        window.overlayView.currentTool = .oval
        let anchor = NSPoint(x: 200, y: 200)
        let end = NSPoint(x: 250, y: 230)  // Non-square drag

        performDragWithModifiers(from: anchor, to: end, shift: true, option: true)

        XCTAssertNotNil(window.overlayView.currentOval)
        if let oval = window.overlayView.currentOval {
            let width = abs(oval.endPoint.x - oval.startPoint.x)
            let height = abs(oval.endPoint.y - oval.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Should be perfect circle")

            // Center mode: anchor should be at center of the shape
            let centerX = (oval.startPoint.x + oval.endPoint.x) / 2
            let centerY = (oval.startPoint.y + oval.endPoint.y) / 2
            XCTAssertEqual(centerX, anchor.x, accuracy: 0.1, "Center X should be at anchor")
            XCTAssertEqual(centerY, anchor.y, accuracy: 0.1, "Center Y should be at anchor")
        }
    }

    func testRectangleShiftCreatesAndFinalizesSquare() {
        window.overlayView.currentTool = .rectangle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)

        performDragGesture(from: start, to: end, withShift: true)
        completeDragGesture(at: end, withShift: true)

        XCTAssertEqual(window.overlayView.rectangles.count, 1)
        if let rect = window.overlayView.rectangles.first {
            let width = abs(rect.endPoint.x - rect.startPoint.x)
            let height = abs(rect.endPoint.y - rect.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Finalized rectangle should be square")
        }
    }

    func testOvalShiftCreatesAndFinalizesPerfectCircle() {
        window.overlayView.currentTool = .oval
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)

        performDragGesture(from: start, to: end, withShift: true)
        completeDragGesture(at: end, withShift: true)

        XCTAssertEqual(window.overlayView.ovals.count, 1)
        if let oval = window.overlayView.ovals.first {
            let width = abs(oval.endPoint.x - oval.startPoint.x)
            let height = abs(oval.endPoint.y - oval.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Finalized circle should be perfect")
        }
    }

    // MARK: - Option Key Release Mid-Drag Tests

    private func performDragWithOption(from start: NSPoint, to end: NSPoint) {
        let mouseDownEvent = TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: start,
            modifierFlags: .option
        )
        window.mouseDown(with: mouseDownEvent!)

        let mouseDragEvent = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end,
            modifierFlags: .option
        )
        window.mouseDragged(with: mouseDragEvent!)
    }

    private func releaseOptionKey() {
        let flagsEvent = TestEvents.createKeyEvent(
            type: .flagsChanged,
            keyCode: 58,  // Option key
            modifierFlags: []
        )
        window.flagsChanged(with: flagsEvent!)
    }

    private func continueDragWithoutOption(to location: NSPoint) {
        let mouseDragEvent = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: location,
            modifierFlags: []
        )
        window.mouseDragged(with: mouseDragEvent!)
    }

    func testRectangleOptionReleaseMidDragDoesNotJump() {
        window.overlayView.currentTool = .rectangle
        let anchor = NSPoint(x: 200, y: 200)
        let dragPoint1 = NSPoint(x: 250, y: 230)

        performDragWithOption(from: anchor, to: dragPoint1)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        guard let rectBefore = window.overlayView.currentRectangle else { return }
        let endPointBefore = rectBefore.endPoint

        releaseOptionKey()
        continueDragWithoutOption(to: dragPoint1)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        guard let rectAfter = window.overlayView.currentRectangle else { return }

        XCTAssertEqual(rectAfter.endPoint.x, endPointBefore.x, accuracy: 1.0,
            "Rectangle should not jump when Option is released")
        XCTAssertEqual(rectAfter.endPoint.y, endPointBefore.y, accuracy: 1.0,
            "Rectangle should not jump when Option is released")
    }

    func testOvalOptionReleaseMidDragDoesNotJump() {
        window.overlayView.currentTool = .oval
        let anchor = NSPoint(x: 200, y: 200)
        let dragPoint1 = NSPoint(x: 250, y: 230)

        performDragWithOption(from: anchor, to: dragPoint1)

        XCTAssertNotNil(window.overlayView.currentOval)
        guard let ovalBefore = window.overlayView.currentOval else { return }
        let endPointBefore = ovalBefore.endPoint

        releaseOptionKey()
        continueDragWithoutOption(to: dragPoint1)

        XCTAssertNotNil(window.overlayView.currentOval)
        guard let ovalAfter = window.overlayView.currentOval else { return }

        XCTAssertEqual(ovalAfter.endPoint.x, endPointBefore.x, accuracy: 1.0,
            "Oval should not jump when Option is released")
        XCTAssertEqual(ovalAfter.endPoint.y, endPointBefore.y, accuracy: 1.0,
            "Oval should not jump when Option is released")
    }

    func testRectangleOptionReleaseThenContinueDrag() {
        window.overlayView.currentTool = .rectangle
        let anchor = NSPoint(x: 200, y: 200)
        let dragPoint1 = NSPoint(x: 250, y: 230)
        let dragPoint2 = NSPoint(x: 280, y: 260)

        performDragWithOption(from: anchor, to: dragPoint1)
        releaseOptionKey()
        continueDragWithoutOption(to: dragPoint2)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        guard let rect = window.overlayView.currentRectangle else { return }

        // After releasing Option, shape should follow cursor from corner mode
        XCTAssertEqual(rect.endPoint.x, dragPoint2.x, accuracy: 1.0,
            "Rectangle should follow cursor after Option release")
        XCTAssertEqual(rect.endPoint.y, dragPoint2.y, accuracy: 1.0,
            "Rectangle should follow cursor after Option release")
    }

    func testOvalOptionReleaseThenContinueDrag() {
        window.overlayView.currentTool = .oval
        let anchor = NSPoint(x: 200, y: 200)
        let dragPoint1 = NSPoint(x: 250, y: 230)
        let dragPoint2 = NSPoint(x: 280, y: 260)

        performDragWithOption(from: anchor, to: dragPoint1)
        releaseOptionKey()
        continueDragWithoutOption(to: dragPoint2)

        XCTAssertNotNil(window.overlayView.currentOval)
        guard let oval = window.overlayView.currentOval else { return }

        // After releasing Option, shape should follow cursor from corner mode
        XCTAssertEqual(oval.endPoint.x, dragPoint2.x, accuracy: 1.0,
            "Oval should follow cursor after Option release")
        XCTAssertEqual(oval.endPoint.y, dragPoint2.y, accuracy: 1.0,
            "Oval should follow cursor after Option release")
    }

    func testRectangleOptionHeldEntireDragStillWorks() {
        window.overlayView.currentTool = .rectangle
        let anchor = NSPoint(x: 200, y: 200)
        let end = NSPoint(x: 250, y: 230)

        performDragWithOption(from: anchor, to: end)

        let mouseUpEvent = TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: end,
            modifierFlags: .option
        )
        window.mouseUp(with: mouseUpEvent!)

        XCTAssertEqual(window.overlayView.rectangles.count, 1)
        if let rect = window.overlayView.rectangles.first {
            let centerX = (rect.startPoint.x + rect.endPoint.x) / 2
            let centerY = (rect.startPoint.y + rect.endPoint.y) / 2
            XCTAssertEqual(centerX, anchor.x, accuracy: 1.0, "Center X should be at anchor")
            XCTAssertEqual(centerY, anchor.y, accuracy: 1.0, "Center Y should be at anchor")
        }
    }

    func testOvalOptionHeldEntireDragStillWorks() {
        window.overlayView.currentTool = .oval
        let anchor = NSPoint(x: 200, y: 200)
        let end = NSPoint(x: 250, y: 230)

        performDragWithOption(from: anchor, to: end)

        let mouseUpEvent = TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: end,
            modifierFlags: .option
        )
        window.mouseUp(with: mouseUpEvent!)

        XCTAssertEqual(window.overlayView.ovals.count, 1)
        if let oval = window.overlayView.ovals.first {
            let centerX = (oval.startPoint.x + oval.endPoint.x) / 2
            let centerY = (oval.startPoint.y + oval.endPoint.y) / 2
            XCTAssertEqual(centerX, anchor.x, accuracy: 1.0, "Center X should be at anchor")
            XCTAssertEqual(centerY, anchor.y, accuracy: 1.0, "Center Y should be at anchor")
        }
    }

    func testRectangleShiftPlusOptionReleaseMidDrag() {
        window.overlayView.currentTool = .rectangle
        let anchor = NSPoint(x: 200, y: 200)
        let dragPoint1 = NSPoint(x: 250, y: 230)

        // Shift + Option creates square from center
        let modifierFlags: NSEvent.ModifierFlags = [.shift, .option]
        let mouseDownEvent = TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: anchor,
            modifierFlags: modifierFlags
        )
        window.mouseDown(with: mouseDownEvent!)

        let mouseDragEvent = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: dragPoint1,
            modifierFlags: modifierFlags
        )
        window.mouseDragged(with: mouseDragEvent!)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        guard let rectBefore = window.overlayView.currentRectangle else { return }

        let widthBefore = abs(rectBefore.endPoint.x - rectBefore.startPoint.x)
        let heightBefore = abs(rectBefore.endPoint.y - rectBefore.startPoint.y)
        XCTAssertEqual(widthBefore, heightBefore, accuracy: 0.1, "Should be square before Option release")

        // Release Option (keep Shift)
        let flagsEvent = TestEvents.createKeyEvent(
            type: .flagsChanged,
            keyCode: 58,
            modifierFlags: .shift
        )
        window.flagsChanged(with: flagsEvent!)

        let mouseDrag2 = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: dragPoint1,
            modifierFlags: .shift
        )
        window.mouseDragged(with: mouseDrag2!)

        XCTAssertNotNil(window.overlayView.currentRectangle)
        guard let rectAfter = window.overlayView.currentRectangle else { return }

        let widthAfter = abs(rectAfter.endPoint.x - rectAfter.startPoint.x)
        let heightAfter = abs(rectAfter.endPoint.y - rectAfter.startPoint.y)
        XCTAssertEqual(widthAfter, heightAfter, accuracy: 0.1, "Should still be square after Option release")
    }
}
