import XCTest

@testable import Annotate

@MainActor
final class OverlayWindowTests: XCTestCase, Sendable {
    var window: OverlayWindow!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            window = OverlayWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            window = nil
        }
        super.tearDown()
    }

    func testWindowInitialization() {
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.hasShadow)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.collectionBehavior, [.canJoinAllSpaces, .stationary])

        // Test view hierarchy
        XCTAssertNotNil(window.contentView)
        XCTAssertNotNil(window.overlayView)
    }

    func testFadeLoop() {
        XCTAssertNil(window.fadeTimer)

        window.startFadeLoop()
        XCTAssertNotNil(window.fadeTimer)
        XCTAssertTrue(window.fadeTimer?.isValid ?? false)

        window.stopFadeLoop()
        XCTAssertNil(window.fadeTimer)
    }

    func testMouseEvents() {
        // Test mouse down
        let mouseDownEvent = TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )
        window.mouseDown(with: mouseDownEvent!)
        XCTAssertEqual(window.anchorPoint, NSPoint(x: 100, y: 100))

        // Test mouse dragged
        let mouseDragEvent = TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 150, y: 150)
        )
        window.mouseDragged(with: mouseDragEvent!)

        // Test mouse up
        let mouseUpEvent = TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 150, y: 150)
        )
        window.mouseUp(with: mouseUpEvent!)
    }

    func testKeyEvents() {
        // Test ESC key
        let escEvent = TestEvents.createKeyEvent(type: .keyDown, keyCode: 53)
        window.keyDown(with: escEvent!)

        let shiftEscEvent = TestEvents.createKeyEvent(type: .keyDown, keyCode: 53, modifierFlags: .shift)
        window.keyDown(with: shiftEscEvent!)

        // Test space bar
        let spaceEvent = TestEvents.createKeyEvent(type: .keyDown, keyCode: 49)
        window.keyDown(with: spaceEvent!)

        // Test tool shortcuts
        let penEvent = TestEvents.createKeyEvent(type: .keyDown, keyCode: 35)  // P key
        window.keyDown(with: penEvent!)
        XCTAssertEqual(window.overlayView.currentTool, .pen)
    }
    
    func testLineWidthInitialization() {
        // Test default line width is set correctly
        XCTAssertEqual(window.overlayView.currentLineWidth, 3.0)
    }
    
    func testLineWidthAdjustment() {
        let initialLineWidth = window.overlayView.currentLineWidth
        
        // Set a new line width
        let newLineWidth: CGFloat = 5.5
        window.overlayView.currentLineWidth = newLineWidth
        
        XCTAssertEqual(window.overlayView.currentLineWidth, newLineWidth)
        XCTAssertNotEqual(window.overlayView.currentLineWidth, initialLineWidth)
    }
    
    func testLineWidthBounds() {
        // Test minimum line width
        window.overlayView.currentLineWidth = 0.1
        XCTAssertEqual(window.overlayView.currentLineWidth, 0.1)
        
        // Test maximum line width
        window.overlayView.currentLineWidth = 20.0
        XCTAssertEqual(window.overlayView.currentLineWidth, 20.0)
        
        // Test very large value (should still be set)
        window.overlayView.currentLineWidth = 50.0
        XCTAssertEqual(window.overlayView.currentLineWidth, 50.0)
    }
}
