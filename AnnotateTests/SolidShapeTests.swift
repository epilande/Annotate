import XCTest

@testable import Annotate

/// Solid Rectangle and Solid Oval: each covers everything drawn before it, whatever the
/// kind, and annotations drawn after it stack on top of it by kind as usual.
@MainActor
final class SolidShapeTests: XCTestCase {
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

    private func solidRectangle(time: CFTimeInterval, color: NSColor = .blue) -> Rectangle {
        Rectangle(
            startPoint: NSPoint(x: 50, y: 50),
            endPoint: NSPoint(x: 150, y: 150),
            color: color,
            lineWidth: 3,
            creationTime: time,
            style: .solidColor)
    }

    private func solidOval(time: CFTimeInterval, color: NSColor = .green) -> Oval {
        Oval(
            startPoint: NSPoint(x: 60, y: 60),
            endPoint: NSPoint(x: 140, y: 140),
            color: color,
            lineWidth: 3,
            creationTime: time,
            solid: true)
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

    func testSolidShapesCoverOlderAnnotationsButAreNotRedactions() {
        let rectangle = solidRectangle(time: 1)
        XCTAssertTrue(rectangle.coversOlder)
        XCTAssertFalse(rectangle.isRedaction, "A solid rectangle fades and draws in its color")
        XCTAssertFalse(TestFactory.createRectangle().coversOlder)
        XCTAssertTrue(solidOval(time: 1).coversOlder)
        XCTAssertFalse(TestFactory.createOval().coversOlder)
        XCTAssertFalse(RectangleStyle.redactionStyles.contains(.solidColor), "The Redact tool doesn't offer the Solid Rectangle style")
        let outlinedOval = Oval(
            startPoint: NSPoint(x: 60, y: 60),
            endPoint: NSPoint(x: 140, y: 140),
            color: .green,
            lineWidth: 3,
            creationTime: 1)
        XCTAssertNotEqual(solidOval(time: 1), outlinedOval)
    }

    func testEachSolidShapeClosesALayerInTheOrderItWasDrawn() {
        var document = OverlayDocument()
        document.rectangles = [TestFactory.createRectangle(time: 1), solidRectangle(time: 3)]
        document.ovals = [solidOval(time: 2), TestFactory.createOval(time: 4)]

        XCTAssertEqual(document.coversByCreation, [.oval(index: 0), .rectangle(index: 1)])
        let covers = document.paintOrder().filter {
            if case .cover = $0 { return true }
            return false
        }
        XCTAssertEqual(covers, [.cover(.oval(index: 0)), .cover(.rectangle(index: 1))])
    }

    // MARK: - Rendering

    func testASolidRectangleCoversEverythingDrawnBeforeIt() throws {
        overlayView.paths = [redStroke(y: 90, time: 1)]
        overlayView.arrows = [redArrow(y: 110, time: 1)]
        overlayView.rectangles = [solidRectangle(time: 2)]

        assertColor(try renderedColor(at: NSPoint(x: 80, y: 90)), red: 0, green: 0, blue: 1, "An older pen stroke is covered")
        assertColor(try renderedColor(at: NSPoint(x: 80, y: 110)), red: 0, green: 0, blue: 1, "An older arrow is covered")
    }

    func testAnnotationsDrawnAfterASolidShapeGoOnTop() throws {
        overlayView.arrows = [redArrow(y: 110, time: 3)]
        overlayView.rectangles = [solidRectangle(time: 2)]

        assertColor(try renderedColor(at: NSPoint(x: 80, y: 110)), red: 1, green: 0, blue: 0, "A newer arrow")
        assertColor(try renderedColor(at: NSPoint(x: 100, y: 140)), red: 0, green: 0, blue: 1, "The fill around it")
    }

    func testANewerSolidShapeCoversWhatWasDrawnOnTheOlderOne() throws {
        overlayView.rectangles = [solidRectangle(time: 2)]
        overlayView.arrows = [redArrow(y: 100, time: 3)]
        overlayView.ovals = [solidOval(time: 4)]

        assertColor(try renderedColor(at: NSPoint(x: 100, y: 100)), red: 0, green: 1, blue: 0, "The oval covers the arrow")
        assertColor(try renderedColor(at: NSPoint(x: 55, y: 55)), red: 0, green: 0, blue: 1, "The rectangle outside the oval")
    }

    func testASolidOvalBeingDrawnCoversCommittedAnnotations() throws {
        overlayView.arrows = [redArrow(y: 100, time: CACurrentMediaTime())]
        overlayView.currentOval = solidOval(time: 0)

        assertColor(try renderedColor(at: NSPoint(x: 100, y: 100)), red: 0, green: 1, blue: 0)
    }

    // MARK: - Selection and erasing

    func testSelectionPicksWhatShowsOnTop() {
        overlayView.counterAnnotations = [
            CounterAnnotation(number: 1, position: NSPoint(x: 100, y: 100), color: .red, creationTime: 1)
        ]
        overlayView.rectangles = [solidRectangle(time: 2)]
        overlayView.arrows = [redArrow(y: 120, time: 3)]

        XCTAssertEqual(
            overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)),
            .rectangle(index: 0),
            "The older counter is under the fill")
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 80, y: 120)), .arrow(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 10, y: 10)), .none)
    }

    func testASolidOvalIsSelectableInsideButNotAtItsCorners() {
        overlayView.ovals = [solidOval(time: 1)]

        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)), .oval(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 62, y: 62)), .none)
    }

    func testASolidShapeStopsClicksReachingWhatItCovers() {
        overlayView.rectangles = [solidRectangle(time: 2)]

        XCTAssertTrue(overlayView.isPointCovered(NSPoint(x: 100, y: 100), over: 1))
        XCTAssertFalse(overlayView.isPointCovered(NSPoint(x: 100, y: 100), over: 3), "Newer items aren't covered")
        XCTAssertFalse(overlayView.isPointCovered(NSPoint(x: 10, y: 10), over: 1))
    }

    func testTheEraserRemovesSolidShapesFromInside() {
        overlayView.rectangles = [solidRectangle(time: 1)]
        overlayView.ovals = [solidOval(time: 2)]

        overlayView.eraseAtPoint(NSPoint(x: 100, y: 100))

        XCTAssertTrue(overlayView.rectangles.isEmpty)
        XCTAssertTrue(overlayView.ovals.isEmpty)
    }

    func testDeleteLastRemovesOnlyTheActiveToolsKind() {
        overlayView.ovals = [TestFactory.createOval(time: 1), solidOval(time: 2), TestFactory.createOval(time: 3)]
        overlayView.currentTool = .solidOval
        overlayView.deleteLastItem()
        XCTAssertEqual(overlayView.ovals.map(\.solid), [false, false])

        overlayView.rectangles = [
            TestFactory.createRectangle(time: 1), solidRectangle(time: 2),
            Rectangle(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .red, lineWidth: 3, creationTime: 3, style: .solid),
        ]
        overlayView.currentTool = .solidRectangle
        overlayView.deleteLastItem()
        XCTAssertEqual(overlayView.rectangles.map(\.style), [.outline, .solid])
        overlayView.currentTool = .rectangle
        overlayView.deleteLastItem()
        XCTAssertEqual(overlayView.rectangles.map(\.style), [.solid])
    }

    // MARK: - Tools, shortcuts and commands

    func testTheToolsHaveShiftShortcutsBesideTheirOutlineTools() {
        XCTAssertEqual(ToolType.solidRectangle.shortcutKey.defaultBinding, ShortcutBinding("r", modifiers: .shift))
        XCTAssertEqual(ToolType.solidOval.shortcutKey.defaultBinding, ShortcutBinding("o", modifiers: .shift))
        XCTAssertNotEqual(ShortcutKey.solidRectangle.defaultBinding, ShortcutKey.rectangle.defaultBinding)
        XCTAssertTrue(ShortcutKey.newlyEditable.contains(.solidRectangle))
        XCTAssertTrue(ShortcutKey.newlyEditable.contains(.solidOval))
        XCTAssertTrue(AppDelegate.statusMenuTools.contains { $0.tool == .solidRectangle })
        XCTAssertTrue(AppDelegate.statusMenuTools.contains { $0.tool == .solidOval })
    }

    func testLinksSelectTheToolsWhateverTheCase() {
        XCTAssertEqual(AnnotateCommand(path: "/tool/solidRectangle"), .tool(.solidRectangle))
        XCTAssertEqual(AnnotateCommand(path: "tool/SOLIDOVAL"), .tool(.solidOval))
        XCTAssertEqual(AnnotateCommand(path: "/tool/oval"), .tool(.oval))
        XCTAssertEqual(AnnotateCommand(path: "/tool/circle"), .tool(.oval), "Links from before the rename still work")
    }

    // MARK: - Capture record

    func testTheCaptureRecordMarksSolidShapes() {
        let space = CaptureRecord.DisplaySpace(height: 200)
        XCTAssertEqual(CaptureRecord.Shape(solidRectangle(time: 1), space: space).solid, true)
        XCTAssertEqual(CaptureRecord.Shape(solidOval(time: 1), space: space).solid, true)
        XCTAssertNil(CaptureRecord.Shape(TestFactory.createRectangle(), space: space).solid)
        XCTAssertNil(CaptureRecord.Shape(TestFactory.createOval(), space: space).solid)
    }
}
