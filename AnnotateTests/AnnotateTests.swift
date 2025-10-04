import XCTest

@testable import Annotate

@MainActor
final class AnnotateTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Array Extension Tests

    func testArrayChunking() {
        let array = [1, 2, 3, 4, 5, 6, 7]

        let chunks = array.chunked(into: 3)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1, 2, 3])
        XCTAssertEqual(chunks[1], [4, 5, 6])
        XCTAssertEqual(chunks[2], [7])

        // Test empty array
        let emptyArray: [Int] = []
        XCTAssertTrue(emptyArray.chunked(into: 3).isEmpty)

        // Test chunk size larger than array
        let smallArray = [1, 2]
        XCTAssertEqual(smallArray.chunked(into: 3), [[1, 2]])

        // Test chunk size of 1
        XCTAssertEqual([1, 2, 3].chunked(into: 1), [[1], [2], [3]])

        // Test chunk size of array length
        XCTAssertEqual([1, 2, 3].chunked(into: 3), [[1, 2, 3]])

        // Test invalid chunk sizes (should default to 1)
        XCTAssertEqual([1, 2].chunked(into: 0), [[1], [2]])
        XCTAssertEqual([1, 2].chunked(into: -1), [[1], [2]])
    }

    // MARK: - Model Tests

    func testTimedPoint() {
        let point = NSPoint(x: 10, y: 20)
        let timestamp: CFTimeInterval = 123.456

        let timedPoint = TimedPoint(point: point, timestamp: timestamp)

        XCTAssertEqual(timedPoint.point.x, 10)
        XCTAssertEqual(timedPoint.point.y, 20)
        XCTAssertEqual(timedPoint.timestamp, timestamp)
    }

    func testDrawingPath() {
        let points = [
            TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0.0),
            TimedPoint(point: NSPoint(x: 10, y: 10), timestamp: 1.0),
        ]
        let color = NSColor.systemRed

        let path = DrawingPath(points: points, color: color, lineWidth: 3.0)

        XCTAssertEqual(path.points.count, 2)
        XCTAssertEqual(path.color, color)
        XCTAssertEqual(path.lineWidth, 3.0)
        XCTAssertEqual(path.points[0].timestamp, 0.0)
        XCTAssertEqual(path.points[1].timestamp, 1.0)

        // Test empty path
        let emptyPath = DrawingPath(points: [], color: color, lineWidth: 3.0)
        XCTAssertTrue(emptyPath.points.isEmpty)
    }
}
