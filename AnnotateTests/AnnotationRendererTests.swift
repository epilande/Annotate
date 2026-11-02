import XCTest

@testable import Annotate

/// The renderer paints a document with no view involved, which is what a capture draws
/// from. Each test renders into an offscreen bitmap and checks pixels.
@MainActor
final class AnnotationRendererTests: XCTestCase {
    private static let canvas = NSRect(x: 0, y: 0, width: 200, height: 200)
    private var originalBoardManager: BoardManager!

    override nonisolated func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppDelegate.shared = nil
            // `OverlayView.renderer()` reads the board; keep it off the user's live defaults.
            originalBoardManager = BoardManager.shared
            BoardManager.shared = BoardManager(userDefaults: TestUserDefaults.create())
        }
    }

    override nonisolated func tearDown() {
        MainActor.assumeIsolated {
            BoardManager.shared = originalBoardManager
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRenderer(
        _ document: OverlayDocument, fade: FadePolicy = .fullStrength, now: CFTimeInterval = 0,
        board: BoardAppearance = .hidden
    ) -> AnnotationRenderer {
        AnnotationRenderer(document: document, live: nil, board: board, fade: fade, now: now, canvas: Self.canvas)
    }

    /// Draws through the renderer's own context setup: the bitmap's context is never made
    /// current, the way a capture's offscreen context is not.
    private func render(_ renderer: AnnotationRenderer, scale: CGFloat = 1) throws -> NSBitmapImageRep {
        let rep = try makeBitmap(scale: scale)
        let graphicsContext = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        graphicsContext.cgContext.scaleBy(x: scale, y: scale)
        renderer.draw(in: graphicsContext.cgContext)
        graphicsContext.flushGraphics()
        return rep
    }

    private func render(_ view: OverlayView) throws -> NSBitmapImageRep {
        let rep = try makeBitmap(scale: 1)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.draw(view.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func makeBitmap(scale: CGFloat) throws -> NSBitmapImageRep {
        try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(Self.canvas.width * scale),
                pixelsHigh: Int(Self.canvas.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0))
    }

    /// Reads a pixel by bottom-up pixel coordinates; bitmap rows run top-down.
    private func color(in rep: NSBitmapImageRep, at point: NSPoint) throws -> NSColor {
        let color = try XCTUnwrap(rep.colorAt(x: Int(point.x), y: rep.pixelsHigh - 1 - Int(point.y)))
        return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
    }

    private func alpha(in rep: NSBitmapImageRep, at point: NSPoint) throws -> CGFloat {
        try color(in: rep, at: point).alphaComponent
    }

    private func bytes(of rep: NSBitmapImageRep) throws -> [UInt8] {
        let data = try XCTUnwrap(rep.bitmapData)
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    /// A thick red line across the middle of the canvas.
    private func makeLine(creationTime: CFTimeInterval? = 0) -> Line {
        Line(
            startPoint: NSPoint(x: 20, y: 100),
            endPoint: NSPoint(x: 180, y: 100),
            color: .red,
            lineWidth: 10,
            creationTime: creationTime)
    }

    private func makeSolidRedaction(over rect: NSRect, creationTime: CFTimeInterval?) -> Rectangle {
        Rectangle(
            startPoint: rect.origin,
            endPoint: NSPoint(x: rect.maxX, y: rect.maxY),
            color: .red,
            lineWidth: 3,
            creationTime: creationTime,
            style: .solid)
    }

    /// Holds one second, then fades out over the next.
    private let fadeMode = FadePolicy(
        isFadeMode: true,
        delay: 1,
        outDuration: 1,
        persistRestoreStart: nil,
        persistRestoreDuration: 0.15)

    // MARK: - Drawing without a view

    func testDrawsEveryKindIntoAnOffscreenContext() throws {
        var document = OverlayDocument()
        document.lines = [makeLine()]
        document.textAnnotations = [
            TextAnnotation(text: "Hi", position: NSPoint(x: 20, y: 20), color: .blue, fontSize: 24)
        ]
        document.counterAnnotations = [
            CounterAnnotation(number: 1, position: NSPoint(x: 160, y: 160), color: .green)
        ]

        let rep = try render(makeRenderer(document))

        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 100, y: 100)), 1, accuracy: 0.01, "line")
        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 160, y: 160)), 1, accuracy: 0.01, "counter")
        var labelPixels = 0
        for x in 20..<60 {
            for y in 20..<50 where try alpha(in: rep, at: NSPoint(x: x, y: y)) > 0.5 {
                labelPixels += 1
            }
        }
        XCTAssertGreaterThan(labelPixels, 20, "label text")
        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 100, y: 30)), 0, "empty canvas stays clear")
    }

    func testScalesWithTheContext() throws {
        var document = OverlayDocument()
        document.lines = [makeLine()]

        let rep = try render(makeRenderer(document), scale: 2)

        XCTAssertEqual(rep.pixelsWide, 400)
        // The line sits at y = 100 pt, so 200 px, and its 10 pt width spans 190 to 210 px.
        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 200, y: 200)), 1, accuracy: 0.01)
        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 200, y: 192)), 1, accuracy: 0.01)
        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 200, y: 186)), 0)
        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 200, y: 100)), 0, "not drawn at 1x")
    }

    func testMatchesTheOverlayViewWhenNothingIsSelected() throws {
        let view = OverlayView(frame: Self.canvas)
        view.pickerUserDefaultsOverride = TestUserDefaults.create()
        view.fadeMode = false
        view.lines = [makeLine(creationTime: 1)]
        view.arrows = [
            Arrow(
                startPoint: NSPoint(x: 20, y: 20),
                endPoint: NSPoint(x: 120, y: 60),
                color: .orange,
                lineWidth: 4,
                creationTime: 2)
        ]
        view.circles = [
            Circle(
                startPoint: NSPoint(x: 120, y: 120),
                endPoint: NSPoint(x: 180, y: 180),
                color: .purple,
                lineWidth: 3,
                creationTime: 3)
        ]
        view.rectangles = [makeSolidRedaction(over: NSRect(x: 60, y: 90, width: 40, height: 40), creationTime: 4)]
        view.textAnnotations = [
            TextAnnotation(
                text: "Label",
                position: NSPoint(x: 20, y: 150),
                color: .blue,
                fontSize: 20,
                hasBackground: true,
                creationTime: 5)
        ]
        view.counterAnnotations = [
            CounterAnnotation(number: 3, position: NSPoint(x: 170, y: 40), color: .green, creationTime: 6)
        ]

        let viewRep = try render(view)
        let rendererRep = try render(view.renderer())

        XCTAssertEqual(try bytes(of: viewRep), try bytes(of: rendererRep))
    }

    // MARK: - Chrome and live previews

    func testNeverDrawsSelectionChrome() throws {
        let view = OverlayView(frame: Self.canvas)
        view.pickerUserDefaultsOverride = TestUserDefaults.create()
        view.fadeMode = false
        view.lines = [makeLine()]
        view.selectedObjects = [.line(index: 0)]
        view.isDrawingSelectionRect = true
        view.selectionRectStart = NSPoint(x: 30, y: 20)
        view.selectionRectEnd = NSPoint(x: 170, y: 60)
        let marqueeInterior = NSPoint(x: 100, y: 40)

        XCTAssertGreaterThan(
            try alpha(in: render(view), at: marqueeInterior), 0, "the view paints the marquee")
        XCTAssertEqual(try alpha(in: render(view.renderer()), at: marqueeInterior), 0)
    }

    func testLeavesLivePreviewsOutWhenNil() throws {
        let view = OverlayView(frame: Self.canvas)
        view.pickerUserDefaultsOverride = TestUserDefaults.create()
        view.currentLine = makeLine(creationTime: nil)
        let center = NSPoint(x: 100, y: 100)

        var renderer = view.renderer()
        XCTAssertEqual(try alpha(in: render(renderer), at: center), 1, accuracy: 0.01)
        renderer.live = nil
        XCTAssertEqual(try alpha(in: render(renderer), at: center), 0)
    }

    // MARK: - Fade policy

    func testFullStrengthIgnoresAge() throws {
        var document = OverlayDocument()
        document.lines = [makeLine(creationTime: 0)]

        let rep = try render(makeRenderer(document, fade: .fullStrength, now: 1000))

        XCTAssertEqual(try alpha(in: rep, at: NSPoint(x: 100, y: 100)), 1, accuracy: 0.01)
    }

    func testFadeModeDrawsTheCurrentAlpha() throws {
        var document = OverlayDocument()
        document.lines = [makeLine(creationTime: 0)]
        let center = NSPoint(x: 100, y: 100)

        let holding = try render(makeRenderer(document, fade: fadeMode, now: 0.9))
        let halfway = try render(makeRenderer(document, fade: fadeMode, now: 1.5))
        let gone = try render(makeRenderer(document, fade: fadeMode, now: 2))

        XCTAssertEqual(try alpha(in: holding, at: center), 1, accuracy: 0.01)
        // Smoothstep is 0.5 at the midpoint of the fade-out.
        XCTAssertEqual(try alpha(in: halfway, at: center), 0.5, accuracy: 0.02)
        XCTAssertEqual(try alpha(in: gone, at: center), 0)
    }

    func testFadePolicyAlphas() {
        XCTAssertEqual(fadeMode.alpha(creationTime: nil, at: 100), 1)
        XCTAssertEqual(fadeMode.alpha(creationTime: 0, at: 1), 1)
        XCTAssertEqual(try XCTUnwrap(fadeMode.alpha(creationTime: 0, at: 1.25)), 0.84375, accuracy: 0.0001)
        XCTAssertNil(fadeMode.alpha(creationTime: 0, at: 2))
        XCTAssertEqual(FadePolicy.fullStrength.alpha(creationTime: 0, at: 1000), 1)

        let redaction = makeSolidRedaction(over: Self.canvas, creationTime: 0)
        XCTAssertEqual(fadeMode.alpha(for: redaction, at: 1000), 1, "redactions never fade")

        var restoring = fadeMode
        restoring.isFadeMode = false
        restoring.persistRestoreStart = 1.5
        XCTAssertEqual(try XCTUnwrap(restoring.alpha(creationTime: 0, at: 1.5)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(restoring.alpha(creationTime: 0, at: 1.7), 1)
        XCTAssertTrue(restoring.isRestoring(at: 1.6))
        XCTAssertFalse(restoring.isRestoring(at: 1.7))
    }

    func testOverlayViewFadeMatchesItsSettings() {
        let view = OverlayView(frame: Self.canvas)
        view.pickerUserDefaultsOverride = TestUserDefaults.create()
        view.fadeDelay = 2
        view.fadeMode = true

        XCTAssertEqual(
            view.fade,
            FadePolicy(
                isFadeMode: true,
                delay: 2,
                outDuration: view.fadeOutDuration,
                persistRestoreStart: nil,
                persistRestoreDuration: view.persistRestoreDuration))
        XCTAssertEqual(view.fade.duration, view.fadeDuration)
    }

    // MARK: - Redactions

    func testRedactionStaysOpaqueOverFadingContent() throws {
        var document = OverlayDocument()
        document.lines = [makeLine(creationTime: 0)]
        document.rectangles = [
            makeSolidRedaction(over: NSRect(x: 80, y: 80, width: 40, height: 40), creationTime: 0.5)
        ]

        let halfway = try render(makeRenderer(document, fade: fadeMode, now: 1.5))
        let covered = try color(in: halfway, at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(covered.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(covered.redComponent, 0, accuracy: 0.01, "the fading line must not show through")
        XCTAssertEqual(try alpha(in: halfway, at: NSPoint(x: 40, y: 100)), 0.5, accuracy: 0.02)

        let longAfter = try render(makeRenderer(document, fade: fadeMode, now: 1000))
        XCTAssertEqual(try alpha(in: longAfter, at: NSPoint(x: 100, y: 100)), 1, accuracy: 0.01)
        XCTAssertEqual(try alpha(in: longAfter, at: NSPoint(x: 40, y: 100)), 0)
    }

    func testRedactionUsesTheBoardPlaceholder() throws {
        var document = OverlayDocument()
        document.rectangles = [
            makeSolidRedaction(over: NSRect(x: 80, y: 80, width: 40, height: 40), creationTime: 0)
        ]
        let blackboard = BoardAppearance(isVisible: true, type: .blackboard)

        let rep = try render(makeRenderer(document, board: blackboard))

        let fill = try color(in: rep, at: NSPoint(x: 100, y: 100))
        XCTAssertEqual(fill.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(fill.redComponent, 0.25, accuracy: 0.02)
    }

    // MARK: - Board

    func testBoardAppearanceAdaptsColors() {
        let blackboard = BoardAppearance(isVisible: true, type: .blackboard)
        let whiteboard = BoardAppearance(isVisible: true, type: .whiteboard)

        XCTAssertEqual(blackboard.adapt(.black), .white)
        XCTAssertEqual(whiteboard.adapt(.white), .black)
        XCTAssertEqual(BoardAppearance.hidden.adapt(.black), .black)
        XCTAssertEqual(BoardAppearance(isVisible: false, type: .blackboard).adapt(.black), .black)
        XCTAssertEqual(BoardAppearance.hidden.redactionPlaceholderColor, .black)
        XCTAssertEqual(whiteboard.redactionPlaceholderColor, .black)
    }
}
