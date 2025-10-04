import XCTest

@testable import Annotate

// MARK: - Test Constants
enum TestConstants {
    static let defaultTimeout: TimeInterval = 2.0
    static let defaultDelay: TimeInterval = 0.1
    static let defaultFrameSize = NSSize(width: 800, height: 600)
    static let smallFrameSize = NSSize(width: 400, height: 300)
}

// MARK: - Test Factory Methods
enum TestFactory {
    static func createTimedPoint(x: CGFloat = 0, y: CGFloat = 0, timestamp: CFTimeInterval = 0)
        -> TimedPoint
    {
        TimedPoint(point: NSPoint(x: x, y: y), timestamp: timestamp)
    }

    static func createDrawingPath(points: [TimedPoint] = [], color: NSColor = .systemRed, lineWidth: CGFloat = 3.0)
        -> DrawingPath
    {
        DrawingPath(points: points, color: color, lineWidth: lineWidth)
    }

    static func createArrow(
        start: NSPoint = .zero,
        end: NSPoint = NSPoint(x: 100, y: 100),
        color: NSColor = .blue,
        lineWidth: CGFloat = 3.0,
        time: CFTimeInterval? = nil
    ) -> Arrow {
        Arrow(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)
    }

    static func createRectangle(
        start: NSPoint = .zero,
        end: NSPoint = NSPoint(x: 100, y: 100),
        color: NSColor = .green,
        lineWidth: CGFloat = 3.0,
        time: CFTimeInterval? = nil
    ) -> Rectangle {
        Rectangle(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)
    }

    static func createCircle(
        start: NSPoint = .zero,
        end: NSPoint = NSPoint(x: 100, y: 100),
        color: NSColor = .purple,
        lineWidth: CGFloat = 3.0,
        time: CFTimeInterval? = nil
    ) -> Circle {
        Circle(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)
    }

    static func createTextAnnotation(
        text: String = "Test",
        position: NSPoint = .zero,
        color: NSColor = .black,
        fontSize: CGFloat = 18.0
    ) -> TextAnnotation {
        TextAnnotation(text: text, position: position, color: color, fontSize: fontSize)
    }
}

// MARK: - Test Event Helpers
enum TestEvents {
    static func createMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        return NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
    }

    static func createKeyEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        return NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

// MARK: - Mock Classes
class MockOverlayView: OverlayView {
    var drawCalled = false
    var clearAllCalled = false
    var undoCalled = false
    var redoCalled = false

    override func draw(_ dirtyRect: NSRect) {
        drawCalled = true
        super.draw(dirtyRect)
    }

    override func clearAll() {
        clearAllCalled = true
        super.clearAll()
    }

    override func undo() {
        undoCalled = true
        super.undo()
    }

    override func redo() {
        redoCalled = true
        super.redo()
    }
}

// MARK: - XCTestCase Extensions
extension XCTestCase {
    func wait(for duration: TimeInterval) {
        let expectation = expectation(description: "Wait for \(duration) seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: duration + 1)
    }

    func assertEventually(
        timeout: TimeInterval = TestConstants.defaultTimeout,
        interval: TimeInterval = TestConstants.defaultDelay,
        description: String? = nil,
        condition: @escaping () -> Bool
    ) {
        let expectation = self.expectation(description: description ?? "Async condition")

        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if condition() {
                timer.invalidate()
                if !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            timer.invalidate()
            if !fulfilled {
                fulfilled = true
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: timeout + 1)
        XCTAssertTrue(condition(), description ?? "Condition not met within timeout")
    }

    func assertColor(_ color1: NSColor, isCloseTo color2: NSColor, tolerance: CGFloat = 0.01) {
        guard let rgb1 = color1.usingColorSpace(.genericRGB),
            let rgb2 = color2.usingColorSpace(.genericRGB)
        else {
            XCTFail("Colors could not be converted to RGB space")
            return
        }

        XCTAssertEqual(rgb1.redComponent, rgb2.redComponent, accuracy: tolerance)
        XCTAssertEqual(rgb1.greenComponent, rgb2.greenComponent, accuracy: tolerance)
        XCTAssertEqual(rgb1.blueComponent, rgb2.blueComponent, accuracy: tolerance)
        XCTAssertEqual(rgb1.alphaComponent, rgb2.alphaComponent, accuracy: tolerance)
    }

    func assertPoint(_ point1: NSPoint, isCloseTo point2: NSPoint, tolerance: CGFloat = 0.01) {
        XCTAssertEqual(point1.x, point2.x, accuracy: tolerance)
        XCTAssertEqual(point1.y, point2.y, accuracy: tolerance)
    }
}
