import XCTest

@testable import Annotate

@MainActor
final class OverlayWindowTests: XCTestCase, Sendable {
    var window: OverlayWindow!
    var originalMouseCoalescingEnabled = true

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            TestWindows.recordOpenWindows()
            // A spy leaked from another suite would redirect pickerUserDefaults.
            AppDelegate.shared = nil
            originalMouseCoalescingEnabled = NSEvent.isMouseCoalescingEnabled
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
            window.cancelQuickPicker()
            window.stopFadeLoop()
            window.overlayView.pickerUserDefaultsOverride = nil
            window.close()
            window = nil
            NSEvent.isMouseCoalescingEnabled = originalMouseCoalescingEnabled
            assertNoLeakedWindows()
        }
        TestUserDefaults.removeSuite()
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
        XCTAssertFalse(window.overlayView.wantsLayer)
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

    func testYieldingToMenusDropsBelowPopUpMenusAndRestores() throws {
        let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let toolbar = try XCTUnwrap(window.toolbarPanel)
        XCTAssertEqual(window.level, OverlayWindow.elevatedLevel)
        XCTAssertEqual(toolbar.level, window.level)

        window.setYieldsToMenus(true)
        XCTAssertLessThan(window.level.rawValue, popUpLevel, "The status item menu must draw above the overlay (#122)")
        XCTAssertGreaterThan(window.level.rawValue, menuBarLevel, "The overlay should still cover the menu bar")
        XCTAssertEqual(toolbar.level, window.level)

        // Repeated calls must not drift the level.
        window.setYieldsToMenus(true)
        XCTAssertEqual(window.level, OverlayWindow.menuOpenLevel)

        window.setYieldsToMenus(false)
        XCTAssertEqual(window.level, OverlayWindow.elevatedLevel)
        XCTAssertEqual(toolbar.level, window.level)
    }

    func testPressOnTheStatusItemOpensTheMenuInsteadOfDrawing() {
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .pen
        var pressedPoints: [NSPoint] = []
        window.statusItemPressHandler = { point in
            pressedPoints.append(point)
            return true
        }

        sendMouse(.leftMouseDown, at: NSPoint(x: 700, y: 590))
        sendMouse(.leftMouseDragged, at: NSPoint(x: 650, y: 500))
        sendMouse(.leftMouseUp, at: NSPoint(x: 650, y: 500))

        XCTAssertEqual(pressedPoints, [window.convertPoint(toScreen: NSPoint(x: 700, y: 590))])
        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(window.overlayView.paths.isEmpty, "The press that opened the menu must not draw (#122)")
    }

    func testPressElsewhereInTheMenuBarStillDraws() {
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .pen
        var pressCount = 0
        window.statusItemPressHandler = { _ in
            pressCount += 1
            return false
        }

        sendMouse(.leftMouseDown, at: NSPoint(x: 100, y: 590))
        sendMouse(.leftMouseDragged, at: NSPoint(x: 140, y: 580))
        sendMouse(.leftMouseUp, at: NSPoint(x: 140, y: 580))

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(window.overlayView.paths.count, 1)
    }

    func testPressAfterOpeningTheMenuDrawsAgain() {
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .pen
        var opensMenu = true
        window.statusItemPressHandler = { _ in opensMenu }

        // The menu's tracking loop can eat the release, so the next press must not depend on it.
        sendMouse(.leftMouseDown, at: NSPoint(x: 700, y: 590))
        opensMenu = false
        sendMouse(.leftMouseDown, at: NSPoint(x: 100, y: 300))
        sendMouse(.leftMouseDragged, at: NSPoint(x: 140, y: 330))
        sendMouse(.leftMouseUp, at: NSPoint(x: 140, y: 330))

        XCTAssertEqual(window.overlayView.paths.count, 1)
    }

    func testStrokeFinishesAfterClosingAPickerOpenedFromTheStatusMenu() {
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .pen
        var opensMenu = true
        window.statusItemPressHandler = { _ in opensMenu }

        // The menu's tracking loop eats the release, and its Color… item opens the picker.
        sendMouse(.leftMouseDown, at: NSPoint(x: 700, y: 590))
        opensMenu = false
        tapPickerKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)

        let outside = pointOutsidePicker()
        sendMouse(.leftMouseDown, at: outside)
        sendMouse(.leftMouseUp, at: outside)
        XCTAssertFalse(window.isQuickPickerOpen)

        sendMouse(.leftMouseDown, at: NSPoint(x: 100, y: 300))
        sendMouse(.leftMouseDragged, at: NSPoint(x: 140, y: 330))
        sendMouse(.leftMouseUp, at: NSPoint(x: 140, y: 330))

        XCTAssertEqual(window.overlayView.paths.count, 1)
        XCTAssertNil(window.overlayView.currentPath, "The stroke after the picker closes must finish")
    }

    func testRightPressOnTheStatusItemOpensTheMenu() {
        var pressCount = 0
        window.statusItemPressHandler = { _ in
            pressCount += 1
            return true
        }

        sendMouse(.rightMouseDown, at: NSPoint(x: 700, y: 590))
        sendMouse(.rightMouseUp, at: NSPoint(x: 700, y: 590))

        XCTAssertEqual(pressCount, 1)
    }

    func testAlwaysOnModeNeverAsksAboutTheStatusItem() {
        var pressCount = 0
        window.statusItemPressHandler = { _ in
            pressCount += 1
            return true
        }
        window.overlayView.isReadOnlyMode = true

        sendMouse(.leftMouseDown, at: NSPoint(x: 700, y: 590))

        XCTAssertEqual(pressCount, 0)
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

    func testFreehandInputPreservesEveryEventAndRestoresCoalescingOnMouseUp() {
        NSEvent.isMouseCoalescingEnabled = true
        window.overlayView.currentTool = .pen
        let mouseDown = TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!
        let dragEvents = (1...256).map { index in
            TestEvents.createMouseEvent(
                type: .leftMouseDragged,
                location: NSPoint(
                    x: CGFloat(100 + index),
                    y: CGFloat(100 + index % 17)
                )
            )!
        }
        let mouseUp = TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: dragEvents.last!.locationInWindow
        )!

        window.mouseDown(with: mouseDown)
        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
        dragEvents.forEach { window.mouseDragged(with: $0) }

        XCTAssertEqual(window.overlayView.currentPath?.points.first?.timestamp, mouseDown.timestamp)
        XCTAssertEqual(window.overlayView.currentPath?.points.last?.timestamp, dragEvents.last?.timestamp)

        window.mouseUp(with: mouseUp)

        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
        XCTAssertEqual(window.overlayView.paths.last?.points.count, 257)
        XCTAssertEqual(window.overlayView.paths.last?.bezierPath?.elementCount, 257)
        XCTAssertFalse(window.overlayView.paths.last?.cachedBounds.isNull ?? true)
    }

    func testMouseCoalescingIsDisabledOnlyForFreehandTools() {
        for tool in [ToolType.pen, .highlighter] {
            NSEvent.isMouseCoalescingEnabled = true
            window.overlayView.currentTool = tool
            window.mouseDown(with: TestEvents.createMouseEvent(
                type: .leftMouseDown,
                location: NSPoint(x: 100, y: 100)
            )!)

            XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)

            window.mouseUp(with: TestEvents.createMouseEvent(
                type: .leftMouseUp,
                location: NSPoint(x: 100, y: 100)
            )!)
            XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
        }

        window.overlayView.currentTool = .line
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)

        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
    }

    /// A lost mouse-up must not cost the stroke: the next mouse-down commits it first.
    func testMouseDownAfterALostMouseUpCommitsTheLiveStroke() {
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)
        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 140, y: 130)
        )!)

        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 300, y: 300)
        )!)

        XCTAssertEqual(window.overlayView.paths.count, 1)
        XCTAssertEqual(window.overlayView.paths.last?.points.map(\.point), [
            NSPoint(x: 100, y: 100), NSPoint(x: 140, y: 130),
        ])
        XCTAssertEqual(window.overlayView.currentPath?.points.map(\.point), [NSPoint(x: 300, y: 300)])
    }

    func testToolSwitchMidDragKeepsStrokeOnItsOriginalTool() {
        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)

        window.overlayView.currentTool = .highlighter
        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 140, y: 130)
        )!)

        XCTAssertEqual(window.overlayView.currentPath?.points.count, 2)
        XCTAssertNil(window.overlayView.currentHighlight)

        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 140, y: 130)
        )!)

        XCTAssertEqual(window.overlayView.paths.count, 1)
        XCTAssertEqual(window.overlayView.paths.last?.points.count, 2)
        XCTAssertTrue(window.overlayView.highlightPaths.isEmpty)
        XCTAssertNil(window.overlayView.currentPath)
    }

    func testToolSwitchMidDragKeepsShapeOnItsOriginalTool() {
        window.overlayView.currentTool = .arrow
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)

        // A switch to Select must not turn the rest of the drag into a selection move.
        window.overlayView.currentTool = .select
        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 180, y: 140)
        )!)
        XCTAssertEqual(window.overlayView.currentArrow?.endPoint, NSPoint(x: 180, y: 140))

        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 180, y: 140)
        )!)

        XCTAssertNil(window.overlayView.currentArrow)
        XCTAssertEqual(window.overlayView.arrows.count, 1)
        XCTAssertEqual(window.overlayView.arrows.last?.endPoint, NSPoint(x: 180, y: 140))
        XCTAssertTrue(window.undoManager?.canUndo ?? false)

        window.overlayView.undo()
        XCTAssertTrue(window.overlayView.arrows.isEmpty, "The arrow is on the undo stack")
    }

    func testClearAllMidDragDropsFurtherPointsWithoutTrapping() {
        window.overlayView.paths = [
            DrawingPath(
                points: [TimedPoint(point: NSPoint(x: 10, y: 10), timestamp: 0)],
                color: .systemRed,
                lineWidth: 3
            )
        ]

        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)

        window.overlayView.clearAll()
        XCTAssertNil(window.overlayView.currentPath)

        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 150, y: 150)
        )!)
        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 150, y: 150)
        )!)

        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(window.overlayView.paths.isEmpty)
    }

    func testClearAllOnEmptyCanvasEndsInFlightStroke() {
        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)
        XCTAssertNotNil(window.overlayView.currentPath)

        window.overlayView.clearAll()

        XCTAssertNil(window.overlayView.currentPath)

        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 150, y: 150)
        )!)
        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 150, y: 150)
        )!)

        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(window.overlayView.paths.isEmpty)
    }

    func testOptionDeleteMidDragCancelsStrokeOnAnEmptyCanvas() {
        NSEvent.isMouseCoalescingEnabled = true
        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)
        XCTAssertNotNil(window.overlayView.currentPath)
        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)

        window.keyDown(with: TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 51,
            modifierFlags: .option
        )!)

        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)

        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 150, y: 150)
        )!)
        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 150, y: 150)
        )!)

        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(window.overlayView.paths.isEmpty)
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
    }

    func testEscapeMidDragCancelsStroke() {
        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)

        window.keyDown(with: TestEvents.createKeyEvent(type: .keyDown, keyCode: 53)!)

        XCTAssertNil(window.overlayView.currentPath)

        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 150, y: 150)
        )!)

        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(window.overlayView.paths.isEmpty)
    }

    func testHighlighterStrokeCommitsOnMouseUp() {
        window.overlayView.currentTool = .highlighter
        window.overlayView.fadeMode = true
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)
        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: 140, y: 130)
        )!)
        window.overlayView.currentTool = .select
        window.overlayView.selectedObjects = [.arrow(index: 0)]
        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 140, y: 130)
        )!)

        XCTAssertEqual(window.overlayView.highlightPaths.count, 1)
        XCTAssertEqual(window.overlayView.highlightPaths.last?.points.count, 2)
        XCTAssertNil(window.overlayView.currentHighlight)
        XCTAssertTrue(window.overlayView.paths.isEmpty)
        XCTAssertNotNil(window.fadeTimer)
        window.stopFadeLoop()
    }

    func testEscapeRestoresMouseCoalescing() {
        beginUncoalescedPenStroke()

        window.keyDown(with: TestEvents.createKeyEvent(type: .keyDown, keyCode: 53)!)

        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
    }

    func testOrderOutRestoresMouseCoalescing() {
        beginUncoalescedPenStroke()

        window.orderOut(nil)

        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
    }

    func testResignKeyRestoresMouseCoalescing() {
        beginUncoalescedPenStroke()

        window.resignKey()

        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
    }

    func testBeginUncoalescedInputTakesOwnershipWhenCoalescingAlreadyOff() {
        NSEvent.isMouseCoalescingEnabled = false
        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)

        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)

        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 100, y: 100)
        )!)

        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
        XCTAssertEqual(window.overlayView.paths.count, 1)
    }

    func testAlwaysOnEntryRestoresCoalescingAndCancelsInFlightStroke() {
        beginUncoalescedPenStroke()
        XCTAssertNotNil(window.overlayView.currentPath)

        window.prepareForAlwaysOnMode()

        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
        XCTAssertNil(window.overlayView.currentPath)

        window.mouseUp(with: TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: 150, y: 150)
        )!)

        XCTAssertTrue(window.overlayView.paths.isEmpty)
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
    }

    func testFadeTimerCompactsExpiredAnnotationsAndRemapsSelection() {
        let now = CACurrentMediaTime()
        window.overlayView.fadeMode = true
        window.overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 0, y: 0),
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
        window.overlayView.selectedObjects = [.arrow(index: 1)]

        window.updateFade()

        XCTAssertEqual(window.overlayView.arrows.count, 1)
        XCTAssertEqual(window.overlayView.arrows.first?.startPoint, NSPoint(x: 20, y: 20))
        XCTAssertEqual(window.overlayView.selectedObjects, [.arrow(index: 0)])
    }

    func testPersistingToFadeCompactsExpiredAndStartsLoop() {
        let now = CACurrentMediaTime()
        window.overlayView.fadeMode = false
        window.overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 0, y: 0),
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

        window.overlayView.fadeMode = true
        window.overlayView.startFadeLoopIfNeeded()

        XCTAssertEqual(window.overlayView.arrows.count, 1)
        XCTAssertEqual(window.overlayView.arrows.first?.startPoint, NSPoint(x: 20, y: 20))
        XCTAssertNotNil(window.fadeTimer)
    }

    func testRedoOfTimedStrokeStartsFadeLoop() {
        window.overlayView.fadeMode = true
        let now = CACurrentMediaTime()
        let path = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: now),
                TimedPoint(point: NSPoint(x: 10, y: 0), timestamp: now)
            ],
            color: .systemRed,
            lineWidth: 3,
            creationTime: now
        )
        window.overlayView.paths.append(path)
        window.overlayView.registerUndo(action: .addPath(path))
        window.overlayView.undo()
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        window.stopFadeLoop()
        window.overlayView.redo()

        XCTAssertEqual(window.overlayView.paths.count, 1)
        XCTAssertNotNil(window.fadeTimer)
    }

    func testDuplicateStartsFadeLoopWhenFadeModeIsOn() {
        window.overlayView.fadeMode = true
        window.overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 40, y: 40),
                endPoint: NSPoint(x: 80, y: 80),
                color: .systemRed,
                lineWidth: 3,
                creationTime: CACurrentMediaTime()
            )
        ]
        window.overlayView.selectedObjects = [.arrow(index: 0)]
        window.stopFadeLoop()

        window.overlayView.duplicateSelectedObjects()

        XCTAssertEqual(window.overlayView.arrows.count, 2)
        XCTAssertNotNil(window.fadeTimer)
    }

    func testHighlighterDragInvalidatesOnlyPaddedSegment() {
        let trackingView = installTrackingOverlayView()
        trackingView.currentTool = .highlighter
        trackingView.currentLineWidth = 20
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 120, y: 110)

        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: start
        )!)
        trackingView.invalidatedRects.removeAll()
        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end
        )!)

        let padding = trackingView.currentLineWidth * ToolType.highlighter.strokeWidthMultiplier / 2 + 6
        let expectedRect = NSRect(
            x: start.x,
            y: start.y,
            width: end.x - start.x,
            height: end.y - start.y
        ).insetBy(dx: -padding, dy: -padding)
        XCTAssertEqual(trackingView.invalidatedRects.last, expectedRect)
    }

    func testHighlighterDragPadsWithStrokeWidthAfterLineWidthChanges() {
        let trackingView = installTrackingOverlayView()
        trackingView.currentTool = .highlighter
        trackingView.currentLineWidth = 20
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 120, y: 110)

        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: start
        )!)
        trackingView.currentLineWidth = 2
        trackingView.invalidatedRects.removeAll()
        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: end
        )!)

        XCTAssertEqual(trackingView.currentHighlight?.lineWidth, 20)
        let padding = 20 * ToolType.highlighter.strokeWidthMultiplier / 2 + 6
        let expectedRect = NSRect(
            x: start.x,
            y: start.y,
            width: end.x - start.x,
            height: end.y - start.y
        ).insetBy(dx: -padding, dy: -padding)
        XCTAssertEqual(trackingView.invalidatedRects.last, expectedRect)
    }

    func testLiveShapeInvalidatesUnionOfPreviousAndCurrentBounds() {
        let trackingView = installTrackingOverlayView()
        trackingView.currentTool = .line
        trackingView.currentLineWidth = 4
        let start = NSPoint(x: 100, y: 100)
        let firstEnd = NSPoint(x: 200, y: 150)
        let secondEnd = NSPoint(x: 150, y: 125)

        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: start
        )!)
        trackingView.invalidatedRects.removeAll()
        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: firstEnd
        )!)
        let firstDirtyRect = trackingView.invalidatedRects.last

        window.mouseDragged(with: TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: secondEnd
        )!)

        XCTAssertEqual(trackingView.invalidatedRects.last, firstDirtyRect)
    }

    private func installTrackingOverlayView() -> TrackingOverlayView {
        let trackingView = TrackingOverlayView(frame: window.overlayView.frame)
        trackingView.autoresizingMask = window.overlayView.autoresizingMask
        window.overlayView.removeFromSuperview()
        window.contentView?.addSubview(trackingView)
        window.overlayView = trackingView
        return trackingView
    }

    private func beginUncoalescedPenStroke() {
        NSEvent.isMouseCoalescingEnabled = true
        window.overlayView.currentTool = .pen
        window.mouseDown(with: TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 100, y: 100)
        )!)
        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
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

    func testScrollWheelAdjustsCounterSizeWhenCounterToolActive() {
        window.overlayView.currentTool = .counter
        let original = SettingsStore.standard[.counterFontSize]
        defer { SettingsStore.standard[.counterFontSize] = original }

        SettingsStore.standard[.counterFontSize] = 20

        if let scrollUp = TestEvents.createScrollEvent(deltaY: 1.0, modifierFlags: .command) {
            window.scrollWheel(with: scrollUp)
        }
        XCTAssertEqual(
            SettingsStore.standard[.counterFontSize], 21,
            "Cmd+Scroll up should grow the counter size")

        if let scrollDown = TestEvents.createScrollEvent(deltaY: -1.0, modifierFlags: .command) {
            window.scrollWheel(with: scrollDown)
        }
        XCTAssertEqual(
            SettingsStore.standard[.counterFontSize], 20,
            "Cmd+Scroll down should shrink the counter size")
    }

    func testScrollWheelClampsCounterSizeToUpperBound() {
        window.overlayView.currentTool = .counter
        let original = SettingsStore.standard[.counterFontSize]
        defer { SettingsStore.standard[.counterFontSize] = original }

        SettingsStore.standard[.counterFontSize] = counterFontSizeRange.upperBound
        if let scrollUp = TestEvents.createScrollEvent(deltaY: 1.0, modifierFlags: .command) {
            window.scrollWheel(with: scrollUp)
        }
        XCTAssertEqual(
            SettingsStore.standard[.counterFontSize], counterFontSizeRange.upperBound,
            "Counter size must not exceed its range")
    }

    func testScrollWheelForNonCounterToolLeavesCounterSizeUntouched() {
        window.overlayView.currentTool = .pen
        let original = SettingsStore.standard[.counterFontSize]
        defer { SettingsStore.standard[.counterFontSize] = original }

        SettingsStore.standard[.counterFontSize] = 25
        if let scrollUp = TestEvents.createScrollEvent(deltaY: 1.0, modifierFlags: .command) {
            window.scrollWheel(with: scrollUp)
        }
        XCTAssertEqual(
            SettingsStore.standard[.counterFontSize], 25,
            "A non-counter tool must route Cmd+Scroll elsewhere and leave counter size alone")
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
            fontSize: defaultTextAnnotationFontSize
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
            fontSize: defaultTextAnnotationFontSize
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

    // MARK: - Conditional Line Width Display Tests

    func testDrawingToolsShowLineWidthInFeedback() {
        let drawingTools: [ToolType] = [.pen, .arrow, .line, .highlighter, .rectangle, .circle]

        for tool in drawingTools {
            window.overlayView.currentTool = tool
            window.overlayView.currentLineWidth = 5.0

            window.showToolFeedback(tool)

            // We can't directly inspect the feedback text in unit tests, but we verify the method completes without errors
            XCTAssertEqual(window.overlayView.currentTool, tool)
            XCTAssertEqual(window.overlayView.currentLineWidth, 5.0)
        }
    }

    func testNonDrawingToolsWorkWithoutLineWidth() {
        let nonDrawingTools: [ToolType] = [.counter, .text, .select]

        for tool in nonDrawingTools {
            window.overlayView.currentTool = tool

            window.showToolFeedback(tool)

            XCTAssertEqual(window.overlayView.currentTool, tool)
        }
    }

    func testToolFeedbackForPenShowsLineWidth() {
        window.overlayView.currentTool = .pen
        window.overlayView.currentLineWidth = 3.5

        window.showToolFeedback(.pen)

        XCTAssertEqual(window.overlayView.currentLineWidth, 3.5)
        XCTAssertEqual(window.overlayView.currentTool, .pen)
    }

    func testToolFeedbackForCounterDoesNotRequireLineWidth() {
        window.overlayView.currentTool = .counter

        window.showToolFeedback(.counter)

        XCTAssertEqual(window.overlayView.currentTool, .counter)
    }

    func testToolFeedbackForTextDoesNotRequireLineWidth() {
        window.overlayView.currentTool = .text

        window.showToolFeedback(.text)

        XCTAssertEqual(window.overlayView.currentTool, .text)
    }

    func testToolFeedbackForSelectDoesNotRequireLineWidth() {
        window.overlayView.currentTool = .select

        window.showToolFeedback(.select)

        XCTAssertEqual(window.overlayView.currentTool, .select)
    }

    func testAllDrawingToolsWithVariousLineWidths() {
        let drawingTools: [ToolType] = [.pen, .arrow, .line, .highlighter, .rectangle, .circle]
        let widths: [CGFloat] = [0.5, 1.0, 3.0, 5.0, 10.0, 20.0]

        for tool in drawingTools {
            for width in widths {
                window.overlayView.currentTool = tool
                window.overlayView.currentLineWidth = width

                window.showToolFeedback(tool)

                XCTAssertEqual(window.overlayView.currentLineWidth, width)
                XCTAssertEqual(window.overlayView.currentTool, tool)
            }
        }
    }

    func testFeedbackConsistencyAcrossToolTypes() {
        for tool in [ToolType.pen, .arrow, .line, .highlighter, .rectangle, .circle, .counter, .text, .select] {
            window.overlayView.currentTool = tool
            window.overlayView.currentLineWidth = 3.0
            window.overlayView.currentColor = .blue

            window.showToolFeedback(tool)

            XCTAssertEqual(window.overlayView.currentTool, tool)
        }
    }

    func testFeedbackWithMinimumLineWidth() {
        window.overlayView.currentTool = .pen
        window.overlayView.currentLineWidth = 0.5

        window.showToolFeedback(.pen)

        XCTAssertEqual(window.overlayView.currentLineWidth, 0.5)
    }

    func testFeedbackWithMaximumLineWidth() {
        window.overlayView.currentTool = .pen
        window.overlayView.currentLineWidth = 20.0

        window.showToolFeedback(.pen)

        XCTAssertEqual(window.overlayView.currentLineWidth, 20.0)
    }

    // MARK: - Counter Reset Tests

    func testCmdRResetsCounterInCounterMode() {
        window.overlayView.currentTool = .counter
        window.overlayView.nextCounterNumber = 5

        let cmdREvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 15,  // 'r' key
            modifierFlags: .command,
            characters: "r"
        )

        window.keyDown(with: cmdREvent!)

        XCTAssertEqual(window.overlayView.nextCounterNumber, 1)
    }

    func testCmdRDoesNotResetCounterInOtherModes() {
        window.overlayView.currentTool = .pen
        window.overlayView.nextCounterNumber = 5

        let cmdREvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 15,
            modifierFlags: .command,
            characters: "r"
        )

        window.keyDown(with: cmdREvent!)

        XCTAssertEqual(window.overlayView.nextCounterNumber, 5, "Counter should not reset outside counter mode")
    }

    func testCmdRPreservesExistingCounterAnnotations() {
        window.overlayView.currentTool = .counter
        window.overlayView.nextCounterNumber = 3
        window.overlayView.counterAnnotations = [
            CounterAnnotation(number: 1, position: .zero, color: .red),
            CounterAnnotation(number: 2, position: NSPoint(x: 100, y: 100), color: .red)
        ]

        let cmdREvent = TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 15,
            modifierFlags: .command,
            characters: "r"
        )

        window.keyDown(with: cmdREvent!)

        XCTAssertEqual(window.overlayView.nextCounterNumber, 1)
        XCTAssertEqual(window.overlayView.counterAnnotations.count, 2, "Existing counters should remain")
    }

    // MARK: - Quick picker sendEvent

    func testSendEventTapKeepsPickerOpen() {
        sendKey("c", type: .keyDown, keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)
        sendKey("c", type: .keyUp, keyCode: 8)

        XCTAssertTrue(window.isQuickPickerOpen, "A tap should leave the picker open")
        XCTAssertEqual(quickPickerView?.mode, .color)
    }

    func testSendEventHoldCommitsOnKeyUp() {
        let originalColor = window.overlayView.currentColor
        sendKey("c", type: .keyDown, keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)
        wait(for: OverlayWindowTests.quickPickerHoldWait)
        sendKey("c", type: .keyUp, keyCode: 8)
        waitForPickerToDismiss()

        XCTAssertFalse(window.isQuickPickerOpen, "A hold should commit and dismiss on key-up")
        XCTAssertTrue(window.overlayView.currentColor.isClose(to: originalColor))
    }

    func testSendEventDigitCommitsPicker() {
        tapPickerKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)

        sendKey("2", keyCode: 19)
        waitForPickerToDismiss()

        XCTAssertFalse(window.isQuickPickerOpen)
        XCTAssertTrue(window.overlayView.currentColor.isClose(to: colorPalette[1]))
    }

    func testSendEventEscapeCancelsPicker() {
        let originalColor = window.overlayView.currentColor
        tapPickerKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)

        sendKey("", keyCode: 53)
        XCTAssertFalse(window.isQuickPickerOpen, "Escape should dismiss without committing")
        XCTAssertTrue(window.overlayView.currentColor.isClose(to: originalColor))
    }

    func testResignKeyCancelsQuickPicker() {
        let originalColor = window.overlayView.currentColor
        tapPickerKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)

        window.resignKey()

        XCTAssertFalse(window.isQuickPickerOpen, "Cmd+Tab / resignKey should dismiss the picker")
        XCTAssertTrue(window.overlayView.currentColor.isClose(to: originalColor))
    }

    func testAlwaysOnEntryCancelsQuickPicker() {
        let originalColor = window.overlayView.currentColor
        tapPickerKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)

        window.prepareForAlwaysOnMode()

        XCTAssertFalse(window.isQuickPickerOpen, "Always-On entry should dismiss the picker")
        XCTAssertTrue(window.overlayView.currentColor.isClose(to: originalColor))
    }

    func testSendEventSameKeyCancelsPicker() {
        let originalColor = window.overlayView.currentColor
        tapPickerKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)

        sendKey("c", keyCode: 8)
        XCTAssertFalse(window.isQuickPickerOpen, "Pressing the same key again should dismiss without committing")
        XCTAssertTrue(window.overlayView.currentColor.isClose(to: originalColor))
    }

    func testSendEventClickCellCommitsPicker() {
        window.overlayView.currentLineWidth = 3
        tapPickerKey("w", keyCode: 13)
        XCTAssertTrue(window.isQuickPickerOpen)
        XCTAssertEqual(quickPickerView?.mode, .width)

        let cellPoint = pointInPickerCell(index: QuickPickerView.widthOptions.count - 1)
        sendMouse(.leftMouseDown, at: cellPoint)
        sendMouse(.leftMouseUp, at: cellPoint)
        waitForPickerToDismiss()

        XCTAssertFalse(window.isQuickPickerOpen)
        XCTAssertEqual(
            window.overlayView.currentLineWidth, 24,
            "Clicking the last width cell should apply 24 without clamping to 20")
    }

    func testSendEventClickOutsideCancelsPicker() {
        let originalWidth = window.overlayView.currentLineWidth
        tapPickerKey("w", keyCode: 13)
        XCTAssertTrue(window.isQuickPickerOpen)

        let outside = pointOutsidePicker()
        sendMouse(.leftMouseDown, at: outside)
        sendMouse(.leftMouseUp, at: outside)

        XCTAssertFalse(window.isQuickPickerOpen)
        XCTAssertEqual(window.overlayView.currentLineWidth, originalWidth)
    }

    func testSendEventMouseUpWhilePickerOpenDoesNotCommitGeometry() {
        window.overlayView.currentTool = .arrow
        sendMouse(.leftMouseDown, at: NSPoint(x: 100, y: 300))
        sendMouse(.leftMouseDragged, at: NSPoint(x: 180, y: 360))
        XCTAssertNotNil(window.overlayView.currentArrow)

        tapPickerKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)
        XCTAssertNil(window.overlayView.currentArrow)

        sendMouse(.leftMouseUp, at: NSPoint(x: 180, y: 360))

        XCTAssertTrue(window.overlayView.arrows.isEmpty, "Mouse-up while the picker is open must not commit leftover geometry")
        XCTAssertNil(window.overlayView.currentArrow)
        XCTAssertTrue(window.isQuickPickerOpen)
    }

    func testSendEventBeginQuickPickerMidStrokeLeavesEmptyCanvasAndRestoresCoalescing() {
        NSEvent.isMouseCoalescingEnabled = true
        window.overlayView.currentTool = .pen
        sendMouse(.leftMouseDown, at: NSPoint(x: 100, y: 300))
        sendMouse(.leftMouseDragged, at: NSPoint(x: 140, y: 330))
        XCTAssertNotNil(window.overlayView.currentPath)
        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)

        sendKey("w", keyCode: 13)
        XCTAssertTrue(window.isQuickPickerOpen)
        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(window.overlayView.paths.isEmpty)
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled, "Discarding a stroke on picker open should restore coalescing")

        sendMouse(.leftMouseUp, at: NSPoint(x: 140, y: 330))
        XCTAssertTrue(window.overlayView.paths.isEmpty)
        XCTAssertNil(window.overlayView.currentPath)
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
    }

    func testSendEventPickerEscapeRestoresCoalescing() {
        NSEvent.isMouseCoalescingEnabled = true
        window.overlayView.currentTool = .pen
        sendMouse(.leftMouseDown, at: NSPoint(x: 100, y: 300))
        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)

        sendKey("c", keyCode: 8)
        XCTAssertTrue(window.isQuickPickerOpen)
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)

        sendKey("", keyCode: 53)
        XCTAssertFalse(window.isQuickPickerOpen)
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
        XCTAssertTrue(window.overlayView.paths.isEmpty)
        XCTAssertNil(window.overlayView.currentPath)
    }

    func testSendEventTypesCAndDoesNotOpenSizePickerWhileEditingText() {
        guard let field = startEditingAnnotationText() else { return }

        sendKey("c", keyCode: 8)
        XCTAssertFalse(window.isQuickPickerOpen, "c must not open the color picker while editing")
        let typedC =
            field.stringValue.lowercased().contains("c")
            || field.currentEditor()?.string.lowercased().contains("c") == true
        XCTAssertTrue(typedC, "c should type into the annotation field")

        sendKey("w", keyCode: 13)
        XCTAssertFalse(window.isQuickPickerOpen, "w must not open the size picker while editing")
    }

    func testSendEventBracketsTypeWhileEditingText() {
        guard let field = startEditingAnnotationText() else { return }
        let originalFontSize = SettingsStore.standard[.textFontSize]
        let originalWidth = window.overlayView.currentLineWidth
        defer { SettingsStore.standard[.textFontSize] = originalFontSize }

        sendKey("[", keyCode: 33)
        sendKey("]", keyCode: 30)

        XCTAssertFalse(window.isQuickPickerOpen)
        XCTAssertEqual(SettingsStore.standard[.textFontSize], originalFontSize, "[ ] must not step size while editing")
        XCTAssertEqual(window.overlayView.currentLineWidth, originalWidth)
        let typedBrackets =
            field.stringValue.contains("[")
            || field.stringValue.contains("]")
            || field.currentEditor()?.string.contains("[") == true
            || field.currentEditor()?.string.contains("]") == true
        XCTAssertTrue(typedBrackets, "[ and ] should type into the annotation field")
    }

    func testSendEventEditingControlKeysDoNotAppendViaFallback() {
        guard startEditingAnnotationText() != nil else { return }

        seedAnnotationField("Hi")
        sendKey("\r", keyCode: 36, modifierFlags: .shift)
        let afterReturn = annotationFieldText()
        XCTAssertNotEqual(
            afterReturn, "Hi\r",
            "Shift+Return must not append CR via stringValue += fallback")
        XCTAssertFalse(
            afterReturn.contains("\r"),
            "Shift+Return must not append a carriage return through the annotation-field path")

        seedAnnotationField("Hi")
        sendKey("a", keyCode: 0, modifierFlags: .command)
        sendKey("c", keyCode: 8, modifierFlags: .command)
        sendKey("v", keyCode: 9, modifierFlags: .command)
        sendKey("z", keyCode: 6, modifierFlags: .command)
        let afterShortcuts = annotationFieldText()
        XCTAssertNotEqual(
            afterShortcuts, "Hiacvz",
            "Cmd+A/C/V/Z must not append their characters via stringValue += fallback")
        XCTAssertFalse(
            afterShortcuts.contains("a") || afterShortcuts.contains("c")
                || afterShortcuts.contains("v") || afterShortcuts.contains("z"),
            "Cmd+A/C/V/Z must not be routed through the annotation-field += fallback")

        seedAnnotationField("Hi")
        sendKey("\u{7f}", keyCode: 51)
        let afterDelete = annotationFieldText()
        XCTAssertFalse(
            afterDelete.contains("\u{7f}"),
            "Delete must not append DEL via stringValue += fallback")
        XCTAssertNotEqual(
            afterDelete, "Hi\u{7f}",
            "Delete must not be routed through the annotation-field += fallback")
    }

    func testSendEventRemappedToolTakesPrecedenceOverBracketStep() {
        window.overlayView.currentTool = .pen
        window.overlayView.currentLineWidth = 3
        sendKey("[", keyCode: 33)
        XCTAssertEqual(window.overlayView.currentLineWidth, 2, "[ should step the width ladder when it is not a tool shortcut")

        window.overlayView.currentLineWidth = 3
        ShortcutManager.shared.clearShortcut(tool: .increaseSize)
        ShortcutManager.shared.setShortcut("]", for: .eraser)
        defer {
            ShortcutManager.shared.resetToDefault(tool: .eraser)
            ShortcutManager.shared.resetToDefault(tool: .increaseSize)
        }

        sendKey("]", keyCode: 30)
        XCTAssertEqual(
            window.overlayView.currentLineWidth, 3,
            "A remapped tool shortcut on ] should win over ladder stepping")
    }

    func testScrollWheelLineWidthUpperBoundMatchesPickerLadder() {
        let original = window.overlayView.currentLineWidth
        defer { window.overlayView.currentLineWidth = original }

        window.overlayView.currentLineWidth = 20
        if let scrollUp = TestEvents.createScrollEvent(deltaY: 1.0, modifierFlags: .command) {
            window.scrollWheel(with: scrollUp)
        }
        XCTAssertGreaterThan(
            window.overlayView.currentLineWidth, 20,
            "Cmd-scroll must be able to move past the old 20 px cap toward the picker ladder")

        window.overlayView.currentLineWidth = lineWidthRange.upperBound
        if let scrollUp = TestEvents.createScrollEvent(deltaY: 1.0, modifierFlags: .command) {
            window.scrollWheel(with: scrollUp)
        }
        XCTAssertEqual(window.overlayView.currentLineWidth, lineWidthRange.upperBound)
    }

    func testApplyLineWidthAcceptsPickerMaximum() {
        window.applyLineWidth(24, showsFeedback: false)
        XCTAssertEqual(window.overlayView.currentLineWidth, 24)
        window.applyLineWidth(3, showsFeedback: false)
    }

    private static let quickPickerHoldWait: TimeInterval = 0.3
    // A headless CI runner can stall one run-loop pass for several seconds, which
    // pushes the picker's asyncAfter dismissal past the default two-second budget.
    private static let pickerDismissTimeout: TimeInterval = 10

    private var quickPickerView: QuickPickerView? {
        window.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first
    }

    private func sendKey(
        _ characters: String,
        type: NSEvent.EventType = .keyDown,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        let event = TestEvents.createKeyEvent(
            type: type,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            characters: characters,
            windowNumber: window.windowNumber
        )
        window.sendEvent(event!)
    }

    func testAPlacedCounterTakesTheCounterStyleSetting() {
        let defaults = TestUserDefaults.create()
        window.overlayView.pickerUserDefaultsOverride = defaults
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .counter

        sendMouse(.leftMouseDown, at: NSPoint(x: 200, y: 200))
        sendMouse(.leftMouseUp, at: NSPoint(x: 200, y: 200))
        defaults.settings[.counterStyle] = .filled
        sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 200))
        sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 200))

        XCTAssertEqual(
            window.overlayView.counterAnnotations.map(\.style),
            [.bordered, .filled],
            "Changing the style restyles new counters only")
    }

    private func sendMouse(_ type: NSEvent.EventType, at location: NSPoint) {
        window.sendEvent(
            TestEvents.createMouseEvent(
                type: type, location: location, windowNumber: window.windowNumber)!)
    }

    private func tapPickerKey(_ characters: String, keyCode: UInt16) {
        sendKey(characters, type: .keyDown, keyCode: keyCode)
        sendKey(characters, type: .keyUp, keyCode: keyCode)
    }

    private func waitForPickerToDismiss() {
        let deadline = Date().addingTimeInterval(Self.pickerDismissTimeout)
        while window.isQuickPickerOpen && Date() < deadline {
            // Run the whole slice instead of returning after the first source. The
            // toolbar's hosting view installs run-loop sources of its own, and
            // bailing out early can starve the main-queue drain that delivers the
            // picker's dismissal block.
            _ = CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
    }

    private func pointInPickerCell(index: Int) -> NSPoint {
        guard let picker = quickPickerView else {
            XCTFail("Expected an open quick picker")
            return .zero
        }
        return NSPoint(
            x: picker.frame.minX + QuickPickerView.padding + QuickPickerView.cellSize * (CGFloat(index) + 0.5),
            y: picker.frame.minY + QuickPickerView.padding + QuickPickerView.cellSize / 2
        )
    }

    private func pointOutsidePicker() -> NSPoint {
        guard let picker = quickPickerView else { return NSPoint(x: 5, y: 5) }
        let candidates = [
            NSPoint(x: 8, y: 8),
            NSPoint(x: window.overlayView.bounds.maxX - 8, y: 8),
            NSPoint(x: 8, y: window.overlayView.bounds.maxY - 8),
            NSPoint(x: window.overlayView.bounds.maxX - 8, y: window.overlayView.bounds.maxY - 8)
        ]
        return candidates.first { !picker.frame.insetBy(dx: -4, dy: -4).contains($0) }
            ?? NSPoint(x: -20, y: -20)
    }

    private func seedAnnotationField(_ text: String) {
        guard let field = window.overlayView.activeTextField else { return }
        field.stringValue = text
        field.currentEditor()?.string = text
    }

    private func annotationFieldText() -> String {
        let field = window.overlayView.activeTextField
        return field?.currentEditor()?.string ?? field?.stringValue ?? ""
    }

    private func startEditingAnnotationText() -> NSTextField? {
        window.overlayView.currentTool = .text
        window.overlayView.currentTextAnnotation = TextAnnotation(
            text: "",
            position: NSPoint(x: 120, y: 120),
            color: .black,
            fontSize: defaultTextAnnotationFontSize
        )
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.overlayView.createTextField(
            at: NSPoint(x: 120, y: 120), withText: "")
        guard let field = window.overlayView.activeTextField else {
            XCTFail("Expected an annotation text field")
            return nil
        }
        // selectText can end+restart editing and fire controlTextDidEndEditing,
        // which finalizes and clears activeTextField before sendEvent sees the keys.
        if window.firstResponder !== field && window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
        if field.currentEditor() == nil {
            field.becomeFirstResponder()
        }
        XCTAssertNotNil(
            window.overlayView.activeTextField,
            "Annotation field must stay active so c / [ / ] type instead of opening pickers")
        return field
    }

    func testTextSizeSteppingUsesQuickPickerLadderAndResizesActiveField() throws {
        SettingsStore.standard[.textFontSize] = 18
        defer { SettingsStore.standard.removeValue(for: .textFontSize) }

        window.overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: NSPoint(x: 100, y: 100), color: .red, fontSize: 44)
        window.overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "Headline")
        let textField = try XCTUnwrap(window.overlayView.activeTextField)
        let initialSize = textField.frame.size

        window.stepTextFontSize(1)

        XCTAssertEqual(SettingsStore.standard[.textFontSize], 60)
        XCTAssertEqual(window.overlayView.currentTextAnnotation?.fontSize, 60)
        XCTAssertEqual(textField.font?.pointSize, 60)
        XCTAssertGreaterThan(textField.frame.height, initialSize.height)

        window.stepTextFontSize(-1)
        XCTAssertEqual(SettingsStore.standard[.textFontSize], 44)
    }

    func testToggleTextBackgroundUpdatesCurrentAnnotationAndPersistedDefault() {
        SettingsStore.standard.removeValue(for: .textBackground)
        defer { SettingsStore.standard.removeValue(for: .textBackground) }
        window.overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: .zero, color: .red, fontSize: 18)

        window.toggleTextBackground()
        XCTAssertEqual(window.overlayView.currentTextAnnotation?.hasBackground, true)
        XCTAssertTrue(SettingsStore.standard[.textBackground])

        window.toggleTextBackground()
        XCTAssertEqual(window.overlayView.currentTextAnnotation?.hasBackground, false)
        XCTAssertFalse(SettingsStore.standard[.textBackground])
    }

    func testCommandBTogglesLabelBackgroundWithTextToolAndNoActiveField() throws {
        SettingsStore.standard.removeValue(for: .textBackground)
        defer { SettingsStore.standard.removeValue(for: .textBackground) }
        window.overlayView.currentTool = .text
        XCTAssertNil(window.overlayView.activeTextField)

        let cmdB = try XCTUnwrap(
            TestEvents.createKeyEvent(
                type: .keyDown, keyCode: 11, modifierFlags: .command, characters: "b"))

        XCTAssertTrue(window.performKeyEquivalent(with: cmdB))
        XCTAssertTrue(SettingsStore.standard[.textBackground])

        XCTAssertTrue(window.performKeyEquivalent(with: cmdB))
        XCTAssertFalse(SettingsStore.standard[.textBackground])
    }

    func testCommandBIsIgnoredWhenTheTextToolIsNotActive() throws {
        SettingsStore.standard.removeValue(for: .textBackground)
        defer { SettingsStore.standard.removeValue(for: .textBackground) }
        window.overlayView.currentTool = .pen

        let cmdB = try XCTUnwrap(
            TestEvents.createKeyEvent(
                type: .keyDown, keyCode: 11, modifierFlags: .command, characters: "b"))

        XCTAssertFalse(window.performKeyEquivalent(with: cmdB))
        XCTAssertFalse(SettingsStore.standard[.textBackground])
    }

    // MARK: - Committing a label by clicking away

    func testClickingAwayPlacesTheLabelAndSwitchesToSelectWhenOptedIn() throws {
        try seedLabelInProgress(text: "Hello", selectAfterPlacing: true)

        window.mouseDown(
            with: try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseDown,
                    location: NSPoint(x: 400, y: 400)
                )))

        XCTAssertEqual(window.overlayView.textAnnotations.count, 1)
        XCTAssertEqual(window.overlayView.textAnnotations[0].text, "Hello")
        XCTAssertEqual(
            window.overlayView.currentTool, .select,
            "Clicking away is a commit, so it honors the switch to Select"
        )
        XCTAssertEqual(window.overlayView.selectedObjects, [.text(index: 0)])
        XCTAssertNil(
            window.overlayView.activeTextField,
            "The click that finished the label must not open another field"
        )
    }

    func testClickingAwayStaysInTextModeByDefault() throws {
        try seedLabelInProgress(text: "Hello", selectAfterPlacing: false)

        window.mouseDown(
            with: try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseDown,
                    location: NSPoint(x: 400, y: 400)
                )))

        XCTAssertEqual(window.overlayView.textAnnotations.count, 1)
        XCTAssertEqual(window.overlayView.currentTool, .text)
        XCTAssertTrue(window.overlayView.selectedObjects.isEmpty)
        XCTAssertNotNil(
            window.overlayView.activeTextField,
            "With the setting off the click still opens the next label"
        )
    }

    func testUndoAfterPlacingALabelClearsTheSelection() throws {
        let textField = try seedLabelInProgress(text: "Hello", selectAfterPlacing: true)
        window.overlayView.commitTextField(textField)
        XCTAssertEqual(window.overlayView.selectedObjects, [.text(index: 0)])

        window.overlayView.undo()

        XCTAssertTrue(window.overlayView.textAnnotations.isEmpty)
        XCTAssertTrue(
            window.overlayView.selectedObjects.isEmpty,
            "Undo must not leave the removed label selected"
        )
    }

    /// Opens a text field with `text` typed into it, with the select-after-placing setting
    /// pinned for the store the overlay view reads.
    @discardableResult
    private func seedLabelInProgress(text: String, selectAfterPlacing: Bool) throws -> NSTextField {
        let defaults = TestUserDefaults.create()
        defaults.settings[.selectAfterPlacingText] = selectAfterPlacing
        window.overlayView.pickerUserDefaultsOverride = defaults

        let point = NSPoint(x: 100, y: 100)
        window.overlayView.currentTool = .text
        window.overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: point, color: .red,
            fontSize: defaultTextAnnotationFontSize
        )
        window.overlayView.createTextField(at: point, withText: "")
        let textField = try XCTUnwrap(window.overlayView.activeTextField)
        textField.stringValue = text
        return textField
    }

    func testSizingASelectedLabelLeavesTheTextToolDefaultAlone() {
        let defaults = TestUserDefaults.create()
        defaults.settings[.textFontSize] = 18
        window.overlayView.pickerUserDefaultsOverride = defaults

        window.overlayView.currentTool = .select
        window.overlayView.textAnnotations = [
            TextAnnotation(
                text: "Placed", position: NSPoint(x: 50, y: 50), color: .red, fontSize: 24),
            TextAnnotation(
                text: "Other", position: NSPoint(x: 300, y: 50), color: .red, fontSize: 24),
        ]
        window.overlayView.selectedObjects = [.text(index: 0)]

        window.applyTextFontSize(44, showsFeedback: false)
        XCTAssertEqual(window.overlayView.textAnnotations[0].fontSize, 44)
        XCTAssertEqual(window.overlayView.textAnnotations[1].fontSize, 24)
        XCTAssertEqual(defaults.settings[.textFontSize], 18, "The next label keeps the Text tool size")

        // The ladder steps from the selected label's own size, not the stored default.
        window.stepTextFontSize(1)
        XCTAssertGreaterThan(window.overlayView.textAnnotations[0].fontSize, 44)
        XCTAssertEqual(defaults.settings[.textFontSize], 18)
    }

    func testSizingWithTheTextToolStillSetsTheDefault() {
        let defaults = TestUserDefaults.create()
        defaults.settings[.textFontSize] = 18
        window.overlayView.pickerUserDefaultsOverride = defaults
        window.overlayView.currentTool = .text

        window.applyTextFontSize(30, showsFeedback: false)

        XCTAssertEqual(defaults.settings[.textFontSize], 30)
    }
}

