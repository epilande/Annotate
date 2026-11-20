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
        let rendered = render(pencil, scale: 2)
        XCTAssertEqual(color(in: rendered, atPoint: NSPoint(x: 3, y: 9), scale: 2).alphaComponent, 0, accuracy: 0.01)
    }

    func testConfirmationIconsFillTheRingInTheStateColor() throws {
        for confirmation in [CaptureConfirmation.saved, .copied] {
            for ringColor in [NSColor.systemRed, .gray] {
                let icon = try XCTUnwrap(AppDelegate.statusIcon(color: ringColor, showing: confirmation))
                let fill = color(in: render(icon, scale: 2), atPoint: NSPoint(x: 3, y: 9), scale: 2)
                let expected = try XCTUnwrap(ringColor.usingColorSpace(.deviceRGB))
                let label = "\(confirmation) in \(ringColor)"
                XCTAssertEqual(fill.alphaComponent, 1, accuracy: 0.01, label)
                XCTAssertEqual(fill.redComponent, expected.redComponent, accuracy: 0.05, label)
                XCTAssertEqual(fill.greenComponent, expected.greenComponent, accuracy: 0.05, label)
                XCTAssertEqual(fill.blueComponent, expected.blueComponent, accuracy: 0.05, label)
            }
        }
    }

    // MARK: - Glyph color

    func testTheGlyphIsWhiteUnlessTheFillIsTooLightForIt() {
        for fill in [NSColor.systemRed, .gray, .systemIndigo, .magenta, .black] {
            XCTAssertEqual(ConfirmationIcon.glyphColor(onFill: fill), .white, "\(fill)")
        }
        for fill in [NSColor.white, .systemYellow, .cyan, .systemGreen, .systemOrange] {
            XCTAssertEqual(ConfirmationIcon.glyphColor(onFill: fill), ConfirmationIcon.darkGlyph, "\(fill)")
        }
        XCTAssertEqual(
            ConfirmationIcon.glyphColor(onFill: NSColor.white.withAlphaComponent(0.7)),
            ConfirmationIcon.darkGlyph,
            "Always-On's translucent ring goes by its color")
    }

    func testEveryRingColorGetsAGlyphWithAtLeastThreeToOneContrast() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
                for fill in colorPalette + [.gray] {
                    let glyph = ConfirmationIcon.glyphColor(onFill: fill)
                    guard let fillLuminance = ConfirmationIcon.relativeLuminance(of: fill),
                        let glyphLuminance = ConfirmationIcon.relativeLuminance(of: glyph)
                    else { return XCTFail("No luminance for \(fill)") }
                    let contrast =
                        (max(fillLuminance, glyphLuminance) + 0.05) / (min(fillLuminance, glyphLuminance) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 3, "\(fill) in \(appearance.rawValue)")
                }
            }
        }
    }

    func testTheGlyphIsDarkOnAWhiteRingAndWhiteOnTheUsualOnes() throws {
        // The glyph's ink inside the ring (how far each pixel moved from the fill toward the
        // expected glyph color, summed) matches the symbol's own ink at the same size. Counting
        // pixels past a brightness cutoff instead depended on the fill under the glyph's soft
        // edges: systemRed is lighter in Aqua, which took the saved glyph on red from 33 such
        // pixels to 18. Both appearances are drawn, so the result doesn't follow the Mac's.
        let scale = 2
        let ringRadius = ConfirmationIcon.ring.width / 2 * CGFloat(scale)
        let rings: [(color: NSColor, glyph: NSColor)] = [(.white, .black), (.systemRed, .white), (.gray, .white)]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try drawing(in: appearance) {
                for confirmation in [CaptureConfirmation.saved, .copied] {
                    let symbol = try XCTUnwrap(
                        NSImage(systemSymbolName: confirmation.symbolName, accessibilityDescription: nil))
                    let fit = min(11 / symbol.size.width, 11 / symbol.size.height)
                    let fitted = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
                    let symbolInk = inkArea(in: render(symbol, size: fitted, scale: scale)) { $0.alphaComponent }
                    XCTAssertGreaterThan(symbolInk, 30, "\(confirmation.symbolName) inks something")

                    for ring in rings {
                        let icon = render(
                            try XCTUnwrap(AppDelegate.statusIcon(color: ring.color, showing: confirmation)), scale: scale)
                        let fill = color(in: icon, atPoint: NSPoint(x: 3, y: 9), scale: scale)
                        let coverage = try XCTUnwrap(glyphCoverage(from: fill, toward: ring.glyph))
                        let label = "\(confirmation) on \(ring.color) in \(appearance.rawValue)"
                        let ink = inkArea(in: icon, coverage: coverage, within: ringRadius)
                        XCTAssertEqual(ink / symbolInk, 1, accuracy: 0.1, label)
                        if ring.glyph == .white {
                            XCTAssertEqual(countPixels(in: icon) { $0.luminance < 0.1 }, 0, label)
                        }
                    }
                }
            }
        }
    }

    func testAlwaysOnConfirmationIsSolidAndReadableOverALightMenuBar() throws {
        // Always-On hands the icon its color at 70%, which over a light menu bar would blend
        // magenta and red light enough to drop a white glyph below 3:1.
        for background in [NSColor.white, NSColor(white: 0.93, alpha: 1)] {
            for color in [NSColor.magenta, .systemRed] {
                for confirmation in [CaptureConfirmation.saved, .copied] {
                    let icon = try XCTUnwrap(
                        AppDelegate.statusIcon(color: color.withAlphaComponent(0.7), showing: confirmation))
                    // 4x, so the thin strokes' middles are fully inked.
                    let rendered = render(icon, scale: 4, over: background)
                    let label = "\(confirmation) in \(color) over \(background)"
                    let fill = try XCTUnwrap(
                        self.color(in: rendered, atPoint: NSPoint(x: 3, y: 9), scale: 4).usingColorSpace(.deviceRGB))
                    let solid = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
                    XCTAssertEqual(fill.redComponent, solid.redComponent, accuracy: 0.05, "\(label): fill is solid")
                    XCTAssertEqual(fill.greenComponent, solid.greenComponent, accuracy: 0.05, "\(label): fill is solid")
                    XCTAssertEqual(fill.blueComponent, solid.blueComponent, accuracy: 0.05, "\(label): fill is solid")

                    // The contrast on screen, between the fill and the glyph's most inked pixel.
                    let glyph = try XCTUnwrap(mostGlyphLikePixel(in: rendered, fill: fill))
                    let fillLuminance = try XCTUnwrap(ConfirmationIcon.relativeLuminance(of: fill))
                    let glyphLuminance = try XCTUnwrap(ConfirmationIcon.relativeLuminance(of: glyph))
                    let contrast =
                        (max(fillLuminance, glyphLuminance) + 0.05) / (min(fillLuminance, glyphLuminance) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 3, label)
                }
            }
        }
    }

    // MARK: - Glyph shape and position

    func testConfirmationGlyphsKeepTheirAspectRatio() throws {
        // A fixed 8x, so the result doesn't depend on the machine's displays. Edges are found to
        // within about a pixel, so 2 pixels (0.25 pt) of slack; stretching either glyph to the
        // 11 pt box would add 8 to 9 pixels to its width.
        let scale = 8
        let tolerance: CGFloat = 2
        for confirmation in [CaptureConfirmation.saved, .copied] {
            let symbol = try XCTUnwrap(NSImage(systemSymbolName: confirmation.symbolName, accessibilityDescription: nil))
            let native = try XCTUnwrap(inkBounds(in: render(symbol, size: symbol.size, scale: scale)) { $0.alphaComponent })
            // The symbol's image fit in the 11 pt box at its own shape, worked out here rather
            // than read from the app, in pixels per symbol pixel.
            let fit = min(11 / symbol.size.width, 11 / symbol.size.height)

            for ringColor in [NSColor.systemRed, .white] {
                let icon = render(try XCTUnwrap(AppDelegate.statusIcon(color: ringColor, showing: confirmation)), scale: scale)
                let glyph = try XCTUnwrap(glyphBounds(in: icon, scale: scale))
                let label = "\(confirmation.symbolName) on \(ringColor)"
                XCTAssertEqual(glyph.width, native.width * fit, accuracy: tolerance, "\(label): width")
                XCTAssertEqual(glyph.height, native.height * fit, accuracy: tolerance, "\(label): height")
            }
        }
    }

    func testConfirmationGlyphsAreCenteredInTheRingAt1xAnd2x() throws {
        for scale in [1, 2] {
            for confirmation in [CaptureConfirmation.saved, .copied] {
                for ringColor in [NSColor.systemRed, .gray, .white] {
                    let icon = render(
                        try XCTUnwrap(AppDelegate.statusIcon(color: ringColor, showing: confirmation)), scale: scale)
                    let glyph = try XCTUnwrap(glyphBounds(in: icon, scale: scale))
                    // The ring's middle, in pixels from the top-left, is the icon's middle.
                    let ringMiddle = 9 * CGFloat(scale)
                    let label = "\(confirmation.symbolName) on \(ringColor) at \(scale)x"
                    XCTAssertEqual(glyph.midX, ringMiddle, accuracy: 0.5, label)
                    XCTAssertEqual(glyph.midY, ringMiddle, accuracy: 0.5, label)
                }
            }
        }
    }

    func testGlyphRectCentersTheInkNotTheImage() {
        // A symbol whose ink sits in the top two thirds of its image, above baseline padding.
        let rect = ConfirmationIcon.glyphRect(
            symbolSize: NSSize(width: 10, height: 20), inkBounds: CGRect(x: 0, y: 6, width: 10, height: 14))

        XCTAssertEqual(rect.size, NSSize(width: 5.5, height: 11))
        XCTAssertEqual(rect.minY + 13 * 0.55, ConfirmationIcon.ring.midY, accuracy: 0.0001, "The ink's middle")
        XCTAssertEqual(rect.midX, ConfirmationIcon.ring.midX, accuracy: 0.0001)
    }

    func testFittingKeepsTheAspectRatioInsideTheBox() {
        let box = NSSize(width: 11, height: 11)

        XCTAssertEqual(ConfirmationIcon.fitted(NSSize(width: 15, height: 17), in: box).width, 15 * 11 / 17, accuracy: 0.001)
        XCTAssertEqual(ConfirmationIcon.fitted(NSSize(width: 15, height: 17), in: box).height, 11, accuracy: 0.001)
        XCTAssertEqual(ConfirmationIcon.fitted(NSSize(width: 22, height: 11), in: box), NSSize(width: 11, height: 5.5))
        XCTAssertEqual(ConfirmationIcon.fitted(NSSize(width: 4, height: 4), in: box), box, "A small symbol grows to the box")
    }

    // MARK: - Pixels

    /// `image` drawn at `size` points into a bitmap of exactly `scale` pixels per point, over
    /// `background` when given, else over transparent pixels.
    private func render(
        _ image: NSImage, size: NSSize = NSSize(width: 18, height: 18), scale: Int, over background: NSColor? = nil
    ) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * CGFloat(scale)).rounded(.up)),
            pixelsHigh: Int((size.height * CGFloat(scale)).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        rep.size = NSSize(width: CGFloat(rep.pixelsWide) / CGFloat(scale), height: CGFloat(rep.pixelsHigh) / CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let background {
            background.setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The color at `point`, in points from the bottom-left.
    private func color(in rep: NSBitmapImageRep, atPoint point: NSPoint, scale: Int) -> NSColor {
        let x = Int(point.x * CGFloat(scale))
        let row = rep.pixelsHigh - 1 - Int(point.y * CGFloat(scale))
        return rep.colorAt(x: x, y: row) ?? .clear
    }

    /// The pixel inside the ring furthest from `fill`, which is the glyph's most inked one.
    /// Only pixels within 6.5 pt of the middle count, inside the ring's 7.25 pt inner edge, so
    /// the background around the icon never does.
    private func mostGlyphLikePixel(in rep: NSBitmapImageRep, fill: NSColor) -> NSColor? {
        let middle = CGFloat(rep.pixelsWide) / 2
        let reach = 6.5 * CGFloat(rep.pixelsWide) / 18
        var best: (NSColor, CGFloat)?
        for row in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard hypot(CGFloat(x) + 0.5 - middle, CGFloat(row) + 0.5 - middle) <= reach,
                    let pixel = rep.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB)
                else { continue }
                let distance = abs(pixel.redComponent - fill.redComponent) + abs(pixel.greenComponent - fill.greenComponent)
                    + abs(pixel.blueComponent - fill.blueComponent)
                if distance > (best?.1 ?? 0) {
                    best = (pixel, distance)
                }
            }
        }
        return best?.0
    }

    /// Opaque pixels inside the ring that `matches` picks out.
    private func countPixels(in rep: NSBitmapImageRep, matching matches: (NSColor) -> Bool) -> Int {
        var count = 0
        for row in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB),
                    color.alphaComponent > 0.99, matches(color)
                else { continue }
                count += 1
            }
        }
        return count
    }

    /// The glyph's bounds in a rendered icon, in pixels from the top-left, with each edge placed
    /// inside its outermost pixel by how much of that pixel the glyph covers (`glyphCoverage`).
    private func glyphBounds(in rep: NSBitmapImageRep, scale: Int) -> CGRect? {
        let fill = color(in: rep, atPoint: NSPoint(x: 3, y: 9), scale: scale)
        guard let coverage = glyphCoverage(from: fill, toward: ConfirmationIcon.glyphColor(onFill: fill)) else {
            return nil
        }
        return inkBounds(in: rep, coverage: coverage)
    }

    /// How much of a pixel the glyph covers: how far its color has moved from `fill` toward
    /// `glyph`, from 0 to 1. Only opaque pixels count, so the ring's soft outer edge never does.
    /// Nil when the two colors are too close to tell apart.
    private func glyphCoverage(from fill: NSColor, toward glyph: NSColor) -> ((NSColor) -> CGFloat)? {
        guard let fill = fill.usingColorSpace(.deviceRGB), let glyph = glyph.usingColorSpace(.deviceRGB) else {
            return nil
        }
        let span = [
            glyph.redComponent - fill.redComponent,
            glyph.greenComponent - fill.greenComponent,
            glyph.blueComponent - fill.blueComponent,
        ]
        let spanSquared = span.reduce(0) { $0 + $1 * $1 }
        guard spanSquared > 0.01 else { return nil }
        return { pixel in
            guard pixel.alphaComponent > 0.99 else { return 0 }
            let offset = [
                pixel.redComponent - fill.redComponent,
                pixel.greenComponent - fill.greenComponent,
                pixel.blueComponent - fill.blueComponent,
            ]
            let along = zip(offset, span).reduce(0) { $0 + $1.0 * $1.1 } / spanSquared
            return min(max(along, 0), 1)
        }
    }

    /// The area `coverage` inks in `rep`, in pixels, counting only pixels whose middle is within
    /// `radius` pixels of the image's middle when given.
    private func inkArea(
        in rep: NSBitmapImageRep, coverage: (NSColor) -> CGFloat, within radius: CGFloat? = nil
    ) -> CGFloat {
        let middle = CGPoint(x: CGFloat(rep.pixelsWide) / 2, y: CGFloat(rep.pixelsHigh) / 2)
        var area: CGFloat = 0
        for row in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let radius, hypot(CGFloat(x) + 0.5 - middle.x, CGFloat(row) + 0.5 - middle.y) > radius { continue }
                guard let pixel = rep.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                area += coverage(pixel)
            }
        }
        return area
    }

    /// Runs `body` with `appearance` as the current drawing appearance, so dynamic colors such
    /// as systemRed resolve the same way whatever the Mac's appearance is.
    private func drawing(in appearance: NSAppearance.Name, _ body: () throws -> Void) throws {
        var result: Result<Void, Error> = .success(())
        try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            result = Result { try body() }
        }
        try result.get()
    }

    /// The bounds of the pixels `coverage` gives more than a trace, in pixels from the top-left,
    /// with each edge placed inside its outermost pixel by that pixel's coverage.
    private func inkBounds(in rep: NSBitmapImageRep, coverage: (NSColor) -> CGFloat) -> CGRect? {
        var columns = [CGFloat](repeating: 0, count: rep.pixelsWide)
        var rows = [CGFloat](repeating: 0, count: rep.pixelsHigh)
        for row in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let pixel = rep.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                let covered = coverage(pixel)
                columns[x] = max(columns[x], covered)
                rows[row] = max(rows[row], covered)
            }
        }
        func edges(_ profile: [CGFloat]) -> (CGFloat, CGFloat)? {
            let trace: CGFloat = 0.05
            guard let first = profile.firstIndex(where: { $0 > trace }),
                let last = profile.lastIndex(where: { $0 > trace })
            else { return nil }
            return (CGFloat(first) + 1 - profile[first], CGFloat(last) + profile[last])
        }
        guard let (left, right) = edges(columns), let (top, bottom) = edges(rows) else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
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
    /// Rec. 709 luma of the color's device RGB components.
    var luminance: CGFloat {
        guard let rgb = usingColorSpace(.deviceRGB) else { return 0 }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}
