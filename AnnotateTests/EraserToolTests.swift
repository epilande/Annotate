import XCTest

@testable import Annotate

// Custom test window with an overridable undoManager
class TestWindow: NSWindow {
    private let testUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        return testUndoManager
    }
}

@MainActor
final class EraserToolTests: XCTestCase, Sendable {
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

    // MARK: - Tool Selection Tests

    func testEraserToolSelection() {
        overlayView.currentTool = .eraser
        XCTAssertEqual(overlayView.currentTool, .eraser)
    }

    // MARK: - Eraser Functionality Tests

    func testErasePenPath() {
        let path = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 100, y: 100), timestamp: 0.0),
                TimedPoint(point: NSPoint(x: 110, y: 110), timestamp: 0.1)
            ],
            color: .systemRed,
            lineWidth: 3.0
        )
        overlayView.paths.append(path)
        XCTAssertEqual(overlayView.paths.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 105, y: 105))

        XCTAssertEqual(overlayView.paths.count, 0)
    }

    func testEraseHighlighterPath() {
        let highlight = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 200, y: 200), timestamp: 0.0),
                TimedPoint(point: NSPoint(x: 220, y: 220), timestamp: 0.1)
            ],
            color: .systemYellow,
            lineWidth: 8.0
        )
        overlayView.highlightPaths.append(highlight)
        XCTAssertEqual(overlayView.highlightPaths.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 205, y: 205))

        XCTAssertEqual(overlayView.highlightPaths.count, 0)
    }

    func testEraseArrow() {
        let arrow = Arrow(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .systemBlue,
            lineWidth: 3.0
        )
        overlayView.arrows.append(arrow)
        XCTAssertEqual(overlayView.arrows.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 150, y: 150))

        XCTAssertEqual(overlayView.arrows.count, 0)
    }

    func testEraseLine() {
        let line = Line(
            startPoint: NSPoint(x: 50, y: 50),
            endPoint: NSPoint(x: 150, y: 50),
            color: .systemRed,
            lineWidth: 3.0
        )
        overlayView.lines.append(line)
        XCTAssertEqual(overlayView.lines.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 100, y: 50))

        XCTAssertEqual(overlayView.lines.count, 0)
    }

    func testEraseRectangle() {
        let rectangle = Rectangle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .systemGreen,
            lineWidth: 3.0
        )
        overlayView.rectangles.append(rectangle)
        XCTAssertEqual(overlayView.rectangles.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 100, y: 150))

        XCTAssertEqual(overlayView.rectangles.count, 0)
    }

    func testEraseCircle() {
        let circle = Circle(
            startPoint: NSPoint(x: 200, y: 200),
            endPoint: NSPoint(x: 300, y: 300),
            color: .systemPurple,
            lineWidth: 3.0
        )
        overlayView.circles.append(circle)
        XCTAssertEqual(overlayView.circles.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 250, y: 200))

        XCTAssertEqual(overlayView.circles.count, 0)
    }

    func testEraseTextAnnotation() {
        let text = TextAnnotation(
            text: "Test",
            position: NSPoint(x: 100, y: 100),
            color: .black,
            fontSize: 16
        )
        overlayView.textAnnotations.append(text)
        XCTAssertEqual(overlayView.textAnnotations.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 105, y: 105))

        XCTAssertEqual(overlayView.textAnnotations.count, 0)
    }

    func testEraseCounterAnnotation() {
        let counter = CounterAnnotation(
            number: 1,
            position: NSPoint(x: 150, y: 150),
            color: .systemOrange
        )
        overlayView.counterAnnotations.append(counter)
        overlayView.nextCounterNumber = 2
        XCTAssertEqual(overlayView.counterAnnotations.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 155, y: 155))

        XCTAssertEqual(overlayView.counterAnnotations.count, 0)
    }

    // MARK: - Eraser Radius Tests

    func testEraserDoesNotEraseOutsideRadius() {
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 100),
            color: .systemRed,
            lineWidth: 3.0
        )
        overlayView.lines.append(line)

        overlayView.eraseAtPoint(NSPoint(x: 150, y: 130))

        XCTAssertEqual(overlayView.lines.count, 1)
    }

    func testEraserRadiusValue() {
        XCTAssertEqual(overlayView.eraserRadius, 12.0)
    }

    // MARK: - Multiple Items Erasure Tests

    func testEraseMultipleItemsOfSameType() {
        let line1 = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 100),
            color: .systemRed,
            lineWidth: 3.0
        )
        let line2 = Line(
            startPoint: NSPoint(x: 100, y: 105),
            endPoint: NSPoint(x: 200, y: 105),
            color: .systemBlue,
            lineWidth: 3.0
        )
        overlayView.lines.append(contentsOf: [line1, line2])
        XCTAssertEqual(overlayView.lines.count, 2)

        overlayView.eraseAtPoint(NSPoint(x: 150, y: 102))

        XCTAssertEqual(overlayView.lines.count, 0)
    }

    func testEraseMultipleItemsOfDifferentTypes() {
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 100),
            color: .systemRed,
            lineWidth: 3.0
        )
        let arrow = Arrow(
            startPoint: NSPoint(x: 100, y: 105),
            endPoint: NSPoint(x: 200, y: 105),
            color: .systemBlue,
            lineWidth: 3.0
        )
        overlayView.lines.append(line)
        overlayView.arrows.append(arrow)

        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.arrows.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 150, y: 102))

        XCTAssertEqual(overlayView.lines.count, 0)
        XCTAssertEqual(overlayView.arrows.count, 0)
    }

    // MARK: - Undo Action Registration Tests

    func testEraserRegistersUndoAction() {
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = overlayView
        let testUndoManager = window.undoManager!

        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 100),
            color: .systemRed,
            lineWidth: 3.0
        )
        overlayView.lines.append(line)
        XCTAssertEqual(overlayView.lines.count, 1)

        overlayView.eraseAtPoint(NSPoint(x: 150, y: 100))
        XCTAssertEqual(overlayView.lines.count, 0)

        XCTAssertTrue(testUndoManager.canUndo, "Undo manager should have an undo action registered")

        testUndoManager.undo()

        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.lines[0].startPoint, line.startPoint)
        XCTAssertEqual(overlayView.lines[0].endPoint, line.endPoint)
    }

    func testEraserRegistersUndoForMultipleItems() {
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = overlayView
        let testUndoManager = window.undoManager!

        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 100),
            color: .systemRed,
            lineWidth: 3.0
        )
        let arrow = Arrow(
            startPoint: NSPoint(x: 100, y: 105),
            endPoint: NSPoint(x: 200, y: 105),
            color: .systemBlue,
            lineWidth: 3.0
        )
        overlayView.lines.append(line)
        overlayView.arrows.append(arrow)

        overlayView.eraseAtPoint(NSPoint(x: 150, y: 102))
        XCTAssertEqual(overlayView.lines.count, 0)
        XCTAssertEqual(overlayView.arrows.count, 0)

        testUndoManager.undo()

        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.arrows.count, 1)
    }

    func testEraserDoesNotRegisterUndoWhenNothingErased() {
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = overlayView
        let testUndoManager = window.undoManager!

        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 100),
            color: .systemRed,
            lineWidth: 3.0
        )
        overlayView.lines.append(line)

        overlayView.eraseAtPoint(NSPoint(x: 500, y: 500))

        XCTAssertEqual(overlayView.lines.count, 1)

        XCTAssertFalse(testUndoManager.canUndo, "Undo manager should not register action when nothing was erased")
    }

    // MARK: - Edge Cases

    func testEraseAtPointWithNoAnnotations() {
        XCTAssertTrue(overlayView.paths.isEmpty)
        XCTAssertTrue(overlayView.arrows.isEmpty)

        overlayView.eraseAtPoint(NSPoint(x: 100, y: 100))

        XCTAssertTrue(overlayView.paths.isEmpty)
        XCTAssertTrue(overlayView.arrows.isEmpty)
    }

    func testDeleteLastItemWithEraserTool() {
        overlayView.currentTool = .eraser

        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 100),
            color: .systemRed,
            lineWidth: 3.0
        )
        overlayView.lines.append(line)

        overlayView.deleteLastItem()

        XCTAssertEqual(overlayView.lines.count, 1)
    }
}
