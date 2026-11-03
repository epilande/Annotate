import ImageIO
import XCTest

@testable import Annotate

/// Stands in for ScreenCaptureKit: CI has no Screen Recording, so no test may capture.
@MainActor
final class StubDisplayCapturing: DisplayCapturing {
    var canCapture: Bool
    var snapshotImage: CGImage?
    private(set) var captureCount = 0

    init(canCapture: Bool = true, snapshotImage: CGImage?) {
        self.canCapture = canCapture
        self.snapshotImage = snapshotImage
    }

    func captureDisplay(_ display: DisplayInfo) async -> DisplaySnapshot? {
        captureCount += 1
        return snapshotImage.map { DisplaySnapshot(image: $0, displayFrame: display.frame) }
    }
}

/// Returns `images` in turn, one per capture. The first capture waits until `open()`, so a
/// test can hold it while a later capture is asked for.
@MainActor
final class GatedDisplayCapturing: DisplayCapturing {
    let canCapture = true
    private var images: [CGImage]
    private var isOpen = false
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var captureCount = 0

    init(images: [CGImage]) {
        self.images = images
    }

    func open() {
        isOpen = true
        waiting?.resume()
        waiting = nil
    }

    func captureDisplay(_ display: DisplayInfo) async -> DisplaySnapshot? {
        captureCount += 1
        let image = images.isEmpty ? nil : images.removeFirst()
        if captureCount == 1, !isOpen {
            await withCheckedContinuation { waiting = $0 }
        }
        return image.map { DisplaySnapshot(image: $0, displayFrame: display.frame) }
    }
}

/// An RGBA color with 0-255 components.
struct RGBA: Equatable, CustomStringConvertible {
    var r: Int, g: Int, b: Int, a: Int

    var description: String { "(\(r), \(g), \(b), \(a))" }

    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255)
    }

    func isClose(to other: RGBA, tolerance: Int = 3) -> Bool {
        abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance
            && abs(b - other.b) <= tolerance && abs(a - other.a) <= tolerance
    }
}

enum CaptureTestImages {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An sRGB image whose top `topRows` rows are `top` and the rest `bottom`, and whose
    /// left `leftColumns` columns are `left` when given.
    static func image(
        width: Int, height: Int, top: RGBA, bottom: RGBA, topRows: Int = 0,
        left: RGBA? = nil, leftColumns: Int = 0
    ) -> CGImage {
        let context = makeContext(width: width, height: height, data: nil)
        func fill(_ color: RGBA, _ rect: CGRect) {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }
        // Context rows run bottom-up, so the top rows sit at the high y end.
        fill(bottom, CGRect(x: 0, y: 0, width: width, height: height))
        fill(top, CGRect(x: 0, y: height - topRows, width: width, height: topRows))
        if let left {
            fill(left, CGRect(x: 0, y: 0, width: leftColumns, height: height))
        }
        return context.makeImage()!
    }

    static func solid(width: Int, height: Int, _ color: RGBA) -> CGImage {
        image(width: width, height: height, top: color, bottom: color)
    }

    /// The pixel at `x`, `y` counted from the top-left corner, as sRGB.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = makeContext(width: 1, height: 1, data: buffer.baseAddress)
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return RGBA(r: Int(bytes[0]), g: Int(bytes[1]), b: Int(bytes[2]), a: Int(bytes[3]))
    }

    /// An 8-bit sRGB RGBA context.
    private static func makeContext(width: Int, height: Int, data: UnsafeMutableRawPointer?) -> CGContext {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}

@MainActor
final class CaptureTests: XCTestCase {
    private static let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private static let green = RGBA(r: 0, g: 255, b: 0, a: 255)
    private static let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    private static let black = RGBA(r: 0, g: 0, b: 0, a: 255)

    /// A 100 x 50 point display away from the origin, so screen and view coordinates differ.
    private func display(scale: CGFloat = 1) -> DisplayInfo {
        DisplayInfo(id: 7, frame: CGRect(x: 300, y: 200, width: 100, height: 50), scale: scale)
    }

