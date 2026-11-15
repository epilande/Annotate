import XCTest

@testable import Annotate

@MainActor
final class CaptureRecordTests: XCTestCase {
    /// 1 November 2026, 16:23:45.125 UTC.
    private static let date = Date(timeIntervalSince1970: 1_793_550_225.125)
    /// A 400 x 300 point display away from the origin at scale 2, so screen, view, and image
    /// coordinates all differ.
    private static let display = DisplayInfo(id: 7, frame: CGRect(x: 300, y: 200, width: 400, height: 300), scale: 2)
    /// Stands in for TextKit, so the record doesn't depend on the system font's metrics.
    private static let labelSize = NSSize(width: 50, height: 20)

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private static func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotateCaptureRecordTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func capture(
        _ document: OverlayDocument?, region: CGRect? = nil, board: BoardAppearance = .hidden,
        fade: FadePolicy = .fullStrength, now: CFTimeInterval = 1000.5
    ) -> Capture {
        let size = Self.display.frame.size
        let region = region ?? CGRect(origin: .zero, size: size)
        return Capture(
            image: CaptureTestImages.solid(
                width: Int(region.width * 2), height: Int(region.height * 2), RGBA(r: 0, g: 0, b: 255, a: 255)),
            display: Self.display,
            region: region,
            scene: document.map {
                CaptureScene(document: $0, board: board, boardOpacity: 0.5, fade: fade, now: now)
            },
            capturedAt: Self.date,
            hostTime: 1000.5)
    }

    private func record(_ capture: Capture, imageFile: String? = nil) -> CaptureRecord {
        CaptureRecord(capture, imageFile: imageFile) { _ in Self.labelSize }
    }

    /// One of every kind, in view points with the display's bottom-left as the origin.
    private var everyKind: OverlayDocument {
        var document = OverlayDocument()
        document.paths = [
            DrawingPath(
                points: [
                    TimedPoint(point: NSPoint(x: 10, y: 290), timestamp: 990),
                    TimedPoint(point: NSPoint(x: 20, y: 280), timestamp: 990.25),
                ],
                color: Self.srgb(1, 0, 0),
                lineWidth: 3,
                creationTime: 990.5,
                id: Self.id(1))
        ]
        document.highlightPaths = [
            DrawingPath(
                points: [
                    TimedPoint(point: NSPoint(x: 30, y: 250), timestamp: 991),
                    TimedPoint(point: NSPoint(x: 60, y: 250), timestamp: 991.25),
                ],
                color: Self.srgb(1, 1, 0),
                lineWidth: 3,
                creationTime: 991.5,
                id: Self.id(2))
        ]
        document.arrows = [
            Arrow(
                startPoint: NSPoint(x: 100, y: 200),
                endPoint: NSPoint(x: 150, y: 250),
                color: Self.srgb(0, 0, 1),
                lineWidth: 4,
                creationTime: 992,
                id: Self.id(3))
        ]
        document.lines = [
            Line(
                startPoint: NSPoint(x: 100, y: 100),
                endPoint: NSPoint(x: 200, y: 100),
                color: Self.srgb(0, 1, 0),
                lineWidth: 2,
                creationTime: 992.5,
                id: Self.id(4))
        ]
        document.rectangles = [
            // Dragged from the bottom-right corner, so the record has to normalize it.
            Rectangle(
                startPoint: NSPoint(x: 260, y: 50),
                endPoint: NSPoint(x: 210, y: 90),
                color: Self.srgb(1, 0, 0, 0.5),
                lineWidth: 3,
                creationTime: 993,
                id: Self.id(5)),
            Rectangle(
                startPoint: NSPoint(x: 20, y: 20),
                endPoint: NSPoint(x: 60, y: 40),
                color: .black,
                lineWidth: 3,
                creationTime: 994,
                style: .pixelate,
                id: Self.id(7)),
        ]
        document.circles = [
            Circle(
                startPoint: NSPoint(x: 300, y: 50),
                endPoint: NSPoint(x: 350, y: 100),
                color: Self.srgb(1, 0.5, 0),
                lineWidth: 5,
                creationTime: 993.5,
                id: Self.id(6))
        ]
        document.textAnnotations = [
            TextAnnotation(
                text: "Click \"Save\"",
                position: NSPoint(x: 40, y: 150),
                color: Self.srgb(1, 1, 1),
                fontSize: 16,
                hasBackground: true,
                creationTime: 995,
                id: Self.id(8))
        ]
        document.counterAnnotations = [
            CounterAnnotation(
                number: 1,
                position: NSPoint(x: 380, y: 20),
                color: Self.srgb(0, 0, 0),
                fontSize: 14,
                style: .filled,
                creationTime: 996,
                id: Self.id(9))
        ]
        return document
    }

