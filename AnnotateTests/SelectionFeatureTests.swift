import XCTest

@testable import Annotate

@MainActor
final class SelectionFeatureTests: XCTestCase {
    var overlayView: OverlayView!
    
    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
    }
    
    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            overlayView = nil
        }
        super.tearDown()
    }
    
    // MARK: - Basic Selection Tests
    
    func testSelectToolMode() {
        overlayView.currentTool = .select
        XCTAssertEqual(overlayView.currentTool, .select)
    }
    
    func testEmptySelectionInitially() {
        XCTAssertTrue(overlayView.selectedObjects.isEmpty)
    }
    
    func testSingleObjectSelection() {
        // Add a line
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        // Find object at point
        let foundObject = overlayView.findObjectAt(point: NSPoint(x: 150, y: 150))
        
        // Should find the line
        if case .line(let index) = foundObject {
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("Should have found line")
        }
    }
    
    func testMultipleObjectSelection() {
        // Add multiple objects
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        let circle = Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.circles.append(circle)
        
        // Select both
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        XCTAssertEqual(overlayView.selectedObjects.count, 2)
        XCTAssertTrue(overlayView.selectedObjects.contains(.line(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.circle(index: 0)))
    }
    
    // MARK: - Hit Testing Tests
    
    func testHitTestLine() {
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        // Point on the line
        let onLine = overlayView.findObjectAt(point: NSPoint(x: 150, y: 150))
        XCTAssertNotEqual(onLine, .none)
        
        // Point far from line
        let offLine = overlayView.findObjectAt(point: NSPoint(x: 500, y: 500))
        XCTAssertEqual(offLine, .none)
    }
    
    func testHitTestRectangleEdgeOnly() {
        let rect = Rectangle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.rectangles.append(rect)
        
        // Point on edge should hit
        let onEdge = overlayView.findObjectAt(point: NSPoint(x: 100, y: 150))
        XCTAssertNotEqual(onEdge, .none)
        
        // Point in center should NOT hit (edge-only selection)
        let inCenter = overlayView.findObjectAt(point: NSPoint(x: 150, y: 150))
        XCTAssertEqual(inCenter, .none)
    }
    
    func testHitTestCircleEdgeOnly() {
        let circle = Circle(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.circles.append(circle)
        
        // Point in center should NOT hit (edge-only selection)
        let inCenter = overlayView.findObjectAt(point: NSPoint(x: 150, y: 150))
        XCTAssertEqual(inCenter, .none)
    }
    
    func testHitTestText() {
        let textAnnotation = TextAnnotation(
            text: "Hello",
            position: NSPoint(x: 100, y: 100),
            color: .black,
            fontSize: defaultTextAnnotationFontSize
        )
        overlayView.textAnnotations.append(textAnnotation)
        
        // Point in text area should hit
        let inText = overlayView.findObjectAt(point: NSPoint(x: 110, y: 110))
        if case .text(let index) = inText {
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("Should have found text")
        }
    }
    
    func testHitTestCounter() {
        let counter = CounterAnnotation(
            number: 1,
            position: NSPoint(x: 100, y: 100),
            color: .red,
            creationTime: nil
        )
        overlayView.counterAnnotations.append(counter)
        
        // Point near counter should hit
        let nearCounter = overlayView.findObjectAt(point: NSPoint(x: 105, y: 105))
        if case .counter(let index) = nearCounter {
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("Should have found counter")
        }
    }
    
    // MARK: - Z-Order Selection Tests
    
    func testZOrderSelectionLatestFirst() {
        // Add two overlapping lines
        let line1 = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 10.0,
            creationTime: nil
        )
        overlayView.lines.append(line1)
        
        let line2 = Line(
            startPoint: NSPoint(x: 110, y: 110),
            endPoint: NSPoint(x: 210, y: 210),
            color: .blue,
            lineWidth: 10.0,
            creationTime: nil
        )
        overlayView.lines.append(line2)
        
        // Click on overlapping area - should get the latest (line2)
        let found = overlayView.findObjectAt(point: NSPoint(x: 150, y: 150))
        if case .line(let index) = found {
            XCTAssertEqual(index, 1, "Should select the latest line (index 1)")
        } else {
            XCTFail("Should have found a line")
        }
    }
    
    // MARK: - Rectangle Selection Tests
    
    func testRectangleSelectionFindsObjects() {
        // Add objects at different positions
        let line = Line(
            startPoint: NSPoint(x: 50, y: 50),
            endPoint: NSPoint(x: 100, y: 100),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        let circle = Circle(
            startPoint: NSPoint(x: 200, y: 200),
            endPoint: NSPoint(x: 250, y: 250),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.circles.append(circle)
        
        // Rectangle that covers the line but not the circle
        let rect = NSRect(x: 40, y: 40, width: 80, height: 80)
        let foundObjects = overlayView.findObjectsInRect(rect)
        
        XCTAssertTrue(foundObjects.contains(.line(index: 0)))
        XCTAssertFalse(foundObjects.contains(.circle(index: 0)))
    }
    
    func testRectangleSelectionEmpty() {
        // Add a line
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        // Rectangle that doesn't cover anything
        let rect = NSRect(x: 300, y: 300, width: 50, height: 50)
        let foundObjects = overlayView.findObjectsInRect(rect)

        XCTAssertTrue(foundObjects.isEmpty)
    }

    func testRectangleSelectionSelectsLargeCounterOverlappingBadgeNotCenter() {
        // At 60 pt the badge spans roughly [435.7, 564.3] around center (500, 500).
        overlayView.counterAnnotations.append(CounterAnnotation(
            number: 1,
            position: NSPoint(x: 500, y: 500),
            color: .red,
            fontSize: 60,
            creationTime: nil
        ))

        // Marquee overlaps the badge but stops short of the center point (maxX = 495 < 500).
        // Center-point-only selection would miss it; area-based selection includes it.
        let rect = NSRect(x: 440, y: 440, width: 55, height: 120)
        let foundObjects = overlayView.findObjectsInRect(rect)

        XCTAssertTrue(foundObjects.contains(.counter(index: 0)))
    }

    func testRectangleSelectionMissesCounterOutsideBadge() {
        overlayView.counterAnnotations.append(CounterAnnotation(
            number: 1,
            position: NSPoint(x: 500, y: 500),
            color: .red,
            fontSize: 60,
            creationTime: nil
        ))

        let rect = NSRect(x: 100, y: 100, width: 50, height: 50)
        let foundObjects = overlayView.findObjectsInRect(rect)

        XCTAssertFalse(foundObjects.contains(.counter(index: 0)))
    }

    // MARK: - Bounding Box Tests
    
    func testGetObjectBoundsLine() {
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        let bounds = overlayView.getObjectBounds(.line(index: 0))
        
        XCTAssertEqual(bounds.origin.x, 100)
        XCTAssertEqual(bounds.origin.y, 100)
        XCTAssertEqual(bounds.width, 100)
        XCTAssertEqual(bounds.height, 100)
    }
    
    func testGetObjectBoundsRectangle() {
        let rect = Rectangle(
            startPoint: NSPoint(x: 50, y: 50),
            endPoint: NSPoint(x: 150, y: 150),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.rectangles.append(rect)
        
        let bounds = overlayView.getObjectBounds(.rectangle(index: 0))
        
        XCTAssertEqual(bounds.origin.x, 50)
        XCTAssertEqual(bounds.origin.y, 50)
        XCTAssertEqual(bounds.width, 100)
        XCTAssertEqual(bounds.height, 100)
    }
    
    func testCalculateSelectionBoundingBoxSingleObject() {
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        overlayView.selectedObjects = [.line(index: 0)]
        
        let boundingBox = overlayView.calculateSelectionBoundingBox()
        
        // Should be the line bounds with 5pt padding
        XCTAssertEqual(boundingBox.origin.x, 95)
        XCTAssertEqual(boundingBox.origin.y, 95)
        XCTAssertEqual(boundingBox.width, 110)
        XCTAssertEqual(boundingBox.height, 110)
    }
    
    func testCalculateSelectionBoundingBoxMultipleObjects() {
        // Add two objects
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        let circle = Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.circles.append(circle)
        
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        let boundingBox = overlayView.calculateSelectionBoundingBox()
        
        // Should encompass both objects with padding
        XCTAssertEqual(boundingBox.origin.x, 95)
        XCTAssertEqual(boundingBox.origin.y, 95)
        XCTAssertEqual(boundingBox.width, 310) // From 95 to 405
        XCTAssertEqual(boundingBox.height, 310)
    }
    
    func testIsPointInSelectionBoundingBox() {
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        overlayView.selectedObjects = [.line(index: 0)]
        
        // Point inside bounding box
        XCTAssertTrue(overlayView.isPointInSelectionBoundingBox(NSPoint(x: 150, y: 150)))
        
        // Point outside bounding box
        XCTAssertFalse(overlayView.isPointInSelectionBoundingBox(NSPoint(x: 300, y: 300)))
    }
    
    // MARK: - Object Movement Tests
    
    func testMoveSelectedObjects() {
        // Add a line
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        overlayView.selectedObjects = [.line(index: 0)]
        
        // Move by delta
        let delta = NSPoint(x: 50, y: 50)
        overlayView.moveSelectedObjects(by: delta)
        
        // Check line moved
        XCTAssertEqual(overlayView.lines[0].startPoint.x, 150)
        XCTAssertEqual(overlayView.lines[0].startPoint.y, 150)
        XCTAssertEqual(overlayView.lines[0].endPoint.x, 250)
        XCTAssertEqual(overlayView.lines[0].endPoint.y, 250)
    }
    
    func testMoveMultipleSelectedObjects() {
        // Add two objects
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        let circle = Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.circles.append(circle)
        
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        // Move both
        let delta = NSPoint(x: 10, y: 20)
        overlayView.moveSelectedObjects(by: delta)
        
        // Check both moved
        XCTAssertEqual(overlayView.lines[0].startPoint.x, 110)
        XCTAssertEqual(overlayView.lines[0].startPoint.y, 120)
        XCTAssertEqual(overlayView.circles[0].startPoint.x, 310)
        XCTAssertEqual(overlayView.circles[0].startPoint.y, 320)
    }
    
    // MARK: - Deletion Tests
    
    func testDeleteSelectedObjects() {
        // Add multiple objects
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        let circle = Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.circles.append(circle)
        
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        // Delete selected
        overlayView.deleteSelectedObjects()
        
        // Both should be deleted
        XCTAssertTrue(overlayView.lines.isEmpty)
        XCTAssertTrue(overlayView.circles.isEmpty)
        XCTAssertTrue(overlayView.selectedObjects.isEmpty)
    }
    
    func testDeleteLastItemInSelectMode() {
        // Add objects
        let line = Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        )
        overlayView.lines.append(line)
        
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.line(index: 0)]
        
        // Call deleteLastItem (which should delete selected)
        overlayView.deleteLastItem()
        
        XCTAssertTrue(overlayView.lines.isEmpty)
        XCTAssertTrue(overlayView.selectedObjects.isEmpty)
    }
    
    // MARK: - Edge Cases
    
    func testEmptySelectionBoundingBox() {
        let boundingBox = overlayView.calculateSelectionBoundingBox()
        XCTAssertEqual(boundingBox, NSRect.zero)
    }
    
    func testMoveEmptySelection() {
        // Should not crash
        overlayView.moveSelectedObjects(by: NSPoint(x: 10, y: 10))
        XCTAssertTrue(overlayView.selectedObjects.isEmpty)
    }
    
    func testDeleteEmptySelection() {
        // Should not crash
        overlayView.deleteSelectedObjects()
        XCTAssertTrue(overlayView.selectedObjects.isEmpty)
    }
    
    func testFindObjectAtEmptyCanvas() {
        let found = overlayView.findObjectAt(point: NSPoint(x: 100, y: 100))
        XCTAssertEqual(found, .none)
    }
    
    func testRectangleSelectionEmptyCanvas() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let found = overlayView.findObjectsInRect(rect)
        XCTAssertTrue(found.isEmpty)
    }
    
    // MARK: - Select All Tests
    
    func testSelectAllInSelectMode() {
        // Add various objects
        overlayView.arrows.append(Arrow(
            startPoint: NSPoint(x: 10, y: 10),
            endPoint: NSPoint(x: 50, y: 50),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.rectangles.append(Rectangle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .green,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 500, y: 500),
            endPoint: NSPoint(x: 600, y: 600),
            color: .yellow,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.textAnnotations.append(TextAnnotation(
            text: "Test",
            position: NSPoint(x: 700, y: 700),
            color: .black,
            fontSize: defaultTextAnnotationFontSize
        ))
        
        // Switch to select mode
        overlayView.currentTool = .select
        
        // Call selectAllObjects
        overlayView.selectAllObjects()
        
        // Should have selected all 5 objects
        XCTAssertEqual(overlayView.selectedObjects.count, 5)
        XCTAssertTrue(overlayView.selectedObjects.contains(.arrow(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.line(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.rectangle(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.circle(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.text(index: 0)))
    }
    
    func testSelectAllNotInSelectMode() {
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))

        overlayView.currentTool = .pen
        overlayView.selectAllObjects()

        // selectAllObjects() now works regardless of mode
        // Mode switching is handled in OverlayWindow's performKeyEquivalent
        XCTAssertEqual(overlayView.selectedObjects.count, 1)
        XCTAssertTrue(overlayView.selectedObjects.contains(.line(index: 0)))
    }
    
    func testSelectAllEmptyCanvas() {
        overlayView.currentTool = .select
        
        // Call selectAllObjects on empty canvas
        overlayView.selectAllObjects()
        
        // Should remain empty
        XCTAssertTrue(overlayView.selectedObjects.isEmpty)
    }
    
    func testSelectAllClearsPreviousSelection() {
        // Add objects
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.arrows.append(Arrow(
            startPoint: NSPoint(x: 10, y: 10),
            endPoint: NSPoint(x: 50, y: 50),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .select
        
        // Select just one object
        overlayView.selectedObjects = [.line(index: 0)]
        XCTAssertEqual(overlayView.selectedObjects.count, 1)
        
        // Call selectAllObjects
        overlayView.selectAllObjects()
        
        // Should now have all objects selected
        XCTAssertEqual(overlayView.selectedObjects.count, 2)
        XCTAssertTrue(overlayView.selectedObjects.contains(.line(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.arrow(index: 0)))
    }
    
    func testSelectAllWithAllObjectTypes() {
        overlayView.currentTool = .select
        
        // Add one of each type
        overlayView.paths.append(DrawingPath(
            points: [TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)],
            color: .red,
            lineWidth: 2.0
        ))
        
        overlayView.arrows.append(Arrow(
            startPoint: NSPoint(x: 10, y: 10),
            endPoint: NSPoint(x: 50, y: 50),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.highlightPaths.append(DrawingPath(
            points: [TimedPoint(point: NSPoint(x: 150, y: 150), timestamp: 0)],
            color: .yellow,
            lineWidth: 20.0
        ))
        
        overlayView.rectangles.append(Rectangle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .green,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 500, y: 500),
            endPoint: NSPoint(x: 600, y: 600),
            color: .yellow,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.textAnnotations.append(TextAnnotation(
            text: "Test",
            position: NSPoint(x: 700, y: 700),
            color: .black,
            fontSize: defaultTextAnnotationFontSize
        ))
        
        overlayView.counterAnnotations.append(CounterAnnotation(
            number: 1,
            position: NSPoint(x: 800, y: 800),
            color: .red,
            creationTime: nil
        ))
        
        // Call selectAllObjects
        overlayView.selectAllObjects()
        
        // Should select all 8 objects (one of each type)
        XCTAssertEqual(overlayView.selectedObjects.count, 8)
        XCTAssertTrue(overlayView.selectedObjects.contains(.path(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.arrow(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.line(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.highlight(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.rectangle(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.circle(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.text(index: 0)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.counter(index: 0)))
    }
    
    // MARK: - Copy/Paste/Cut/Duplicate Tests
    
    func testCopySelectedObjects() {
        // Add objects
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        // Copy
        overlayView.copySelectedObjects()
        
        // Original objects should still exist
        XCTAssertEqual(overlayView.lines.count, 1)
        XCTAssertEqual(overlayView.circles.count, 1)
        
        // Selection should remain
        XCTAssertEqual(overlayView.selectedObjects.count, 2)
    }
    
    func testCutSelectedObjects() {
        // Add objects
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        // Cut
        overlayView.cutSelectedObjects()
        
        // Objects should be removed
        XCTAssertTrue(overlayView.lines.isEmpty)
        XCTAssertTrue(overlayView.circles.isEmpty)
        
        // Selection should be cleared
        XCTAssertTrue(overlayView.selectedObjects.isEmpty)
    }
    
    func testPasteObjectsAtCursor() {
        // Add and copy objects
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.line(index: 0)]
        overlayView.copySelectedObjects()
        
        // Set cursor position
        overlayView.lastMousePosition = NSPoint(x: 400, y: 400)
        
        // For testing purposes, we can't easily test pasteObjects() because it requires
        // a window context. Instead, let's verify that the clipboard has the data.
        
        // Verify clipboard is not empty after copy
        XCTAssertFalse(overlayView.clipboard.isEmpty)
        XCTAssertEqual(overlayView.clipboard.count, 1)

        // Verify the clipboard contains the line data
        if let clipboardItem = overlayView.clipboard.first {
            if case .line = clipboardItem {
                XCTAssertTrue(true, "Clipboard contains line data")
            } else {
                XCTFail("Clipboard should contain line object type")
            }
        }
    }
    
    func testPasteWithoutCopy() {
        overlayView.currentTool = .select
        
        // Verify clipboard is empty
        XCTAssertTrue(overlayView.clipboard.isEmpty)
    }
    
    func testDuplicateSelectedObjects() {
        // Add objects
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        // Duplicate
        overlayView.duplicateSelectedObjects()
        
        // Should have duplicated objects
        XCTAssertEqual(overlayView.lines.count, 2)
        XCTAssertEqual(overlayView.circles.count, 2)
        
        // Duplicates should be offset by 20 points right and 20 points down (negative Y in macOS coordinates)
        XCTAssertEqual(overlayView.lines[1].startPoint.x, 120)  // 100 + 20
        XCTAssertEqual(overlayView.lines[1].startPoint.y, 80)   // 100 - 20 (down is negative)
        XCTAssertEqual(overlayView.lines[1].endPoint.x, 220)    // 200 + 20
        XCTAssertEqual(overlayView.lines[1].endPoint.y, 180)    // 200 - 20
        
        XCTAssertEqual(overlayView.circles[1].startPoint.x, 320)  // 300 + 20
        XCTAssertEqual(overlayView.circles[1].startPoint.y, 280)  // 300 - 20
        XCTAssertEqual(overlayView.circles[1].endPoint.x, 420)    // 400 + 20
        XCTAssertEqual(overlayView.circles[1].endPoint.y, 380)    // 400 - 20
        
        // Should be in select mode with duplicated objects selected
        XCTAssertEqual(overlayView.currentTool, .select)
        XCTAssertEqual(overlayView.selectedObjects.count, 2)
        XCTAssertTrue(overlayView.selectedObjects.contains(.line(index: 1)))
        XCTAssertTrue(overlayView.selectedObjects.contains(.circle(index: 1)))
    }
    
    func testDuplicateWithoutSelection() {
        overlayView.currentTool = .select
        let initialLineCount = overlayView.lines.count
        
        // Duplicate without selecting anything
        overlayView.duplicateSelectedObjects()
        
        // Nothing should be duplicated
        XCTAssertEqual(overlayView.lines.count, initialLineCount)
    }
    
    func testCopyPasteMultipleObjects() {
        // Add multiple object types
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.rectangles.append(Rectangle(
            startPoint: NSPoint(x: 150, y: 150),
            endPoint: NSPoint(x: 250, y: 250),
            color: .green,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.textAnnotations.append(TextAnnotation(
            text: "Hello",
            position: NSPoint(x: 300, y: 300),
            color: .black,
            fontSize: defaultTextAnnotationFontSize
        ))
        
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.line(index: 0), .rectangle(index: 0), .text(index: 0)]
        
        // Copy
        overlayView.copySelectedObjects()
        
        // Verify clipboard has all 3 objects
        XCTAssertEqual(overlayView.clipboard.count, 3)

        // Verify each object type is in clipboard
        XCTAssertTrue(overlayView.clipboard.contains { if case .line = $0 { return true }; return false })
        XCTAssertTrue(overlayView.clipboard.contains { if case .rectangle = $0 { return true }; return false })
        XCTAssertTrue(overlayView.clipboard.contains { if case .text = $0 { return true }; return false })
    }
    
    func testCutAndPaste() {
        // Add objects
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.circles.append(Circle(
            startPoint: NSPoint(x: 300, y: 300),
            endPoint: NSPoint(x: 400, y: 400),
            color: .blue,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.line(index: 0), .circle(index: 0)]
        
        // Cut
        overlayView.cutSelectedObjects()
        
        // Objects should be removed
        XCTAssertEqual(overlayView.lines.count, 0)
        XCTAssertEqual(overlayView.circles.count, 0)
        
        // Clipboard should contain the cut objects
        XCTAssertEqual(overlayView.clipboard.count, 2)
    }
    
    func testCopyNotInSelectMode() {
        // Add object
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .pen  // Not in select mode
        
        // Try to copy (should do nothing since there's no selection)
        overlayView.copySelectedObjects()
        
        // Clipboard should be empty
        XCTAssertTrue(overlayView.clipboard.isEmpty)
    }
    
    func testDuplicateNotInSelectMode() {
        // Add object
        overlayView.lines.append(Line(
            startPoint: NSPoint(x: 100, y: 100),
            endPoint: NSPoint(x: 200, y: 200),
            color: .red,
            lineWidth: 2.0,
            creationTime: nil
        ))
        
        overlayView.currentTool = .pen  // Not in select mode
        
        // Try to duplicate (should do nothing)
        overlayView.duplicateSelectedObjects()
        
        // Should still have only 1 line
        XCTAssertEqual(overlayView.lines.count, 1)
    }

    func testTextSelectionClipboardPreservesBackgroundPill() {
        overlayView.textAnnotations = [
            TextAnnotation(
                text: "Label",
                position: NSPoint(x: 100, y: 100),
                color: .white,
                fontSize: 44,
                hasBackground: true,
                creationTime: 1.5)
        ]
        overlayView.currentTool = .select
        overlayView.selectedObjects = [.text(index: 0)]

        overlayView.copySelectedObjects()

        guard case .text(let copied)? = overlayView.clipboard.first else {
            return XCTFail("Clipboard should contain the selected text annotation")
        }
        XCTAssertTrue(copied.hasBackground)
        XCTAssertEqual(copied.creationTime, 1.5)
    }

    // MARK: - Text Resize Anchors

    private let longLabelText = "Wrapping needs several words before a line ever breaks"

    /// Places one label, selects it, and returns the box its anchors are drawn on.
    @discardableResult
    private func selectSingleLabel(text: String = "Label", fontSize: CGFloat = 24) -> NSRect {
        overlayView.currentTool = .select
        overlayView.textAnnotations = [
            TextAnnotation(
                text: text, position: NSPoint(x: 100, y: 100), color: .red, fontSize: fontSize)
        ]
        overlayView.selectedObjects = [.text(index: 0)]
        return overlayView.calculateSelectionBoundingBox()
    }

    func testSideHandlesHitTestByPositionAndOnlyForOneSelectedLabel() {
        let box = selectSingleLabel()

        XCTAssertEqual(overlayView.textResizeHandle(at: NSPoint(x: box.minX, y: box.midY)), .left)
        XCTAssertEqual(overlayView.textResizeHandle(at: NSPoint(x: box.maxX, y: box.midY)), .right)
        // No corner, top or bottom handles: font size stays on the size controls.
        XCTAssertNil(overlayView.textResizeHandle(at: NSPoint(x: box.minX, y: box.minY)))
        XCTAssertNil(overlayView.textResizeHandle(at: NSPoint(x: box.maxX, y: box.maxY)))
        XCTAssertNil(overlayView.textResizeHandle(at: NSPoint(x: box.midX, y: box.maxY)))
        XCTAssertNil(overlayView.textResizeHandle(at: NSPoint(x: box.midX, y: box.minY)))
        XCTAssertNil(overlayView.textResizeHandle(at: NSPoint(x: box.midX, y: box.midY)))

        // Nothing selected: no box to transform.
        overlayView.selectedObjects = []
        XCTAssertNil(overlayView.textResizeHandle(at: NSPoint(x: box.minX, y: box.midY)))

        // Two labels: a multi-selection has no single box either.
        _ = selectSingleLabel()
        overlayView.textAnnotations.append(
            TextAnnotation(
                text: "Other", position: NSPoint(x: 400, y: 400), color: .red, fontSize: 24))
        overlayView.selectedObjects = [.text(index: 0), .text(index: 1)]
        XCTAssertNil(overlayView.textResizeHandle(at: NSPoint(x: box.minX, y: box.midY)))
    }

    func testRightHandleChangesOnlyTheWidthAndKeepsTheTopLeftCorner() {
        let box = selectSingleLabel(text: longLabelText)

        overlayView.beginTextResize(.right)
        overlayView.updateTextResize(to: NSPoint(x: box.minX + 120, y: box.minY - 300))

        let label = overlayView.textAnnotations[0]
        XCTAssertEqual(label.fontSize, 24, "a side handle never scales the font")
        XCTAssertNotNil(label.wrapWidth)
        let resized = overlayView.calculateSelectionBoundingBox()
        XCTAssertEqual(resized.minX, box.minX, accuracy: 0.001)
        XCTAssertEqual(resized.maxX, box.minX + 120, accuracy: 0.001)
        XCTAssertEqual(resized.maxY, box.maxY, accuracy: 0.001, "the top edge stays put")
        XCTAssertGreaterThan(resized.height, box.height, "a narrower box wraps to more lines, downward")

        overlayView.endTextResize()
        XCTAssertNil(overlayView.resizeHandle)
        XCTAssertNil(overlayView.resizeStart)
    }

    func testLeftHandleKeepsTheRightEdgeAndTheTop() {
        let box = selectSingleLabel(text: longLabelText)

        overlayView.beginTextResize(.left)
        overlayView.updateTextResize(to: NSPoint(x: box.maxX - 150, y: box.midY))

        let resized = overlayView.calculateSelectionBoundingBox()
        XCTAssertEqual(resized.maxX, box.maxX, accuracy: 0.001)
        XCTAssertEqual(resized.minX, box.maxX - 150, accuracy: 0.001)
        XCTAssertEqual(resized.maxY, box.maxY, accuracy: 0.001)
        XCTAssertEqual(overlayView.textAnnotations[0].fontSize, 24)
        overlayView.endTextResize()
    }

    func testDraggingAHandlePastTheOtherSideStopsAtTheMinimumWidth() {
        let box = selectSingleLabel(text: longLabelText)

        overlayView.beginTextResize(.right)
        overlayView.updateTextResize(to: NSPoint(x: box.minX - 500, y: box.midY))

        XCTAssertEqual(
            overlayView.textAnnotations[0].wrapWidth ?? 0, TextAnnotation.minimumWrapWidth,
            accuracy: 0.001)
        XCTAssertEqual(overlayView.calculateSelectionBoundingBox().minX, box.minX, accuracy: 0.001)
        overlayView.endTextResize()
    }

    func testHandleResizeIsOneUndoStep() {
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = overlayView
        let undoManager = window.undoManager!
        let box = selectSingleLabel(text: longLabelText)
        let original = overlayView.textAnnotations[0]

        overlayView.beginTextResize(.right)
        overlayView.updateTextResize(to: NSPoint(x: box.minX + 200, y: box.midY))
        overlayView.updateTextResize(to: NSPoint(x: box.minX + 120, y: box.midY))
        overlayView.endTextResize()
        let resized = overlayView.textAnnotations[0]
        XCTAssertNotEqual(resized, original)

        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations[0], original)
        undoManager.redo()
        XCTAssertEqual(overlayView.textAnnotations[0], resized)
    }

    // MARK: - Resize history follows its label

    /// Attaches the view to a window with its own undo manager, one undo group per action.
    private func makeUndoWindow() -> (TestWindow, UndoManager) {
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = overlayView
        let undoManager = window.undoManager!
        undoManager.groupsByEvent = false
        return (window, undoManager)
    }

    private func asOneStep(_ undoManager: UndoManager, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    /// Three labels with the middle one selected.
    private func placeThreeLabelsSelectingTheMiddle() -> NSRect {
        overlayView.currentTool = .select
        overlayView.textAnnotations = ["Alpha", longLabelText, "Charlie"].enumerated().map {
            TextAnnotation(
                text: $0.element, position: NSPoint(x: 100, y: 400 - CGFloat($0.offset) * 120),
                color: .red, fontSize: 24)
        }
        overlayView.selectedObjects = [.text(index: 1)]
        return overlayView.calculateSelectionBoundingBox()
    }

    private func resizeSelectedLabel(from box: NSRect, by width: CGFloat) {
        overlayView.beginTextResize(.right)
        overlayView.updateTextResize(to: NSPoint(x: box.minX + width, y: box.midY))
        overlayView.endTextResize()
    }

    func testUndoingAResizeFindsItsLabelAfterTheListIsReordered() {
        let (window, undoManager) = makeUndoWindow()
        _ = window
        let box = placeThreeLabelsSelectingTheMiddle()
        let original = overlayView.textAnnotations
        asOneStep(undoManager) { resizeSelectedLabel(from: box, by: 120) }
        asOneStep(undoManager) {
            overlayView.selectedObjects = [.text(index: 0)]
            overlayView.deleteSelectedObjects()
        }

        // Undoing the delete puts Alpha back at the end: [B, C, A].
        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations.map(\.text), [longLabelText, "Charlie", "Alpha"])

        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations[0], original[1], "The resize undoes on its own label")
        XCTAssertEqual(overlayView.textAnnotations[1], original[2], "Charlie is untouched")
        XCTAssertEqual(overlayView.textAnnotations[2], original[0], "Alpha is untouched")
    }

    func testUndoingAFontSizeChangeFindsItsLabelAfterTheListIsReordered() {
        let (window, undoManager) = makeUndoWindow()
        _ = window
        _ = placeThreeLabelsSelectingTheMiddle()
        let original = overlayView.textAnnotations
        asOneStep(undoManager) { overlayView.setSelectedTextFontSize(44) }
        asOneStep(undoManager) {
            overlayView.selectedObjects = [.text(index: 0)]
            overlayView.deleteSelectedObjects()
        }

        undoManager.undo()
        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations[0], original[1])
        XCTAssertEqual(overlayView.textAnnotations[1], original[2])
        XCTAssertEqual(overlayView.textAnnotations[2], original[0])
    }

    func testUndoingAResizeFindsItsLabelAfterFadeCompaction() {
        let (window, undoManager) = makeUndoWindow()
        _ = window
        overlayView.fadeMode = true
        let box = placeThreeLabelsSelectingTheMiddle()
        let now = CACurrentMediaTime()
        for index in overlayView.textAnnotations.indices {
            overlayView.textAnnotations[index].creationTime = now
        }
        let original = overlayView.textAnnotations
        asOneStep(undoManager) { resizeSelectedLabel(from: box, by: 120) }

        // Alpha fades out after the resize was recorded.
        overlayView.textAnnotations[0].creationTime = now - overlayView.fadeDuration - 1
        overlayView.compactExpiredAnnotations()
        XCTAssertEqual(overlayView.textAnnotations.count, 2)

        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations, [original[1], original[2]])
    }

    func testRedoingAResizeFindsItsLabelAfterFadeCompaction() {
        let (window, undoManager) = makeUndoWindow()
        _ = window
        overlayView.fadeMode = true
        let box = placeThreeLabelsSelectingTheMiddle()
        let now = CACurrentMediaTime()
        for index in overlayView.textAnnotations.indices {
            overlayView.textAnnotations[index].creationTime = now
        }
        let charlie = overlayView.textAnnotations[2]
        asOneStep(undoManager) { resizeSelectedLabel(from: box, by: 120) }
        let resized = overlayView.textAnnotations[1]
        undoManager.undo()

        overlayView.textAnnotations[0].creationTime = now - overlayView.fadeDuration - 1
        overlayView.compactExpiredAnnotations()

        undoManager.redo()
        XCTAssertEqual(overlayView.textAnnotations, [resized, charlie])
    }

    func testUndoingAResizeOfALabelThatFadedAwayChangesNothing() {
        let (window, undoManager) = makeUndoWindow()
        _ = window
        overlayView.fadeMode = true
        let box = placeThreeLabelsSelectingTheMiddle()
        let now = CACurrentMediaTime()
        for index in overlayView.textAnnotations.indices {
            overlayView.textAnnotations[index].creationTime = now
        }
        asOneStep(undoManager) { resizeSelectedLabel(from: box, by: 120) }

        overlayView.textAnnotations[1].creationTime = now - overlayView.fadeDuration - 1
        overlayView.compactExpiredAnnotations()
        let survivors = overlayView.textAnnotations

        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations, survivors, "No other label takes its place")
    }

    func testAFontChangeMidResizeSticksAndUndoesInOrder() {
        let (window, undoManager) = makeUndoWindow()
        _ = window
        let box = placeThreeLabelsSelectingTheMiddle()
        let original = overlayView.textAnnotations[1]

        // The size control is used while the handle is still held.
        undoManager.beginUndoGrouping()
        overlayView.beginTextResize(.right)
        overlayView.updateTextResize(to: NSPoint(x: box.minX + 220, y: box.midY))
        let firstWidth = overlayView.textAnnotations[1].wrapWidth
        overlayView.setSelectedTextFontSize(44)
        undoManager.endUndoGrouping()
        let afterFont = overlayView.textAnnotations[1]
        XCTAssertEqual(afterFont.fontSize, 44)
        XCTAssertEqual(afterFont.wrapWidth, firstWidth)

        asOneStep(undoManager) {
            overlayView.updateTextResize(to: NSPoint(x: box.minX + 170, y: box.midY))
            overlayView.endTextResize()
        }
        let final = overlayView.textAnnotations[1]
        XCTAssertEqual(final.fontSize, 44, "The rest of the drag keeps the new size")
        XCTAssertNotEqual(final.wrapWidth, firstWidth, "and still changes the width")

        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations[1], afterFont)
        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations[1], original, "Two undos get back to the start")
        undoManager.redo()
        XCTAssertEqual(overlayView.textAnnotations[1], afterFont)
        undoManager.redo()
        XCTAssertEqual(overlayView.textAnnotations[1], final)
    }

    func testADuplicatedLabelIsItsOwnLabelForUndo() {
        let (window, undoManager) = makeUndoWindow()
        _ = window
        selectSingleLabel(text: longLabelText)
        asOneStep(undoManager) { overlayView.duplicateSelectedObjects() }
        XCTAssertEqual(overlayView.textAnnotations.count, 2)
        XCTAssertNotEqual(overlayView.textAnnotations[0].id, overlayView.textAnnotations[1].id)

        overlayView.selectedObjects = [.text(index: 1)]
        let original = overlayView.textAnnotations
        let box = overlayView.calculateSelectionBoundingBox()
        asOneStep(undoManager) { resizeSelectedLabel(from: box, by: 120) }
        undoManager.undo()
        XCTAssertEqual(overlayView.textAnnotations, original)
    }

    func testSetSelectedTextFontSizeChangesOnlyTheSelectedLabel() {
        overlayView.currentTool = .select
        overlayView.textAnnotations = [
            TextAnnotation(text: "One", position: NSPoint(x: 100, y: 100), color: .red, fontSize: 18),
            TextAnnotation(text: "Two", position: NSPoint(x: 300, y: 300), color: .red, fontSize: 18),
        ]
        overlayView.selectedObjects = [.text(index: 1)]

        overlayView.setSelectedTextFontSize(44)

        XCTAssertEqual(overlayView.textAnnotations[0].fontSize, 18)
        XCTAssertEqual(overlayView.textAnnotations[1].fontSize, 44)
    }

    func testSelectedLabelGrowsDownwardWhenItsFontSizeChanges() {
        selectSingleLabel(text: "Grow", fontSize: 18)
        let top = overlayView.textAnnotations[0].textTop
        let left = overlayView.textAnnotations[0].position.x

        overlayView.setSelectedTextFontSize(48)

        XCTAssertEqual(overlayView.textAnnotations[0].textTop, top, accuracy: 0.001)
        XCTAssertEqual(overlayView.textAnnotations[0].position.x, left)
        XCTAssertLessThan(overlayView.textAnnotations[0].position.y, 100)
    }

    // MARK: - Wrapped Text Boxes

    func testWrappingMakesTheBoxTallerInsteadOfWider() {
        let text = "Wrapping needs several words before a line ever breaks"
        let single = TextAnnotation(
            text: text, position: .zero, color: .red, fontSize: 24)
        let wrapped = TextAnnotation(
            text: text, position: .zero, color: .red, fontSize: 24, wrapWidth: 80)

        let singleBounds = single.bounds(fallbackInsets: OverlayView.plainLabelSlop)
        let wrappedBounds = wrapped.bounds(fallbackInsets: OverlayView.plainLabelSlop)

        // The wrapped box keeps the fixed width plus insets, and is taller because AppKit
        // has broken the same text into several lines.
        XCTAssertEqual(
            wrappedBounds.width,
            wrapped.textSize().width + OverlayView.plainLabelSlop.left
                + OverlayView.plainLabelSlop.right,
            accuracy: 0.001)
        XCTAssertLessThan(wrappedBounds.width, singleBounds.width)
        XCTAssertGreaterThan(wrappedBounds.height, singleBounds.height)
        XCTAssertEqual(wrapped.textSize().width, 80, accuracy: 0.001)
    }

    func testAHandleCannotWidenALabelPastWhatTheScreenAllows() {
        overlayView.currentTool = .select
        overlayView.textAnnotations = [
            TextAnnotation(
                text: longLabelText, position: NSPoint(x: 10, y: 300), color: .red, fontSize: 24)
        ]
        overlayView.selectedObjects = [.text(index: 0)]
        let box = overlayView.calculateSelectionBoundingBox()

        overlayView.beginTextResize(.right)
        overlayView.updateTextResize(to: NSPoint(x: overlayView.bounds.maxX, y: box.midY))
        overlayView.endTextResize()

        XCTAssertEqual(
            overlayView.textAnnotations[0].wrapWidth ?? 0, overlayView.maximumTextLayoutWidth,
            accuracy: 0.001)
        XCTAssertEqual(overlayView.calculateSelectionBoundingBox().minX, box.minX, accuracy: 0.001)
    }

    func testResizeFollowsItsLabelWhenAnOlderLabelFadesMidDrag() {
        overlayView.fadeMode = true
        let now = CACurrentMediaTime()
        let expired = now - overlayView.fadeDuration - 1
        overlayView.currentTool = .select
        overlayView.textAnnotations = [
            TextAnnotation(
                text: "Fading", position: NSPoint(x: 100, y: 400), color: .red, fontSize: 24,
                creationTime: expired),
            TextAnnotation(
                text: "Wrapping needs several words before a line ever breaks",
                position: NSPoint(x: 100, y: 300), color: .red, fontSize: 24,
                creationTime: now),
            TextAnnotation(
                text: "Bystander", position: NSPoint(x: 100, y: 100), color: .blue, fontSize: 24,
                creationTime: now),
        ]
        let bystander = overlayView.textAnnotations[2]
        overlayView.selectedObjects = [.text(index: 1)]
        let box = overlayView.calculateSelectionBoundingBox()

        overlayView.beginTextResize(.right)
        // The first label expires mid-drag, so everything after it shifts down a slot.
        overlayView.compactExpiredAnnotations()
        overlayView.updateTextResize(to: NSPoint(x: box.minX + 120, y: box.midY))
        overlayView.endTextResize()

        XCTAssertEqual(overlayView.textAnnotations.count, 2)
        XCTAssertEqual(
            overlayView.textAnnotations[0].text,
            "Wrapping needs several words before a line ever breaks")
        XCTAssertNotNil(overlayView.textAnnotations[0].wrapWidth, "the resize must land on its own label")
        XCTAssertEqual(overlayView.textAnnotations[1], bystander, "the label after it must be untouched")
    }

    func testLabelBeingResizedSurvivesItsOwnFade() {
        overlayView.fadeMode = true
        overlayView.currentTool = .select
        overlayView.textAnnotations = [
            TextAnnotation(
                text: "Wrapping needs several words before a line ever breaks",
                position: NSPoint(x: 100, y: 300), color: .red, fontSize: 24,
                creationTime: CACurrentMediaTime() - overlayView.fadeDuration - 1)
        ]
        overlayView.selectedObjects = [.text(index: 0)]
        let box = overlayView.calculateSelectionBoundingBox()

        overlayView.beginTextResize(.right)
        overlayView.compactExpiredAnnotations()
        overlayView.updateTextResize(to: NSPoint(x: box.minX + 120, y: box.midY))

        XCTAssertEqual(overlayView.textAnnotations.count, 1)
        XCTAssertNotNil(overlayView.textAnnotations[0].wrapWidth)
        overlayView.endTextResize()
    }
}