    private func scene(
        _ document: OverlayDocument = OverlayDocument(), board: BoardAppearance = .hidden,
        opacity: CGFloat = 0.9, fade: FadePolicy = .fullStrength, now: CFTimeInterval = 0
    ) -> CaptureScene {
        CaptureScene(document: document, board: board, boardOpacity: opacity, fade: fade, now: now)
    }

    private func request(display: DisplayInfo, scene: CaptureScene?) -> CaptureRequest {
        CaptureRequest(display: display, scene: scene, hostTime: 42, date: Date(timeIntervalSince1970: 0))
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotateCaptureTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func privatePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnnotateCaptureTests-\(UUID().uuidString)"))
        addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
        return pasteboard
    }

    private func redaction(_ rect: CGRect, style: RectangleStyle = .solid) -> Rectangle {
        Rectangle(
            startPoint: rect.origin,
            endPoint: NSPoint(x: rect.maxX, y: rect.maxY),
            color: .black,
            lineWidth: 1,
            style: style)
    }

    /// A stale red sample for `rectangle`, standing in for one the overlay took earlier.
    private func staleSample(for rectangle: Rectangle) -> RedactionSample {
        RedactionSample(
            image: CaptureTestImages.solid(width: 4, height: 4, Self.red),
            bounds: rectangle.bounds,
            key: RedactionSampleKey(rectangle))
    }

    // MARK: - Composite

    func testCompositeKeepsSnapshotUprightAtScaleOneAndTwo() throws {
        for scale in [CGFloat(1), 2] {
            let info = display(scale: scale)
            let snapshot = DisplaySnapshot(
                image: CaptureTestImages.image(
                    width: Int(100 * scale),
                    height: Int(50 * scale),
                    top: Self.red,
                    bottom: Self.blue,
                    topRows: Int(10 * scale)),
                displayFrame: info.frame)

            let image = try XCTUnwrap(CaptureCompositor.composite(snapshot: snapshot, display: info, scene: nil))

            XCTAssertEqual(image.width, Int(100 * scale), "scale \(scale)")
            XCTAssertEqual(image.height, Int(50 * scale), "scale \(scale)")
            XCTAssertTrue(CaptureTestImages.pixel(image, x: 2, y: 2).isClose(to: Self.red), "scale \(scale)")
            XCTAssertTrue(
                CaptureTestImages.pixel(image, x: 2, y: image.height - 2).isClose(to: Self.blue), "scale \(scale)")
        }
    }

    func testCompositeDrawsAnnotationsInViewPointsAtScaleOneAndTwo() throws {
        for scale in [CGFloat(1), 2] {
            let info = display(scale: scale)
            let snapshot = DisplaySnapshot(
                image: CaptureTestImages.solid(width: Int(100 * scale), height: Int(50 * scale), Self.blue),
                displayFrame: info.frame)
            var document = OverlayDocument()
            // View points, bottom-left origin: the top-left 20 x 10 points of the display.
            document.rectangles = [redaction(CGRect(x: 0, y: 40, width: 20, height: 10))]

            let image = try XCTUnwrap(
                CaptureCompositor.composite(snapshot: snapshot, display: info, scene: scene(document)))

            let inside = CaptureTestImages.pixel(image, x: Int(10 * scale), y: Int(5 * scale))
            let outside = CaptureTestImages.pixel(image, x: Int(30 * scale), y: Int(5 * scale))
            let below = CaptureTestImages.pixel(image, x: Int(10 * scale), y: Int(15 * scale))
            XCTAssertTrue(inside.isClose(to: Self.black), "scale \(scale): \(inside)")
            XCTAssertTrue(outside.isClose(to: Self.blue), "scale \(scale): \(outside)")
            XCTAssertTrue(below.isClose(to: Self.blue), "scale \(scale): \(below)")
        }
    }

