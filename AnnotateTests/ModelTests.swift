import XCTest

@testable import Annotate

final class ModelTests: XCTestCase {

    func testArrow() {
        let start = NSPoint(x: 0, y: 0)
        let end = NSPoint(x: 100, y: 100)
        let color = NSColor.blue
        let time: CFTimeInterval = 1.0

        let arrow = Arrow(startPoint: start, endPoint: end, color: color, creationTime: time)

        XCTAssertEqual(arrow.startPoint, start)
        XCTAssertEqual(arrow.endPoint, end)
        XCTAssertEqual(arrow.color, color)
        XCTAssertEqual(arrow.creationTime, time)

        // Test nil creation time
        let arrowNoTime = Arrow(startPoint: start, endPoint: end, color: color)
        XCTAssertNil(arrowNoTime.creationTime)
    }

    func testRectangle() {
        let start = NSPoint(x: 10, y: 10)
        let end = NSPoint(x: 50, y: 50)
        let color = NSColor.green
        let time: CFTimeInterval = 2.0

        let rectangle = Rectangle(
            startPoint: start, endPoint: end, color: color, creationTime: time)

        XCTAssertEqual(rectangle.startPoint, start)
        XCTAssertEqual(rectangle.endPoint, end)
        XCTAssertEqual(rectangle.color, color)
        XCTAssertEqual(rectangle.creationTime, time)
    }

    func testCircle() {
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 200)
        let color = NSColor.yellow
        let time: CFTimeInterval = 3.0

        let circle = Circle(startPoint: start, endPoint: end, color: color, creationTime: time)

        XCTAssertEqual(circle.startPoint, start)
        XCTAssertEqual(circle.endPoint, end)
        XCTAssertEqual(circle.color, color)
        XCTAssertEqual(circle.creationTime, time)
    }

    func testTextAnnotation() {
        let text = "Test Text"
        let position = NSPoint(x: 50, y: 50)
        let color = NSColor.green
        let fontSize: CGFloat = 18.0

        let annotation = TextAnnotation(
            text: text, position: position, color: color, fontSize: fontSize)

        XCTAssertEqual(annotation.text, text)
        XCTAssertEqual(annotation.position, position)
        XCTAssertEqual(annotation.color, color)
        XCTAssertEqual(annotation.fontSize, fontSize)

        // Test empty text
        let emptyAnnotation = TextAnnotation(
            text: "", position: .zero, color: .black, fontSize: 12.0)
        XCTAssertTrue(emptyAnnotation.text.isEmpty)
    }

    func testCounterAnnotation() {
        let position = NSPoint(x: 50, y: 50)
        let color = NSColor.blue
        let number = 3
        let time: CFTimeInterval = 1.5

        let counter = CounterAnnotation(
            number: number,
            position: position,
            color: color,
            creationTime: time
        )

        XCTAssertEqual(counter.number, number)
        XCTAssertEqual(counter.position, position)
        XCTAssertEqual(counter.color, color)
        XCTAssertEqual(counter.creationTime, time)

        let counterNoTime = CounterAnnotation(
            number: number,
            position: position,
            color: color
        )
        XCTAssertNil(counterNoTime.creationTime)

        let counterCopy = CounterAnnotation(
            number: number,
            position: position,
            color: color,
            creationTime: time
        )
        XCTAssertEqual(counter, counterCopy)

        let differentCounter = CounterAnnotation(
            number: number + 1,
            position: position,
            color: color,
            creationTime: time
        )
        XCTAssertNotEqual(counter, differentCounter)
    }

    func testToolType() {
        let tools: [ToolType] = [.pen, .arrow, .highlighter, .rectangle, .circle, .text]
        XCTAssertEqual(tools.count, 6)  // Ensure we have all tool types

        // Test each tool type is unique
        var uniqueTools = Set<String>()
        for tool in tools {
            let toolString = String(describing: tool)
            XCTAssertFalse(uniqueTools.contains(toolString))
            uniqueTools.insert(toolString)
        }
    }
}
