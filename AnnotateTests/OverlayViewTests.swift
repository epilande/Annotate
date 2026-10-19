import XCTest

@testable import Annotate

@MainActor
final class OverlayViewTests: XCTestCase, Sendable {
    var overlayView: OverlayView!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            // A leaked AppDelegate.shared would redirect pickerUserDefaults into
            // another suite's store and let commitTextField rewrite its windows.
            AppDelegate.shared = nil
            overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            overlayView.pickerUserDefaultsOverride = TestUserDefaults.create()
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            overlayView?.pickerUserDefaultsOverride = nil
            overlayView = nil
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testOverlayViewInitialization() {
        XCTAssertEqual(overlayView.currentColor, .systemRed)
        XCTAssertEqual(overlayView.currentTool, .pen)
        XCTAssertTrue(overlayView.fadeMode)
        XCTAssertEqual(overlayView.fadeDuration, 1.25)

        // Test empty collections
        XCTAssertTrue(overlayView.paths.isEmpty)
        XCTAssertTrue(overlayView.arrows.isEmpty)
        XCTAssertTrue(overlayView.lines.isEmpty)
        XCTAssertTrue(overlayView.highlightPaths.isEmpty)
        XCTAssertTrue(overlayView.rectangles.isEmpty)
        XCTAssertTrue(overlayView.circles.isEmpty)
        XCTAssertTrue(overlayView.textAnnotations.isEmpty)

        // Test nil values
        XCTAssertNil(overlayView.currentPath)
        XCTAssertNil(overlayView.currentArrow)
        XCTAssertNil(overlayView.currentLine)
        XCTAssertNil(overlayView.currentHighlight)
        XCTAssertNil(overlayView.currentRectangle)
        XCTAssertNil(overlayView.currentCircle)
        XCTAssertNil(overlayView.currentTextAnnotation)
    }

    func testFreehandStrokeLifecyclePreservesEveryPoint() {
        let points = (0...256).map { index in
            TimedPoint(
                point: NSPoint(x: CGFloat(index), y: CGFloat(index % 17)),
                timestamp: CFTimeInterval(index)
            )
        }

        for tool in [ToolType.pen, .highlighter] {
            overlayView.beginFreehandStroke(
                DrawingPath(points: [points[0]], color: .systemRed, lineWidth: 3),
                tool: tool
            )
            for point in points.dropFirst() {
                overlayView.appendFreehandPoint(point, tool: tool)
            }

            let completedStroke = overlayView.endFreehandStroke(tool: tool)

            XCTAssertEqual(completedStroke?.points, points)
            XCTAssertEqual(completedStroke?.bezierPath?.elementCount, points.count)
            XCTAssertFalse(completedStroke?.cachedBounds.isNull ?? true)
            XCTAssertNil(overlayView.currentPath)
            XCTAssertNil(overlayView.currentHighlight)
        }
    }

    func testHighlighterSelectionUsesRenderedStrokeWidth() {
        let now = CACurrentMediaTime()
        overlayView.highlightPaths = [
            DrawingPath(
                points: [
                    TimedPoint(point: NSPoint(x: 100, y: 100), timestamp: now),
                    TimedPoint(point: NSPoint(x: 200, y: 100), timestamp: now),
                ],
                color: .systemYellow,
                lineWidth: 10
            )
        ]

        XCTAssertEqual(
            overlayView.findObjectAt(point: NSPoint(x: 150, y: 120)),
            .highlight(index: 0)
        )
    }

    func testHighlighterEraserHitTestUsesRenderedStrokeWidth() {
        overlayView.highlightPaths = [
            DrawingPath(
                points: [TimedPoint(point: NSPoint(x: 100, y: 100), timestamp: 0)],
                color: .systemYellow,
                lineWidth: 10
            )
        ]

        overlayView.eraseAtPoint(NSPoint(x: 130, y: 100))

        XCTAssertTrue(overlayView.highlightPaths.isEmpty)
    }

    func testToolSwitching() {
        // Test all tool types
        overlayView.currentTool = .pen
        XCTAssertEqual(overlayView.currentTool, .pen)

        overlayView.currentTool = .arrow
        XCTAssertEqual(overlayView.currentTool, .arrow)
        
        overlayView.currentTool = .line
        XCTAssertEqual(overlayView.currentTool, .line)

        overlayView.currentTool = .highlighter
        XCTAssertEqual(overlayView.currentTool, .highlighter)

        overlayView.currentTool = .rectangle
        XCTAssertEqual(overlayView.currentTool, .rectangle)

        overlayView.currentTool = .circle
        XCTAssertEqual(overlayView.currentTool, .circle)

        overlayView.currentTool = .text
        XCTAssertEqual(overlayView.currentTool, .text)
    }

    func testClearAll() {
        // Add some test data
        overlayView.paths = [DrawingPath(points: [], color: .red, lineWidth: 3.0)]
        overlayView.arrows = [Arrow(startPoint: .zero, endPoint: .zero, color: .blue, lineWidth: 3.0)]
        overlayView.lines = [Line(startPoint: .zero, endPoint: .zero, color: .red, lineWidth: 3.0)]
        overlayView.highlightPaths = [DrawingPath(points: [], color: .yellow, lineWidth: 3.0)]
        overlayView.rectangles = [Rectangle(startPoint: .zero, endPoint: .zero, color: .green, lineWidth: 3.0)]
        overlayView.circles = [Circle(startPoint: .zero, endPoint: .zero, color: .purple, lineWidth: 3.0)]
        overlayView.textAnnotations = [
            TextAnnotation(text: "Test", position: .zero, color: .black, fontSize: 12)
        ]

        // Clear all
        overlayView.clearAll()

        // Verify everything is cleared
        XCTAssertTrue(overlayView.paths.isEmpty)
        XCTAssertTrue(overlayView.arrows.isEmpty)
        XCTAssertTrue(overlayView.lines.isEmpty)
        XCTAssertTrue(overlayView.highlightPaths.isEmpty)
        XCTAssertTrue(overlayView.rectangles.isEmpty)
        XCTAssertTrue(overlayView.circles.isEmpty)
        XCTAssertTrue(overlayView.textAnnotations.isEmpty)
    }