    func testCompositeLaysBoardOverScreenAtItsOpacity() throws {
        let info = display()
        let snapshot = DisplaySnapshot(
            image: CaptureTestImages.solid(width: 100, height: 50, Self.blue), displayFrame: info.frame)
        let whiteboard = BoardAppearance(isVisible: true, type: .whiteboard)

        let image = try XCTUnwrap(
            CaptureCompositor.composite(
                snapshot: snapshot, display: info, scene: scene(board: whiteboard, opacity: 0.5)))

        let pixel = CaptureTestImages.pixel(image, x: 50, y: 25)
        XCTAssertTrue(pixel.isClose(to: RGBA(r: 128, g: 128, b: 255, a: 255), tolerance: 4), "\(pixel)")
        // No 1 pt border, unlike the board view.
        XCTAssertTrue(CaptureTestImages.pixel(image, x: 0, y: 0).isClose(to: pixel, tolerance: 1))
    }

    func testCompositeWithBoardOffShowsScreenUnchanged() throws {
        let info = display()
        let snapshot = DisplaySnapshot(
            image: CaptureTestImages.solid(width: 100, height: 50, Self.blue), displayFrame: info.frame)

        let hidden = scene(board: BoardAppearance(isVisible: false, type: .whiteboard), opacity: 1)
        let image = try XCTUnwrap(CaptureCompositor.composite(snapshot: snapshot, display: info, scene: hidden))

        XCTAssertTrue(CaptureTestImages.pixel(image, x: 50, y: 25).isClose(to: Self.blue))
    }

    func testCompositeLeavesOutFullyFadedAnnotations() throws {
        let info = display()
        let snapshot = DisplaySnapshot(
            image: CaptureTestImages.solid(width: 100, height: 50, Self.blue), displayFrame: info.frame)
        var outline = Rectangle(
            startPoint: NSPoint(x: 10, y: 10), endPoint: NSPoint(x: 40, y: 40), color: .red, lineWidth: 10)
        outline.creationTime = 0
        var document = OverlayDocument()
        document.rectangles = [outline]
        let fade = FadePolicy(
            isFadeMode: true, delay: 1, outDuration: 1, persistRestoreStart: nil, persistRestoreDuration: 0)

        let shown = try XCTUnwrap(
            CaptureCompositor.composite(snapshot: snapshot, display: info, scene: scene(document, fade: fade, now: 0.5)))
        let faded = try XCTUnwrap(
            CaptureCompositor.composite(snapshot: snapshot, display: info, scene: scene(document, fade: fade, now: 5)))

        // The outline's left edge, at view x 10, display-local y 50 - 25.
        XCTAssertTrue(CaptureTestImages.pixel(shown, x: 10, y: 25).isClose(to: Self.red, tolerance: 8))
        XCTAssertTrue(CaptureTestImages.pixel(faded, x: 10, y: 25).isClose(to: Self.blue))
    }

    func testRedactionsResampleFromTheCapturedPixels() async throws {
        let info = display()
        // Green on the left 50 points, blue on the right.
        let snapshot = DisplaySnapshot(
            image: CaptureTestImages.image(
                width: 100, height: 50, top: Self.blue, bottom: Self.blue, left: Self.green, leftColumns: 50),
            displayFrame: info.frame)
        var pixelate = redaction(CGRect(x: 5, y: 5, width: 40, height: 40), style: .pixelate)
        // A sample from before the screen changed must not reach the file.
        pixelate.sample = staleSample(for: pixelate)
        var document = OverlayDocument()
        document.rectangles = [pixelate]

        let resampled = await CaptureCompositor.resampleRedactions(in: document, from: snapshot, display: info)
        let image = try XCTUnwrap(
            CaptureCompositor.composite(snapshot: snapshot, display: info, scene: scene(resampled)))

        let pixel = CaptureTestImages.pixel(image, x: 25, y: 25)
        XCTAssertTrue(pixel.isClose(to: Self.green, tolerance: 8), "\(pixel)")
    }

