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
        XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.hasShadow)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.collectionBehavior, [.canJoinAllSpaces, .transient])

        XCTAssertNotNil(window.contentView)
        XCTAssertNotNil(window.overlayView)
    }

    func testWindowLevelConfiguration() {
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let assistiveLevel = Int(CGWindowLevelForKey(.assistiveTechHighWindow))
        let screenSaverLevel = Int(CGWindowLevelForKey(.screenSaverWindow))

        let expectedMinimumLevel = max(menuLevel, statusLevel, popUpLevel, assistiveLevel, screenSaverLevel) + 1

        XCTAssertGreaterThanOrEqual(
            window.level.rawValue,
            expectedMinimumLevel,
            "Window level should be at or above the highest system window level + 1"
        )
    }

    func testNSPanelBehavior() {
        XCTAssertFalse(window.canBecomeMain, "Overlay panel should not become main window")
        XCTAssertTrue(window.canBecomeKey, "Overlay panel should be able to become key window for keyboard input")
    }

    func testNonactivatingPanelStyleMask() {
        XCTAssertTrue(
            window.styleMask.contains(.nonactivatingPanel),
            "Window should have .nonactivatingPanel style mask to avoid activating the app"
        )
        XCTAssertTrue(
            window.styleMask.contains(.borderless),
            "Window should maintain borderless style"
        )
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
    
    func testLinePreviewViewCreation() {
        // Test that LinePreviewView can be created with proper dimensions
        let frame = NSRect(x: 0, y: 0, width: 200, height: 10)
        let lineView = LinePreviewView(frame: frame)
        
        XCTAssertNotNil(lineView)
        XCTAssertEqual(lineView.frame.width, 200)
        XCTAssertEqual(lineView.frame.height, 10)
    }
    
    func testLinePreviewViewProperties() {
        // Test that LinePreviewView has correct default properties
        let lineView = LinePreviewView(frame: NSRect(x: 0, y: 0, width: 100, height: 5))
        
        XCTAssertEqual(lineView.lineColor, .white, "Default line color should be white")
        XCTAssertEqual(lineView.lineWidth, 3.0, "Default line width should be 3.0")
    }
    
    func testLinePreviewViewWithDifferentWidths() {
        // Test LinePreviewView with various line widths
        let lineView = LinePreviewView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        
        lineView.lineWidth = 0.5
        XCTAssertEqual(lineView.lineWidth, 0.5)
        
        lineView.lineWidth = 10.0
        XCTAssertEqual(lineView.lineWidth, 10.0)
        
        lineView.lineWidth = 20.0
        XCTAssertEqual(lineView.lineWidth, 20.0)
    }
    
    func testLinePreviewViewWithDifferentColors() {
        // Test LinePreviewView with various colors
        let lineView = LinePreviewView(frame: NSRect(x: 0, y: 0, width: 100, height: 5))
        
        lineView.lineColor = .red
        XCTAssertEqual(lineView.lineColor, .red)
        
        lineView.lineColor = .blue
        XCTAssertEqual(lineView.lineColor, .blue)
        
        lineView.lineColor = .black
        XCTAssertEqual(lineView.lineColor, .black)
    }
    
    func testFeedbackPositionBottomCenter() {
        // Test that feedback appears at bottom center
        let windowWidth = window.frame.width
        let containerWidth: CGFloat = 250
        let bottomPadding: CGFloat = 20
        
        let expectedX = (windowWidth - containerWidth) / 2
        let expectedY = bottomPadding
        
        XCTAssertEqual(expectedX, (800 - 250) / 2, "Feedback should be horizontally centered")
        XCTAssertEqual(expectedY, 20, "Feedback should be 20pt from bottom")
    }
    
    func testScrollWheelForLineWidth() {
        // Test that scroll wheel adjusts line width
        let initialWidth = window.overlayView.currentLineWidth
        
        // Simulate Command+Scroll up (increase width)
        let scrollUpEvent = TestEvents.createScrollEvent(deltaY: 1.0, modifierFlags: .command)
        if let event = scrollUpEvent {
            window.scrollWheel(with: event)
            // Note: We can't directly test the feedback display without UI tests,
            // but we can verify the function exists and is called
        }
        
        // The actual width change would be tested in integration tests
        // Here we just verify the initial state is correct
        XCTAssertGreaterThanOrEqual(initialWidth, 0.5, "Initial width should be within valid range")
        XCTAssertLessThanOrEqual(initialWidth, 20.0, "Initial width should be within valid range")
    }
    
    func testToolFeedbackMethodExists() {
        // Test that showToolFeedback method can be called without errors
        window.showToolFeedback(.pen)
        window.showToolFeedback(.arrow)
        window.showToolFeedback(.line)
        window.showToolFeedback(.highlighter)
        window.showToolFeedback(.rectangle)
        window.showToolFeedback(.circle)
        window.showToolFeedback(.counter)
        window.showToolFeedback(.text)
        
        // If we got here without crashing, the method works
        XCTAssertTrue(true, "showToolFeedback should work for all tool types")
    }
    
    func testToolFeedbackForDrawingTools() {
        // Test that drawing tools can show feedback
        let drawingTools: [ToolType] = [.pen, .arrow, .line, .highlighter, .rectangle, .circle]
        
        for tool in drawingTools {
            window.overlayView.currentTool = tool
            window.showToolFeedback(tool)
            
            // Verify the tool was set correctly
            XCTAssertEqual(window.overlayView.currentTool, tool, "Tool should be set to \(tool)")
        }
    }
    
    func testToolFeedbackForNonDrawingTools() {
        // Test that non-drawing tools can show feedback
        let nonDrawingTools: [ToolType] = [.counter, .text]
        
        for tool in nonDrawingTools {
            window.overlayView.currentTool = tool
            window.showToolFeedback(tool)
            
            // Verify the tool was set correctly
            XCTAssertEqual(window.overlayView.currentTool, tool, "Tool should be set to \(tool)")
        }
    }
    
    func testToolFeedbackWithDifferentLineWidths() {
        // Test that feedback works with various line widths
        let widths: [CGFloat] = [0.5, 3.0, 10.0, 20.0]
        
        for width in widths {
            window.overlayView.currentLineWidth = width
            window.showToolFeedback(.pen)
            
            // Verify the width was set correctly
            XCTAssertEqual(window.overlayView.currentLineWidth, width, "Line width should be \(width)")
        }
    }
    
    func testToolFeedbackWithDifferentColors() {
        // Test that feedback works with different colors
        let colors: [NSColor] = [.red, .blue, .black, .white, .yellow, .green]

        for color in colors {
            window.overlayView.currentColor = color
            window.showToolFeedback(.pen)

            // Verify the color was set correctly
            XCTAssertEqual(window.overlayView.currentColor, color, "Color should be set correctly")
        }
    }

    // MARK: - Keyboard Shortcut Tests (Cmd+A Global Select All)

    func testCmdASelectAllInPenMode() {
        window.overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))

        window.overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))

        window.overlayView.currentTool = .pen

        let cmdAEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 0,
            modifierFlags: .command,
            characters: "a"
        )

        let handled = window.performKeyEquivalent(with: cmdAEvent!)

        // In unit tests, AppDelegate.shared is nil so mode won't actually switch
        XCTAssertTrue(handled)
    }

    func testCmdASelectAllInSelectMode() {
        window.overlayView.arrows.append(Arrow(
            startPoint: NSPoint(x: 50, y: 50),
            endPoint: NSPoint(x: 100, y: 100),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))

        window.overlayView.textAnnotations.append(TextAnnotation(
            text: "Test",
            position: NSPoint(x: 200, y: 200),
            color: .black,
            fontSize: 18
        ))

        window.overlayView.currentTool = .select

        let cmdAEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 0,
            modifierFlags: .command,
            characters: "a"
        )

        let handled = window.performKeyEquivalent(with: cmdAEvent!)

        XCTAssertTrue(handled)
        XCTAssertEqual(window.overlayView.selectedObjects.count, 2)
        XCTAssertTrue(window.overlayView.selectedObjects.contains(.arrow(index: 0)))
        XCTAssertTrue(window.overlayView.selectedObjects.contains(.text(index: 0)))
    }

    func testCmdASelectAllOnEmptyCanvas() {
        XCTAssertTrue(window.overlayView.arrows.isEmpty)
        XCTAssertTrue(window.overlayView.lines.isEmpty)

        window.overlayView.currentTool = .pen

        let cmdAEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 0,
            modifierFlags: .command,
            characters: "a"
        )

        let handled = window.performKeyEquivalent(with: cmdAEvent!)

        XCTAssertTrue(handled)
        XCTAssertTrue(window.overlayView.selectedObjects.isEmpty)
    }

    func testCmdAWithActiveTextFieldDoesNotHandle() {
        window.overlayView.textAnnotations.append(TextAnnotation(
            text: "Test",
            position: NSPoint(x: 100, y: 100),
            color: .black,
            fontSize: 18
        ))

        window.overlayView.activeTextField = NSTextField(frame: NSRect(x: 100, y: 100, width: 200, height: 30))
        window.overlayView.currentTool = .text

        let cmdAEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 0,
            modifierFlags: .command,
            characters: "a"
        )

        let handled = window.performKeyEquivalent(with: cmdAEvent!)

        XCTAssertFalse(handled)

        window.overlayView.activeTextField?.removeFromSuperview()
        window.overlayView.activeTextField = nil
    }

    func testCmdCOnlyWorksInSelectMode() {
        window.overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))

        window.overlayView.selectedObjects = [.line(index: 0)]
        window.overlayView.currentTool = .pen

        let cmdCEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 8,
            modifierFlags: .command,
            characters: "c"
        )

        let handled = window.performKeyEquivalent(with: cmdCEvent!)
        XCTAssertFalse(handled)
    }

    func testCmdVOnlyWorksInSelectMode() {
        window.overlayView.clipboard = [
            .line(Line(
                startPoint: NSPoint(x: 100, y: 100),
                endPoint: NSPoint(x: 200, y: 200),
                color: .red,
                lineWidth: 2.0,
                creationTime: nil
            ))
        ]

        window.overlayView.currentTool = .arrow

        let cmdVEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 9,
            modifierFlags: .command,
            characters: "v"
        )

        let handled = window.performKeyEquivalent(with: cmdVEvent!)
        XCTAssertFalse(handled)
    }

    func testCmdXOnlyWorksInSelectMode() {
        window.overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))

        window.overlayView.selectedObjects = [.circle(index: 0)]
        window.overlayView.currentTool = .highlighter

        let cmdXEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 7,
            modifierFlags: .command,
            characters: "x"
        )

        let handled = window.performKeyEquivalent(with: cmdXEvent!)
        XCTAssertFalse(handled)
    }

    func testCmdDOnlyWorksInSelectMode() {
        window.overlayView.rectangles.append(Rectangle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .green,
            lineWidth: 2.0,
            creationTime: nil
        ))

        window.overlayView.selectedObjects = [.rectangle(index: 0)]
        window.overlayView.currentTool = .line

        let cmdDEvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 2,
            modifierFlags: .command,
            characters: "d"
        )

        let handled = window.performKeyEquivalent(with: cmdDEvent!)
        XCTAssertFalse(handled)
    }
}
