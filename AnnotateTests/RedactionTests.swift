import XCTest

@testable import Annotate

/// Records capture and filter requests instead of touching Screen Recording. Both stay
/// pending until the test answers them, mirroring the asynchronous work in production.
/// Filters run the real crop and filter code against the snapshot they were given.
@MainActor
final class StubRedactionSampler: RedactionSampling {
    var isAvailable = true
    private(set) var captureCount = 0
    private(set) var filterRequests: [[RedactionFilterRequest]] = []
    private var captureCompletions: [@MainActor (DisplaySnapshot?) -> Void] = []
    private var filterCompletions: [(requests: [RedactionFilterRequest], snapshot: DisplaySnapshot, completion: @MainActor ([RedactionFilterResult?]) -> Void)] = []

    var canSample: Bool { isAvailable }
    var hasPendingFilters: Bool { !filterCompletions.isEmpty }

    func captureDisplay(under view: NSView, completion: @escaping @MainActor (DisplaySnapshot?) -> Void) {
        captureCount += 1
        captureCompletions.append(completion)
    }

    func filter(
        _ requests: [RedactionFilterRequest], from snapshot: DisplaySnapshot,
        completion: @escaping @MainActor ([RedactionFilterResult?]) -> Void
    ) {
        filterRequests.append(requests)
        filterCompletions.append((requests, snapshot, completion))
    }

    func completeCaptures(with snapshot: DisplaySnapshot?) {
        let pending = captureCompletions
        captureCompletions.removeAll()
        pending.forEach { $0(snapshot) }
    }

    /// Answers the oldest pending filter pass with real results.
    func completeNextFilter() {
        guard !filterCompletions.isEmpty else { return }
        let next = filterCompletions.removeFirst()
        next.completion(next.requests.map {
            ScreenSampler.makeSample(from: next.snapshot, screenRect: $0.screenRect, style: $0.style)
        })
    }

    func failNextFilter() {
        guard !filterCompletions.isEmpty else { return }
        let next = filterCompletions.removeFirst()
        next.completion(next.requests.map { _ in nil })
    }
}

@MainActor
final class RedactionTests: XCTestCase, Sendable {
    var overlayView: OverlayView!
    var sampler: StubRedactionSampler!
    private var originalBoardManager: BoardManager!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppDelegate.shared = nil
            // Redaction rendering consults the board state; keep it off the user's live defaults.
            originalBoardManager = BoardManager.shared
            BoardManager.shared = BoardManager(userDefaults: TestUserDefaults.create())
            overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
            overlayView.pickerUserDefaultsOverride = TestUserDefaults.create()
            sampler = StubRedactionSampler()
            overlayView.redactionSampler = sampler
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            overlayView?.pickerUserDefaultsOverride = nil
            overlayView = nil
            sampler = nil
            BoardManager.shared = originalBoardManager
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRectangle(style: RectangleStyle, creationTime: CFTimeInterval? = nil) -> Rectangle {
        Rectangle(
            startPoint: NSPoint(x: 50, y: 50), endPoint: NSPoint(x: 150, y: 150),
            color: .systemRed, lineWidth: 3, creationTime: creationTime, style: style)
    }

    /// Renders an overlay (the test's own by default) into a bitmap and returns the color
    /// at a view point.
    private func renderedColor(at point: NSPoint, in view: OverlayView? = nil) throws -> NSColor {
        let view = view ?? overlayView!
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

    /// A 2D gradient: red grows left to right and green grows bottom to top (in CGContext
    /// coordinates), so every pixel differs from its neighbors on both axes.
    private func makeGradientImage(size: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<size {
            for y in 0..<size {
                let red = CGFloat(x) / CGFloat(size - 1)
                let green = CGFloat(y) / CGFloat(size - 1)
                context.setFillColor(CGColor(red: red, green: green, blue: 1 - red, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    /// A display image with one color per quadrant as seen on screen: red top-left, green
    /// top-right, blue bottom-left, yellow bottom-right.
    private func makeQuadrantImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let halfWidth = width / 2
        let halfHeight = height / 2
        // CGContext is bottom-up, so the top half starts at halfHeight.
        let quadrants: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight), CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight), CGColor(red: 0, green: 1, blue: 0, alpha: 1)),
            (CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight), CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            (CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight), CGColor(red: 1, green: 1, blue: 0, alpha: 1)),
        ]
        for (rect, color) in quadrants {
            context.setFillColor(color)
            context.fill(rect)
        }
        return try XCTUnwrap(context.makeImage())
    }

    /// A 2x capture of a display that exactly matches `frame`, quadrant colored.
    private func makeSnapshot(frame: CGRect? = nil) throws -> DisplaySnapshot {
        let frame = frame ?? overlayView.bounds
        return DisplaySnapshot(
            image: try makeQuadrantImage(width: Int(frame.width) * 2, height: Int(frame.height) * 2),
            displayFrame: frame)
    }

    /// A ready-made sample that matches `rectangle` where it sits.
    private func makeSample(for rectangle: Rectangle) throws -> RedactionSample {
        RedactionSample(
            image: try makeGradientImage(size: 8), bounds: rectangle.bounds, key: RedactionSampleKey(rectangle))
    }

    /// Plays the display cycle until every redaction has its sample: draw, answer the
    /// capture, answer each filter pass.
    private func settleSamples() throws {
        _ = try renderedColor(at: .zero)
        sampler.completeCaptures(with: try makeSnapshot())
        while sampler.hasPendingFilters {
            sampler.completeNextFilter()
        }
    }

    /// Reads a pixel by bottom-up coordinates, matching Core Image and CGContext; bitmap
    /// rows run top-down.
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> NSColor {
        let rep = NSBitmapImageRep(cgImage: image)
        let color = try XCTUnwrap(rep.colorAt(x: x, y: image.height - 1 - y))
        return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
    }

    /// Asserts an opaque color whose channels are clearly on (1) or off (0). Core Image
    /// color-matches its output, so pure primaries come back a little off.
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

    private func assertBlack(_ color: NSColor, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(color.blueComponent, 0, accuracy: 0.01, message, file: file, line: line)
    }

