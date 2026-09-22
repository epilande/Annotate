import XCTest

@testable import Annotate

/// Records sample requests instead of touching Screen Recording. Requests stay pending
/// until the test answers them, mirroring the asynchronous capture in production.
@MainActor
final class StubRedactionSampler: RedactionSampling {
    var isAvailable = true
    var requests: [Rectangle] = []
    private var completions: [@MainActor (CGImage?) -> Void] = []

    func prepareForSampling() -> Bool { isAvailable }

    func requestSample(
        for rectangle: Rectangle, in view: NSView,
        completion: @escaping @MainActor (CGImage?) -> Void
    ) {
        requests.append(rectangle)
        completions.append(completion)
    }

    func completeAll(with image: CGImage?) {
        let pending = completions
        completions.removeAll()
        pending.forEach { $0(image) }
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

    /// Renders the overlay into a bitmap and returns the color at a view point.
    private func renderedColor(at point: NSPoint) throws -> NSColor {
        let width = Int(overlayView.bounds.width)
        let height = Int(overlayView.bounds.height)
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
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

    /// A horizontal gradient so every column differs from its neighbor.
    private func makeGradientImage(size: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<size {
            let level = CGFloat(x) / CGFloat(size - 1)
            context.setFillColor(CGColor(red: level, green: 0, blue: 1 - level, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: size))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> NSColor {
        let rep = NSBitmapImageRep(cgImage: image)
        let color = try XCTUnwrap(rep.colorAt(x: x, y: y))
        return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
    }

    private func assertSameColor(_ a: NSColor, _ b: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.02, file: file, line: line)
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
        withSample.sample = try makeGradientImage(size: 8)
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

    // MARK: - Filters

    func testPixelateProducesUniformBlocksAlignedToTheOrigin() throws {
        let source = try makeGradientImage(size: 64)
        let output = try XCTUnwrap(ScreenSampler.pixelate(source, scale: 1))
        XCTAssertEqual(output.width, 64)
        XCTAssertEqual(output.height, 64)

        let block = Int(ScreenSampler.pixelBlockSize(forPixelWidth: 64, height: 64, scale: 1))
        XCTAssertEqual(block, 10, "A 64 px capture at 1x uses the 10 pt minimum block")

        let inside = try pixel(output, x: 1, y: 1)
        assertSameColor(inside, try pixel(output, x: block - 2, y: block - 2))
        assertSameColor(inside, try pixel(output, x: 1, y: block - 2))

        let nextBlock = try pixel(output, x: block + 1, y: 1)
        XCTAssertGreaterThan(
            abs(nextBlock.redComponent - inside.redComponent), 0.05,
            "Neighboring blocks must differ on a gradient")

        let sourceAcrossBlock = try pixel(source, x: 1, y: 1)
        XCTAssertGreaterThan(
            abs(try pixel(source, x: block - 2, y: 1).redComponent - sourceAcrossBlock.redComponent), 0.05,
            "Sanity: the source gradient itself varies inside one block")
    }

    func testBlurKeepsTheOriginalExtent() throws {
        let source = try makeGradientImage(size: 48)
        let output = try XCTUnwrap(ScreenSampler.blur(source, scale: 2))
        XCTAssertEqual(output.width, 48)
        XCTAssertEqual(output.height, 48)
        let center = try pixel(output, x: 24, y: 24)
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.01, "Clamping keeps the edges opaque")
    }

    func testPixelBlockSizeGrowsWithLargeCaptures() {
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 100, height: 100, scale: 2), 20)
        XCTAssertEqual(ScreenSampler.pixelBlockSize(forPixelWidth: 1_200, height: 600, scale: 2), 50)
    }

    // MARK: - Rendering

    func testSampleLessPixelateRendersOpaqueBlackPlaceholder() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate)]
        let center = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(center.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(center.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(center.blueComponent, 0, accuracy: 0.01)
    }

    func testSolidRendersOpaqueBlackAndOutlineStaysClear() throws {
        overlayView.rectangles = [makeRectangle(style: .solid)]
        let solid = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(solid.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(solid.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(solid.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(solid.blueComponent, 0, accuracy: 0.01)

        overlayView.rectangles = [makeRectangle(style: .outline)]
        let outline = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(outline.alphaComponent, 0, accuracy: 0.01, "An outline leaves its interior clear")
    }

    func testDrawRequestsOneSamplePerRedactionAndAppliesTheResult() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate), makeRectangle(style: .solid)]
        _ = try renderedColor(at: .zero)
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.requests.count, 1, "One request per rectangle while it is in flight")
        XCTAssertEqual(sampler.requests.first?.style, .pixelate)
        XCTAssertTrue(overlayView.pendingSampleKeys.contains(RedactionSampleKey(overlayView.rectangles[0])))

        let image = try makeGradientImage(size: 16)
        sampler.completeAll(with: image)
        XCTAssertTrue(overlayView.pendingSampleKeys.isEmpty)
        XCTAssertNotNil(overlayView.rectangles[0].sample)
        XCTAssertNil(overlayView.rectangles[1].sample, "Solid never needs a sample")

        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.requests.count, 1, "A sampled rectangle is not requested again")
    }

    func testFailedCaptureLeavesPlaceholderAndDoesNotRetryUntilTheRectangleChanges() throws {
        overlayView.rectangles = [makeRectangle(style: .blur)]
        _ = try renderedColor(at: .zero)
        sampler.completeAll(with: nil)
        XCTAssertNil(overlayView.rectangles[0].sample)

        let center = try renderedColor(at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(center.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(sampler.requests.count, 1, "A failed key is not spammed on every redraw")

        overlayView.selectedObjects = [.rectangle(index: 0)]
        overlayView.moveSelectedObjects(by: NSPoint(x: 10, y: 0))
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.requests.count, 2, "Moving yields a new key and a fresh request")
    }

    func testNoRequestWithoutScreenCaptureAccessOrDuringADrag() throws {
        overlayView.rectangles = [makeRectangle(style: .pixelate)]

        sampler.isAvailable = false
        _ = try renderedColor(at: .zero)
        XCTAssertTrue(sampler.requests.isEmpty, "No access means the placeholder stays")

        sampler.isAvailable = true
        overlayView.selectionDragOffset = NSPoint(x: 1, y: 1)
        _ = try renderedColor(at: .zero)
        XCTAssertTrue(sampler.requests.isEmpty, "Never sample while the rectangle is being dragged")

        overlayView.selectionDragOffset = nil
        _ = try renderedColor(at: .zero)
        XCTAssertEqual(sampler.requests.count, 1)
    }

    func testMovingClearsTheSampleSoItResamples() throws {
        var rect = makeRectangle(style: .pixelate)
        rect.sample = try makeGradientImage(size: 8)
        overlayView.rectangles = [rect]
        overlayView.selectedObjects = [.rectangle(index: 0)]

        overlayView.moveSelectedObjects(by: NSPoint(x: 5, y: 5))
        XCTAssertNil(overlayView.rectangles[0].sample)
        XCTAssertEqual(overlayView.rectangles[0].bounds.origin, NSPoint(x: 55, y: 55))
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

    func testEraserRemovesRedactionFromItsInterior() {
        overlayView.rectangles = [makeRectangle(style: .outline), makeRectangle(style: .pixelate)]
        overlayView.currentTool = .eraser

        overlayView.eraseAtPoint(NSPoint(x: 100, y: 100))
        XCTAssertEqual(overlayView.rectangles.count, 1)
        XCTAssertEqual(overlayView.rectangles.first?.style, .outline, "Interior erasing spares the outline")
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
}