    private func fixture() throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: CaptureRecordTests.self)
        #endif
        // SwiftPM keeps the Fixtures folder; Xcode copies the file to the bundle's top level.
        let url = try XCTUnwrap(
            bundle.url(forResource: "CaptureRecordV1", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "CaptureRecordV1", withExtension: "json"),
            "The golden file ships in the test bundle")
        return try Data(contentsOf: url)
    }

    /// Asserts two parsed JSON values match, with numbers equal to within rounding: the
    /// highlighter's drawn width is 3 x 4.67, which isn't exact in binary.
    private func assertJSONEqual(_ actual: Any, _ expected: Any, path: String = "$", line: UInt = #line) {
        switch (actual, expected) {
        case let (actual as [String: Any], expected as [String: Any]):
            XCTAssertEqual(actual.keys.sorted(), expected.keys.sorted(), "Keys at \(path)", line: line)
            for (key, value) in expected {
                guard let other = actual[key] else { continue }
                assertJSONEqual(other, value, path: "\(path).\(key)", line: line)
            }
        case let (actual as [Any], expected as [Any]):
            XCTAssertEqual(actual.count, expected.count, "Count at \(path)", line: line)
            for (index, (lhs, rhs)) in zip(actual, expected).enumerated() {
                assertJSONEqual(lhs, rhs, path: "\(path)[\(index)]", line: line)
            }
        case let (actual as String, expected as String):
            XCTAssertEqual(actual, expected, path, line: line)
        case let (actual as NSNumber, expected as NSNumber):
            // Booleans parse as NSNumber too; the golden file says which each one is.
            let isBool = CFGetTypeID(expected) == CFBooleanGetTypeID()
            XCTAssertEqual(CFGetTypeID(actual) == CFBooleanGetTypeID(), isBool, "Type at \(path)", line: line)
            XCTAssertEqual(actual.doubleValue, expected.doubleValue, accuracy: 1e-9, path, line: line)
        default:
            XCTFail("\(path): \(actual) is not \(expected)", line: line)
        }
    }

    // MARK: - Format

    func testRecordMatchesTheGoldenFile() throws {
        let record = record(
            capture(everyKind, board: BoardAppearance(isVisible: true, type: .whiteboard)),
            imageFile: "Annotate 2026-11-01 at 08.23.45.png")

        let written = try JSONSerialization.jsonObject(with: try record.jsonData())
        let golden = try JSONSerialization.jsonObject(with: try fixture())

        assertJSONEqual(written, golden)
    }

    func testGoldenFileDecodesAndRoundTrips() throws {
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: try fixture())

        XCTAssertEqual(decoded.format, "annotate.capture")
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.annotations.map(\.kind), [
            "arrow", "line", "pen", "highlighter", "rectangle", "ellipse", "redaction", "text", "pin",
        ])
        XCTAssertEqual(try JSONDecoder().decode(CaptureRecord.self, from: try decoded.jsonData()), decoded)
    }

    func testUnknownKindFailsToDecode() {
        let json = #"{"kind": "sticker", "id": "x"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(CaptureRecord.Annotation.self, from: Data(json.utf8)))
    }

    func testJSONIsTheSameBytesEachTime() throws {
        let record = record(capture(everyKind))
        XCTAssertEqual(try record.jsonData(), try record.jsonData())
    }

    // MARK: - Coordinates

    func testCoordinatesAreDisplayLocalFromTheTopLeft() {
        let space = CaptureRecord.DisplaySpace(height: 300)

        XCTAssertEqual(space.point(NSPoint(x: 10, y: 290)), CaptureRecord.Point(x: 10, y: 10))
        XCTAssertEqual(space.point(NSPoint(x: 0, y: 0)), CaptureRecord.Point(x: 0, y: 300))
        XCTAssertEqual(
            space.rect(NSRect(x: 210, y: 50, width: 50, height: 40)),
            CaptureRecord.Rect(x: 210, y: 210, width: 50, height: 40),
            "A rect's top edge is its view maxY")
        XCTAssertEqual(
            space.viewRect(CGRect(x: 210, y: 210, width: 50, height: 40)), CGRect(x: 210, y: 50, width: 50, height: 40))
    }

    func testLabelRectHangsFromTheTextTop() throws {
        let record = record(capture(everyKind))
        guard case .text(let label) = try XCTUnwrap(record.annotations.first { $0.kind == "text" }) else {
            return XCTFail("No label")
        }
        // `position` is the bottom-left at y 150, so the 20 point text's top is at view y 170.
        XCTAssertEqual(label.rect, CaptureRecord.Rect(x: 40, y: 130, width: 50, height: 20))
    }

    func testAreaCaptureKeepsDisplayCoordinatesAndOnlyWhatShowsInTheArea() async throws {
        var document = OverlayDocument()
        // Inside the area, which spans view y 150 to 250.
        let inside = Arrow(
            startPoint: NSPoint(x: 150, y: 200),
            endPoint: NSPoint(x: 180, y: 220),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        // Its arrowhead padding still ends well short of the area.
        let outside = Arrow(
            startPoint: NSPoint(x: 10, y: 10),
            endPoint: NSPoint(x: 20, y: 20),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        document.arrows = [inside, outside]
        let area = CGRect(x: 100, y: 50, width: 200, height: 100)
        let service = CaptureService(
            source: StubDisplayCapturing(
                snapshotImage: CaptureTestImages.solid(width: 800, height: 600, RGBA(r: 0, g: 0, b: 255, a: 255))),
            sinks: [])
        var request = CaptureRequest(
            display: Self.display,
            region: .rect(area),
            scene: CaptureScene(document: document, board: .hidden, boardOpacity: 1, fade: .fullStrength, now: 2),
            hostTime: 5,
            date: Self.date)
        request.savesAnnotationData = true

        let result = try await service.capture(request)

        let record = try XCTUnwrap(result.capture.record, "The service makes the record when asked to")
        XCTAssertEqual(record.region, CaptureRecord.Rect(x: 100, y: 50, width: 200, height: 100))
        XCTAssertEqual(record.image.width, 400)
        XCTAssertEqual(record.image.height, 200)
        XCTAssertNil(record.image.file, "Only a saved image has a name")
        XCTAssertEqual(record.display, CaptureRecord.Display(id: 7, width: 400, height: 300, scale: 2))
        XCTAssertEqual(record.annotations, [
            .arrow(
                CaptureRecord.Segment(
                    id: inside.id.uuidString,
                    time: 1,
                    color: "#FF0000",
                    width: 2,
                    start: CaptureRecord.Point(x: 150, y: 100),
                    end: CaptureRecord.Point(x: 180, y: 80)))
        ])
        // The arrow's start in image pixels, as the schema says to find it.
        let start = CaptureRecord.Point(x: (150 - record.region.x) * 2, y: (100 - record.region.y) * 2)
        XCTAssertEqual(start, CaptureRecord.Point(x: 100, y: 100))
    }

    func testServiceMakesNoRecordUnlessAsked() async throws {
        let service = CaptureService(
            source: StubDisplayCapturing(
                snapshotImage: CaptureTestImages.solid(width: 800, height: 600, RGBA(r: 0, g: 0, b: 255, a: 255))),
            sinks: [])
        let request = CaptureRequest(display: Self.display, scene: nil, hostTime: 5, date: Self.date)

        let result = try await service.capture(request)

        XCTAssertNil(result.capture.record)
    }

    // MARK: - Clock

    func testClockFieldsNameTheHostClockAndTheWallTime() throws {
        let record = record(capture(everyKind))

        XCTAssertEqual(record.clock, "mach_absolute_time")
        XCTAssertEqual(record.hostTime, 1000.5)
        XCTAssertEqual(record.capturedAt, "2026-11-01T16:23:45.125Z")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = try XCTUnwrap(formatter.date(from: record.capturedAt))
        XCTAssertEqual(parsed.timeIntervalSince1970, Self.date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testAnnotationTimesAreOnTheHostClock() throws {
        let record = record(capture(everyKind))

        guard case .pen(let stroke) = try XCTUnwrap(record.annotations.first { $0.kind == "pen" }) else {
            return XCTFail("No pen stroke")
        }
        XCTAssertEqual(stroke.time, 990.5, "The creation time, unconverted")
        XCTAssertEqual(stroke.points.map(\.time), [990, 990.25])
        // Converting with the record's own clock fields: the stroke ended 10 s before the capture.
        let wall = Self.date.addingTimeInterval(try XCTUnwrap(stroke.time) - record.hostTime)
        XCTAssertEqual(wall.timeIntervalSince(Self.date), -10)
    }

    // MARK: - What the image shows

    func testFullyFadedAnnotationsAreLeftOut() {
        var document = OverlayDocument()
        let faded = Arrow(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 150, y: 150),
            color: .red,
            lineWidth: 2,
            creationTime: 5)
        let fading = Arrow(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 150, y: 150),
            color: .red,
            lineWidth: 2,
            creationTime: 8.5)
        document.arrows = [faded, fading]
        let fade = FadePolicy(
            isFadeMode: true, delay: 1, outDuration: 1, persistRestoreStart: nil, persistRestoreDuration: 0)

        let record = record(capture(document, fade: fade, now: 10))

        XCTAssertEqual(record.annotations.map(\.id), [fading.id.uuidString], "Half faded still shows")
    }

    func testANewerRedactionHidesWhatItCovers() {
        var document = OverlayDocument()
        let covered = TextAnnotation(
            text: "hunter2", position: NSPoint(x: 110, y: 110), color: .red, fontSize: 16, creationTime: 1)
        let redaction = Rectangle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 140),
            color: .black,
            lineWidth: 1,
            creationTime: 2,
            style: .solid)
        let onTop = TextAnnotation(
            text: "Password", position: NSPoint(x: 110, y: 110), color: .red, fontSize: 16, creationTime: 3)
        document.textAnnotations = [covered, onTop]
        document.rectangles = [redaction]

        let record = record(capture(document))

        XCTAssertEqual(
            record.annotations.map(\.id),
            [redaction.id.uuidString, onTop.id.uuidString],
            "The label under the redaction stays hidden; the one placed over it shows")
    }

    /// A solid redaction from (100, 100) to (200, 140) in view points, made at time 2, over
    /// `items` made at time 1.
    private func recordWithNewerRedaction(_ fill: (inout OverlayDocument) -> Void) -> (CaptureRecord, Rectangle) {
        var document = OverlayDocument()
        fill(&document)
        let redaction = Rectangle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 140),
            color: .black,
            lineWidth: 1,
            creationTime: 2,
            style: .solid)
        document.rectangles.append(redaction)
        return (record(capture(document)), redaction)
    }

    func testAnnotationsBesideANewerRedactionStay() {
        // Each paints within a few points of the redaction without touching it, so their padded
        // paint bounds reach it but their ink doesn't.
        let arrow = Arrow(
            startPoint: NSPoint(x: 100, y: 160),
            endPoint: NSPoint(x: 200, y: 160),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        let line = Line(
            startPoint: NSPoint(x: 100, y: 95),
            endPoint: NSPoint(x: 200, y: 95),
            color: .red,
            lineWidth: 4,
            creationTime: 1)
        let stroke = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 203, y: 100), timestamp: 0),
                TimedPoint(point: NSPoint(x: 203, y: 140), timestamp: 0),
            ],
            color: .red,
            lineWidth: 3,
            creationTime: 1)
        // An outline drawn around the redaction: only its stroke is ink, and that misses it.
        let frame = Rectangle(
            startPoint: NSPoint(x: 80, y: 80),
            endPoint: NSPoint(x: 220, y: 160),
            color: .red,
            lineWidth: 2,
            creationTime: 1)

        let (record, redaction) = recordWithNewerRedaction {
            $0.arrows = [arrow]
            $0.lines = [line]
            $0.paths = [stroke]
            $0.rectangles = [frame]
        }

        let expected: [UUID] = [arrow.id, line.id, stroke.id, frame.id, redaction.id]
        XCTAssertEqual(Set(record.annotations.map(\.id)), Set(expected.map(\.uuidString)))
    }

    func testAnnotationsANewerRedactionOverlapsAreLeftOut() {
        let crossing = Arrow(
            startPoint: NSPoint(x: 50, y: 120),
            endPoint: NSPoint(x: 250, y: 120),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        // Its shaft stops short of the redaction, but the head's tip reaches into it.
        let headOnly = Arrow(
            startPoint: NSPoint(x: 150, y: 200),
            endPoint: NSPoint(x: 150, y: 138),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        let dot = DrawingPath(
            points: [TimedPoint(point: NSPoint(x: 150, y: 120), timestamp: 0)],
            color: .red,
            lineWidth: 3,
            creationTime: 1)
        let edge = Rectangle(
            startPoint: NSPoint(x: 190, y: 110),
            endPoint: NSPoint(x: 260, y: 130),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        let ellipse = Circle(
            startPoint: NSPoint(x: 60, y: 100),
            endPoint: NSPoint(x: 110, y: 140),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        let label = TextAnnotation(
            text: "hunter2", position: NSPoint(x: 195, y: 90), color: .red, fontSize: 16, creationTime: 1)

        let (record, redaction) = recordWithNewerRedaction {
            $0.arrows = [crossing, headOnly]
            $0.paths = [dot]
            $0.rectangles = [edge]
            $0.circles = [ellipse]
            $0.textAnnotations = [label]
        }

        XCTAssertEqual(record.annotations.map(\.id), [redaction.id.uuidString], "Only the redaction is left")
    }

    /// The middle 100 x 100 points of the display. Its top-left corner is at (100, 100) from
    /// the display's top-left, and its view rect, from the bottom-left, is the same.
    private static let area = CGRect(x: 100, y: 100, width: 100, height: 100)

    func testAreaCaptureLeavesOutInkThatMissesTheArea() {
        // Its stroke runs all the way around the area, 50 points outside it.
        let surrounding = Rectangle(
            startPoint: NSPoint(x: 50, y: 50),
            endPoint: NSPoint(x: 250, y: 250),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        // Its box overlaps the area's top-left corner, but the line passes 14 points above it.
        let diagonal = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 60, y: 180), timestamp: 0),
                TimedPoint(point: NSPoint(x: 180, y: 300), timestamp: 0),
            ],
            color: .red,
            lineWidth: 3,
            creationTime: 1)
        // Its text starts 5 points right of the area. Only its pill reaches in.
        let pillOnly = TextAnnotation(
            text: "Right",
            position: NSPoint(x: 205, y: 150),
            color: .red,
            fontSize: 16,
            hasBackground: true,
            creationTime: 1)
        // Its text ends 2 points below the area. Only the hit-test slop above it reaches in.
        let slopOnly = TextAnnotation(
            text: "Below", position: NSPoint(x: 150, y: 78), color: .red, fontSize: 16, creationTime: 1)
        var document = OverlayDocument()
        document.rectangles = [surrounding]
        document.paths = [diagonal]
        document.textAnnotations = [pillOnly, slopOnly]

        let record = record(capture(document, region: Self.area))

        XCTAssertEqual(record.annotations, [], "Each one's box reaches the area, but nothing it draws is in the image")
    }

    func testAreaCaptureKeepsWhatIsPartlyInside() {
        let arrow = Arrow(
            startPoint: NSPoint(x: 50, y: 150),
            endPoint: NSPoint(x: 150, y: 150),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        // Its left and bottom edges cross the area.
        let outline = Rectangle(
            startPoint: NSPoint(x: 150, y: 150),
            endPoint: NSPoint(x: 250, y: 250),
            color: .red,
            lineWidth: 2,
            creationTime: 1)
        let label = TextAnnotation(
            text: "Half", position: NSPoint(x: 180, y: 150), color: .red, fontSize: 16, creationTime: 1)
        var document = OverlayDocument()
        document.arrows = [arrow]
        document.rectangles = [outline]
        document.textAnnotations = [label]

        let record = record(capture(document, region: Self.area))

        XCTAssertEqual(
            record.annotations.map(\.id),
            [arrow.id, outline.id, label.id].map(\.uuidString),
            "Each draws partly inside the area")
    }

    func testPlainScreenCaptureHasNoAnnotationsOrBoard() {
        let record = record(capture(nil))

        XCTAssertTrue(record.annotations.isEmpty)
        XCTAssertNil(record.board)
    }

    func testRedactionSamplesAreNeverRecorded() throws {
        var rectangle = Rectangle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 140, y: 140),
            color: .black,
            lineWidth: 1,
            creationTime: 1,
            style: .blur)
        rectangle.sample = RedactionSample(
            image: CaptureTestImages.solid(width: 4, height: 4, RGBA(r: 255, g: 0, b: 0, a: 255)),
            bounds: rectangle.bounds,
            key: RedactionSampleKey(rectangle))
        var document = OverlayDocument()
        document.rectangles = [rectangle]

        let json = try XCTUnwrap(String(data: try record(capture(document)).jsonData(), encoding: .utf8))

        XCTAssertTrue(json.contains(#""style" : "blur""#) || json.contains(#""style":"blur""#), json)
        XCTAssertFalse(json.contains("sample"), json)
    }

    // MARK: - Colors

    func testColorsAreSRGBHex() {
        XCTAssertEqual(CaptureRecord.hex(Self.srgb(1, 0, 0)), "#FF0000")
        XCTAssertEqual(CaptureRecord.hex(Self.srgb(0, 0.5, 1, 0.5)), "#0080FF80")
        XCTAssertEqual(CaptureRecord.hex(NSColor(white: 1, alpha: 1)), "#FFFFFF", "Gray converts to sRGB")
        XCTAssertEqual(
            CaptureRecord.hex(NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)),
            "#FF0000",
            "Display P3 red is outside sRGB, so it clamps to sRGB red")
    }

    // MARK: - Writing

    func testRecordIsWrittenNextToTheImageUnderItsName() async throws {
        let folder = try temporaryFolder()
        let record = record(capture(everyKind))

        let first = try await FileSink.save(Data([1]), record: record, baseName: "Annotate X", in: folder).url
        let second = try await FileSink.save(Data([2]), record: record, baseName: "Annotate X", in: folder).url

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
            ["Annotate X (2).json", "Annotate X (2).png", "Annotate X.json", "Annotate X.png"],
            "Each image has its record, the colliding one included, and no temporary file is left")
        let saved = try JSONDecoder().decode(
            CaptureRecord.self, from: Data(contentsOf: FileSink.recordURL(for: second)))
        XCTAssertEqual(saved.image.file, "Annotate X (2).png", "The record names its own image")
        var expected = record
        expected.image.file = first.lastPathComponent
        XCTAssertEqual(
            try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: FileSink.recordURL(for: first))),
            expected)
    }

    func testAnOldRecordIsNeverReplaced() async throws {
        let folder = try temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let orphan = folder.appendingPathComponent("Annotate X.json")
        try Data("old".utf8).write(to: orphan)

        let saved = try await FileSink.save(
            Data([1]), record: record(capture(nil)), baseName: "Annotate X", in: folder)

        XCTAssertNil(saved.recordError)
        XCTAssertEqual(saved.url.lastPathComponent, "Annotate X (2).png", "The image moves on so it keeps its record's name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Annotate X (2).json").path))
        XCTAssertEqual(try Data(contentsOf: orphan), Data("old".utf8))
    }

    func testWithoutARecordOnlyTheImageIsWritten() async throws {
        let folder = try temporaryFolder()

        _ = try await FileSink.write(Data([1]), baseName: "Annotate X", in: folder)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Annotate X.png"])
    }

    /// Records under every name from no suffix to ` (last)`.
    private func takeRecordNames(in folder: URL, through last: Int) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for attempt in 1...last {
            let image = folder.appendingPathComponent(FileSink.fileName("Annotate X", attempt: attempt))
            try Data("old".utf8).write(to: FileSink.recordURL(for: image))
        }
    }

    func testNoFreeRecordNameFailsBeforeTheImageIsSaved() async throws {
        let folder = try temporaryFolder()
        try takeRecordNames(in: folder, through: FileSink.maxAttempts)

        do {
            _ = try await FileSink.save(Data([1]), record: record(capture(nil)), baseName: "Annotate X", in: folder)
            XCTFail("Every name's record is taken, so the save fails")
        } catch CocoaError.fileWriteFileExists {
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files.count, FileSink.maxAttempts, "No image and no temporary file")
        XCTAssertTrue(files.allSatisfy { $0.hasSuffix(".json") })
        let last = folder.appendingPathComponent(FileSink.fileName("Annotate X", attempt: FileSink.maxAttempts))
        XCTAssertEqual(try Data(contentsOf: FileSink.recordURL(for: last)), Data("old".utf8), "The last record stays")
    }

    func testTheLastNameIsUsedWhenItsRecordIsFree() async throws {
        let folder = try temporaryFolder()
        try takeRecordNames(in: folder, through: FileSink.maxAttempts - 1)

        let saved = try await FileSink.save(
            Data([1]), record: record(capture(nil)), baseName: "Annotate X", in: folder)

        XCTAssertEqual(saved.url.lastPathComponent, "Annotate X (\(FileSink.maxAttempts)).png")
        XCTAssertNil(saved.recordError)
    }

    func testARecordThatCantBeWrittenLeavesTheImageSaved() async throws {
        let folder = try temporaryFolder()
        struct DiskFull: Error {}

        let saved = try await FileSink.save(
            Data([1]), record: record(capture(nil)), baseName: "Annotate X", in: folder
        ) { data, url in
            if url.lastPathComponent.hasSuffix(".json.tmp") { throw DiskFull() }
            try data.write(to: url, options: .withoutOverwriting)
        }

        XCTAssertTrue(saved.recordError is DiskFull, "The save says why the record is missing")
        XCTAssertEqual(try Data(contentsOf: saved.url), Data([1]))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: folder.path),
            ["Annotate X.png"],
            "No record and no temporary file")
    }

    func testFileSinkWritesTheCapturesRecord() async throws {
        let folder = try temporaryFolder()
        var withRecord = capture(everyKind)
        withRecord.record = record(withRecord)

        let delivery = try await FileSink(folder: folder).deliver(withRecord, png: Data([1]))

        guard case let .file(url, _, annotationDataError) = delivery else {
            return XCTFail("Expected a file, got \(delivery)")
        }
        XCTAssertNil(annotationDataError)
        let saved = try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: FileSink.recordURL(for: url)))
        XCTAssertEqual(saved.annotations.count, 9)
        XCTAssertEqual(saved.image.file, url.lastPathComponent)
    }

    func testFileSinkSaysWhenTheRecordCouldntBeSaved() async throws {
        let folder = try temporaryFolder()
        var withRecord = capture(nil)
        withRecord.record = record(withRecord)
        var sink = FileSink(folder: folder)
        sink.writeBytes = { data, url in
            if url.lastPathComponent.hasSuffix(".json.tmp") { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .withoutOverwriting)
        }

        let delivery = try await sink.deliver(withRecord, png: Data([1]))

        guard case let .file(url, nil, annotationDataError) = delivery else {
            return XCTFail("Expected a file, got \(delivery)")
        }
        XCTAssertEqual(try Data(contentsOf: url), Data([1]), "The image is still delivered")
        XCTAssertEqual(annotationDataError, CocoaError(.fileWriteOutOfSpace).localizedDescription)
    }
}
