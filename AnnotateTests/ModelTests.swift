import XCTest

@testable import Annotate

@MainActor
final class ModelTests: XCTestCase {

    func testArrow() {
        let start = NSPoint(x: 0, y: 0)
        let end = NSPoint(x: 100, y: 100)
        let color = NSColor.blue
        let lineWidth: CGFloat = 3.0
        let time: CFTimeInterval = 1.0

        let arrow = Arrow(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)

        XCTAssertEqual(arrow.startPoint, start)
        XCTAssertEqual(arrow.endPoint, end)
        XCTAssertEqual(arrow.color, color)
        XCTAssertEqual(arrow.lineWidth, lineWidth)
        XCTAssertEqual(arrow.creationTime, time)

        // Test nil creation time
        let arrowNoTime = Arrow(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth)
        XCTAssertNil(arrowNoTime.creationTime)
    }
    
    func testArrowWithLineWidth() {
        let start = NSPoint(x: 0, y: 0)
        let end = NSPoint(x: 50, y: 50)
        let color = NSColor.red
        let lineWidth1: CGFloat = 1.5
        let lineWidth2: CGFloat = 5.0
        
        let arrow1 = Arrow(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth1)
        let arrow2 = Arrow(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth2)
        
        XCTAssertEqual(arrow1.lineWidth, lineWidth1)
        XCTAssertEqual(arrow2.lineWidth, lineWidth2)
        XCTAssertNotEqual(arrow1, arrow2) // Different line widths should make them unequal
    }

    func testRectangle() {
        let start = NSPoint(x: 10, y: 10)
        let end = NSPoint(x: 50, y: 50)
        let color = NSColor.green
        let lineWidth: CGFloat = 2.5
        let time: CFTimeInterval = 2.0

        let rectangle = Rectangle(
            startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)

        XCTAssertEqual(rectangle.startPoint, start)
        XCTAssertEqual(rectangle.endPoint, end)
        XCTAssertEqual(rectangle.color, color)
        XCTAssertEqual(rectangle.lineWidth, lineWidth)
        XCTAssertEqual(rectangle.creationTime, time)
    }

    func testCircle() {
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 200, y: 200)
        let color = NSColor.yellow
        let lineWidth: CGFloat = 4.0
        let time: CFTimeInterval = 3.0

        let circle = Circle(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)

        XCTAssertEqual(circle.startPoint, start)
        XCTAssertEqual(circle.endPoint, end)
        XCTAssertEqual(circle.color, color)
        XCTAssertEqual(circle.lineWidth, lineWidth)
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
    
    func testLineWithLineWidth() {
        let start = NSPoint(x: 10, y: 20)
        let end = NSPoint(x: 50, y: 60)
        let color = NSColor.green
        let lineWidth: CGFloat = 2.0
        let time: CFTimeInterval = 1.5
        
        let line = Line(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)
        
        XCTAssertEqual(line.startPoint, start)
        XCTAssertEqual(line.endPoint, end)
        XCTAssertEqual(line.color, color)
        XCTAssertEqual(line.lineWidth, lineWidth)
        XCTAssertEqual(line.creationTime, time)
    }
    
    func testDrawingPathWithLineWidth() {
        let points = [
            TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0.0),
            TimedPoint(point: NSPoint(x: 10, y: 10), timestamp: 0.1),
            TimedPoint(point: NSPoint(x: 20, y: 20), timestamp: 0.2)
        ]
        let color = NSColor.blue
        let lineWidth: CGFloat = 3.5
        
        let path = DrawingPath(points: points, color: color, lineWidth: lineWidth)
        
        XCTAssertEqual(path.points.count, 3)
        XCTAssertEqual(path.color, color)
        XCTAssertEqual(path.lineWidth, lineWidth)
    }
    
    func testShapeEqualityWithLineWidth() {
        let start = NSPoint(x: 0, y: 0)
        let end = NSPoint(x: 100, y: 100)
        let color = NSColor.red
        
        // Test that shapes with different line widths are not equal
        let rect1 = Rectangle(startPoint: start, endPoint: end, color: color, lineWidth: 2.0)
        let rect2 = Rectangle(startPoint: start, endPoint: end, color: color, lineWidth: 5.0)
        XCTAssertNotEqual(rect1, rect2)
        
        let circle1 = Circle(startPoint: start, endPoint: end, color: color, lineWidth: 2.0)
        let circle2 = Circle(startPoint: start, endPoint: end, color: color, lineWidth: 5.0)
        XCTAssertNotEqual(circle1, circle2)
        
        let line1 = Line(startPoint: start, endPoint: end, color: color, lineWidth: 2.0)
        let line2 = Line(startPoint: start, endPoint: end, color: color, lineWidth: 5.0)
        XCTAssertNotEqual(line1, line2)
        
        // Test that shapes with same line widths are equal (all other properties equal)
        let rect3 = Rectangle(startPoint: start, endPoint: end, color: color, lineWidth: 3.0)
        let rect4 = Rectangle(startPoint: start, endPoint: end, color: color, lineWidth: 3.0)
        XCTAssertEqual(rect3, rect4)
    }
}