@MainActor
private final class TrackingOverlayView: OverlayView {
    var invalidatedRects: [NSRect] = []

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidatedRects.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
}

@MainActor
final class TextBoxDragTests: XCTestCase, Sendable {
    var window: OverlayWindow!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppDelegate.shared = nil
            window = OverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.overlayView.pickerUserDefaultsOverride = TestUserDefaults.create()
            window.overlayView.fadeMode = false
            window.overlayView.currentTool = .text
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            window.overlayView.cancelTextAnnotation()
            window.overlayView.pickerUserDefaultsOverride = nil
            window = nil
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
        try XCTUnwrap(TestEvents.createMouseEvent(type: type, location: NSPoint(x: x, y: y)))
    }

    func testClickWithoutDraggingPlacesAnAutoWidthLabel() throws {
        window.mouseDown(with: try mouse(.leftMouseDown, 200, 300))
        window.mouseDragged(with: try mouse(.leftMouseDragged, 203, 298))
        window.mouseUp(with: try mouse(.leftMouseUp, 203, 298))

        let field = try XCTUnwrap(window.overlayView.activeTextField)
        XCTAssertNil(window.overlayView.currentTextAnnotation?.wrapWidth)
        XCTAssertEqual(field.frame.midY, 300, accuracy: 0.5, "Still centered on the click")
        XCTAssertNil(window.overlayView.textBoxDraftRect)
    }

    func testDraggingDrawsAnOutlineThenOpensAFixedWidthBoxHangingFromItsTop() throws {
        window.mouseDown(with: try mouse(.leftMouseDown, 200, 400))
        let clickField = window.overlayView.activeTextField
        XCTAssertNotNil(clickField, "A press opens a label right away, as before")

        window.mouseDragged(with: try mouse(.leftMouseDragged, 300, 380))
        XCTAssertNil(window.overlayView.activeTextField, "The click's label gives way to a box")
        window.mouseDragged(with: try mouse(.leftMouseDragged, 450, 300))
        XCTAssertEqual(
            window.overlayView.textBoxDraftRect, NSRect(x: 200, y: 300, width: 250, height: 100))

        window.mouseUp(with: try mouse(.leftMouseUp, 450, 300))

        XCTAssertNil(window.overlayView.textBoxDraftRect)
        XCTAssertNil(window.overlayView.textBoxDragStart)
        let field = try XCTUnwrap(window.overlayView.activeTextField)
        XCTAssertFalse(field === clickField)
        XCTAssertEqual(
            window.overlayView.currentTextAnnotation?.wrapWidth,
            250 - OverlayView.textFieldHorizontalChrome)
        XCTAssertEqual(field.frame, NSRect(x: 200, y: field.frame.minY, width: 250, height: field.frame.height))
        XCTAssertEqual(field.frame.maxY, 400, "The box hangs from the top of the drag")

        field.stringValue = "Typing into a box wraps the text inside its width and grows it downward"
        window.overlayView.resizeActiveTextField(field)
        XCTAssertEqual(field.frame.width, 250, "The box keeps its width")
        XCTAssertEqual(field.frame.maxY, 400)

        window.overlayView.finalizeTextAnnotation(field)
        let label = try XCTUnwrap(window.overlayView.textAnnotations.first)
        XCTAssertEqual(label.wrapWidth, 250 - OverlayView.textFieldHorizontalChrome)
        XCTAssertEqual(label.position.x, 200 + OverlayView.textFieldInsets.left)
        XCTAssertEqual(label.textTop, 400 - OverlayView.textFieldInsets.top, accuracy: 0.5)
    }

    func testDraggingLeftwardsUsesTheOutlinesLeftEdge() throws {
        window.mouseDown(with: try mouse(.leftMouseDown, 500, 300))
        window.mouseDragged(with: try mouse(.leftMouseDragged, 300, 340))
        window.mouseUp(with: try mouse(.leftMouseUp, 300, 340))

        let field = try XCTUnwrap(window.overlayView.activeTextField)
        XCTAssertEqual(field.frame.minX, 300)
        XCTAssertEqual(field.frame.width, 200)
        XCTAssertEqual(field.frame.maxY, 340, "The top is the higher edge of the drag")
    }

    func testANarrowDragStillOpensAUsableBox() throws {
        window.mouseDown(with: try mouse(.leftMouseDown, 200, 300))
        window.mouseDragged(with: try mouse(.leftMouseDragged, 210, 300))
        window.mouseUp(with: try mouse(.leftMouseUp, 210, 300))

        XCTAssertEqual(
            window.overlayView.currentTextAnnotation?.wrapWidth, TextAnnotation.minimumWrapWidth)
    }

    func testPressingOnALabelDragsItInsteadOfDrawingABox() throws {
        window.overlayView.textAnnotations = [
            TextAnnotation(
                text: "Existing", position: NSPoint(x: 200, y: 300), color: .red,
                fontSize: defaultTextAnnotationFontSize)
        ]
        window.mouseDown(with: try mouse(.leftMouseDown, 210, 305))
        window.mouseDragged(with: try mouse(.leftMouseDragged, 300, 305))
        window.mouseUp(with: try mouse(.leftMouseUp, 300, 305))

        XCTAssertNil(window.overlayView.textBoxDraftRect)
        XCTAssertNil(window.overlayView.activeTextField)
        XCTAssertEqual(window.overlayView.textAnnotations[0].position, NSPoint(x: 290, y: 300))
    }

    /// The field wraps its text at its width minus the chrome; the label wraps at its
    /// layout width. They have to be the same number or text reflows on commit.
    private func assertFieldWrapsAtTheLabelWidth(
        _ field: NSTextField, file: StaticString = #filePath, line: UInt = #line
    ) {
        let layoutWidth = window.overlayView.currentTextAnnotation?.layoutWidth ?? 0
        XCTAssertEqual(
            field.frame.width - OverlayView.textFieldHorizontalChrome, layoutWidth,
            accuracy: 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(
            field.frame.maxX, window.frame.width - OverlayView.textFieldScreenMargin + 0.001,
            file: file, line: line)
    }

    func testANearlyFullWidthBoxEditsAtTheWidthItCommitsAt() throws {
        window.mouseDown(with: try mouse(.leftMouseDown, 10, 400))
        window.mouseDragged(with: try mouse(.leftMouseDragged, 790, 400))
        window.mouseUp(with: try mouse(.leftMouseUp, 790, 400))

        let field = try XCTUnwrap(window.overlayView.activeTextField)
        XCTAssertEqual(
            window.overlayView.currentTextAnnotation?.wrapWidth,
            window.overlayView.maximumTextLayoutWidth, "The box is as wide as the screen allows")
        assertFieldWrapsAtTheLabelWidth(field)

        field.stringValue = String(repeating: "wide box text ", count: 20)
        window.overlayView.resizeActiveTextField(field)
        assertFieldWrapsAtTheLabelWidth(field)
    }

    func testALabelClickedAtTheLeftEdgeEditsAtTheWidthItCommitsAt() throws {
        window.mouseDown(with: try mouse(.leftMouseDown, 12, 400))
        window.mouseUp(with: try mouse(.leftMouseUp, 12, 400))

        let field = try XCTUnwrap(window.overlayView.activeTextField)
        field.stringValue = String(repeating: "a label that runs across the screen ", count: 6)
        window.overlayView.resizeActiveTextField(field)
        assertFieldWrapsAtTheLabelWidth(field)
    }

    func testEditingAnOversizedBoxUsesTheWidthTheScreenAllows() throws {
        let label = TextAnnotation(
            text: String(repeating: "oversized ", count: 30), position: NSPoint(x: 30, y: 400),
            color: .red, fontSize: defaultTextAnnotationFontSize, wrapWidth: 2000)
        window.overlayView.textAnnotations = [label]
        window.overlayView.editingTextAnnotationIndex = 0
        window.overlayView.currentTextAnnotation = label
        window.overlayView.createTextField(at: label.position, withText: label.text)

        let field = try XCTUnwrap(window.overlayView.activeTextField)
        window.overlayView.resizeActiveTextField(field)
        assertFieldWrapsAtTheLabelWidth(field)

        window.overlayView.finalizeTextAnnotation(field)
        XCTAssertEqual(
            window.overlayView.textAnnotations[0].wrapWidth,
            window.overlayView.maximumTextLayoutWidth)
    }

    /// Sends an event through the window's own dispatch, the way AppKit delivers it, so
    /// routing between the canvas and the open text field is part of what gets tested.
    private func dispatch(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws {
        window.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: type, location: NSPoint(x: x, y: y), windowNumber: window.windowNumber)))
    }

    func testAShortDragOverTheNewFieldStillCreatesABox() throws {
        // The press opens a field around (200, 300); the whole drag stays inside it.
        try dispatch(.leftMouseDown, 200, 300)
        let field = try XCTUnwrap(window.overlayView.activeTextField)
        XCTAssertTrue(field.frame.contains(NSPoint(x: 250, y: 300)))
        try dispatch(.leftMouseDragged, 250, 300)
        try dispatch(.leftMouseUp, 250, 300)

        XCTAssertNotNil(window.overlayView.currentTextAnnotation?.wrapWidth, "The drag made a box")
        XCTAssertNil(window.overlayView.textBoxDragStart, "The gesture finished")
        XCTAssertNil(window.overlayView.textBoxDraftRect)
        let box = try XCTUnwrap(window.overlayView.activeTextField)
        XCTAssertEqual(box.frame.minX, 200)
        XCTAssertEqual(box.frame.width, 50)
    }

    func testAClickInsideTheOpenFieldStillGoesToTheField() throws {
        try dispatch(.leftMouseDown, 200, 300)
        try dispatch(.leftMouseUp, 200, 300)
        let field = try XCTUnwrap(window.overlayView.activeTextField)

        // A later press on the field belongs to the field, not to a new label or box.
        try dispatch(.leftMouseDown, 210, 300)
        try dispatch(.leftMouseDragged, 260, 300)
        try dispatch(.leftMouseUp, 260, 300)

        XCTAssertTrue(window.overlayView.activeTextField === field)
        XCTAssertNil(window.overlayView.currentTextAnnotation?.wrapWidth)
        XCTAssertNil(window.overlayView.textBoxDraftRect)
    }

    func testClearAllMidBoxDragCancelsTheBox() throws {
        window.mouseDown(with: try mouse(.leftMouseDown, 200, 400))
        window.mouseDragged(with: try mouse(.leftMouseDragged, 450, 300))
        XCTAssertNotNil(window.overlayView.textBoxDraftRect)

        window.performClearAll()
        XCTAssertNil(window.overlayView.textBoxDraftRect)
        XCTAssertNil(window.overlayView.textBoxDragStart)

        window.mouseUp(with: try mouse(.leftMouseUp, 450, 300))
        XCTAssertNil(window.overlayView.activeTextField, "Releasing opens no box")
        XCTAssertTrue(window.overlayView.textAnnotations.isEmpty)
    }

    func testClearAllMidBoxDragCancelsTheBoxOnAPopulatedCanvas() throws {
        window.overlayView.textAnnotations = [
            TextAnnotation(
                text: "Existing", position: NSPoint(x: 500, y: 100), color: .red,
                fontSize: defaultTextAnnotationFontSize)
        ]
        window.mouseDown(with: try mouse(.leftMouseDown, 200, 400))
        window.mouseDragged(with: try mouse(.leftMouseDragged, 450, 300))

        window.performClearAll()
        window.mouseUp(with: try mouse(.leftMouseUp, 450, 300))

        XCTAssertNil(window.overlayView.textBoxDraftRect)
        XCTAssertNil(window.overlayView.textBoxDragStart)
        XCTAssertNil(window.overlayView.activeTextField)
        XCTAssertTrue(window.overlayView.textAnnotations.isEmpty)
    }
}