    private func makeDoubleClick(at location: NSPoint) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 2, pressure: 1))
    }

    /// Hosts the view in a window with its own undo manager so undo actions register.
    private func makeUndoWindow() -> TestWindow {
        let window = TestWindow(
            contentRect: overlayView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlayView
        return window
    }

    // MARK: - Model

    func testRectangleDefaultsToOutline() {
        let rect = TestFactory.createRectangle()
        XCTAssertEqual(rect.style, .outline)
        XCTAssertNil(rect.sample)
        XCTAssertFalse(rect.isRedaction)
        XCTAssertFalse(rect.needsSample)
    }

    func testRedactionFlagsPerStyle() {
        XCTAssertTrue(makeRectangle(style: .solid).isRedaction)
        XCTAssertFalse(makeRectangle(style: .solid).needsSample)
        XCTAssertTrue(makeRectangle(style: .pixelate).isRedaction)
        XCTAssertTrue(makeRectangle(style: .pixelate).needsSample)
        XCTAssertTrue(makeRectangle(style: .blur).isRedaction)
        XCTAssertTrue(makeRectangle(style: .blur).needsSample)
    }

    func testEqualityComparesStyleButIgnoresSample() throws {
        var withSample = makeRectangle(style: .pixelate)
        withSample.sample = try makeSample(for: withSample)
        let withoutSample = makeRectangle(style: .pixelate)
        XCTAssertEqual(withSample, withoutSample, "The sample is derived data, not identity")

        XCTAssertNotEqual(makeRectangle(style: .pixelate), makeRectangle(style: .outline))
        XCTAssertNotEqual(makeRectangle(style: .solid), makeRectangle(style: .blur))
    }

    func testRedactionStyleSettingDefaultsToSolidAndNeverOutline() {
        let defaults = TestUserDefaults.create()
        XCTAssertEqual(defaults.redactionStyle, .solid)

        defaults.redactionStyle = .blur
        XCTAssertEqual(defaults.redactionStyle, .blur)

        defaults.set("outline", forKey: UserDefaults.redactionStyleKey)
        XCTAssertEqual(defaults.redactionStyle, .solid, "A redaction must always hide")

        defaults.set("mosaic", forKey: UserDefaults.redactionStyleKey)
        XCTAssertEqual(defaults.redactionStyle, .solid)
    }

    // MARK: - Tool wiring

    func testRedactToolIsWiredWithAUniqueDefaultShortcut() {
        XCTAssertTrue(ToolType.allCases.contains(.redact))
        XCTAssertEqual(ToolType.redact.displayName, "Redact")
        XCTAssertEqual(ToolType.redact.shortcutKey, .redact)
        XCTAssertEqual(ToolType.redact.symbolName, "eye.slash")
        XCTAssertEqual(ShortcutKey.redact.defaultBinding, ShortcutBinding("x"))
        XCTAssertFalse(ShortcutKey.redact.defaultBinding.isReserved)

        let others = ShortcutKey.allCases.filter { $0 != .redact && !$0.defaultKey.isEmpty }
        XCTAssertFalse(
            others.contains { $0.defaultBinding == ShortcutKey.redact.defaultBinding },
            "Redact's default binding must not collide with another default")
    }

    func testRedactToolCreatesRectangleWithSavedStyle() throws {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.close() }
        let defaults = TestUserDefaults.create()
        defaults.redactionStyle = .pixelate
        window.overlayView.pickerUserDefaultsOverride = defaults
        window.overlayView.redactionSampler = sampler
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .redact

        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 20, y: 20))))
        XCTAssertEqual(window.overlayView.currentRectangle?.style, .pixelate)
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 120, y: 90))))
        window.mouseUp(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseUp, location: NSPoint(x: 120, y: 90))))

        XCTAssertNil(window.overlayView.currentRectangle)
        XCTAssertEqual(window.overlayView.rectangles.count, 1)
        XCTAssertEqual(window.overlayView.rectangles.first?.style, .pixelate)
        XCTAssertEqual(window.overlayView.rectangles.first?.bounds, NSRect(x: 20, y: 20, width: 100, height: 70))

        window.overlayView.currentTool = .rectangle
        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 200, y: 200))))
        XCTAssertEqual(window.overlayView.currentRectangle?.style, .outline)
        window.mouseUp(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseUp, location: NSPoint(x: 250, y: 250))))
        XCTAssertEqual(window.overlayView.rectangles.last?.style, .outline)
    }

    // MARK: - Coordinate conversion

    func testDisplayLocalRectOnPrimaryDisplay() throws {
        let display = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let rect = try XCTUnwrap(
            ScreenSampler.displayLocalRect(
                screenRect: CGRect(x: 100, y: 980, width: 200, height: 50), displayFrame: display))
        XCTAssertEqual(rect, CGRect(x: 100, y: 50, width: 200, height: 50))
    }

    func testDisplayLocalRectOnSecondaryDisplayWithNegativeOrigin() throws {
        let display = CGRect(x: -1_440, y: -200, width: 1_440, height: 900)
        let rect = try XCTUnwrap(
            ScreenSampler.displayLocalRect(
                screenRect: CGRect(x: -1_000, y: 0, width: 100, height: 100), displayFrame: display))
        XCTAssertEqual(rect, CGRect(x: 440, y: 600, width: 100, height: 100))
    }

    func testDisplayLocalRectClampsToDisplayAndSkipsEmptyRects() {
        let display = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(
            ScreenSampler.displayLocalRect(
                screenRect: CGRect(x: -50, y: 550, width: 100, height: 100), displayFrame: display),
            CGRect(x: 0, y: 0, width: 50, height: 50))
        XCTAssertNil(
            ScreenSampler.displayLocalRect(
                screenRect: CGRect(x: 900, y: 0, width: 10, height: 10), displayFrame: display))
        XCTAssertNil(
            ScreenSampler.displayLocalRect(
                screenRect: CGRect(x: 10, y: 10, width: 0.5, height: 20), displayFrame: display))
    }

    func testPixelRectOnA2xMainDisplay() throws {
        let display = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let screenRect = CGRect(x: 100, y: 980, width: 200, height: 50.5)
        let rect = try XCTUnwrap(ScreenSampler.pixelRect(screenRect: screenRect, displayFrame: display, scale: 2))
        XCTAssertEqual(rect, CGRect(x: 200, y: 99, width: 400, height: 101), "Top-left origin, in pixels")
        XCTAssertEqual(ScreenSampler.screenRect(pixelRect: rect, displayFrame: display, scale: 2), screenRect)
    }

    func testPixelRectOnAPortraitSecondaryDisplayWithNegativeOrigin() throws {
        // A 1440x2560 pt portrait display at 2x, right of a 1920x1080 main display and
        // hanging below it, so its frame starts below the main display's origin.
        let display = CGRect(x: 1_920, y: -693, width: 1_440, height: 2_560)
        let nearTop = CGRect(x: 2_020, y: 1_767, width: 300, height: 50)
        let rect = try XCTUnwrap(ScreenSampler.pixelRect(screenRect: nearTop, displayFrame: display, scale: 2))
        XCTAssertEqual(rect, CGRect(x: 200, y: 100, width: 600, height: 100))
        XCTAssertEqual(ScreenSampler.screenRect(pixelRect: rect, displayFrame: display, scale: 2), nearTop)

        let bottomLeft = CGRect(x: 1_920, y: -693, width: 10, height: 10)
        XCTAssertEqual(
            ScreenSampler.pixelRect(screenRect: bottomLeft, displayFrame: display, scale: 2),
            CGRect(x: 0, y: 5_100, width: 20, height: 20), "The bottom-left corner is the last pixel rows")
        XCTAssertNil(
            ScreenSampler.pixelRect(
                screenRect: CGRect(x: 100, y: 100, width: 50, height: 50), displayFrame: display, scale: 2),
            "A rect on the main display is not on this one")
    }

    // MARK: - Filters

    func testCropKeepsRegionForBothStyles() throws {
        let snapshot = try makeSnapshot()
        let cases: [(CGRect, (CGFloat, CGFloat, CGFloat), String)] = [
            (CGRect(x: 10, y: 120, width: 60, height: 60), (1, 0, 0), "top-left is red"),
            (CGRect(x: 130, y: 120, width: 60, height: 60), (0, 1, 0), "top-right is green"),
            (CGRect(x: 10, y: 10, width: 60, height: 60), (0, 0, 1), "bottom-left is blue"),
            (CGRect(x: 130, y: 10, width: 60, height: 60), (1, 1, 0), "bottom-right is yellow"),
        ]
        for style in [RectangleStyle.pixelate, .blur] {
            for (rect, (red, green, blue), message) in cases {
                let result = try XCTUnwrap(ScreenSampler.makeSample(from: snapshot, screenRect: rect, style: style))
                XCTAssertTrue(result.screenRect.contains(rect), "\(style): covers the rectangle")
                let center = try pixel(result.image, x: result.image.width / 2, y: result.image.height / 2)
                assertColor(center, red: red, green: green, blue: blue, "\(style): \(message)")
            }
        }
    }

    func testPixelateSpansQuadrantsRightSideUp() throws {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        let result = try XCTUnwrap(ScreenSampler.makeSample(from: try makeSnapshot(), screenRect: rect, style: .pixelate))
        // 200 px at 2x uses the 20 px minimum block: ten blocks a side, one pixel each.
        XCTAssertEqual(result.image.width, 10)
        XCTAssertEqual(result.image.height, 10)
        XCTAssertEqual(result.screenRect, rect, "Already on the display's block grid")
        assertColor(try pixel(result.image, x: 0, y: 9), red: 1, green: 0, blue: 0, "top-left")
        assertColor(try pixel(result.image, x: 9, y: 9), red: 0, green: 1, blue: 0, "top-right")
        assertColor(try pixel(result.image, x: 0, y: 0), red: 0, green: 0, blue: 1, "bottom-left")
        assertColor(try pixel(result.image, x: 9, y: 0), red: 1, green: 1, blue: 0, "bottom-right")
    }

    func testPixelateAveragesEachBlock() throws {
        // One-pixel black and white stripes: any single pixel is black or white, the average gray.
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for x in stride(from: 0, to: 40, by: 2) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: 40))
        }
        let snapshot = DisplaySnapshot(
            image: try XCTUnwrap(context.makeImage()), displayFrame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let rect = CGRect(x: 0, y: 10, width: 10, height: 10)
        let result = try XCTUnwrap(ScreenSampler.makeSample(from: snapshot, screenRect: rect, style: .pixelate))
        XCTAssertEqual(result.screenRect, rect, "One 20 px block")
        let block = try pixel(result.image, x: 0, y: 0)
        for channel in [block.redComponent, block.greenComponent, block.blueComponent] {
            XCTAssertGreaterThan(channel, 0.2, "Averaged, not a single sampled pixel")
            XCTAssertLessThan(channel, 0.9, "Averaged, not a single sampled pixel")
        }
    }

    func testPixelateGridIsAnchoredToTheDisplay() throws {
        let snapshot = try makeSnapshot()
        let first = try XCTUnwrap(
            ScreenSampler.makeSample(from: snapshot, screenRect: CGRect(x: 55, y: 43, width: 100, height: 100), style: .pixelate))
        let nudged = try XCTUnwrap(
            ScreenSampler.makeSample(from: snapshot, screenRect: CGRect(x: 57, y: 45, width: 100, height: 100), style: .pixelate))
        // Both round out to the same 20 px (10 pt) blocks counted from the display's top-left.
        XCTAssertEqual(first.screenRect, CGRect(x: 50, y: 40, width: 110, height: 110))
        XCTAssertEqual(nudged.screenRect, first.screenRect, "Blocks stay put as the rectangle moves")
        XCTAssertEqual(first.image.width, 11)
        for (x, y) in [(0, 0), (5, 5), (10, 10), (2, 8)] {
            let a = try pixel(first.image, x: x, y: y)
            let b = try pixel(nudged.image, x: x, y: y)
            XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.01)
            XCTAssertEqual(a.greenComponent, b.greenComponent, accuracy: 0.01)
            XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.01)
        }
    }

    func testBlurReadsPastTheCropForNaturalEdges() throws {
        // Inside the red quadrant, with the right edge on the green one.
        let rect = CGRect(x: 40, y: 120, width: 60, height: 60)
        let result = try XCTUnwrap(ScreenSampler.makeSample(from: try makeSnapshot(), screenRect: rect, style: .blur))
        XCTAssertEqual(result.screenRect, rect)
        // A 40 px sigma is stored at a fifth of the crop resolution.
        XCTAssertEqual(result.image.width, 24)
        XCTAssertEqual(result.image.height, 24)
        let middleRow = result.image.height / 2
        let rightEdge = try pixel(result.image, x: result.image.width - 1, y: middleRow)
        XCTAssertGreaterThan(rightEdge.greenComponent, 0.2, "Green from beyond the crop blends in, instead of clamped red")
        let leftEdge = try pixel(result.image, x: 0, y: middleRow)
        assertColor(leftEdge, red: 1, green: 0, blue: 0, "Three sigma from the boundary stays red")
        XCTAssertGreaterThan(rightEdge.greenComponent - leftEdge.greenComponent, 0.2)
        for (x, y) in [(0, 0), (23, 23), (0, 23), (23, 0)] {
            XCTAssertEqual(try pixel(result.image, x: x, y: y).alphaComponent, 1, accuracy: 0.01, "Opaque at \(x),\(y)")
        }
    }

    func testFiltersStayOpaqueWhereTheRectangleLeavesTheDisplay() throws {
        let rect = CGRect(x: 170, y: -20, width: 60, height: 60)
        for style in [RectangleStyle.pixelate, .blur] {
            let result = try XCTUnwrap(ScreenSampler.makeSample(from: try makeSnapshot(), screenRect: rect, style: style))
            XCTAssertEqual(result.screenRect, CGRect(x: 170, y: 0, width: 30, height: 40), "\(style): clipped to the display")
            let corner = try pixel(result.image, x: result.image.width - 1, y: 0)
            assertColor(corner, red: 1, green: 1, blue: 0, "\(style): the display edge repeats instead of fading")
        }
    }

    func testPixelBlockSizeGrowsInPowerOfTwoSteps() {
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 64, height: 64, scale: 1), 10)
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 100, height: 100, scale: 2), 20)
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 1_200, height: 600, scale: 2), 40)
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 1_200, height: 959, scale: 2), 40)
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 1_200, height: 960, scale: 2), 80)
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 3_840, height: 2_160, scale: 2), 160)
    }

    func testBlurSigmaGrowsWithLargeCaptures() {
        XCTAssertEqual(ScreenSampler.blurSigma(forPixelWidth: 100, height: 100, scale: 2), 40)
        XCTAssertEqual(ScreenSampler.blurSigma(forPixelWidth: 1_200, height: 800, scale: 2), 100)
    }

    func testMakeSampleSkipsStylesThatNeedNoPixelsAndRectsOffTheDisplay() throws {
        let snapshot = try makeSnapshot()
        let rect = CGRect(x: 10, y: 10, width: 50, height: 50)
        XCTAssertNil(ScreenSampler.makeSample(from: snapshot, screenRect: rect, style: .outline))
        XCTAssertNil(ScreenSampler.makeSample(from: snapshot, screenRect: rect, style: .solid))
        XCTAssertNil(
            ScreenSampler.makeSample(
                from: snapshot, screenRect: CGRect(x: 300, y: 10, width: 50, height: 50), style: .blur))
    }

    // MARK: - Rendering

    func testSampleLessPixelateRendersOpaqueBlackPlaceholder() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate)]
        assertBlack(try renderedColor(at: NSPoint(x: 100, y: 100)))
    }

    func testRedactionHidesOlderAnnotations() throws {
        overlayView.fadeMode = false
        var stroke = TestFactory.createDrawingPath(
            points: [TestFactory.createTimedPoint(x: 60, y: 90), TestFactory.createTimedPoint(x: 140, y: 90)],
            color: .red, lineWidth: 6)
        stroke.creationTime = 1
        overlayView.paths = [stroke]
        overlayView.arrows = [
            TestFactory.createArrow(
                start: NSPoint(x: 60, y: 110), end: NSPoint(x: 140, y: 110), color: .red, lineWidth: 6, time: 1)
        ]
        overlayView.rectangles = [makeRectangle(style: .solid, creationTime: 2)]

        assertBlack(try renderedColor(at: NSPoint(x: 80, y: 90)), "A pen stroke drawn before is hidden")
        assertBlack(try renderedColor(at: NSPoint(x: 80, y: 110)), "An arrow drawn before is hidden")
    }

    func testAnnotationsDrawnAfterARedactionShowOnTop() throws {
        overlayView.fadeMode = false
        var stroke = TestFactory.createDrawingPath(
            points: [TestFactory.createTimedPoint(x: 60, y: 90), TestFactory.createTimedPoint(x: 140, y: 90)],
            color: .red, lineWidth: 6)
        stroke.creationTime = 3
        overlayView.paths = [stroke]
        overlayView.arrows = [
            TestFactory.createArrow(
                start: NSPoint(x: 60, y: 110), end: NSPoint(x: 140, y: 110), color: .red, lineWidth: 6, time: 3)
        ]
        overlayView.rectangles = [makeRectangle(style: .solid, creationTime: 2)]

        assertColor(try renderedColor(at: NSPoint(x: 80, y: 90)), red: 1, green: 0, blue: 0, "A later pen stroke")
        assertColor(try renderedColor(at: NSPoint(x: 80, y: 110)), red: 1, green: 0, blue: 0, "A later arrow")
        assertBlack(try renderedColor(at: NSPoint(x: 100, y: 130)), "The redaction still hides the screen around them")
    }

    func testInProgressAnnotationsDrawOverRedactions() throws {
        overlayView.rectangles = [makeRectangle(style: .solid, creationTime: CACurrentMediaTime())]
        overlayView.currentArrow = TestFactory.createArrow(
            start: NSPoint(x: 60, y: 100), end: NSPoint(x: 140, y: 100), color: .red, lineWidth: 6)

        assertColor(try renderedColor(at: NSPoint(x: 80, y: 100)), red: 1, green: 0, blue: 0)
    }

    func testRedactionsLayerByCreationNotByKind() throws {
        overlayView.fadeMode = false
        // An older redaction under a circle, a newer one over it, side by side.
        overlayView.circles = [
            TestFactory.createCircle(
                start: NSPoint(x: 20, y: 20), end: NSPoint(x: 180, y: 180), color: .red, lineWidth: 6, time: 2)
        ]
        overlayView.rectangles = [
            Rectangle(
                startPoint: NSPoint(x: 0, y: 80), endPoint: NSPoint(x: 40, y: 120),
                color: .systemRed, lineWidth: 3, creationTime: 3, style: .solid),
            Rectangle(
                startPoint: NSPoint(x: 160, y: 80), endPoint: NSPoint(x: 200, y: 120),
                color: .systemRed, lineWidth: 3, creationTime: 1, style: .solid),
        ]
        XCTAssertEqual(overlayView.redactionIndicesByCreation, [1, 0])

        assertBlack(try renderedColor(at: NSPoint(x: 20, y: 100)), "The newer redaction covers the circle")
        assertColor(try renderedColor(at: NSPoint(x: 180, y: 100)), red: 1, green: 0, blue: 0, "The older one sits under it")
    }

    func testWithoutRedactionsKindsKeepTheirPaintOrder() throws {
        overlayView.fadeMode = false
        // A newer arrow still paints under an older circle: kinds keep their fixed order.
        overlayView.arrows = [
            TestFactory.createArrow(
                start: NSPoint(x: 20, y: 100), end: NSPoint(x: 180, y: 100), color: .blue, lineWidth: 8, time: 2)
        ]
        overlayView.circles = [
            TestFactory.createCircle(
                start: NSPoint(x: 40, y: 40), end: NSPoint(x: 160, y: 160), color: .red, lineWidth: 8, time: 1)
        ]
        XCTAssertTrue(overlayView.redactionIndicesByCreation.isEmpty)

        assertColor(try renderedColor(at: NSPoint(x: 40, y: 100)), red: 1, green: 0, blue: 0, "The circle paints last")
        assertColor(try renderedColor(at: NSPoint(x: 100, y: 100)), red: 0, green: 0, blue: 1)
    }

    func testSolidRendersOpaqueBlackAndOutlineStaysClear() throws {
        overlayView.rectangles = [makeRectangle(style: .solid)]
        assertBlack(try renderedColor(at: NSPoint(x: 100, y: 100)))

        overlayView.rectangles = [makeRectangle(style: .outline)]
        let outline = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(outline.alphaComponent, 0, accuracy: 0.01, "An outline leaves its interior clear")
    }

    func testDrawCapturesOnceFiltersTheCropAndReleasesTheSnapshot() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate), makeRectangle(style: .solid)]
        _ = try renderedColor(at: .zero)
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1, "One display capture while it is in flight")
        XCTAssertTrue(sampler.filterRequests.isEmpty)

        sampler.completeCaptures(with: try makeSnapshot())
        XCTAssertNotNil(overlayView.redactionSnapshot)
        XCTAssertEqual(sampler.filterRequests.count, 1)
        XCTAssertEqual(sampler.filterRequests.first?.count, 1, "Solid never needs pixels")
        XCTAssertEqual(sampler.filterRequests.first?.first?.screenRect, overlayView.rectangles[0].bounds)
        XCTAssertEqual(sampler.filterRequests.first?.first?.style, .pixelate)

        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.filterRequests.count, 1, "One filter pass at a time")

        sampler.completeNextFilter()
        XCTAssertEqual(overlayView.rectangles[0].sample?.key, RedactionSampleKey(overlayView.rectangles[0]))
        XCTAssertNil(overlayView.rectangles[1].sample)
        XCTAssertNil(overlayView.redactionSnapshot, "Released once nothing needs it")

        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1, "A sampled rectangle is not captured again")
        XCTAssertEqual(sampler.filterRequests.count, 1)
    }

    func testAppliedSampleShowsTheContentUnderTheRectangle() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate)]
        assertBlack(try renderedColor(at: NSPoint(x: 70, y: 130)), "Placeholder before the sample")

        try settleSamples()
        assertColor(try renderedColor(at: NSPoint(x: 70, y: 130)), red: 1, green: 0, blue: 0, "Top-left of the display")
        assertColor(try renderedColor(at: NSPoint(x: 130, y: 70)), red: 1, green: 1, blue: 0, "Bottom-right of the display")
    }

    func testNewerSampledRedactionKeepsAnOlderSolidOneOpaque() throws {
        overlayView.fadeMode = false
        overlayView.rectangles = [
            makeRectangle(style: .solid, creationTime: 1),
            Rectangle(
                startPoint: NSPoint(x: 100, y: 100), endPoint: NSPoint(x: 190, y: 190),
                color: .systemRed, lineWidth: 3, creationTime: 3, style: .pixelate),
        ]
        // Drawn between the two: over the solid block, but under the newer pixelate.
        overlayView.arrows = [
            TestFactory.createArrow(
                start: NSPoint(x: 60, y: 120), end: NSPoint(x: 185, y: 120), color: .red, lineWidth: 6, time: 2)
        ]
        try settleSamples()

        assertBlack(
            try renderedColor(at: NSPoint(x: 120, y: 140)),
            "A sampled redaction never shows real content over a solid one")
        assertBlack(try renderedColor(at: NSPoint(x: 120, y: 120)), "The overlap hides the arrow too")
        assertColor(try renderedColor(at: NSPoint(x: 70, y: 120)), red: 1, green: 0, blue: 0, "The arrow over the solid block alone")
        assertColor(try renderedColor(at: NSPoint(x: 170, y: 170)), red: 0, green: 1, blue: 0, "The pixelate alone shows its sample")
    }

    func testLiveSampledRedactionNeverCoversASolidOne() throws {
        overlayView.rectangles = [makeRectangle(style: .solid)]
        var live = Rectangle(
            startPoint: NSPoint(x: 100, y: 100), endPoint: NSPoint(x: 190, y: 190),
            color: .systemRed, lineWidth: 3, style: .blur)
        live.sample = try makeSample(for: live)
        overlayView.currentRectangle = live

        assertBlack(try renderedColor(at: NSPoint(x: 120, y: 120)), "The solid block still hides the overlap")
        let liveOnly = try renderedColor(at: NSPoint(x: 170, y: 170))
        XCTAssertGreaterThan(liveOnly.redComponent + liveOnly.greenComponent + liveOnly.blueComponent, 0.5)
    }

    func testSuccessfulCaptureAndClearAllResetFailedKeys() throws {
        overlayView.rectangles = [makeRectangle(style: .blur)]
        _ = try renderedColor(at: .zero)
        sampler.completeCaptures(with: nil)
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1)

        overlayView.clearAll()
        overlayView.rectangles = [makeRectangle(style: .blur)]
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 2, "Clear All forgets earlier failures")

        sampler.completeCaptures(with: nil)
        overlayView.rectangles.append(
            Rectangle(
                startPoint: NSPoint(x: 0, y: 0), endPoint: NSPoint(x: 40, y: 40),
                color: .systemRed, lineWidth: 3, style: .pixelate))
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 3)
        sampler.completeCaptures(with: try makeSnapshot())
        XCTAssertEqual(sampler.filterRequests.last?.count, 2, "A successful capture lets the failed one retry")
    }

    func testFailuresLeaveThePlaceholderAndDoNotRetryUntilTheRectangleChanges() throws {
        overlayView.rectangles = [makeRectangle(style: .blur)]
        _ = try renderedColor(at: .zero)
        sampler.completeCaptures(with: nil)
        XCTAssertNil(overlayView.rectangles[0].sample)
        assertBlack(try renderedColor(at: NSPoint(x: 100, y: 100)))
        XCTAssertEqual(sampler.captureCount, 1, "A failed key is not spammed on every redraw")

        overlayView.selectedObjects = [.rectangle(index: 0)]
        overlayView.moveSelectedObjects(by: NSPoint(x: 10, y: 0))
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 2, "Moving yields a new key and a fresh capture")

        sampler.completeCaptures(with: try makeSnapshot())
        sampler.failNextFilter()
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.filterRequests.count, 1, "A failed filter is not retried either")
        XCTAssertNil(overlayView.redactionSnapshot)
    }

    func testFailedCaptureIsNotRetriedForTheRestOfADrag() throws {
        overlayView.currentRectangle = makeRectangle(style: .pixelate)
        overlayView.beginRedactionDrag()
        XCTAssertEqual(sampler.captureCount, 1, "The drag captures right away")
        sampler.completeCaptures(with: nil)

        overlayView.currentRectangle?.endPoint = NSPoint(x: 170, y: 170)
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1)
        assertBlack(try renderedColor(at: NSPoint(x: 100, y: 100)))
    }

    func testNoCaptureWithoutScreenCaptureAccess() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate)]

        sampler.isAvailable = false
        _ = try renderedColor(at: .zero)
        overlayView.currentRectangle = makeRectangle(style: .blur)
        overlayView.beginRedactionDrag()
        XCTAssertEqual(sampler.captureCount, 0, "No access means the placeholder stays")
        overlayView.endRedactionDrag()
        overlayView.currentRectangle = nil

        sampler.isAvailable = true
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1)
    }

    func testBoardEnabledDrawsSolidOnlyAndDoesNotSample() throws {
        BoardManager.shared.isEnabled = true
        overlayView.updateAdaptColors(boardEnabled: true)
        overlayView.rectangles = [makeRectangle(style: .pixelate)]

        let center = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(sampler.captureCount, 0, "A visible board never captures the screen")
        XCTAssertNil(overlayView.rectangles[0].sample)

        let expected = try XCTUnwrap(
            overlayView.redactionPlaceholderColor.usingColorSpace(.deviceRGB))
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(center.redComponent, expected.redComponent, accuracy: 0.02)
        XCTAssertEqual(center.greenComponent, expected.greenComponent, accuracy: 0.02)
        XCTAssertEqual(center.blueComponent, expected.blueComponent, accuracy: 0.02)
    }

    func testTurningTheBoardOffRequestsASample() throws {
        BoardManager.shared.isEnabled = true
        overlayView.updateAdaptColors(boardEnabled: true)
        overlayView.rectangles = [makeRectangle(style: .blur)]
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 0)

        BoardManager.shared.isEnabled = false
        overlayView.updateAdaptColors(boardEnabled: false)
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1, "The first draw without the board samples")
    }

    func testPasteClearsTheSampleAndResamples() throws {
        var rect = makeRectangle(style: .pixelate)
        rect.sample = try makeSample(for: rect)
        overlayView.rectangles = [rect]
        overlayView.selectedObjects = [.rectangle(index: 0)]

        overlayView.duplicateSelectedObjects()
        XCTAssertEqual(overlayView.rectangles.count, 2)
        XCTAssertNotNil(overlayView.rectangles[0].sample)
        XCTAssertNil(overlayView.rectangles[1].sample, "The copy's pixels belong to the original spot")

        _ = try renderedColor(at: .zero)
        sampler.completeCaptures(with: try makeSnapshot())
        XCTAssertEqual(sampler.filterRequests.first?.map(\.screenRect), [overlayView.rectangles[1].bounds])
    }

    func testUndoingAMoveClearsTheSampleAndResamples() throws {
        let window = makeUndoWindow()
        defer { window.close() }
        let original = makeRectangle(style: .pixelate)
        var moved = original
        moved.startPoint = NSPoint(x: 60, y: 60)
        moved.endPoint = NSPoint(x: 160, y: 160)
        moved.sample = try makeSample(for: moved)
        overlayView.rectangles = [moved]
        overlayView.registerMoveUndo(
            object: .rectangle(index: 0),
            from: (original.startPoint, original.endPoint), to: (moved.startPoint, moved.endPoint))

        overlayView.undo()
        XCTAssertEqual(overlayView.rectangles[0].bounds, original.bounds)
        XCTAssertNil(overlayView.rectangles[0].sample)
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1)
    }

    func testUndoingADeleteRestoresARedactionWithoutItsStaleSample() throws {
        let window = makeUndoWindow()
        defer { window.close() }
        var rect = makeRectangle(style: .pixelate)
        rect.sample = try makeSample(for: rect)
        overlayView.rectangles = [rect]
        overlayView.selectedObjects = [.rectangle(index: 0)]

        overlayView.deleteSelectedObjects()
        XCTAssertTrue(overlayView.rectangles.isEmpty)

        overlayView.undo()
        XCTAssertEqual(overlayView.rectangles.count, 1)
        XCTAssertNil(overlayView.rectangles[0].sample, "Undo must not bring back the old captured image")

        // A cleared sample means the draw loop asks for a fresh one instead of reusing the
        // stale picture that was on the undo stack.
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 1)
    }

    func testMovingKeepsTheOldSampleWhereItCameFromUntilTheNewOneLands() throws {
        var rect = makeRectangle(style: .pixelate)
        rect.sample = try makeSample(for: rect)
        overlayView.rectangles = [rect]
        overlayView.selectedObjects = [.rectangle(index: 0)]

        overlayView.moveSelectedObjects(by: NSPoint(x: 10, y: 0))
        XCTAssertEqual(overlayView.rectangles[0].bounds.origin, NSPoint(x: 60, y: 50))
        XCTAssertEqual(overlayView.rectangles[0].sample?.bounds, rect.bounds, "Still where its pixels came from")

        let overlap = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertGreaterThan(overlap.redComponent + overlap.greenComponent + overlap.blueComponent, 0.5)
        assertBlack(
            try renderedColor(at: NSPoint(x: 155, y: 100)),
            "Newly covered ground stays on the placeholder until its sample lands")
        XCTAssertEqual(sampler.captureCount, 1, "The new spot is sampled")
    }

    func testHidingTheOverlayDiscardsSamplesSoTheyAreRetaken() throws {
        overlayView.rectangles = [makeRectangle(style: .blur)]
        try settleSamples()
        XCTAssertNotNil(overlayView.rectangles[0].sample)

        overlayView.discardRedactionSamples()
        XCTAssertNil(overlayView.rectangles[0].sample, "What was under it may have changed while hidden")
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.captureCount, 2, "Shown again, it samples from a fresh capture")
    }

    // MARK: - Live preview

    func testDraggingARedactionPreviewsLiveFromOneSnapshot() throws {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.close() }
        let view: OverlayView = window.overlayView
        let defaults = TestUserDefaults.create()
        defaults.redactionStyle = .pixelate
        view.pickerUserDefaultsOverride = defaults
        view.redactionSampler = sampler
        view.fadeMode = false
        view.currentTool = .redact

        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 20, y: 20))))
        XCTAssertEqual(sampler.captureCount, 1, "The drag captures the display as it starts")
        sampler.completeCaptures(with: try makeSnapshot(frame: window.frame))

        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 120, y: 90))))
        _ = try renderedColor(at: .zero, in: view)
        XCTAssertEqual(sampler.filterRequests.last?.first?.screenRect, window.convertToScreen(CGRect(x: 20, y: 20, width: 100, height: 70)))
        sampler.completeNextFilter()
        XCTAssertNotNil(view.currentRectangle?.sample)
        assertColor(try renderedColor(at: NSPoint(x: 60, y: 50), in: view), red: 0, green: 0, blue: 1, "Live preview of the bottom-left")

        // Two more drag events while a pass runs: only the newest geometry is filtered next.
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 300, y: 250))))
        _ = try renderedColor(at: .zero, in: view)
        XCTAssertEqual(sampler.filterRequests.count, 2)
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 320, y: 260))))
        _ = try renderedColor(at: .zero, in: view)
        XCTAssertEqual(sampler.filterRequests.count, 2, "Nothing queues behind the pass in flight")

        sampler.completeNextFilter()
        XCTAssertEqual(
            view.currentRectangle?.sample?.key.bounds, CGRect(x: 20, y: 20, width: 280, height: 230),
            "The dragged rectangle takes the newer sample even though it has moved on")
        XCTAssertEqual(sampler.filterRequests.count, 3)
        XCTAssertEqual(sampler.filterRequests.last?.first?.screenRect, window.convertToScreen(CGRect(x: 20, y: 20, width: 300, height: 240)))
        sampler.completeNextFilter()

        window.mouseUp(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseUp, location: NSPoint(x: 320, y: 260))))
        XCTAssertEqual(view.rectangles.count, 1)
        XCTAssertEqual(view.rectangles[0].sample?.key, RedactionSampleKey(view.rectangles[0]), "Placed with its final sample")
        XCTAssertFalse(view.isRedactionDragActive)
        XCTAssertNil(view.redactionSnapshot, "The snapshot is released after the drag")
        XCTAssertEqual(sampler.captureCount, 1, "The whole drag used one capture")
        assertColor(try renderedColor(at: NSPoint(x: 280, y: 230), in: view), red: 0, green: 1, blue: 0, "Top-right")
        assertColor(try renderedColor(at: NSPoint(x: 40, y: 230), in: view), red: 1, green: 0, blue: 0, "Top-left")
    }

    /// A tool-switch hotkey mid-drag used to route mouse-up to the new tool's branch, which
    /// neither released the snapshot nor committed the redaction. The redaction then stayed
    /// painted but out of reach of select, erase, and undo, and vanished on the next drag.
    func testToolSwitchMidRedactionDragStillCommitsAndEndsTheDrag() throws {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.close() }
        let view: OverlayView = window.overlayView
        let defaults = TestUserDefaults.create()
        defaults.redactionStyle = .blur
        view.pickerUserDefaultsOverride = defaults
        view.redactionSampler = sampler
        view.fadeMode = false
        view.currentTool = .redact

        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 20, y: 20))))
        sampler.completeCaptures(with: try makeSnapshot(frame: window.frame))
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 120, y: 90))))
        XCTAssertTrue(view.isRedactionDragActive, "A blur/pixelate drag starts a live preview")
        XCTAssertNotNil(view.redactionSnapshot)

        view.currentTool = .pen
        window.mouseUp(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseUp, location: NSPoint(x: 120, y: 90))))

        XCTAssertFalse(view.isRedactionDragActive)
        XCTAssertNil(view.currentRectangle)
        XCTAssertEqual(view.rectangles.count, 1, "Committed on the tool the drag started with")
        // The snapshot stays until the settled geometry has its sample, then goes.
        while sampler.hasPendingFilters {
            sampler.completeNextFilter()
        }
        XCTAssertNotNil(view.rectangles.first?.sample)
        XCTAssertNil(view.redactionSnapshot, "The snapshot is released after the drag")
        XCTAssertEqual(view.rectangles.first?.style, .blur)
        XCTAssertEqual(view.rectangles.first?.bounds, NSRect(x: 20, y: 20, width: 100, height: 70))
        XCTAssertTrue(view.paths.isEmpty)
        XCTAssertTrue(window.undoManager?.canUndo ?? false)

        view.undo()
        XCTAssertTrue(view.rectangles.isEmpty, "The redaction is on the undo stack")
    }

    /// A mouse-up can go missing, for example when macOS rejects a synthesized event. The
    /// next mouse-down used to start over the live rectangle, so a finished solid redaction
    /// vanished without a trace and uncovered what it hid.
    func testMouseDownAfterALostMouseUpCommitsTheLiveRedaction() throws {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.close() }
        let view: OverlayView = window.overlayView
        let defaults = TestUserDefaults.create()
        defaults.redactionStyle = .solid
        view.pickerUserDefaultsOverride = defaults
        view.redactionSampler = sampler
        view.fadeMode = false
        view.currentTool = .redact

        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 20, y: 20))))
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 120, y: 90))))

        // No mouse-up. The next drag starts on another spot.
        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 200, y: 20))))

        XCTAssertEqual(view.rectangles.count, 1, "The live redaction is committed, not dropped")
        XCTAssertEqual(view.rectangles.first?.style, .solid)
        XCTAssertEqual(view.rectangles.first?.bounds, NSRect(x: 20, y: 20, width: 100, height: 70))
        XCTAssertEqual(view.currentRectangle?.startPoint, NSPoint(x: 200, y: 20), "The new drag begins")

        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 300, y: 90))))
        window.mouseUp(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseUp, location: NSPoint(x: 300, y: 90))))

        XCTAssertNil(view.currentRectangle)
        XCTAssertEqual(view.rectangles.map(\.bounds), [
            NSRect(x: 20, y: 20, width: 100, height: 70),
            NSRect(x: 200, y: 20, width: 100, height: 70),
        ])

        // Both are on the undo stack. The test runs in a single run loop turn, so the undo
        // manager groups the two registrations into one step.
        view.undo()
        XCTAssertTrue(view.rectangles.isEmpty)
    }

    /// The lost mouse-up also left the live preview running, so the next pixelate or blur
    /// drag skipped its fresh capture and reused the previous drag's picture.
    func testMouseDownAfterALostMouseUpEndsTheRedactionDragBeforeStartingAnother() throws {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.close() }
        let view: OverlayView = window.overlayView
        let defaults = TestUserDefaults.create()
        defaults.redactionStyle = .pixelate
        view.pickerUserDefaultsOverride = defaults
        view.redactionSampler = sampler
        view.fadeMode = false
        view.currentTool = .redact

        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 20, y: 20))))
        sampler.completeCaptures(with: try makeSnapshot(frame: window.frame))
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 120, y: 90))))
        XCTAssertEqual(sampler.captureCount, 1)

        // No mouse-up. The next drag starts on another spot.
        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown, location: NSPoint(x: 200, y: 20))))

        XCTAssertEqual(view.rectangles.count, 1, "The live redaction is committed, not dropped")
        XCTAssertEqual(view.rectangles.first?.style, .pixelate)
        XCTAssertTrue(view.isRedactionDragActive, "The new drag has its own live preview")
        XCTAssertEqual(sampler.captureCount, 2, "The new drag captures a fresh picture")

        sampler.completeCaptures(with: try makeSnapshot(frame: window.frame))
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged, location: NSPoint(x: 300, y: 90))))
        window.mouseUp(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseUp, location: NSPoint(x: 300, y: 90))))
        while sampler.hasPendingFilters {
            sampler.completeNextFilter()
        }

        XCTAssertFalse(view.isRedactionDragActive)
        XCTAssertEqual(view.rectangles.count, 2)
        XCTAssertTrue(view.rectangles.allSatisfy { $0.sample != nil }, "Both settle with a sample")
    }

    func testStaleResultsNeverLandOnTheWrongRectangle() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate)]
        _ = try renderedColor(at: .zero)
        sampler.completeCaptures(with: try makeSnapshot())

        // Moved without a drag while its filter pass ran: that result depicts the old spot.
        overlayView.selectedObjects = [.rectangle(index: 0)]
        overlayView.moveSelectedObjects(by: NSPoint(x: 30, y: 0))
        sampler.completeNextFilter()
        XCTAssertNil(overlayView.rectangles[0].sample)
        XCTAssertEqual(sampler.filterRequests.count, 2, "The new spot is filtered from the same snapshot")
        sampler.completeNextFilter()
        XCTAssertEqual(overlayView.rectangles[0].sample?.key, RedactionSampleKey(overlayView.rectangles[0]))

        // Hidden while a pass ran: the result belongs to a picture that is gone.
        overlayView.moveSelectedObjects(by: NSPoint(x: -30, y: 0))
        _ = try renderedColor(at: .zero)
        sampler.completeCaptures(with: try makeSnapshot())
        XCTAssertTrue(sampler.hasPendingFilters)
        overlayView.discardRedactionSamples()
        sampler.completeNextFilter()
        XCTAssertNil(overlayView.rectangles[0].sample)

        // A pass from an earlier drag never lands on the rectangle of the next one.
        overlayView.rectangles = []
        overlayView.selectedObjects = []
        overlayView.currentRectangle = makeRectangle(style: .blur)
        overlayView.beginRedactionDrag()
        sampler.completeCaptures(with: try makeSnapshot())
        _ = try renderedColor(at: .zero)
        XCTAssertTrue(sampler.hasPendingFilters)
        overlayView.currentRectangle = nil
        overlayView.endRedactionDrag()
        overlayView.currentRectangle = Rectangle(
            startPoint: NSPoint(x: 10, y: 10), endPoint: NSPoint(x: 40, y: 40),
            color: .systemRed, lineWidth: 3, style: .blur)
        overlayView.beginRedactionDrag()
        sampler.completeNextFilter()
        XCTAssertNil(overlayView.currentRectangle?.sample)
    }

    // MARK: - Hit testing

    func testInteriorHitTestOnlyForRedactions() {
        overlayView.rectangles = [makeRectangle(style: .outline)]
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)), .none)
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 50, y: 100)), .rectangle(index: 0))

        overlayView.rectangles = [makeRectangle(style: .solid)]
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)), .rectangle(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 10, y: 10)), .none)
    }

    func testHitTestFollowsCreationOrderAroundARedaction() {
        overlayView.fadeMode = false
        overlayView.counterAnnotations = [
            CounterAnnotation(number: 1, position: NSPoint(x: 100, y: 100), color: .systemRed, creationTime: 1)
        ]
        let textPoint = NSPoint(x: 75, y: 75)
        var label = TestFactory.createTextAnnotation(text: "Secret", position: NSPoint(x: 70, y: 70))
        label.creationTime = 1
        overlayView.textAnnotations = [label]
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)), .counter(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: textPoint), .text(index: 0))

        overlayView.rectangles = [makeRectangle(style: .solid, creationTime: 2)]
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)), .rectangle(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: textPoint), .rectangle(index: 0))
        XCTAssertTrue(overlayView.isPointCoveredByRedaction(textPoint, over: label.creationTime))

        // Created after the redaction, so drawn and hit on top of it.
        overlayView.arrows = [
            TestFactory.createArrow(
                start: NSPoint(x: 60, y: 130), end: NSPoint(x: 140, y: 130), color: .red, lineWidth: 6, time: 3)
        ]
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 130)), .arrow(index: 0))
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 100, y: 140)), .rectangle(index: 0))
        XCTAssertFalse(overlayView.isPointCoveredByRedaction(NSPoint(x: 100, y: 130), over: 3))
    }

    func testTextToolDoubleClickNeverEditsALabelUnderARedaction() throws {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.close() }
        let view: OverlayView = window.overlayView
        view.pickerUserDefaultsOverride = TestUserDefaults.create()
        view.redactionSampler = sampler
        var label = TestFactory.createTextAnnotation(text: "Secret", position: NSPoint(x: 70, y: 70))
        label.creationTime = 1
        view.textAnnotations = [label]
        view.rectangles = [makeRectangle(style: .solid, creationTime: 2)]
        view.currentTool = .text

        window.mouseDown(with: try makeDoubleClick(at: NSPoint(x: 75, y: 75)))

        XCTAssertNil(view.editingTextAnnotationIndex, "The hidden label must not open for editing")
        XCTAssertNil(view.draggedTextAnnotationIndex)
        XCTAssertEqual(view.currentTextAnnotation?.text, "", "The click starts a new label instead")
    }

    func testTextToolDoubleClickEditsALabelNewerThanTheRedaction() throws {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.close() }
        let view: OverlayView = window.overlayView
        view.pickerUserDefaultsOverride = TestUserDefaults.create()
        view.redactionSampler = sampler
        var label = TestFactory.createTextAnnotation(text: "Visible", position: NSPoint(x: 70, y: 70))
        label.creationTime = 3
        view.textAnnotations = [label]
        view.rectangles = [makeRectangle(style: .solid, creationTime: 2)]
        view.currentTool = .text

        window.mouseDown(with: try makeDoubleClick(at: NSPoint(x: 75, y: 75)))

        XCTAssertEqual(view.editingTextAnnotationIndex, 0, "A label drawn over the redaction stays editable")
    }

    func testHitTestPicksTheNewerOfOverlappingRedactions() {
        overlayView.rectangles = [
            makeRectangle(style: .solid, creationTime: 2),
            Rectangle(
                startPoint: NSPoint(x: 100, y: 100), endPoint: NSPoint(x: 190, y: 190),
                color: .systemRed, lineWidth: 3, creationTime: 1, style: .blur),
        ]
        XCTAssertEqual(overlayView.redactionIndicesByCreation, [1, 0], "Oldest first")
        XCTAssertEqual(
            overlayView.findObjectAt(point: NSPoint(x: 120, y: 120)), .rectangle(index: 0),
            "The newer redaction wins the overlap")
        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 170, y: 170)), .rectangle(index: 1))

        overlayView.rectangles[1].creationTime = 3
        XCTAssertEqual(
            overlayView.findObjectAt(point: NSPoint(x: 120, y: 120)), .rectangle(index: 1),
            "Style does not matter for which one is on top")
    }

    func testPastedObjectsLandOnTopAndKeepTheirOrder() throws {
        overlayView.fadeMode = false
        let past = CACurrentMediaTime() - 10
        overlayView.arrows = [
            TestFactory.createArrow(
                start: NSPoint(x: 60, y: 100), end: NSPoint(x: 140, y: 100), color: .red, time: past)
        ]
        overlayView.rectangles = [makeRectangle(style: .solid, creationTime: past + 1)]

        overlayView.selectedObjects = [.arrow(index: 0), .rectangle(index: 0)]
        overlayView.duplicateSelectedObjects()

        XCTAssertEqual(overlayView.arrows.count, 2)
        let pastedArrow = try XCTUnwrap(overlayView.arrows.last?.creationTime)
        let pastedRedaction = try XCTUnwrap(overlayView.rectangles.last?.creationTime)
        XCTAssertGreaterThan(pastedArrow, past + 1, "A paste is new even in persist mode")
        XCTAssertGreaterThan(pastedRedaction, pastedArrow, "The copied redaction still covers the copied arrow")
    }

    func testEraserRemovesRedactionFromItsInterior() {
        overlayView.rectangles = [makeRectangle(style: .outline), makeRectangle(style: .pixelate)]
        overlayView.currentTool = .eraser

        overlayView.eraseAtPoint(NSPoint(x: 100, y: 100))
        XCTAssertEqual(overlayView.rectangles.count, 1)
        XCTAssertEqual(overlayView.rectangles.first?.style, .outline, "Interior erasing spares the outline")
    }

    // MARK: - Delete last item

    func testDeleteLastItemWithRectangleToolRemovesTheNewestOutlineSkippingARedaction() {
        overlayView.currentTool = .rectangle
        let outline = makeRectangle(style: .outline)
        let redaction = makeRectangle(style: .pixelate)
        overlayView.rectangles = [outline, redaction]

        overlayView.deleteLastItem()

        XCTAssertEqual(overlayView.rectangles.count, 1)
        XCTAssertEqual(overlayView.rectangles.first?.style, .pixelate, "The newer redaction is untouched")
    }

    func testDeleteLastItemWithRedactToolRemovesTheNewestRedactionSkippingAnOutline() {
        overlayView.currentTool = .redact
        let redaction = makeRectangle(style: .pixelate)
        let outline = makeRectangle(style: .outline)
        overlayView.rectangles = [redaction, outline]

        overlayView.deleteLastItem()

        XCTAssertEqual(overlayView.rectangles.count, 1)
        XCTAssertEqual(overlayView.rectangles.first?.style, .outline, "The newer outline is untouched")
    }

    // MARK: - Fade

    func testRedactionsDoNotFade() throws {
        overlayView.fadeMode = true
        let stale = CACurrentMediaTime() - overlayView.fadeDuration * 4
        overlayView.rectangles = [
            makeRectangle(style: .solid, creationTime: stale),
            Rectangle(
                startPoint: NSPoint(x: 0, y: 0), endPoint: NSPoint(x: 10, y: 10),
                color: .systemRed, lineWidth: 3, creationTime: stale),
        ]

        overlayView.compactExpiredAnnotations()
        XCTAssertEqual(overlayView.rectangles.count, 1, "The stale outline goes; the redaction stays")
        XCTAssertEqual(overlayView.rectangles.first?.style, .solid)
        XCTAssertFalse(overlayView.isAnythingFading(), "A redaction never keeps the fade loop alive")

        let center = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.01, "Drawn at full alpha regardless of age")
        XCTAssertEqual(
            overlayView.findObjectAt(point: NSPoint(x: 100, y: 100)), .rectangle(index: 0),
            "Still selectable after the fade window")
    }

    func testUndoingAFadedOutlineLeavesTheRedaction() {
        let window = makeUndoWindow()
        defer { window.close() }
        overlayView.fadeMode = true
        let stale = CACurrentMediaTime() - overlayView.fadeDuration * 4
        let redaction = makeRectangle(style: .solid, creationTime: stale)
        let outline = Rectangle(
            startPoint: NSPoint(x: 0, y: 0), endPoint: NSPoint(x: 10, y: 10),
            color: .systemRed, lineWidth: 3, creationTime: stale)
        overlayView.rectangles = [redaction, outline]
        overlayView.registerUndo(action: .addRectangle(outline))
        overlayView.compactExpiredAnnotations()
        XCTAssertEqual(overlayView.rectangles, [redaction])

        overlayView.undo()
        XCTAssertEqual(overlayView.rectangles, [redaction], "Undoing the outline must not uncover the secret")
    }

    func testUndoingAMoveAfterCompactionNeverMovesAnotherRectangle() {
        let window = makeUndoWindow()
        defer { window.close() }
        overlayView.fadeMode = true
        let stale = CACurrentMediaTime() - overlayView.fadeDuration * 4
        let outline = Rectangle(
            startPoint: NSPoint(x: 10, y: 10), endPoint: NSPoint(x: 30, y: 30),
            color: .systemRed, lineWidth: 3, creationTime: stale)
        let redaction = makeRectangle(style: .solid, creationTime: stale)
        overlayView.rectangles = [outline, redaction]
        overlayView.registerMoveUndo(
            object: .rectangle(index: 0),
            from: (NSPoint(x: 0, y: 0), NSPoint(x: 20, y: 20)), to: (outline.startPoint, outline.endPoint))
        overlayView.compactExpiredAnnotations()
        XCTAssertEqual(overlayView.rectangles, [redaction], "The redaction now sits at the outline's index")

        overlayView.undo()
        XCTAssertEqual(overlayView.rectangles, [redaction], "The move belonged to the outline, which is gone")
    }
}
