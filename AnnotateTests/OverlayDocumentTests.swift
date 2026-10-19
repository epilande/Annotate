import XCTest

@testable import Annotate

@MainActor
final class OverlayDocumentTests: XCTestCase, Sendable {
    var sampler: StubRedactionSampler!
    private var originalBoardManager: BoardManager!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppDelegate.shared = nil
            // Rendering consults the board state; keep it off the user's live defaults.
            originalBoardManager = BoardManager.shared
            BoardManager.shared = BoardManager(userDefaults: TestUserDefaults.create())
            sampler = StubRedactionSampler()
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            sampler = nil
            BoardManager.shared = originalBoardManager
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeView() -> OverlayView {
        let view = OverlayView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.pickerUserDefaultsOverride = TestUserDefaults.create()
        view.redactionSampler = sampler
        view.fadeMode = false
        return view
    }

    /// A view hosted in a window, so `needsDisplay` reflects what AppKit would repaint.
    private func makeHostedView() -> (NSWindow, OverlayView) {
        let view = makeView()
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return (window, view)
    }

    private func makeOverlayWindow() -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.overlayView.pickerUserDefaultsOverride = TestUserDefaults.create()
        window.overlayView.redactionSampler = sampler
        window.overlayView.fadeMode = false
        return window
    }

    /// Runs the display pass AppKit would run before the next event. Setting `needsDisplay`
    /// to false does not clear a dirty region the window already holds; displaying does.
    private func displayPendingChanges(of view: OverlayView, file: StaticString = #filePath, line: UInt = #line) {
        view.display()
        XCTAssertFalse(view.needsDisplay, "Nothing is left to display", file: file, line: line)
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(TestEvents.createMouseEvent(type: type, location: point))
    }

    /// Renders the view into a bitmap and returns the color at a view point.
    private func renderedColor(at point: NSPoint, in view: OverlayView) throws -> NSColor {
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.draw(view.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        // Bitmap rows run top-down while the view is bottom-up.
        let color = try XCTUnwrap(rep.colorAt(x: Int(point.x), y: height - 1 - Int(point.y)))
        return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
    }

    private func assertBlack(_ color: NSColor, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01, message, file: file, line: line)
        XCTAssertLessThan(color.redComponent + color.greenComponent + color.blueComponent, 0.05, message, file: file, line: line)
    }

    private func assertNotBlack(_ color: NSColor, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(color.redComponent + color.greenComponent + color.blueComponent, 0.5, message, file: file, line: line)
    }

    private func makeSnapshot(frame: CGRect) throws -> DisplaySnapshot {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: Int(frame.width) * 2, height: Int(frame.height) * 2, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return DisplaySnapshot(image: try XCTUnwrap(context.makeImage()), displayFrame: frame)
    }

    private func steps(of order: [OverlayPaintStep], in layer: Int) -> [OverlayPaintStep] {
        var layers: [[OverlayPaintStep]] = [[]]
        for step in order {
            layers[layers.count - 1].append(step)
            if case .redaction = step { layers.append([]) }
        }
        return layers[layer]
    }

    // MARK: - Bands

    func testBandsPaintStrokesThenShapesThenTextThenRedactionsThenSelection() {
        XCTAssertEqual(OverlayBand.allCases, [.strokes, .shapes, .text, .redactions, .selection])
    }

    func testContentKindsBelongToTheirBandAndKeepTheirOrderWithinIt() {
        XCTAssertEqual(OverlayContent.allCases.filter { $0.band == .strokes }, [.arrows, .lines, .penStrokes, .highlights])
        XCTAssertEqual(OverlayContent.allCases.filter { $0.band == .shapes }, [.outlines, .circles])
        XCTAssertEqual(OverlayContent.allCases.filter { $0.band == .text }, [.labels, .counters])
    }

    func testWithoutRedactionsEverythingPaintsInOneLayerUnderTheSelection() {
        let layer = OverlayDocument.RedactionLayer()
        let expected: [OverlayPaintStep] =
            OverlayContent.allCases.map { .content($0, layer: layer, includesLive: true) }
            + [.liveRedaction, .selection]
        XCTAssertEqual(OverlayDocument().paintOrder(), expected)
    }

    func testEachRedactionClosesTheLayerOfWhatItCovers() {
        var document = OverlayDocument()
        document.rectangles = [
            TestFactory.createRectangle(time: 1),
            Rectangle(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .red, lineWidth: 3, creationTime: 5, style: .solid),
            Rectangle(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .red, lineWidth: 3, creationTime: 2, style: .blur),
        ]
        let order = document.paintOrder()

        let older = OverlayDocument.RedactionLayer(start: -.infinity, end: 2)
        XCTAssertEqual(
            steps(of: order, in: 0),
            OverlayContent.allCases.map { .content($0, layer: older, includesLive: false) } + [.redaction(index: 2)],
            "Everything older than the first redaction, every band of it, paints under that redaction")
        let between = OverlayDocument.RedactionLayer(start: 2, end: 5)
        XCTAssertEqual(
            steps(of: order, in: 1),
            OverlayContent.allCases.map { .content($0, layer: between, includesLive: false) } + [.redaction(index: 1)])
        let newest = OverlayDocument.RedactionLayer(start: 5, end: .infinity)
        XCTAssertEqual(
            steps(of: order, in: 2),
            OverlayContent.allCases.map { .content($0, layer: newest, includesLive: true) } + [.liveRedaction, .selection],
            "Live previews and the selection stay on top")
    }

    // MARK: - #107: redaction draw order

    /// #107 review: redactions painted before circles, labels and counters, so those drew
    /// over a redaction that should hide them. A redaction now covers every band created
    /// before it and stays under what is created after it.
    func testRedactionCoversOlderShapesAndTextButNotNewerText() throws {
        let view = makeView()
        view.circles = [
            TestFactory.createCircle(
                start: NSPoint(x: 60, y: 60), end: NSPoint(x: 140, y: 140), color: .red, lineWidth: 8, time: 1)
        ]
        view.counterAnnotations = [
            CounterAnnotation(number: 1, position: NSPoint(x: 100, y: 100), color: .red, creationTime: 1),
            CounterAnnotation(number: 2, position: NSPoint(x: 140, y: 50), color: .red, creationTime: 3),
        ]
        view.textAnnotations = [
            TextAnnotation(text: "Old", position: NSPoint(x: 60, y: 120), color: .red, fontSize: 18, hasBackground: true, creationTime: 1),
            TextAnnotation(text: "New", position: NSPoint(x: 60, y: 70), color: .red, fontSize: 18, hasBackground: true, creationTime: 3),
        ]
        view.rectangles = [
            Rectangle(
                startPoint: NSPoint(x: 40, y: 40), endPoint: NSPoint(x: 160, y: 160),
                color: .red, lineWidth: 3, creationTime: 2, style: .solid)
        ]

        assertBlack(try renderedColor(at: NSPoint(x: 100, y: 60), in: view), "An older circle is hidden")
        assertBlack(try renderedColor(at: NSPoint(x: 85, y: 100), in: view), "An older counter is hidden")
        assertBlack(try renderedColor(at: NSPoint(x: 56, y: 126), in: view), "An older label is hidden")
        let newerCounter = try renderedColor(at: NSPoint(x: 125, y: 50), in: view)
        XCTAssertGreaterThan(newerCounter.redComponent, 0.75, "A newer counter paints over the redaction")
        XCTAssertLessThan(newerCounter.greenComponent, 0.3)
        assertNotBlack(try renderedColor(at: NSPoint(x: 56, y: 76), in: view), "A newer label paints over the redaction")
    }

    // MARK: - #107: move settle

    /// #107 review: a select-tool move of a pixelate redaction settled without a redraw, so
    /// it never resampled where it landed. Settling now changes the document, which redraws.
    func testSettlingAMovedRedactionRedrawsAndResamplesWhereItLanded() throws {
        let window = makeOverlayWindow()
        defer { window.close() }
        let view: OverlayView = window.overlayView
        view.currentTool = .select
        var redaction = Rectangle(
            startPoint: NSPoint(x: 50, y: 50), endPoint: NSPoint(x: 150, y: 150),
            color: .red, lineWidth: 3, creationTime: 1, style: .pixelate)
        redaction.sample = RedactionSample(
            image: try makeSnapshot(frame: redaction.bounds).image, bounds: redaction.bounds,
            key: RedactionSampleKey(redaction))
        view.rectangles = [redaction]
        view.selectedObjects = [.rectangle(index: 0)]

        window.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 100, y: 100)))
        window.mouseDragged(with: try mouse(.leftMouseDragged, at: NSPoint(x: 130, y: 100)))
        XCTAssertEqual(view.rectangles[0].bounds.origin, NSPoint(x: 80, y: 50))
        displayPendingChanges(of: view)

        window.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: 130, y: 100)))
        XCTAssertTrue(view.needsDisplay, "Settling the move redraws")

        _ = try renderedColor(at: .zero, in: view)
        sampler.completeCaptures(with: try makeSnapshot(frame: window.frame))
        while sampler.hasPendingFilters {
            sampler.completeNextFilter()
        }
        XCTAssertEqual(
            view.rectangles[0].sample?.key, RedactionSampleKey(view.rectangles[0]),
            "Resampled where it landed")
        XCTAssertNil(view.redactionSnapshot)
    }

    func testSettlingAnyMoveRedraws() throws {
        let window = makeOverlayWindow()
        defer { window.close() }
        let view: OverlayView = window.overlayView
        view.currentTool = .select
        view.arrows = [
            TestFactory.createArrow(start: NSPoint(x: 50, y: 100), end: NSPoint(x: 150, y: 100), time: 1)
        ]
        view.selectedObjects = [.arrow(index: 0)]

        window.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 100, y: 100)))
        window.mouseDragged(with: try mouse(.leftMouseDragged, at: NSPoint(x: 120, y: 100)))
        displayPendingChanges(of: view)

        window.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: 120, y: 100)))
        XCTAssertTrue(view.needsDisplay)
    }

    // MARK: - Redraw follows the document

    func testEveryDocumentChangeRedraws() {
        let (window, view) = makeHostedView()
        defer { window.close() }
        view.arrows = [TestFactory.createArrow(time: 1)]
        view.rectangles = [TestFactory.createRectangle(time: 1)]
        view.textAnnotations = [TestFactory.createTextAnnotation()]

        let changes: [(String, (OverlayView) -> Void)] = [
            ("arrows", { $0.arrows.append(TestFactory.createArrow()) }),
            ("lines", { $0.lines.append(Line(startPoint: .zero, endPoint: NSPoint(x: 5, y: 5), color: .red, lineWidth: 3, creationTime: nil)) }),
            ("paths", { $0.paths.append(TestFactory.createDrawingPath(points: [TestFactory.createTimedPoint()])) }),
            ("highlightPaths", { $0.highlightPaths.append(TestFactory.createDrawingPath(points: [TestFactory.createTimedPoint()])) }),
            ("rectangles", { $0.rectangles.append(TestFactory.createRectangle()) }),
            ("circles", { $0.circles.append(TestFactory.createCircle()) }),
            ("textAnnotations", { $0.textAnnotations.append(TestFactory.createTextAnnotation()) }),
            ("counterAnnotations", { $0.counterAnnotations.append(CounterAnnotation(number: 1, position: .zero, color: .red)) }),
            ("moving an element in place", { $0.arrows[0].endPoint.x += 1 }),
            ("a sample landing", { $0.rectangles[0].sample = nil }),
            ("selection", { $0.selectedObjects = [.arrow(index: 0)] }),
            ("drag settle", { $0.selectionDragOffset = nil }),
            ("marquee", { $0.selectionRectEnd = NSPoint(x: 10, y: 10) }),
            ("label being edited", { $0.editingTextAnnotationIndex = 0 }),
        ]
        for (name, change) in changes {
            displayPendingChanges(of: view)
            change(view)
            XCTAssertTrue(view.needsDisplay, "Changing \(name) redraws")
        }
    }

    func testCounterClickRedrawsWithoutTheWindowAskingForIt() throws {
        let window = makeOverlayWindow()
        defer { window.close() }
        let view: OverlayView = window.overlayView
        view.currentTool = .counter
        displayPendingChanges(of: view)

        window.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 100, y: 100)))

        XCTAssertEqual(view.counterAnnotations.count, 1)
        XCTAssertTrue(view.needsDisplay)
    }

    func testTextBoxOutlineRedrawsWithoutTheWindowAskingForIt() throws {
        let window = makeOverlayWindow()
        defer { window.close() }
        let view: OverlayView = window.overlayView
        view.currentTool = .text

        window.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 50, y: 150)))
        displayPendingChanges(of: view)

        window.mouseDragged(with: try mouse(.leftMouseDragged, at: NSPoint(x: 200, y: 120)))
        XCTAssertNotNil(view.textBoxDraftRect)
        XCTAssertTrue(view.needsDisplay, "The outline draws as the drag grows it")

        displayPendingChanges(of: view)
        view.cancelTextBoxDrag()
        XCTAssertNil(view.textBoxDraftRect)
        XCTAssertTrue(view.needsDisplay, "A cancelled drag clears its outline")
    }
}