    func testClearAllEndsInFlightStrokeWhenCollectionsAreEmpty() {
        overlayView.beginFreehandStroke(
            DrawingPath(
                points: [TimedPoint(point: NSPoint(x: 10, y: 10), timestamp: 0)],
                color: .systemRed,
                lineWidth: 3
            ),
            tool: .pen
        )
        XCTAssertNotNil(overlayView.currentPath)

        overlayView.clearAll()

        XCTAssertNil(overlayView.currentPath)
    }
    
    func testDrawLine() {
        // Create a new line
        let startPoint = NSPoint(x: 100, y: 100)
        let endPoint = NSPoint(x: 200, y: 200)
        let line = Line(startPoint: startPoint, endPoint: endPoint, color: .systemBlue, lineWidth: 3.0)
        
        // Add it to the view
        overlayView.lines.append(line)
        
        // Verify line was added
        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.lines[0].startPoint, startPoint)
        XCTAssertEqual(overlayView.lines[0].endPoint, endPoint)
        XCTAssertEqual(overlayView.lines[0].color, .systemBlue)
        XCTAssertEqual(overlayView.lines[0].lineWidth, 3.0)
        
        // Test delete last item when tool is line
        overlayView.currentTool = .line
        overlayView.deleteLastItem()
        XCTAssertTrue(overlayView.lines.isEmpty)
    }
    
    func testLineFade() {
        // Create a line with a creation time
        let now = CACurrentMediaTime()
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .systemBlue,
            lineWidth: 3.0,
            creationTime: now
        )
        
        overlayView.lines.append(line)
        
        // Test line with recent creation time should be visible
        overlayView.fadeMode = true
        XCTAssertEqual(overlayView.lines.count, 1)
        
        // Add a line with an old creation time
        let oldLine = Line(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .systemRed,
            lineWidth: 3.0,
            creationTime: now - 10.0 // Way beyond fade duration
        )
        
        overlayView.lines.append(oldLine)
        XCTAssertEqual(overlayView.lines.count, 2)

        overlayView.compactExpiredAnnotations()
        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.lines.first?.startPoint, NSPoint(x: 100, y: 100))
    }

    func testDrawDoesNotCompactExpiredAnnotations() {
        overlayView.fadeMode = true
        overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 0, y: 0),
                endPoint: NSPoint(x: 10, y: 10),
                color: .systemRed,
                lineWidth: 3,
                creationTime: CACurrentMediaTime() - 10
            )
        ]

        let image = NSImage(size: overlayView.bounds.size)
        image.lockFocus()
        overlayView.draw(overlayView.bounds)
        image.unlockFocus()

        XCTAssertEqual(overlayView.arrows.count, 1)
    }

    func testFadeCompactionRemapsIndexBasedSelection() {
        let now = CACurrentMediaTime()
        overlayView.fadeMode = true
        overlayView.arrows = [
            Arrow(
                startPoint: .zero,
                endPoint: NSPoint(x: 10, y: 10),
                color: .systemRed,
                lineWidth: 3,
                creationTime: now - 10
            ),
            Arrow(
                startPoint: NSPoint(x: 20, y: 20),
                endPoint: NSPoint(x: 30, y: 30),
                color: .systemBlue,
                lineWidth: 3,
                creationTime: now
            )
        ]
        overlayView.selectedObjects = [.arrow(index: 1)]

        overlayView.compactExpiredAnnotations()

        XCTAssertEqual(overlayView.arrows.count, 1)
        XCTAssertEqual(overlayView.selectedObjects, [.arrow(index: 0)])
    }

    func testFadeCompactionTrimsExpiredPathPointsAndRebuildsBezier() {
        overlayView.fadeMode = true
        let now = CACurrentMediaTime()
        var path = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: now - 10),
                TimedPoint(point: NSPoint(x: 10, y: 0), timestamp: now - 10),
                TimedPoint(point: NSPoint(x: 20, y: 0), timestamp: now)
            ],
            color: .systemRed,
            lineWidth: 3
        )
        path.bezierPath = NSBezierPath()
        path.bezierPath?.move(to: NSPoint(x: 0, y: 0))
        path.bezierPath?.line(to: NSPoint(x: 10, y: 0))
        path.bezierPath?.line(to: NSPoint(x: 20, y: 0))
        overlayView.paths = [path]
        overlayView.selectedObjects = [.path(index: 0)]

        overlayView.compactExpiredAnnotations()

        XCTAssertEqual(overlayView.paths.count, 1)
        XCTAssertEqual(overlayView.paths.first?.points.count, 1)
        XCTAssertEqual(overlayView.paths.first?.bezierPath?.elementCount, 1)
        XCTAssertEqual(overlayView.selectedObjects, [.path(index: 0)])
    }

    func testFindObjectAtSkipsExpiredAnnotations() {
        overlayView.fadeMode = true
        overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 0, y: 0),
                endPoint: NSPoint(x: 10, y: 10),
                color: .systemRed,
                lineWidth: 3,
                creationTime: CACurrentMediaTime() - 10
            )
        ]

        XCTAssertEqual(overlayView.findObjectAt(point: NSPoint(x: 5, y: 5)), .none)
        XCTAssertTrue(
            overlayView.findObjectsInRect(NSRect(x: 0, y: 0, width: 20, height: 20)).isEmpty
        )
    }

    func testCounterAnnotations() {
        XCTAssertTrue(overlayView.counterAnnotations.isEmpty)
        XCTAssertEqual(overlayView.nextCounterNumber, 1)

        let counter = CounterAnnotation(
            number: 1,
            position: NSPoint(x: 100, y: 100),
            color: .systemBlue
        )
        overlayView.counterAnnotations.append(counter)
        overlayView.nextCounterNumber = 2

        // Verify counter was added
        XCTAssertEqual(overlayView.counterAnnotations.count, 1)
        XCTAssertEqual(overlayView.counterAnnotations[0].number, 1)
        XCTAssertEqual(overlayView.nextCounterNumber, 2)

        // Test clearing counters
        overlayView.clearAll()
        XCTAssertTrue(overlayView.counterAnnotations.isEmpty)
        XCTAssertEqual(overlayView.nextCounterNumber, 1)
    }

    func testCounterToolSelection() {
        overlayView.currentTool = .counter
        XCTAssertEqual(overlayView.currentTool, .counter)
    }

    func testResetCounter() {
        overlayView.nextCounterNumber = 5
        overlayView.counterAnnotations = [
            CounterAnnotation(number: 1, position: .zero, color: .blue)
        ]

        overlayView.resetCounter()

        XCTAssertEqual(overlayView.nextCounterNumber, 1)
        XCTAssertEqual(overlayView.counterAnnotations.count, 1, "Existing counters should remain")
    }

    func testDeleteLastCounter() {
        // Add two counters
        let counter1 = CounterAnnotation(
            number: 1,
            position: NSPoint(x: 100, y: 100),
            color: .systemBlue
        )
        let counter2 = CounterAnnotation(
            number: 2,
            position: NSPoint(x: 200, y: 200),
            color: .systemRed
        )

        overlayView.counterAnnotations = [counter1, counter2]
        overlayView.nextCounterNumber = 3
        overlayView.currentTool = .counter

        // Delete last counter
        overlayView.deleteLastItem()

        // Verify only counter1 remains
        XCTAssertEqual(overlayView.counterAnnotations.count, 1)
        XCTAssertEqual(overlayView.counterAnnotations[0].number, 1)
        XCTAssertEqual(overlayView.nextCounterNumber, 2)
    }

    func testUpdateAdaptColors() {
        overlayView.updateAdaptColors(boardEnabled: true)
        XCTAssertTrue(
            overlayView.adaptColorsToBoardType, "adaptColorsToBoardType should be true when enabled"
        )

        overlayView.updateAdaptColors(boardEnabled: false)
        XCTAssertFalse(
            overlayView.adaptColorsToBoardType,
            "adaptColorsToBoardType should be false when disabled")
    }

    // MARK: - Cursor Tests

    func testCursorIsIBeamInTextModeWithoutActiveTextField() {
        overlayView.currentTool = .text
        overlayView.activeTextField = nil

        XCTAssertEqual(overlayView.currentTool, .text)
        XCTAssertNil(overlayView.activeTextField)

        let shouldShowIBeam = overlayView.currentTool == .text && overlayView.activeTextField == nil
        XCTAssertTrue(shouldShowIBeam, "Should show I-beam cursor in text mode without active text field")
    }

    func testCursorIsNotIBeamWhenTextFieldIsActive() {
        overlayView.currentTool = .text
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "")

        XCTAssertEqual(overlayView.currentTool, .text)
        XCTAssertNotNil(overlayView.activeTextField)

        let shouldShowIBeam = overlayView.currentTool == .text && overlayView.activeTextField == nil
        XCTAssertFalse(shouldShowIBeam, "Should not show I-beam cursor when text field is active")

        overlayView.activeTextField?.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    // MARK: - Text Field Positioning Tests

    func testCreateTextFieldForNewTextCentersVertically() {
        let clickPoint = NSPoint(x: 200, y: 300)
        // Pin the font so the box height (and the centering offset derived from it) is
        // deterministic regardless of any persisted textToolFontSize.
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .black, fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: clickPoint, withText: "")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        // At the default font the box is at its 32px floor, so Y offset is -16 (half the
        // height) to center at the click. X offset is -8 for left padding.
        XCTAssertEqual(textField.frame.origin.x, clickPoint.x - 8, "X should offset by left padding")
        XCTAssertEqual(textField.frame.origin.y, clickPoint.y - 16, "Y should center text field at click point")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testCreateTextFieldForNewTextHeightGrowsWithFontSize() {
        let clickPoint = NSPoint(x: 200, y: 300)
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .black, fontSize: textAnnotationFontSizeRange.upperBound
        )
        overlayView.createTextField(at: clickPoint, withText: "")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        XCTAssertGreaterThan(
            textField.frame.height, 32,
            "A new field created with a large font should be taller than the 32px floor so text is not clipped"
        )
        XCTAssertEqual(
            textField.frame.midY, clickPoint.y, accuracy: 0.5,
            "The taller box should stay vertically centered on the click point"
        )

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testCreateTextFieldForEditingAlignWithStoredPosition() {
        let storedPosition = NSPoint(x: 200, y: 300)
        overlayView.createTextField(at: storedPosition, withText: "Existing text")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        // The field's text sits inside the cell padding: 8 from the left, 4 from the top.
        // Its top edge lines up with the drawn label's, so opening the editor never jumps.
        let textHeight = "Existing text".size(
            withAttributes: [.font: NSFont.systemFont(ofSize: textField.font!.pointSize)]
        ).height
        XCTAssertEqual(textField.frame.origin.x, storedPosition.x - 8, "X should offset by left padding")
        XCTAssertEqual(
            textField.frame.maxY, storedPosition.y + textHeight + 4,
            "The field's text top should sit on the label's text top")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testResizeActiveTextFieldGrowsWithFontSize() {
        let clickPoint = NSPoint(x: 100, y: 200)
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .black, fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: clickPoint, withText: "Hello world")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        let anchoredTop = textField.frame.maxY

        textField.font = NSFont.systemFont(ofSize: textAnnotationFontSizeRange.lowerBound)
        overlayView.resizeActiveTextField(textField)
        let smallSize = textField.frame.size

        textField.font = NSFont.systemFont(ofSize: textAnnotationFontSizeRange.upperBound)
        overlayView.resizeActiveTextField(textField)
        let largeSize = textField.frame.size

        XCTAssertGreaterThan(
            largeSize.width, smallSize.width,
            "Text field width should grow when font size increases"
        )
        XCTAssertGreaterThan(
            largeSize.height, smallSize.height,
            "Text field height should grow when font size increases so text is not clipped"
        )
        XCTAssertEqual(
            textField.frame.maxY, anchoredTop,
            "Growing the height should keep the top edge anchored so the box grows downward"
        )

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testNewLabelWrapsAtTheRightEdgeInsteadOfSliding() {
        // The view is 800 wide with no window, so the screen width falls back to bounds.width.
        let clickPoint = NSPoint(x: 400, y: 300)
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .black, fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: clickPoint, withText: "")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }
        let anchorX = textField.frame.origin.x
        let oneLineHeight = textField.frame.height
        let rightEdge = overlayView.bounds.width - OverlayView.textFieldScreenMargin
        XCTAssertEqual(
            overlayView.currentTextAnnotation?.maxWidth ?? 0,
            rightEdge - anchorX - OverlayView.textFieldHorizontalChrome,
            "A clicked label may grow as far as the right edge")

        textField.stringValue =
            "A long sentence that keeps going well past the right edge of the screen"
        overlayView.resizeActiveTextField(textField)

        XCTAssertEqual(textField.frame.origin.x, anchorX, "The left edge stays where it was clicked")
        XCTAssertEqual(textField.frame.maxX, rightEdge, accuracy: 0.5, "The field stops at the right edge")
        XCTAssertGreaterThan(textField.frame.height, oneLineHeight, "Overflowing text wraps onto new lines")

        overlayView.finalizeTextAnnotation(textField)
        let label = overlayView.textAnnotations[0]
        XCTAssertNil(label.wrapWidth, "A clicked label stays auto width")
        XCTAssertLessThanOrEqual(
            label.bounds(fallbackInsets: NSEdgeInsetsZero).maxX, rightEdge,
            "The placed label wraps at the edge instead of running off it")
        XCTAssertGreaterThan(label.textSize().height, oneLineHeight - 8)
    }

    func testNewLabelRightAtTheEdgeKeepsAMinimumWidthAndSlidesLeft() {
        let clickPoint = NSPoint(x: 790, y: 300)
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .black, fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: clickPoint, withText: "")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }
        XCTAssertEqual(overlayView.currentTextAnnotation?.maxWidth, OverlayView.minimumAutoWrapWidth)

        textField.font = NSFont.systemFont(ofSize: textAnnotationFontSizeRange.upperBound)
        textField.stringValue = "Hello world test"
        overlayView.resizeActiveTextField(textField)

        let rightEdge = overlayView.bounds.width - OverlayView.textFieldScreenMargin
        XCTAssertEqual(
            textField.frame.width,
            OverlayView.minimumAutoWrapWidth + OverlayView.textFieldHorizontalChrome)
        XCTAssertEqual(textField.frame.maxX, rightEdge, accuracy: 0.5, "Slid left to stay on screen")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testResizeActiveTextFieldReturnsToAnchorWhenTextShrinks() {
        // Close enough to the right edge that the minimum wrap width does not fit, so a long
        // string slides the box left, but far enough that a short one fits at the anchor.
        let clickPoint = NSPoint(x: 658, y: 300)
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .black, fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: clickPoint, withText: "")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        let anchorX = textField.frame.origin.x

        textField.stringValue = "A very long sentence that overflows the screen"
        overlayView.resizeActiveTextField(textField)
        XCTAssertLessThan(
            textField.frame.origin.x, anchorX,
            "Text field should slide left when the text overflows the right edge"
        )

        // Shrinking the text should let the box return to its creation anchor, not stay stuck left.
        textField.stringValue = "Hi"
        overlayView.resizeActiveTextField(textField)
        XCTAssertEqual(
            textField.frame.origin.x, anchorX, accuracy: 0.5,
            "Text field should return to its creation anchor when the text fits there again"
        )

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    /// Offscreen-renders the view and counts its non-transparent pixels.
    private func renderedPixelCount(of view: NSView) -> Int {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        var count = 0
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 { count += 1 }
                x += 3
            }
            y += 3
        }
        return count
    }

    func testEditedAnnotationNotDrawnBehindEditField() {
        let annotation = TextAnnotation(
            text: "GHOST", position: NSPoint(x: 120, y: 300), color: .red, fontSize: 28
        )
        overlayView.textAnnotations = [annotation]

        // Not editing: the committed annotation renders.
        overlayView.editingTextAnnotationIndex = nil
        overlayView.currentTextAnnotation = nil
        XCTAssertGreaterThan(
            renderedPixelCount(of: overlayView), 0,
            "Sanity check: a committed text annotation should render"
        )

        // Editing it (mirrors double-click): must not be drawn as a ghost behind the field.
        overlayView.editingTextAnnotationIndex = 0
        overlayView.currentTextAnnotation = annotation
        XCTAssertEqual(
            renderedPixelCount(of: overlayView), 0,
            "The annotation being edited must not be drawn behind the edit field"
        )
    }

    func testEditingAFixedWidthBoxWrapsTheFieldAtTheBoxWidth() {
        let label = TextAnnotation(
            text: "A boxed label that wraps inside its fixed width",
            position: NSPoint(x: 100, y: 300), color: .red, fontSize: defaultTextAnnotationFontSize,
            wrapWidth: 150)
        overlayView.currentTool = .text
        overlayView.textAnnotations = [label]
        overlayView.editingTextAnnotationIndex = 0
        overlayView.currentTextAnnotation = label
        overlayView.createTextField(at: label.position, withText: label.text)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }
        XCTAssertEqual(textField.frame.width, 150 + OverlayView.textFieldHorizontalChrome)
        XCTAssertEqual(textField.frame.maxY, label.textTop + 4, accuracy: 0.5)

        // Typing more text adds lines below; the top edge holds still.
        let top = textField.frame.maxY
        textField.stringValue = label.text + " and keeps going for a few more words"
        overlayView.resizeActiveTextField(textField)
        XCTAssertEqual(textField.frame.maxY, top)
        XCTAssertEqual(textField.frame.width, 150 + OverlayView.textFieldHorizontalChrome)

        overlayView.finalizeTextAnnotation(textField)
        let edited = overlayView.textAnnotations[0]
        XCTAssertEqual(edited.wrapWidth, 150, "Editing keeps the box width")
        XCTAssertEqual(edited.textTop, label.textTop, accuracy: 0.5, "The box grew downward")
        XCTAssertGreaterThan(edited.textSize().height, label.textSize().height)
    }

    /// Lines the field editor shows for `textField`, each with the height it occupies, and
    /// the width the editor breaks them at.
    private func fieldEditorLines(
        of textField: NSTextField, in window: NSWindow
    ) throws -> (lines: [(text: String, height: CGFloat)], wrapWidth: CGFloat) {
        let editor: NSTextView
        if let current = textField.currentEditor() as? NSTextView {
            editor = current
        } else {
            // Headless runs cannot make the field first responder, so attach the field
            // editor the way AppKit does when editing starts.
            editor = try XCTUnwrap(window.fieldEditor(true, for: textField) as? NSTextView)
            textField.cell?.select(
                withFrame: textField.bounds, in: textField, editor: editor,
                delegate: textField, start: 0, length: 0)
        }
        let container = try XCTUnwrap(editor.textContainer)
        let wrapWidth = container.size.width - 2 * container.lineFragmentPadding
        var lines: [(text: String, height: CGFloat)] = []
        if let textLayoutManager = editor.textLayoutManager {
            textLayoutManager.enumerateTextLayoutFragments(
                from: textLayoutManager.documentRange.location, options: [.ensuresLayout]
            ) { fragment in
                for line in fragment.textLineFragments {
                    let text = line.attributedString.attributedSubstring(from: line.characterRange)
                    lines.append((text.string, line.typographicBounds.height))
                }
                return true
            }
        } else {
            let layoutManager = try XCTUnwrap(editor.layoutManager)
            let glyphs = layoutManager.glyphRange(for: container)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, _ in
                let characters = layoutManager.characterRange(
                    forGlyphRange: range, actualGlyphRange: nil)
                lines.append(((editor.string as NSString).substring(with: characters), rect.height))
            }
        }
        textField.abortEditing()
        return (lines, wrapWidth)
    }

    /// Right edge of the ink drawn in each of `lines`, stacked down from `top`, in view
    /// coordinates. A line with no ink reports `-1`.
    private func drawnLineRightEdges(
        in view: NSView, top: CGFloat, lines: [(text: String, height: CGFloat)]
    ) throws -> [CGFloat] {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        var edges: [CGFloat] = []
        var lineTop = top
        for line in lines {
            // The view is not flipped, but bitmap rows count down from the top.
            let firstRow = Int(((view.bounds.height - lineTop) * scale).rounded())
            let lastRow = Int(((view.bounds.height - lineTop + line.height) * scale).rounded())
            var rightmost = -1
            for row in max(firstRow, 0)..<min(lastRow, rep.pixelsHigh) {
                for column in stride(from: rep.pixelsWide - 1, to: rightmost, by: -1)
                where (rep.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.5 {
                    rightmost = column
                    break
                }
            }
            edges.append(rightmost < 0 ? -1 : CGFloat(rightmost + 1) / scale)
            lineTop -= line.height
        }
        return edges
    }

    func testCommittedLabelKeepsTheEditorsLineBreaks() throws {
        let window = NSWindow(
            contentRect: overlayView.frame, styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlayView
        defer {
            window.contentView = nil
            window.close()
        }
        overlayView.fadeMode = false

        // Each string leaves a single word on the last line. That is where AppKit's string
        // drawing was seen to pull one more word down than the editor showed.
        let cases: [(text: String, width: CGFloat)] = [
            ("hello world this wraps at the edge again", 288),
            ("slides left at the edge", 160),
        ]
        for (text, width) in cases {
            let font = NSFont.systemFont(ofSize: 18)
            overlayView.textAnnotations = []
            overlayView.currentTool = .text
            overlayView.currentTextAnnotation = TextAnnotation(
                text: "", position: NSPoint(x: 100, y: 300), color: .red, fontSize: font.pointSize,
                wrapWidth: width)
            overlayView.createTextField(at: NSPoint(x: 100, y: 300), withText: "")
            let textField = try XCTUnwrap(overlayView.activeTextField)
            textField.stringValue = text
            overlayView.resizeActiveTextField(textField)

            let (editorLines, editorWrapWidth) = try fieldEditorLines(of: textField, in: window)
            XCTAssertEqual(editorLines.count, 2, "Sanity check: the editor wraps \"\(text)\"")
            XCTAssertEqual(textField.stringValue, text)

            overlayView.finalizeTextAnnotation(textField)
            overlayView.selectedObjects = []
            let label = try XCTUnwrap(overlayView.textAnnotations.first)
            XCTAssertEqual(
                editorWrapWidth, label.layoutWidth, accuracy: 0.5,
                "The editor breaks lines at the width the label lays out at")
            let drawnEdges = try drawnLineRightEdges(
                in: overlayView, top: label.textTop, lines: editorLines)

            // Each drawn line has to end with the editor's last word on that line: its ink
            // stops where that line's text ends, give or take the last glyph's side bearing.
            for (line, drawnEdge) in zip(editorLines, drawnEdges) {
                let lineText = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let expectedEdge =
                    label.position.x + (lineText as NSString).size(withAttributes: [.font: font]).width
                XCTAssertEqual(
                    drawnEdge, expectedEdge, accuracy: 3,
                    "\"\(text)\" at \(width) pt: the label draws \"\(lineText)\" on one line, like the editor")
            }
        }
    }

    func testFinalizeTextAnnotationAccountsForPadding() {
        let clickPoint = NSPoint(x: 200, y: 300)
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: clickPoint, color: .red, fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: clickPoint, withText: "")

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        textField.stringValue = "Test text"
        overlayView.finalizeTextAnnotation(textField)

        XCTAssertEqual(overlayView.textAnnotations.count, 1, "Should have one text annotation")

        let annotation = overlayView.textAnnotations[0]
        // The field draws its text 8 in from the left and 4 down from the top, and the label
        // keeps that left and top edge. The field is 32 tall, centered on the click.
        let expectedX = clickPoint.x - 8 + 8
        let expectedY = clickPoint.y + 16 - 4 - annotation.textSize().height
        XCTAssertEqual(annotation.position.x, expectedX, accuracy: 0.01, "Position X should account for padding")
        XCTAssertEqual(annotation.position.y, expectedY, accuracy: 0.01, "Position Y should account for padding")
    }

    func testTextFieldCommandShortcutsStepAndToggle() throws {
        let textField = AnnotationTextField(frame: .zero)
        var directions: [Int] = []
        var toggleCount = 0
        textField.onFontSizeStep = { directions.append($0) }
        textField.onToggleBackground = { toggleCount += 1 }

        for character in ["=", "+", "-", "b"] {
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: character,
                    charactersIgnoringModifiers: character,
                    isARepeat: false,
                    keyCode: 0))
            XCTAssertTrue(textField.performKeyEquivalent(with: event))
        }

        XCTAssertEqual(directions, [1, 1, -1])
        XCTAssertEqual(toggleCount, 1)
    }

    func testFinalizePreservesBackgroundAndStartsFadeLifecycle() throws {
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "",
            position: NSPoint(x: 200, y: 300),
            color: .red,
            fontSize: 44,
            hasBackground: true)
        overlayView.createTextField(at: NSPoint(x: 200, y: 300))
        let textField = try XCTUnwrap(overlayView.activeTextField)
        textField.stringValue = "Pill"

        overlayView.finalizeTextAnnotation(textField)

        let annotation = try XCTUnwrap(overlayView.textAnnotations.first)
        XCTAssertTrue(annotation.hasBackground)
        XCTAssertEqual(annotation.fontSize, 44)
        XCTAssertNotNil(annotation.creationTime)
    }

    func testBackgroundPillAddsRenderedAreaAndFadesWithText() {
        overlayView.fadeMode = false
        let plain = TextAnnotation(
            text: "A",
            position: NSPoint(x: 120, y: 300),
            color: .red,
            fontSize: 44)
        overlayView.textAnnotations = [plain]
        let plainPixels = renderedPixelCount(of: overlayView)

        var pill = plain
        pill.hasBackground = true
        overlayView.textAnnotations = [pill]
        XCTAssertGreaterThan(renderedPixelCount(of: overlayView), plainPixels)

        pill.creationTime = CACurrentMediaTime() - overlayView.fadeDuration - 1
        overlayView.fadeMode = true
        overlayView.textAnnotations = [pill]
        _ = renderedPixelCount(of: overlayView)
        XCTAssertEqual(overlayView.textAnnotations.count, 1, "draw must not compact expired text")
        overlayView.compactExpiredAnnotations()
        XCTAssertTrue(overlayView.textAnnotations.isEmpty)
    }

    // MARK: - Text compaction under an active edit or drag

    private func seedFadingTextAnnotations(now: CFTimeInterval) {
        overlayView.fadeMode = true
        overlayView.textAnnotations = [
            TextAnnotation(
                text: "expired", position: NSPoint(x: 10, y: 10), color: .black, fontSize: 18,
                creationTime: now - overlayView.fadeDuration - 1),
            TextAnnotation(
                text: "live", position: NSPoint(x: 20, y: 20), color: .black, fontSize: 18,
                creationTime: now),
        ]
    }

    func testCompactionRemapsEditingTextIndexWhenAnEarlierLabelExpires() {
        seedFadingTextAnnotations(now: CACurrentMediaTime())
        overlayView.editingTextAnnotationIndex = 1

        overlayView.compactExpiredAnnotations()

        XCTAssertEqual(overlayView.textAnnotations.count, 1)
        XCTAssertEqual(
            overlayView.editingTextAnnotationIndex, 0,
            "The edited label moved down a slot, so its index has to follow")
        XCTAssertEqual(overlayView.textAnnotations[0].text, "live")
    }

    func testCompactionRemapsDraggedTextIndexWhenAnEarlierLabelExpires() {
        seedFadingTextAnnotations(now: CACurrentMediaTime())
        overlayView.draggedTextAnnotationIndex = 1

        overlayView.compactExpiredAnnotations()

        XCTAssertEqual(overlayView.textAnnotations.count, 1)
        XCTAssertEqual(
            overlayView.draggedTextAnnotationIndex, 0,
            "The dragged label moved down a slot, so its index has to follow")
        XCTAssertEqual(overlayView.textAnnotations[0].text, "live")
    }

    func testCompactionKeepsAnExpiredLabelWhileItIsBeingEdited() {
        let now = CACurrentMediaTime()
        let expired = now - overlayView.fadeDuration - 1
        overlayView.fadeMode = true
        overlayView.textAnnotations = [
            TextAnnotation(
                text: "gone", position: NSPoint(x: 10, y: 10), color: .black, fontSize: 18,
                creationTime: expired),
            TextAnnotation(
                text: "editing", position: NSPoint(x: 20, y: 20), color: .black, fontSize: 18,
                creationTime: expired),
            TextAnnotation(
                text: "live", position: NSPoint(x: 30, y: 30), color: .black, fontSize: 18,
                creationTime: now),
        ]
        overlayView.editingTextAnnotationIndex = 1

        overlayView.compactExpiredAnnotations()

        XCTAssertEqual(overlayView.textAnnotations.count, 2)
        XCTAssertEqual(overlayView.editingTextAnnotationIndex, 0)
        XCTAssertEqual(overlayView.textAnnotations[0].text, "editing")
        XCTAssertEqual(overlayView.textAnnotations[1].text, "live")
    }

    func testCompactionKeepsAnExpiredLabelWhileItIsBeingDragged() {
        let now = CACurrentMediaTime()
        let expired = now - overlayView.fadeDuration - 1
        overlayView.fadeMode = true
        overlayView.textAnnotations = [
            TextAnnotation(
                text: "gone", position: NSPoint(x: 10, y: 10), color: .black, fontSize: 18,
                creationTime: expired),
            TextAnnotation(
                text: "dragging", position: NSPoint(x: 20, y: 20), color: .black, fontSize: 18,
                creationTime: expired),
        ]
        overlayView.draggedTextAnnotationIndex = 1

        overlayView.compactExpiredAnnotations()

        XCTAssertEqual(overlayView.textAnnotations.count, 1)
        XCTAssertEqual(overlayView.draggedTextAnnotationIndex, 0)
        XCTAssertEqual(overlayView.textAnnotations[0].text, "dragging")
    }

    // MARK: - Label geometry

    func testPlainLabelRectKeepsInteractionSlop() {
        let annotation = TextAnnotation(
            text: "Hello", position: NSPoint(x: 100, y: 100), color: .black, fontSize: 18)
        overlayView.textAnnotations = [annotation]
        let bareSize = annotation.text.size(
            withAttributes: [.font: NSFont.systemFont(ofSize: annotation.fontSize)])

        let rect = overlayView.getObjectBounds(.text(index: 0))

        XCTAssertEqual(rect.origin.x, annotation.position.x)
        XCTAssertEqual(rect.origin.y, annotation.position.y)
        XCTAssertGreaterThan(
            rect.width, bareSize.width,
            "A label without a background still needs slop so it stays easy to grab")
        XCTAssertGreaterThan(rect.height, bareSize.height)
    }

    func testLabelWithBackgroundUsesPillGeometry() {
        var annotation = TextAnnotation(
            text: "Hello", position: NSPoint(x: 100, y: 100), color: .black, fontSize: 18)
        annotation.hasBackground = true
        overlayView.textAnnotations = [annotation]
        let bareSize = annotation.text.size(
            withAttributes: [.font: NSFont.systemFont(ofSize: annotation.fontSize)])
        let insets = TextAnnotation.pillInsets

        let rect = overlayView.getObjectBounds(.text(index: 0))

        XCTAssertEqual(rect.origin.x, annotation.position.x - insets.left)
        XCTAssertEqual(rect.origin.y, annotation.position.y - insets.bottom)
        XCTAssertEqual(rect.width, bareSize.width + insets.left + insets.right, accuracy: 0.001)
        XCTAssertEqual(rect.height, bareSize.height + insets.top + insets.bottom, accuracy: 0.001)
    }

    // MARK: - Finalizing an edit

    func testFinalizingAnEditRestampsCreationTime() throws {
        let seeded = CACurrentMediaTime() - 0.5
        overlayView.fadeMode = true
        overlayView.currentTool = .text
        overlayView.textAnnotations = [
            TextAnnotation(
                text: "before", position: NSPoint(x: 100, y: 100), color: .black, fontSize: 18,
                creationTime: seeded)
        ]
        overlayView.editingTextAnnotationIndex = 0
        overlayView.currentTextAnnotation = overlayView.textAnnotations[0]
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "before")

        let textField = try XCTUnwrap(overlayView.activeTextField)
        textField.stringValue = "after"
        overlayView.finalizeTextAnnotation(textField)

        XCTAssertEqual(overlayView.textAnnotations.count, 1)
        XCTAssertEqual(overlayView.textAnnotations[0].text, "after")
        let stamped = try XCTUnwrap(overlayView.textAnnotations[0].creationTime)
        XCTAssertGreaterThan(
            stamped, seeded,
            "A re-edited label restarts its fade clock instead of inheriting the old one")
    }

    // MARK: - Text mode stickiness

    func testEnterCommitsLabelAndStaysInTextModeByDefault() throws {
        try withSelectAfterPlacingText(nil) {
            overlayView.currentTool = .text
            seedNewTextField(text: "Hello")
            let textField = try XCTUnwrap(overlayView.activeTextField)

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertEqual(overlayView.currentTool, .text, "Enter should stay in text mode by default")
            XCTAssertEqual(overlayView.textAnnotations.count, 1)
            XCTAssertEqual(overlayView.textAnnotations[0].text, "Hello")
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testEnterSelectsThePlacedLabelWhenOptedIn() throws {
        try withSelectAfterPlacingText(true) {
            overlayView.currentTool = .text
            seedNewTextField(text: "Hello")
            let textField = try XCTUnwrap(overlayView.activeTextField)

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertEqual(
                overlayView.currentTool, .select,
                "Enter should switch to Select when select after placing text is on"
            )
            XCTAssertEqual(overlayView.textAnnotations.count, 1)
            XCTAssertEqual(
                overlayView.selectedObjects, [.text(index: 0)],
                "The label that was just placed should be the selection"
            )
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testEscapeCommitsLabelAndStaysInTextModeByDefault() throws {
        try withSelectAfterPlacingText(nil) {
            overlayView.currentTool = .text
            seedNewTextField(text: "Draft")
            let textField = try XCTUnwrap(overlayView.activeTextField)

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertEqual(overlayView.currentTool, .text, "Esc should stay in text mode by default")
            XCTAssertEqual(overlayView.textAnnotations.count, 1)
            XCTAssertEqual(
                overlayView.textAnnotations[0].text, "Draft",
                "Esc on a field with text should place the label instead of discarding it"
            )
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testEscapeSelectsThePlacedLabelWhenOptedIn() throws {
        try withSelectAfterPlacingText(true) {
            overlayView.currentTool = .text
            seedNewTextField(text: "Draft")
            let textField = try XCTUnwrap(overlayView.activeTextField)

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertEqual(overlayView.currentTool, .select, "Esc commits like Enter, including the switch")
            XCTAssertEqual(overlayView.textAnnotations.count, 1)
            XCTAssertEqual(overlayView.selectedObjects, [.text(index: 0)])
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testEscapeOnEmptyFieldDiscardsItAndStaysInTextMode() throws {
        try withSelectAfterPlacingText(true) {
            overlayView.currentTool = .text
            seedNewTextField(text: "")
            let textField = try XCTUnwrap(overlayView.activeTextField)

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertEqual(
                overlayView.currentTool, .text,
                "An empty field is a cancel, so it never switches tools"
            )
            XCTAssertTrue(overlayView.textAnnotations.isEmpty)
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testEscapeOnClearedEditKeepsTheOriginalLabel() throws {
        try withSelectAfterPlacingText(true) {
            overlayView.currentTool = .text
            let original = TextAnnotation(
                text: "Hi", position: NSPoint(x: 100, y: 100), color: .red,
                fontSize: defaultTextAnnotationFontSize
            )
            overlayView.textAnnotations = [original]
            overlayView.editingTextAnnotationIndex = 0
            overlayView.currentTextAnnotation = original
            overlayView.createTextField(at: original.position, withText: original.text)
            let textField = try XCTUnwrap(overlayView.activeTextField)
            textField.stringValue = ""

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertEqual(overlayView.textAnnotations.count, 1, "Cancelling an edit must not delete the label")
            XCTAssertEqual(overlayView.textAnnotations[0].text, "Hi")
            XCTAssertEqual(overlayView.currentTool, .text)
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testCommandReturnSelectsThePlacedLabelWhenOptedIn() throws {
        try withSelectAfterPlacingText(true) {
            overlayView.currentTool = .text
            seedNewTextField(text: "Hello")
            let textField = try XCTUnwrap(overlayView.activeTextField as? AnnotationTextField)

            textField.onCommandReturn?()

            XCTAssertEqual(
                overlayView.currentTool, .select,
                "Cmd+Enter commits like Enter, including the switch"
            )
            XCTAssertEqual(overlayView.textAnnotations.count, 1)
            XCTAssertEqual(overlayView.textAnnotations[0].text, "Hello")
            XCTAssertEqual(overlayView.selectedObjects, [.text(index: 0)])
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testEnterOnEmptyFieldPlacesNothingAndStaysInTextModeWhenOptedIn() throws {
        try withSelectAfterPlacingText(true) {
            overlayView.currentTool = .text
            seedNewTextField(text: "")
            let textField = try XCTUnwrap(overlayView.activeTextField)

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertTrue(overlayView.textAnnotations.isEmpty, "An empty field places no label")
            XCTAssertEqual(
                overlayView.currentTool, .text,
                "There is nothing to select, so the tool stays put"
            )
            XCTAssertTrue(overlayView.selectedObjects.isEmpty)
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    func testEnterOnAnEditedLabelSelectsThatLabelWhenOptedIn() throws {
        try withSelectAfterPlacingText(true) {
            overlayView.currentTool = .text
            let first = TextAnnotation(
                text: "First", position: NSPoint(x: 100, y: 100), color: .red,
                fontSize: defaultTextAnnotationFontSize
            )
            let second = TextAnnotation(
                text: "Second", position: NSPoint(x: 300, y: 300), color: .red,
                fontSize: defaultTextAnnotationFontSize
            )
            overlayView.textAnnotations = [first, second]
            overlayView.editingTextAnnotationIndex = 0
            overlayView.currentTextAnnotation = first
            overlayView.createTextField(at: first.position, withText: first.text)
            let textField = try XCTUnwrap(overlayView.activeTextField)
            textField.stringValue = "Edited"

            let handled = overlayView.control(
                textField,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            )

            XCTAssertTrue(handled)
            XCTAssertEqual(overlayView.textAnnotations.count, 2, "Editing must not add a label")
            XCTAssertEqual(overlayView.textAnnotations[0].text, "Edited")
            XCTAssertEqual(overlayView.textAnnotations[1].text, "Second")
            XCTAssertEqual(
                overlayView.selectedObjects, [.text(index: 0)],
                "The edited label is the selection, not the last one in the array"
            )
            XCTAssertEqual(overlayView.currentTool, .select)
            XCTAssertNil(overlayView.activeTextField)
        }
    }

    /// Opens a new-label field at a fixed point, seeded the way `OverlayWindow` seeds it on a
    /// click, and types `text` into it.
    func testShiftReturnInsertsALineBreakInTheSameLabel() throws {
        overlayView.currentTool = .text
        seedNewTextField(text: "First")
        let textField = try XCTUnwrap(overlayView.activeTextField)
        let editor = NSTextView()
        editor.string = "First"
        editor.setSelectedRange(NSRange(location: 5, length: 0))

        // `control(_:textView:doCommandBy:)` reads Shift from the app's current event, which
        // only an event the app dequeued itself becomes.
        let shiftReturn = try XCTUnwrap(
            TestEvents.createKeyEvent(
                type: .keyDown, keyCode: 36, modifierFlags: .shift, characters: "\r"))
        NSApplication.shared.postEvent(shiftReturn, atStart: true)
        _ = NSApplication.shared.nextEvent(
            matching: .keyDown, until: .distantPast, inMode: .default, dequeue: true)

        let handled = overlayView.control(
            textField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled)
        XCTAssertEqual(editor.string, "First\n", "Shift+Return types a line break")
        XCTAssertTrue(overlayView.activeTextField === textField, "The same label stays open")
        XCTAssertTrue(overlayView.textAnnotations.isEmpty, "Nothing is placed yet")
    }

    func testLineBreaksGrowTheFieldDownwardAndPlaceOneLabel() throws {
        overlayView.currentTool = .text
        seedNewTextField(text: "First")
        let textField = try XCTUnwrap(overlayView.activeTextField)
        overlayView.resizeActiveTextField(textField)
        let top = textField.frame.maxY
        let oneLineHeight = textField.frame.height

        // A trailing line break already makes room for the cursor on the new line.
        textField.stringValue = "First\n"
        overlayView.resizeActiveTextField(textField)
        XCTAssertGreaterThan(textField.frame.height, oneLineHeight)
        XCTAssertEqual(textField.frame.maxY, top)

        textField.stringValue = "First\nSecond"
        overlayView.resizeActiveTextField(textField)
        XCTAssertEqual(textField.frame.maxY, top)

        overlayView.finalizeTextAnnotation(textField)
        XCTAssertEqual(overlayView.textAnnotations.count, 1)
        let label = overlayView.textAnnotations[0]
        XCTAssertEqual(label.text, "First\nSecond")
        XCTAssertEqual(label.textTop, top - 4, accuracy: 0.5, "The label keeps the field's text top")
    }

    private func seedNewTextField(text: String) {
        let point = NSPoint(x: 100, y: 100)
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: point, color: .red,
            fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: point, withText: "")
        overlayView.activeTextField?.stringValue = text
    }

    private func withSelectAfterPlacingText(
        _ enabled: Bool?,
        body: () throws -> Void
    ) rethrows {
        let defaults = overlayView.pickerUserDefaults
        let key = UserDefaults.selectAfterPlacingTextKey
        let saved = defaults.object(forKey: key)
        defer {
            if let saved {
                defaults.set(saved, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        if let enabled {
            defaults.selectAfterPlacingText = enabled
        } else {
            defaults.removeObject(forKey: key)
        }

        try body()
    }
}
