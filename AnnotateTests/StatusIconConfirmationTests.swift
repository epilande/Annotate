import XCTest

@testable import Annotate

@MainActor
final class StatusIconConfirmationTests: XCTestCase {
    /// Expiries the confirmation scheduled, in order, which the tests run by hand.
    private var expiries: [(delay: TimeInterval, run: @MainActor () -> Void)] = []
    /// Whether the confirmation was up each time `onChange` ran.
    private var changes: [Bool] = []
    private var confirmation: StatusIconConfirmation!

    override func setUp() {
        super.setUp()
        expiries = []
        changes = []
        confirmation = StatusIconConfirmation(
            duration: 1.5,
            schedule: { [unowned self] delay, action in self.expiries.append((delay, action)) },
            onChange: { [unowned self] in self.changes.append(self.confirmation.isShowing) })
    }

    override func tearDown() {
        confirmation = nil
        super.tearDown()
    }

    func testShowPutsTheConfirmationUpAndItsExpiryTakesItDown() throws {
        confirmation.show()

        XCTAssertTrue(confirmation.isShowing)
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(expiries.map(\.delay), [1.5])

        try XCTUnwrap(expiries.first).run()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false])
    }

    func testShowingAgainRestartsTheTimeWithoutRedrawing() {
        confirmation.show()
        confirmation.show()

        XCTAssertEqual(changes, [true], "The confirmation is already up")
        XCTAssertEqual(expiries.count, 2)

        expiries[0].run()
        XCTAssertTrue(confirmation.isShowing, "The first show's time no longer counts")
        XCTAssertEqual(changes, [true])

        expiries[1].run()
        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false])
    }

    func testExpiriesRunOutOfOrderStillEndOnTheLatest() {
        confirmation.show()
        confirmation.show()
        confirmation.show()

        expiries[2].run()
        expiries[0].run()
        expiries[1].run()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false], "Ends once, and the stale expiries do nothing")
    }

    func testEndTakesTheConfirmationDownAndIgnoresItsPendingExpiry() {
        confirmation.show()
        confirmation.end()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false])

        confirmation.show()
        expiries[0].run()
        XCTAssertTrue(confirmation.isShowing, "The expiry from before the end belongs to an older show")

        expiries[1].run()
        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false, true, false])
    }

    func testEndingWhenNothingShowsDoesNothing() {
        confirmation.end()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertTrue(changes.isEmpty)
    }

    func testAnExpiryAfterTheConfirmationIsGoneDoesNothing() throws {
        confirmation.show()
        let expiry = try XCTUnwrap(expiries.first).run
        confirmation = nil

        expiry()

        XCTAssertEqual(changes, [true])
    }

    func testTheRunLoopTimerEndsTheConfirmationOnItsOwn() {
        var ended = false
        let realTime = StatusIconConfirmation(duration: 0.05) { ended = true }
        realTime.show()
        ended = false

        let deadline = CACurrentMediaTime() + 3
        while realTime.isShowing, CACurrentMediaTime() < deadline {
            wait(for: 0.01)
        }

        XCTAssertFalse(realTime.isShowing)
        XCTAssertTrue(ended)
    }

    // MARK: - What a capture confirms

    func testCaptureConfirmationSaysSavedForAFileAndCopiedForTheClipboardOnly() {
        let capture = makeCapture()
        let file = URL(fileURLWithPath: "/tmp/Annotate.png")
        let saved = CaptureResult(capture: capture, png: Data(), deliveries: [.file(file)], failures: [])
        let both = CaptureResult(capture: capture, png: Data(), deliveries: [.file(file), .clipboard], failures: [])
        let copied = CaptureResult(capture: capture, png: Data(), deliveries: [.clipboard], failures: [])
        let nowhere = CaptureResult(capture: capture, png: Data(), deliveries: [], failures: [])

        XCTAssertEqual(CaptureConfirmation(saved)?.announcement, "Capture saved")
        XCTAssertEqual(CaptureConfirmation(both)?.announcement, "Capture saved")
        XCTAssertEqual(CaptureConfirmation(copied)?.announcement, "Capture copied")
        XCTAssertNil(CaptureConfirmation(nowhere))
    }

    func testSavedAndCopiedHaveTheirOwnGlyphs() {
        XCTAssertEqual(CaptureConfirmation.saved.symbolName, "square.and.arrow.down")
        XCTAssertEqual(CaptureConfirmation.copied.symbolName, "doc.on.clipboard")
    }

    func testThePencilSavedAndCopiedIconsLookDifferent() throws {
        let pencil = try XCTUnwrap(AppDelegate.statusIcon(color: .gray, showing: nil))
        let saved = try XCTUnwrap(AppDelegate.statusIcon(color: .gray, showing: .saved))
        let copied = try XCTUnwrap(AppDelegate.statusIcon(color: .gray, showing: .copied))

        XCTAssertEqual(Set([pencil, saved, copied].map(\.tiffRepresentation)).count, 3)
        XCTAssertEqual(pencil.accessibilityDescription, "Annotate")
        XCTAssertEqual(saved.accessibilityDescription, "Capture saved")
        XCTAssertEqual(copied.accessibilityDescription, "Capture copied")
    }

    func testThePencilIconIsDrawnAsBefore() throws {
        let pencil = try XCTUnwrap(AppDelegate.statusIcon(color: .gray, showing: nil))
        let direct = try XCTUnwrap(AppDelegate.statusIcon(color: .gray, symbolName: "pencil", description: "Annotate"))

        XCTAssertEqual(pencil.tiffRepresentation, direct.tiffRepresentation)
        // Outline ring: inside the ring, clear of the glyph, nothing is drawn.
        XCTAssertEqual(pixel(of: pencil, atPoint: NSPoint(x: 3, y: 9)).alphaComponent, 0, accuracy: 0.01)
    }

    func testConfirmationIconsFillTheRingInTheStateColor() throws {
        for confirmation in [CaptureConfirmation.saved, .copied] {
            for color in [NSColor.systemRed, .gray] {
                let icon = try XCTUnwrap(AppDelegate.statusIcon(color: color, showing: confirmation))
                let fill = pixel(of: icon, atPoint: NSPoint(x: 3, y: 9))
                let expected = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
                XCTAssertEqual(fill.alphaComponent, 1, accuracy: 0.01, "\(confirmation) in \(color)")
                XCTAssertEqual(fill.redComponent, expected.redComponent, accuracy: 0.05, "\(confirmation) in \(color)")
                XCTAssertEqual(fill.greenComponent, expected.greenComponent, accuracy: 0.05, "\(confirmation) in \(color)")
                XCTAssertEqual(fill.blueComponent, expected.blueComponent, accuracy: 0.05, "\(confirmation) in \(color)")
            }
        }
    }

    func testConfirmationGlyphsKeepTheirAspectRatio() throws {
        for confirmation in [CaptureConfirmation.saved, .copied] {
            let symbol = try XCTUnwrap(NSImage(systemSymbolName: confirmation.symbolName, accessibilityDescription: nil))
            let icon = try XCTUnwrap(AppDelegate.statusIcon(color: .systemRed, showing: confirmation))
            // The white glyph's ink on the red fill, against the symbol's own ink at its own shape.
            // A stretched glyph would come out about 13% wider than its shape.
            let glyph = try XCTUnwrap(inkBounds(of: icon, size: NSSize(width: 18, height: 18)) { $0.isGlyphOnRed })
            let native = try XCTUnwrap(inkBounds(of: symbol, size: symbol.size) { $0.alphaComponent > 0.5 })

            let glyphRatio = glyph.width / glyph.height
            let nativeRatio = native.width / native.height
            XCTAssertEqual(glyphRatio, nativeRatio, accuracy: 0.05, "\(confirmation.symbolName) is stretched")
            XCTAssertLessThan(glyph.width, glyph.height, "\(confirmation.symbolName) is taller than wide")
            XCTAssertLessThanOrEqual(glyph.height, 11.25, "Fits in the 11 pt box")
            XCTAssertLessThanOrEqual(glyph.width, 11.25, "Fits in the 11 pt box")
        }
    }

    func testFittingKeepsTheAspectRatioInsideTheBox() {
        let box = NSSize(width: 11, height: 11)

        XCTAssertEqual(AppDelegate.fitted(NSSize(width: 15, height: 17), in: box).width, 15 * 11 / 17, accuracy: 0.001)
        XCTAssertEqual(AppDelegate.fitted(NSSize(width: 15, height: 17), in: box).height, 11, accuracy: 0.001)
        XCTAssertEqual(AppDelegate.fitted(NSSize(width: 22, height: 11), in: box), NSSize(width: 11, height: 5.5))
        XCTAssertEqual(AppDelegate.fitted(NSSize(width: 4, height: 4), in: box), box, "A small symbol grows to the box")
    }

    // MARK: - Pixels

    /// The icon draws into an image cached at 2x, so measuring finer only blurs its edges.
    private static let renderScale: CGFloat = 2

    /// `image` drawn at `size` points into a bitmap at `renderScale`.
    private func bitmap(of image: NSImage, size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * Self.renderScale),
            pixelsHigh: Int(size.height * Self.renderScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The color at `point`, in points from the bottom-left.
    private func pixel(of image: NSImage, atPoint point: NSPoint) -> NSColor {
        let rep = bitmap(of: image, size: NSSize(width: 18, height: 18))
        let x = Int(point.x * Self.renderScale)
        let y = rep.pixelsHigh - 1 - Int(point.y * Self.renderScale)
        return rep.colorAt(x: x, y: y) ?? .clear
    }

    /// The bounds, in points, of the pixels `isInk` picks out.
    private func inkBounds(of image: NSImage, size: NSSize, isInk: (NSColor) -> Bool) -> CGSize? {
        let rep = bitmap(of: image, size: size)
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), isInk(color) else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGSize(
            width: CGFloat(maxX - minX + 1) / Self.renderScale, height: CGFloat(maxY - minY + 1) / Self.renderScale)
    }

    private func makeCapture() -> Capture {
        Capture(
            image: CaptureTestImages.solid(width: 4, height: 4, RGBA(r: 0, g: 0, b: 255, a: 255)),
            display: DisplayInfo(id: 7, frame: CGRect(x: 0, y: 0, width: 4, height: 4), scale: 1),
            region: CGRect(x: 0, y: 0, width: 4, height: 4),
            scene: nil,
            capturedAt: Date(timeIntervalSince1970: 0),
            hostTime: 0)
    }
}

private extension NSColor {
    /// At least half white over a red fill: green is about 0.25 in the red and 1 in the glyph.
    var isGlyphOnRed: Bool {
        guard let rgb = usingColorSpace(.deviceRGB) else { return false }
        return rgb.alphaComponent > 0.5 && rgb.greenComponent > 0.62 && rgb.blueComponent > 0.62
    }
}