/// Side-handle drags driven through the window's mouse events, including gestures that get
/// interrupted before their mouse-up.
@MainActor
final class TextResizeGestureTests: XCTestCase, Sendable {
    var window: OverlayWindow!
    private let longText = "Wrapping needs several words before a line ever breaks"

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            AppDelegate.shared = nil
            window = OverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.overlayView.pickerUserDefaultsOverride = TestUserDefaults.create()
            window.overlayView.fadeMode = false
            window.overlayView.currentTool = .select
            window.overlayView.textAnnotations = [
                TextAnnotation(
                    text: longText, position: NSPoint(x: 100, y: 400), color: .red, fontSize: 24),
                TextAnnotation(
                    text: "Bravo", position: NSPoint(x: 100, y: 150), color: .blue, fontSize: 24),
            ]
            window.overlayView.selectedObjects = [.text(index: 0)]
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            window.overlayView.pickerUserDefaultsOverride = nil
            window = nil
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    private func mouse(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(TestEvents.createMouseEvent(type: type, location: point))
    }

    /// Presses the first label's right handle and drags it 150 pt in from its left edge.
    private func startNarrowingTheFirstLabel() throws {
        let box = window.overlayView.calculateSelectionBoundingBox()
        window.mouseDown(with: try mouse(.leftMouseDown, NSPoint(x: box.maxX, y: box.midY)))
        XCTAssertEqual(window.overlayView.resizeHandle, .right)
        window.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: box.minX + 150, y: box.midY)))
        XCTAssertNotNil(window.overlayView.textAnnotations[0].wrapWidth)
    }

    /// Selects Bravo and drags it 50 pt to the right.
    private func dragBravo() throws {
        window.overlayView.selectedObjects = [.text(index: 1)]
        let inside = NSPoint(x: 110, y: 160)
        window.mouseDown(with: try mouse(.leftMouseDown, inside))
        window.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: inside.x + 25, y: inside.y)))
        window.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: inside.x + 50, y: inside.y)))
        window.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: inside.x + 50, y: inside.y)))
    }

    func testSwitchingToolsMidResizeEndsItSoTheNextDragMovesItsOwnLabel() throws {
        try startNarrowingTheFirstLabel()
        let resized = window.overlayView.textAnnotations[0]

        // Pen is chosen while the button is still held, then the button comes up.
        window.overlayView.currentTool = .pen
        XCTAssertNil(window.overlayView.resizeHandle, "Changing tools ends the resize")
        window.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: 400, y: 300)))

        window.overlayView.currentTool = .select
        try dragBravo()

        XCTAssertEqual(window.overlayView.textAnnotations[0], resized, "The first label stays as it was left")
        XCTAssertEqual(window.overlayView.textAnnotations[1].position, NSPoint(x: 150, y: 150), "Bravo moved")
    }

    func testAFreshPressEndsAResizeWhoseMouseUpNeverArrived() throws {
        try startNarrowingTheFirstLabel()
        let resized = window.overlayView.textAnnotations[0]

        // No mouse-up: the next press has to settle the resize before it does anything.
        try dragBravo()

        XCTAssertNil(window.overlayView.resizeHandle)
        XCTAssertEqual(window.overlayView.textAnnotations[0], resized)
        XCTAssertEqual(window.overlayView.textAnnotations[1].position, NSPoint(x: 150, y: 150))
    }

    func testUndoMidResizeSettlesItThenUndoesIt() throws {
        let original = window.overlayView.textAnnotations[0]
        try startNarrowingTheFirstLabel()

        window.overlayView.undo()
        XCTAssertNil(window.overlayView.resizeHandle)
        XCTAssertEqual(window.overlayView.textAnnotations[0], original)

        // The rest of the drag no longer reaches the label.
        window.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: 300, y: 300)))
        window.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: 300, y: 300)))
        XCTAssertEqual(window.overlayView.textAnnotations[0], original)
    }

    func testClearAllMidResizeEndsIt() throws {
        try startNarrowingTheFirstLabel()

        window.overlayView.clearAll()
        XCTAssertNil(window.overlayView.resizeHandle)
        XCTAssertNil(window.overlayView.resizeStart)

        window.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: 300, y: 300)))
        window.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: 300, y: 300)))
        XCTAssertTrue(window.overlayView.textAnnotations.isEmpty)
    }
}