    func testRedactionsWithoutSnapshotStayOpaque() async throws {
        var blur = redaction(CGRect(x: 5, y: 5, width: 40, height: 40), style: .blur)
        blur.sample = staleSample(for: blur)
        var document = OverlayDocument()
        document.rectangles = [blur]

        let resampled = await CaptureCompositor.resampleRedactions(in: document, from: nil, display: display())

        XCTAssertNil(resampled.rectangles[0].sample)
    }

    // MARK: - Encoding

    func testPNGCarriesRetinaDPI() async throws {
        let image = CaptureTestImages.solid(width: 20, height: 10, Self.blue)
        let png = try await XCTUnwrapAsync(await CaptureCompositor.encodePNG(image, scale: 2))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, 144)
        XCTAssertEqual((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue, 144)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 20)
    }

    // MARK: - Service

    func testServiceSavesFileAndCopiesToClipboard() async throws {
        let folder = try temporaryFolder()
        let pasteboard = privatePasteboard()
        let source = StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 200, height: 100, Self.blue))
        let service = CaptureService(
            source: source, sinks: [FileSink(folder: folder), ClipboardSink(pasteboard: pasteboard)])

        let result = try await service.capture(request(display: display(scale: 2), scene: scene()))

        let file = try XCTUnwrap(result.savedFile)
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertTrue(file.lastPathComponent.hasPrefix("Annotate "))
        XCTAssertEqual(file.pathExtension, "png")
        let saved = try Data(contentsOf: file)
        XCTAssertEqual(pasteboard.data(forType: .png), saved)
        XCTAssertTrue(result.copiedToClipboard)
        XCTAssertEqual(result.capture.scale, 2)
        XCTAssertEqual(result.capture.region, CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(result.capture.hostTime, 42)
        XCTAssertEqual(source.captureCount, 1)
        let decoded = try XCTUnwrap(NSImage(data: saved))
        XCTAssertEqual(decoded.size, NSSize(width: 100, height: 50))
    }

    func testServiceRefusesWithoutScreenRecording() async throws {
        let source = StubDisplayCapturing(canCapture: false, snapshotImage: nil)
        let service = CaptureService(source: source, sinks: [])

        do {
            _ = try await service.capture(request(display: display(), scene: scene()))
            XCTFail("Expected screenRecordingOff")
        } catch {
            XCTAssertEqual(error as? CaptureError, .screenRecordingOff)
        }
        XCTAssertEqual(source.captureCount, 0)
    }

    func testOpaqueBoardCapturesWithoutScreenRecording() async throws {
        let pasteboard = privatePasteboard()
        let source = StubDisplayCapturing(canCapture: false, snapshotImage: nil)
        let service = CaptureService(source: source, sinks: [ClipboardSink(pasteboard: pasteboard)])
        let blackboard = BoardAppearance(isVisible: true, type: .blackboard)

        let result = try await service.capture(
            request(display: display(scale: 2), scene: scene(board: blackboard, opacity: 1)))

        XCTAssertEqual(source.captureCount, 0)
        XCTAssertEqual(result.capture.image.width, 200)
        XCTAssertEqual(result.capture.image.height, 100)
        let pixel = CaptureTestImages.pixel(result.capture.image, x: 100, y: 50)
        let board = try XCTUnwrap(
            BoardView.BoardType.blackboard.backgroundColor(opacity: 1).usingColorSpace(.sRGB))
        // A gray, so red, green, and blue match.
        let expected = Int((board.redComponent * 255).rounded())
        XCTAssertTrue(pixel.isClose(to: RGBA(r: expected, g: expected, b: expected, a: 255)), "\(pixel)")
    }

    func testServiceReportsFailedSnapshot() async throws {
        let service = CaptureService(source: StubDisplayCapturing(snapshotImage: nil), sinks: [])

        do {
            _ = try await service.capture(request(display: display(), scene: nil))
            XCTFail("Expected snapshotFailed")
        } catch {
            XCTAssertEqual(error as? CaptureError, .snapshotFailed)
        }
    }

    func testServiceKeepsClipboardWhenFileFails() async throws {
        // A regular file where the folder should be makes every write fail.
        let blocker = try temporaryFolder()
        try Data().write(to: blocker)
        let pasteboard = privatePasteboard()
        let service = CaptureService(
            source: StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 100, height: 50, Self.blue)),
            sinks: [FileSink(folder: blocker), ClipboardSink(pasteboard: pasteboard)])

        let result = try await service.capture(request(display: display(), scene: nil))

        XCTAssertNil(result.savedFile)
        XCTAssertTrue(result.copiedToClipboard)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertNotNil(pasteboard.data(forType: .png))
    }

    // MARK: - File naming

    func testFileNameMirrorsMacOSScreenshots() throws {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 11, 1)
        (components.hour, components.minute, components.second) = (10, 23, 45)
        components.timeZone = TimeZone(identifier: "America/Los_Angeles")
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))

        let baseName = FileSink.baseName(for: date, timeZone: try XCTUnwrap(components.timeZone))

        XCTAssertEqual(baseName, "Annotate 2026-11-01 at 10.23.45")
        XCTAssertEqual(FileSink.fileName(baseName, attempt: 1), "Annotate 2026-11-01 at 10.23.45.png")
        XCTAssertEqual(FileSink.fileName(baseName, attempt: 2), "Annotate 2026-11-01 at 10.23.45 (2).png")
    }

    func testCollidingNamesGetANumberInsteadOfOverwriting() async throws {
        let folder = try temporaryFolder()

        let first = try await FileSink.write(Data([1]), baseName: "Annotate X", in: folder)
        let second = try await FileSink.write(Data([2]), baseName: "Annotate X", in: folder)
        let third = try await FileSink.write(Data([3]), baseName: "Annotate X", in: folder)

        XCTAssertEqual(first.lastPathComponent, "Annotate X.png")
        XCTAssertEqual(second.lastPathComponent, "Annotate X (2).png")
        XCTAssertEqual(third.lastPathComponent, "Annotate X (3).png")
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
        XCTAssertEqual(try Data(contentsOf: second), Data([2]))
    }

    func testDefaultFolderIsPicturesAnnotateInTheRealHome() {
        let folder = FileSink.defaultFolder
        XCTAssertEqual(folder.lastPathComponent, "Annotate")
        XCTAssertEqual(folder.deletingLastPathComponent().lastPathComponent, "Pictures")
        XCTAssertFalse(folder.path.contains("/Library/Containers/"))
        XCTAssertEqual(CaptureSettingsView.folderDisplayPath, "~/Pictures/Annotate")
    }

    // MARK: - Display rule

    func testCaptureTargetPrefersKeyOverlayThenPointerThenMain() {
        let cases: [(key: String?, pointer: String?, main: String?, expected: String?)] = [
            ("key", "pointer", "main", "key"),
            (nil, "pointer", "main", "pointer"),
            (nil, nil, "main", "main"),
            (nil, nil, nil, nil),
        ]
        for row in cases {
            XCTAssertEqual(
                AppDelegate.captureTarget(keyOverlay: row.key, pointer: row.pointer, main: row.main), row.expected)
        }
    }

    // MARK: - Shortcut

    func testCaptureScreenDefaultsToCommandS() {
        XCTAssertEqual(ShortcutKey.captureScreen.defaultBinding, ShortcutBinding("s", modifiers: .command))
        XCTAssertFalse(ShortcutKey.captureScreen.defaultBinding.isReserved)
        XCTAssertTrue(ShortcutKey.newlyEditable.contains(.captureScreen))
        XCTAssertEqual(ShortcutKey.captureScreen.displayName, "Capture Screen")
    }
}

/// `XCTUnwrap` for an optional produced by an `await`.
func XCTUnwrapAsync<T>(
    _ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line
) async throws -> T {
    let resolved = try await value()
    return try XCTUnwrap(resolved, file: file, line: line)
}
