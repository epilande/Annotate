import XCTest

@testable import Annotate

/// Filled Rectangle and Filled Circle: each covers everything drawn before it, whatever the
/// kind, and annotations drawn after it stack on top of it by kind as usual.
@MainActor
final class FilledShapeTests: XCTestCase {
    private var overlayView: OverlayView!
    private var originalBoardManager: BoardManager!

    override func setUp() {
        super.setUp()
        TestWindows.recordOpenWindows()
        AppDelegate.shared = nil
        // Rendering consults the board; keep it off the user's live defaults.
        originalBoardManager = BoardManager.shared
        BoardManager.shared = BoardManager(userDefaults: TestUserDefaults.create())
        overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        overlayView.pickerUserDefaultsOverride = TestUserDefaults.create()
        overlayView.fadeMode = false
    }

    override func tearDown() {
        overlayView?.pickerUserDefaultsOverride = nil
        overlayView = nil
        BoardManager.shared = originalBoardManager
        assertNoLeakedWindows()
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    // MARK: - Helpers

    private func filledRectangle(time: CFTimeInterval, color: NSColor = .blue) -> Rectangle {
        Rectangle(
            startPoint: NSPoint(x: 50, y: 50),
            endPoint: NSPoint(x: 150, y: 150),
            color: color,
            lineWidth: 3,
            creationTime: time,
            style: .filled)
    }

    private func filledCircle(time: CFTimeInterval, color: NSColor = .green) -> Circle {
        Circle(
            startPoint: NSPoint(x: 60, y: 60),
            endPoint: NSPoint(x: 140, y: 140),
            color: color,
            lineWidth: 3,
            creationTime: time,
            filled: true)
    }

    private func redArrow(y: CGFloat, time: CFTimeInterval) -> Arrow {
        TestFactory.createArrow(
            start: NSPoint(x: 60, y: y), end: NSPoint(x: 140, y: y), color: .red, lineWidth: 6, time: time)
    }

    private func redStroke(y: CGFloat, time: CFTimeInterval) -> DrawingPath {
        var stroke = TestFactory.createDrawingPath(
            points: [TestFactory.createTimedPoint(x: 60, y: y), TestFactory.createTimedPoint(x: 140, y: y)],
            color: .red,
            lineWidth: 6)
        stroke.creationTime = time
        return stroke
    }

    /// Renders the overlay into a bitmap and returns the color at a view point.
    private func renderedColor(at point: NSPoint) throws -> NSColor {
        let width = Int(overlayView.bounds.width)
        let height = Int(overlayView.bounds.height)
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        overlayView.draw(overlayView.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        // Bitmap rows run top-down while the view is bottom-up.
        let color = try XCTUnwrap(rep.colorAt(x: Int(point.x), y: height - 1 - Int(point.y)))
        return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
    }

    /// Asserts an opaque color whose channels are clearly on (1) or off (0).
    private func assertColor(
        _ color: NSColor, red: CGFloat, green: CGFloat, blue: CGFloat, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01, message, file: file, line: line)
        for (actual, expected) in [(color.redComponent, red), (color.greenComponent, green), (color.blueComponent, blue)] {
            if expected > 0.5 {
                XCTAssertGreaterThan(actual, 0.75, message, file: file, line: line)
            } else {
                XCTAssertLessThan(actual, 0.3, message, file: file, line: line)
            }
        }
    }

    // MARK: - Model

    func testFilledShapesCoverOlderAnnotationsButAreNotRedactions() {
        let rectangle = filledRectangle(time: 1)
        XCTAssertTrue(rectangle.coversOlder)
        XCTAssertFalse(rectangle.isRedaction, "A filled rectangle fades and draws in its color")
        XCTAssertFalse(TestFactory.createRectangle().coversOlder)
        XCTAssertTrue(filledCircle(time: 1).coversOlder)
        XCTAssertFalse(TestFactory.createCircle().coversOlder)
        XCTAssertFalse(RectangleStyle.redactionStyles.contains(.filled), "The Redact tool doesn't offer the Filled Rectangle style")
        let outlinedCircle = Circle(
            startPoint: NSPoint(x: 60, y: 60),
            endPoint: NSPoint(x: 140, y: 140),
            color: .green,
            lineWidth: 3,
            creationTime: 1)
        XCTAssertNotEqual(filledCircle(time: 1), outlinedCircle)
    }

    func testEachFilledShapeClosesALayerInTheOrderItWasDrawn() {
        var document = OverlayDocument()
        document.rectangles = [TestFactory.createRectangle(time: 1), filledRectangle(time: 3)]
        document.circles = [filledCircle(time: 2), TestFactory.createCircle(time: 4)]

        XCTAssertEqual(document.coversByCreation, [.circle(index: 0), .rectangle(index: 1)])
        let covers = document.paintOrder().filter {
            if case .cover = $0 { return true }
            return false
        }
        XCTAssertEqual(covers, [.cover(.circle(index: 0)), .cover(.rectangle(index: 1))])
    }

    // MARK: - Rendering

    func testAFilledRectangleCoversEverythingDrawnBeforeIt() throws {
        overlayView.paths = [redStroke(y: 90, time: 1)]
        overlayView.arrows = [redArrow(y: 110, time: 1)]
        overlayView.rectangles = [filledRectangle(time: 2)]

        assertColor(try renderedColor(at: NSPoint(x: 80, y: 90)), red: 0, green: 0, blue: 1, "An older pen stroke is covered")
        assertColor(try renderedColor(at: NSPoint(x: 80, y: 110)), red: 0, green: 0, blue: 1, "An older arrow is covered")
    }

    func testAnnotationsDrawnAfterAFilledShapeGoOnTop() throws {
        overlayView.arrows = [redArrow(y: 110, time: 3)]
        overlayView.rectangles = [filledRectangle(time: 2)]

        assertColor(try renderedColor(at: NSPoint(x: 80, y: 110)), red: 1, green: 0, blue: 0, "A newer arrow")
        assertColor(try renderedColor(at: NSPoint(x: 100, y: 140)), red: 0, green: 0, blue: 1, "The fill around it")
    }

    func testANewerFilledShapeCoversWhatWasDrawnOnTheOlderOne() throws {
        overlayView.rectangles = [filledRectangle(time: 2)]
        overlayView.arrows = [redArrow(y: 100, time: 3)]
        overlayView.circles = [filledCircle(time: 4)]

        assertColor(try renderedColor(at: NSPoint(x: 100, y: 100)), red: 0, green: 1, blue: 0, "The circle covers the arrow")
        assertColor(try renderedColor(at: NSPoint(x: 55, y: 55)), red: 0, green: 0, blue: 1, "The rectangle outside the circle")
    }

    func testAFilledCircleBeingDrawnCoversCommittedAnnotations() throws {
        overlayView.arrows = [redArrow(y: 100, time: CACurrentMediaTime())]
        overlayView.currentCircle = filledCircle(time: 0)

        assertColor(try renderedColor(at: NSPoint(x: 100, y: 100)), red: 0, green: 1, blue: 0)
    }

    // MARK: - Selection and erasing

    func testSelectionPicksWhatShowsOnTop() {
        overlayView.counterAnnotations = [
            CounterAnnotation(number: 1, position: NSPoint(x: 100, y: 100), color: .red, creationTime: 1)
        ]
        overlayView.rectangles = [filledRectangle(time: 2)]
        overlayView.arrows = [redArrow(y: 120, time: 3)]

        XCTAssertEqual(
            overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)),
            .rectangle(index: 0),
            "The older counter is under the fill")
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 80, y: 120)), .arrow(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 10, y: 10)), .none)
    }

    func testAFilledCircleIsSelectableInsideButNotAtItsCorners() {
        overlayView.circles = [filledCircle(time: 1)]

        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)), .circle(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 62, y: 62)), .none)
    }

    func testAFlatCircleIsClickableOnlyWithinAFewPointsOfItsEdge() {
        var flat = TestFactory.createCircle(start: NSPoint(x: 20, y: 90), end: NSPoint(x: 180, y: 110), time: 1)
        for filled in [false, true] {
            flat.filled = filled
            overlayView.circles = [flat]
            let kind = filled ? "filled" : "outlined"

            XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 183, y: 100)), .circle(index: 0), kind)
            XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 113)), .circle(index: 0), kind)
            XCTAssertEqual(
                overlayView.findObjectAt(point: NSPoint(x: 195, y: 100)),
                .none,
                "\(kind): 15 points past the end of the long axis is not on the circle")
            XCTAssertEqual(
                overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)),
                filled ? .circle(index: 0) : .none,
                "\(kind): only a filled circle is clickable inside")
        }
    }

    func testAFilledShapesOutlineCoversWhatIsUnderIt() {
        // Each paints 10 points past its bounds with a 20 point line.
        var rectangle = filledRectangle(time: 2)
        rectangle.lineWidth = 20
        var circle = filledCircle(time: 2)
        circle.lineWidth = 20

        overlayView.rectangles = [rectangle]
        XCTAssertTrue(overlayView.isPointCovered(NSPoint(x: 155, y: 100), over: 1), "On the rectangle's outline")
        XCTAssertFalse(overlayView.isPointCovered(NSPoint(x: 165, y: 100), over: 1), "Past the rectangle's outline")

        overlayView.rectangles = []
        overlayView.circles = [circle]
        XCTAssertTrue(overlayView.isPointCovered(NSPoint(x: 145, y: 100), over: 1), "On the circle's outline")
        XCTAssertFalse(overlayView.isPointCovered(NSPoint(x: 155, y: 100), over: 1), "Past the circle's outline")

        overlayView.circles = []
        overlayView.rectangles = [
            Rectangle(
                startPoint: NSPoint(x: 50, y: 50),
                endPoint: NSPoint(x: 150, y: 150),
                color: .black,
                lineWidth: 20,
                creationTime: 2,
                style: .solid)
        ]
        XCTAssertFalse(overlayView.isPointCovered(NSPoint(x: 155, y: 100), over: 1), "A redaction paints only its bounds")
    }

    func testAFilledShapeStopsClicksReachingWhatItCovers() {
        overlayView.rectangles = [filledRectangle(time: 2)]

        XCTAssertTrue(overlayView.isPointCovered(NSPoint(x: 100, y: 100), over: 1))
        XCTAssertFalse(overlayView.isPointCovered(NSPoint(x: 100, y: 100), over: 3), "Newer items aren't covered")
        XCTAssertFalse(overlayView.isPointCovered(NSPoint(x: 10, y: 10), over: 1))
    }

    func testAFilledCirclesInkIncludesItsOutlineBetweenTheAxes() {
        let circle = Circle(
            startPoint: .zero,
            endPoint: NSPoint(x: 200, y: 20),
            color: .green,
            lineWidth: 20,
            creationTime: 1,
            filled: true)
        // 9.5 points out from the ellipse along its normal, so inside the 10 point half
        // stroke, but outside the ellipse grown by 10 points on each axis.
        let onTheOutline = NSPoint(x: 202.21, y: 20.506)
        let grown = CGPath(ellipseIn: circle.bounds.insetBy(dx: -10, dy: -10), transform: nil)
        XCTAssertFalse(grown.contains(onTheOutline))
        XCTAssertTrue(circle.ink.contains(onTheOutline))
        XCTAssertTrue(circle.ink.contains(NSPoint(x: 100, y: 10)), "The inside is ink too")
        XCTAssertFalse(circle.ink.contains(NSPoint(x: 215, y: 25)))
    }

    func testTheEraserReachesAFlatCircleOnlyFromNearItsEdge() {
        let flat = TestFactory.createCircle(start: NSPoint(x: 20, y: 90), end: NSPoint(x: 180, y: 110), time: 1)
        overlayView.circles = [flat]

        overlayView.eraseAtPoint(NSPoint(x: 260, y: 100))
        XCTAssertEqual(overlayView.circles.count, 1, "80 points past the end of the long axis is out of reach")

        overlayView.eraseAtPoint(NSPoint(x: 183, y: 100))
        XCTAssertTrue(overlayView.circles.isEmpty, "3 points past the end is within reach")
    }

    func testTheEraserRemovesFilledShapesFromInside() {
        overlayView.rectangles = [filledRectangle(time: 1)]
        overlayView.circles = [filledCircle(time: 2)]

        overlayView.eraseAtPoint(NSPoint(x: 100, y: 100))

        XCTAssertTrue(overlayView.rectangles.isEmpty)
        XCTAssertTrue(overlayView.circles.isEmpty)
    }

    func testDeleteLastRemovesOnlyTheActiveToolsKind() {
        overlayView.circles = [TestFactory.createCircle(time: 1), filledCircle(time: 2), TestFactory.createCircle(time: 3)]
        overlayView.currentTool = .filledCircle
        overlayView.deleteLastItem()
        XCTAssertEqual(overlayView.circles.map(\.filled), [false, false])

        overlayView.rectangles = [
            TestFactory.createRectangle(time: 1), filledRectangle(time: 2),
            Rectangle(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .red, lineWidth: 3, creationTime: 3, style: .solid),
        ]
        overlayView.currentTool = .filledRectangle
        overlayView.deleteLastItem()
        XCTAssertEqual(overlayView.rectangles.map(\.style), [.outline, .solid])
        overlayView.currentTool = .rectangle
        overlayView.deleteLastItem()
        XCTAssertEqual(overlayView.rectangles.map(\.style), [.solid])
    }

    // MARK: - Tools, shortcuts and commands

    func testTheToolsHaveShiftShortcutsBesideTheirOutlineTools() {
        XCTAssertEqual(ToolType.filledRectangle.shortcutKey.defaultBinding, ShortcutBinding("r", modifiers: .shift))
        XCTAssertEqual(ToolType.filledCircle.shortcutKey.defaultBinding, ShortcutBinding("o", modifiers: .shift))
        XCTAssertNotEqual(ShortcutKey.filledRectangle.defaultBinding, ShortcutKey.rectangle.defaultBinding)
        XCTAssertTrue(ShortcutKey.newlyEditable.contains(.filledRectangle))
        XCTAssertTrue(ShortcutKey.newlyEditable.contains(.filledCircle))
        XCTAssertTrue(AppDelegate.statusMenuTools.contains { $0.tool == .filledRectangle })
        XCTAssertTrue(AppDelegate.statusMenuTools.contains { $0.tool == .filledCircle })
    }

    func testLinksSelectTheToolsWhateverTheCase() {
        XCTAssertEqual(AnnotateCommand(path: "/tool/filledRectangle"), .tool(.filledRectangle))
        XCTAssertEqual(AnnotateCommand(path: "tool/FILLEDCIRCLE"), .tool(.filledCircle))
        XCTAssertEqual(AnnotateCommand(path: "/tool/circle"), .tool(.circle), "Oval keeps its link name")
        XCTAssertNil(AnnotateCommand(path: "/tool/oval"), "The display name is not a link name")
    }

    // MARK: - Capture record

    func testTheCaptureRecordMarksFilledShapes() {
        let space = CaptureRecord.DisplaySpace(height: 200)
        XCTAssertEqual(CaptureRecord.Shape(filledRectangle(time: 1), space: space).filled, true)
        XCTAssertEqual(CaptureRecord.Shape(filledCircle(time: 1), space: space).filled, true)
        XCTAssertNil(CaptureRecord.Shape(TestFactory.createRectangle(), space: space).filled)
        XCTAssertNil(CaptureRecord.Shape(TestFactory.createCircle(), space: space).filled)
    }
}
