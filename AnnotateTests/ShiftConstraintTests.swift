import XCTest

@testable import Annotate

@MainActor
final class ShiftConstraintTests: XCTestCase, Sendable {
    var window: OverlayWindow!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
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
            window = nil
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

    // MARK: - Circle Shift Constraint Tests

    func testCircleShiftConstrainsToPerfectCircle() {
        window.overlayView.currentTool = .circle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)  // Non-square bounding box

        performDragGesture(from: start, to: end, withShift: true)

        XCTAssertNotNil(window.overlayView.currentCircle)
        if let circle = window.overlayView.currentCircle {
            let width = abs(circle.endPoint.x - circle.startPoint.x)
            let height = abs(circle.endPoint.y - circle.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Circle should have square bounding box")
        }
    }

    func testCircleWithoutShiftIsNotConstrained() {
        window.overlayView.currentTool = .circle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)  // Non-square bounding box

        performDragGesture(from: start, to: end)

        XCTAssertNotNil(window.overlayView.currentCircle)
        if let circle = window.overlayView.currentCircle {
            XCTAssertEqual(circle.endPoint, end, "Circle should not be constrained without shift")
        }
    }

    func testCircleShiftPreservesDirection() {
        window.overlayView.currentTool = .circle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)

        performDragGesture(from: start, to: end, withShift: true)

        if let circle = window.overlayView.currentCircle {
            XCTAssertGreaterThan(circle.endPoint.x, circle.startPoint.x, "X should increase when dragging right")
            XCTAssertGreaterThan(circle.endPoint.y, circle.startPoint.y, "Y should increase when dragging down")
        }
    }

    func testCircleShiftUsesLargerDimension() {
        window.overlayView.currentTool = .circle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 130)  // Width 100, Height 30

        performDragGesture(from: start, to: end, withShift: true)

        XCTAssertNotNil(window.overlayView.currentCircle)
        if let circle = window.overlayView.currentCircle {
            let width = abs(circle.endPoint.x - circle.startPoint.x)
            let height = abs(circle.endPoint.y - circle.startPoint.y)
            XCTAssertEqual(width, 100, accuracy: 0.1, "Circle should use larger dimension (100)")
            XCTAssertEqual(height, 100, accuracy: 0.1, "Circle should use larger dimension (100)")
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

    func testCircleShiftPlusCenterMode() {
        window.overlayView.currentTool = .circle
        let anchor = NSPoint(x: 200, y: 200)
        let end = NSPoint(x: 250, y: 230)  // Non-square drag

        performDragWithModifiers(from: anchor, to: end, shift: true, option: true)

        XCTAssertNotNil(window.overlayView.currentCircle)
        if let circle = window.overlayView.currentCircle {
            let width = abs(circle.endPoint.x - circle.startPoint.x)
            let height = abs(circle.endPoint.y - circle.startPoint.y)
            XCTAssertEqual(width, height, accuracy: 0.1, "Should be perfect circle")

            // Center mode: anchor should be at center of the shape
            let centerX = (circle.startPoint.x + circle.endPoint.x) / 2
            let centerY = (circle.startPoint.y + circle.endPoint.y) / 2
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

    func testCircleShiftCreatesAndFinalizesPerfectCircle() {
        window.overlayView.currentTool = .circle
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 150)

        performDragGesture(from: start, to: end, withShift: true)
        completeDragGesture(at: end, withShift: true)

        XCTAssertEqual(window.overlayView.circles.count, 1)
        if let circle = window.overlayView.circles.first {
            let width = abs(circle.endPoint.x - circle.startPoint.x)
            let height = abs(circle.endPoint.y - circle.startPoint.y)
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

    func testCircleOptionReleaseMidDragDoesNotJump() {
        window.overlayView.currentTool = .circle
        let anchor = NSPoint(x: 200, y: 200)
        let dragPoint1 = NSPoint(x: 250, y: 230)

        performDragWithOption(from: anchor, to: dragPoint1)

        XCTAssertNotNil(window.overlayView.currentCircle)
        guard let circleBefore = window.overlayView.currentCircle else { return }
        let endPointBefore = circleBefore.endPoint

        releaseOptionKey()
        continueDragWithoutOption(to: dragPoint1)

        XCTAssertNotNil(window.overlayView.currentCircle)
        guard let circleAfter = window.overlayView.currentCircle else { return }

        XCTAssertEqual(circleAfter.endPoint.x, endPointBefore.x, accuracy: 1.0,
            "Circle should not jump when Option is released")
        XCTAssertEqual(circleAfter.endPoint.y, endPointBefore.y, accuracy: 1.0,
            "Circle should not jump when Option is released")
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

    func testCircleOptionReleaseThenContinueDrag() {
        window.overlayView.currentTool = .circle
        let anchor = NSPoint(x: 200, y: 200)
        let dragPoint1 = NSPoint(x: 250, y: 230)
        let dragPoint2 = NSPoint(x: 280, y: 260)

        performDragWithOption(from: anchor, to: dragPoint1)
        releaseOptionKey()
        continueDragWithoutOption(to: dragPoint2)

        XCTAssertNotNil(window.overlayView.currentCircle)
        guard let circle = window.overlayView.currentCircle else { return }

        // After releasing Option, shape should follow cursor from corner mode
        XCTAssertEqual(circle.endPoint.x, dragPoint2.x, accuracy: 1.0,
            "Circle should follow cursor after Option release")
        XCTAssertEqual(circle.endPoint.y, dragPoint2.y, accuracy: 1.0,
            "Circle should follow cursor after Option release")
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

    func testCircleOptionHeldEntireDragStillWorks() {
        window.overlayView.currentTool = .circle
        let anchor = NSPoint(x: 200, y: 200)
        let end = NSPoint(x: 250, y: 230)

        performDragWithOption(from: anchor, to: end)

        let mouseUpEvent = TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: end,
            modifierFlags: .option
        )
        window.mouseUp(with: mouseUpEvent!)

        XCTAssertEqual(window.overlayView.circles.count, 1)
        if let circle = window.overlayView.circles.first {
            let centerX = (circle.startPoint.x + circle.endPoint.x) / 2
            let centerY = (circle.startPoint.y + circle.endPoint.y) / 2
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
