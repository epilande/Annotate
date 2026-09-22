import SwiftUI
import XCTest

@testable import Annotate

@MainActor
final class ToolbarTests: XCTestCase {
    private var defaults: UserDefaults!
    private var appDelegate: AppDelegate!
    private var window: OverlayWindow!
    private var installedStatusItem = false

    override func setUp() {
        super.setUp()
        defaults = TestUserDefaults.create()
        appDelegate = AppDelegate(userDefaults: defaults)
        AppDelegate.shared = appDelegate
        ShortcutManager.shared = ShortcutManager(userDefaults: defaults)
        window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView?.layoutSubtreeIfNeeded()
    }

    override func tearDown() {
        if installedStatusItem {
            NSStatusBar.system.removeStatusItem(appDelegate.statusItem)
        }
        window.close()
        window = nil
        AppDelegate.shared = nil
        appDelegate = nil
        ShortcutManager.shared = ShortcutManager()
        TestUserDefaults.removeSuite()
        defaults = nil
        super.tearDown()
    }

    func testToolbarUsesRequiredPersistenceKeyAndIsVisibleByDefault() {
        XCTAssertEqual(UserDefaults.toolbarVisibleKey, "ToolbarVisible")
        XCTAssertTrue(appDelegate.toolbarVisible)
        XCTAssertTrue(window.toolbarPanel?.isAttached ?? false)
        XCTAssertFalse(window.toolbarFrame.isEmpty)
        XCTAssertEqual(window.toolbarFrame.minY, 20, accuracy: 0.5)
        XCTAssertEqual(
            window.toolbarFrame.midX, window.frame.width / 2, accuracy: 0.5,
            "With nothing stored the bar keeps its historic bottom-center resting place")
        XCTAssertNil(
            defaults.object(forKey: UserDefaults.toolbarPositionsKey),
            "Placing the bar at its default must not be recorded as the user parking it there")
    }

    func testToolbarLivesInANonKeyChildPanelOfTheOverlay() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)

        XCTAssertTrue(panel.parent === window)
        XCTAssertTrue(window.childWindows?.contains { $0 === panel } ?? false)
        XCTAssertFalse(
            panel.canBecomeKey,
            "A key toolbar would steal the keystrokes that belong to the canvas")
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(
            panel.isMovableByWindowBackground,
            "Dragging the bar is AppKit's job, not the overlay's")
        XCTAssertEqual(panel.level, window.level)
        // AppKit adds bits of its own once the panel is a child, so check what we asked for.
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
    }

    func testConstrainFrameRectKeepsTheBarInsideTheOverlay() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        let size = panel.frame.size

        let clamped = panel.constrainFrameRect(
            NSRect(origin: NSPoint(x: 5_000, y: -400), size: size), to: nil)

        XCTAssertEqual(clamped.size, size, "Clamping moves the bar, it never resizes it")
        XCTAssertEqual(clamped.maxX, window.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(clamped.minY, window.frame.minY, accuracy: 0.5)
    }

    func testAUserMoveIsStoredAsAnOffsetKeyedByDisplay() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        let key = try XCTUnwrap(ToolbarPanel.displayKey(for: window))

        panel.setFrameOrigin(NSPoint(x: window.frame.minX + 140, y: window.frame.minY + 500))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)

        let stored = try XCTUnwrap(
            defaults.dictionary(forKey: UserDefaults.toolbarPositionsKey)?[key] as? [Double],
            "The bar's offset must be stored under this display's number")
        XCTAssertEqual(
            stored, [140, 500],
            "An offset, not a screen coordinate, so it survives a resolution change")
    }

    func testADragWritesOnceAtTheEndRatherThanOnEveryFrame() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        let key = try XCTUnwrap(ToolbarPanel.displayKey(for: window))
        // Below the bar in the panel's own coordinates, so the synthetic press cannot reach
        // the hosting view and start a real drag. Only the panel's event bookkeeping runs.
        let miss = NSPoint(x: panel.frame.width / 2, y: -50)

        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseDown, location: miss, windowNumber: panel.windowNumber)))

        panel.setFrameOrigin(NSPoint(x: window.frame.minX + 100, y: window.frame.minY + 300))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)
        panel.setFrameOrigin(NSPoint(x: window.frame.minX + 200, y: window.frame.minY + 350))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)

        XCTAssertNil(
            defaults.object(forKey: UserDefaults.toolbarPositionsKey),
            "A drag reports a move per frame; none of them is worth a write of its own")

        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseUp, location: miss, windowNumber: panel.windowNumber)))

        let stored = try XCTUnwrap(
            defaults.dictionary(forKey: UserDefaults.toolbarPositionsKey)?[key] as? [Double],
            "Letting go of the bar is what records where the user parked it")
        XCTAssertEqual(stored, [200, 350])
    }

    func testADragDoesNotChangeTheToolEvenWhenThePointerStaysOnTheChip() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        let host = try XCTUnwrap(panel.hostingView)
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy
        defer { AppDelegate.shared = appDelegate }

        // Same miss as the persistence drag test: inside-panel coordinates would reach the
        // hosting view and start a real performDrag. The bookkeeping is what we need here.
        let miss = NSPoint(x: panel.frame.width / 2, y: -50)
        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseDown, location: miss, windowNumber: panel.windowNumber)))

        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x + 80, y: origin.y + 50))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)

        XCTAssertTrue(
            panel.isSuppressingChipAction,
            "The bar moved with the press; a chip mouse-up must not count as choosing a tool")
        host.rootView.perform(.tool(.highlighter))
        XCTAssertNil(
            spy.selectedTool,
            "A drag that started on a chip must not switch tools — the chip rides with the pointer")

        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseUp, location: miss, windowNumber: panel.windowNumber)))

        XCTAssertFalse(panel.isSuppressingChipAction)
        host.rootView.perform(.tool(.highlighter))
        XCTAssertEqual(
            spy.selectedTool, .highlighter,
            "A chip click after the drag has ended must still switch tools")
    }

    func testPointerTravelPastTheThresholdSuppressesTheChipWithoutMovingTheBar() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        let host = try XCTUnwrap(panel.hostingView)
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy
        defer { AppDelegate.shared = appDelegate }

        let start = NSPoint(x: panel.frame.width / 2, y: -50)
        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseDown, location: start, windowNumber: panel.windowNumber)))
        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseDragged,
                    location: NSPoint(x: start.x + ToolbarPress.dragThreshold + 1, y: start.y),
                    windowNumber: panel.windowNumber)))

        XCTAssertTrue(
            panel.isSuppressingChipAction,
            "A clamped bar that cannot follow the pointer still has to treat this as a drag")
        host.rootView.perform(.tool(.rectangle))
        XCTAssertNil(spy.selectedTool)
    }

    func testAChipClickWithoutADragStillChangesTheTool() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        let host = try XCTUnwrap(panel.hostingView)
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy
        defer { AppDelegate.shared = appDelegate }

        let miss = NSPoint(x: panel.frame.width / 2, y: -50)
        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseDown, location: miss, windowNumber: panel.windowNumber)))
        panel.sendEvent(
            try XCTUnwrap(
                TestEvents.createMouseEvent(
                    type: .leftMouseUp, location: miss, windowNumber: panel.windowNumber)))

        XCTAssertFalse(panel.isSuppressingChipAction)
        host.rootView.perform(.tool(.arrow))
        XCTAssertEqual(spy.selectedTool, .arrow)
    }

    func testAStoredPositionIsRestoredOnAFreshOverlayForTheSameDisplay() throws {
        let key = try XCTUnwrap(ToolbarPanel.displayKey(for: window))
        defaults.set([key: [140.0, 500.0]], forKey: UserDefaults.toolbarPositionsKey)

        let reopened = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { reopened.close() }

        XCTAssertEqual(reopened.toolbarFrame.minX, 140, accuracy: 0.5)
        XCTAssertEqual(reopened.toolbarFrame.minY, 500, accuracy: 0.5)
    }

    func testMovingTheOverlayDoesNotPersistAPositionTheUserNeverChose() throws {
        window.setFrame(NSRect(x: 0, y: 0, width: 1_000, height: 700), display: false)

        XCTAssertNil(
            defaults.object(forKey: UserDefaults.toolbarPositionsKey),
            "Resizing the overlay carries the bar along with it; that is not the user parking it")
        XCTAssertEqual(window.toolbarFrame.minY, 20, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(window.toolbarFrame.minX, 0)
        XCTAssertLessThanOrEqual(
            window.toolbarFrame.maxX, 1_000,
            "A narrower overlay has to pull the bar back inside it")
    }

    func testAToolbarActionDismissesAnOpenQuickPicker() {
        window.performToolbarAction(.colorPicker)
        XCTAssertTrue(window.isQuickPickerOpen)

        window.performToolbarAction(.tool(.pen))

        XCTAssertFalse(
            window.isQuickPickerOpen,
            "A click on the bar no longer reaches the canvas, so the action has to close the picker")
    }

    func testASavedPositionOutsideTheOverlayIsClampedBackIn() throws {
        let key = try XCTUnwrap(ToolbarPanel.displayKey(for: window))
        defaults.set([key: [10_000.0, 10_000.0]], forKey: UserDefaults.toolbarPositionsKey)

        let reopened = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { reopened.close() }

        XCTAssertEqual(reopened.toolbarFrame.maxX, 1_200, accuracy: 0.5)
        XCTAssertEqual(reopened.toolbarFrame.maxY, 800, accuracy: 0.5)
    }

    func testReShowingTheBarAfterAResizeRestoresTheSavedOffset() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        appDelegate.overlayWindows[screen] = window
        let key = try XCTUnwrap(ToolbarPanel.displayKey(for: window))
        defaults.set([key: [20.0, 300.0]], forKey: UserDefaults.toolbarPositionsKey)

        appDelegate.setToolbarVisible(false)
        window.setFrame(NSRect(x: 0, y: 0, width: 1_000, height: 700), display: false)
        appDelegate.setToolbarVisible(true)

        XCTAssertEqual(
            window.toolbarFrame.minX, 20, accuracy: 0.5,
            "A hidden bar is not carried along by the overlay, so showing it has to place it "
                + "from the saved offset rather than from wherever it was left")
        XCTAssertEqual(window.toolbarFrame.minY, 300, accuracy: 0.5)
    }

    func testAnUnreadableSavedPositionFallsBackToTheDefaultPlacement() throws {
        let key = try XCTUnwrap(ToolbarPanel.displayKey(for: window))
        defaults.set([key: ["nonsense"]], forKey: UserDefaults.toolbarPositionsKey)

        let reopened = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { reopened.close() }

        XCTAssertEqual(reopened.toolbarFrame.minY, 20, accuracy: 0.5)
        XCTAssertEqual(reopened.toolbarFrame.midX, 600, accuracy: 0.5)
    }

    func testABarWithNoAppBehindItNeitherReadsNorWritesTheStandardSuite() throws {
        let key = try XCTUnwrap(ToolbarPanel.displayKey(for: window))
        let standard = UserDefaults.standard
        let saved = standard.object(forKey: UserDefaults.toolbarPositionsKey)
        defer {
            if let saved {
                standard.set(saved, forKey: UserDefaults.toolbarPositionsKey)
            } else {
                standard.removeObject(forKey: UserDefaults.toolbarPositionsKey)
            }
            AppDelegate.shared = appDelegate
        }

        let planted = [key: [140.0, 500.0]]
        standard.set(planted, forKey: UserDefaults.toolbarPositionsKey)
        AppDelegate.shared = nil

        let detachedFromAnyApp = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { detachedFromAnyApp.close() }
        // Whether the bar starts attached is read from a suite this test does not own, so ask
        // for it rather than assuming it. Attaching is also what places it from a saved offset.
        let panel = try XCTUnwrap(detachedFromAnyApp.toolbarPanel)
        panel.attach(to: detachedFromAnyApp)

        XCTAssertEqual(
            detachedFromAnyApp.toolbarFrame.minY, 20, accuracy: 0.5,
            "With no app behind it the bar has no stored position to honor, so it takes the "
                + "default placement rather than the developer's own")
        XCTAssertEqual(detachedFromAnyApp.toolbarFrame.midX, 600, accuracy: 0.5)

        panel.setFrameOrigin(NSPoint(x: 300, y: 400))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)

        XCTAssertEqual(
            standard.dictionary(forKey: UserDefaults.toolbarPositionsKey)?[key] as? [Double],
            [140, 500],
            "A bar with no user behind it must not rewrite the developer's own suite")
    }

    func testVisibilityPersistsAndUpdatesEveryOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        appDelegate.overlayWindows[screen] = window

        appDelegate.setToolbarVisible(false)

        XCTAssertEqual(defaults.object(forKey: UserDefaults.toolbarVisibleKey) as? Bool, false)
        XCTAssertFalse(
            window.toolbarPanel?.isAttached ?? true,
            "A hidden bar leaves the overlay's window group; a hidden view would still be clickable")
        XCTAssertFalse(window.toolbarPanel?.isVisible ?? true)
        XCTAssertTrue(window.toolbarFrame.isEmpty)
        XCTAssertEqual(window.toolbarClearance, 0)
        XCTAssertEqual(window.feedbackBottomPadding, 20)

        appDelegate.setToolbarVisible(true)

        XCTAssertTrue(window.toolbarPanel?.isAttached ?? false)
        XCTAssertGreaterThan(window.toolbarClearance, 20)
        XCTAssertEqual(window.feedbackBottomPadding, window.toolbarClearance + 8)
    }

    func testStatusMenuToolbarToggleFlipsItsTitle() throws {
        appDelegate.setupStatusBarItem()
        installedStatusItem = true

        let item = try XCTUnwrap(
            appDelegate.statusItem.menu?.items.first {
                $0.action == #selector(AppDelegate.toggleToolbar)
            }
        )
        XCTAssertEqual(item.title, "Hide Toolbar")
        XCTAssertEqual(item.keyEquivalent, "t")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option])

        appDelegate.setToolbarVisible(false)
        XCTAssertEqual(item.title, "Show Toolbar")

        appDelegate.setToolbarVisible(true)
        XCTAssertEqual(item.title, "Hide Toolbar")
    }

    func testToolbarModelTracksLiveOverlayStateAndShortcutChanges() throws {
        window.overlayView.currentTool = .highlighter
        window.overlayView.currentColor = .systemBlue
        window.overlayView.currentLineWidth = 16
        window.overlayView.fadeMode = false

        XCTAssertEqual(window.toolbarModel.activeTool, .highlighter)
        XCTAssertTrue(window.toolbarModel.currentColor.isClose(to: .systemBlue))
        XCTAssertEqual(window.toolbarModel.currentWidth, 16)
        XCTAssertFalse(window.toolbarModel.fadeMode)

        XCTAssertEqual(window.toolbarModel.shortcuts[.pen], ShortcutKey.pen.defaultKey)

        ShortcutManager.shared.setShortcut("g", for: .pen)
        XCTAssertEqual(
            window.toolbarModel.shortcuts[.pen], "g",
            "The toolbar snapshot must refresh on .shortcutsDidChange")
    }

    func testWidthChipSizeFollowsCanonicalWidthLadder() {
        window.toolbarModel.currentWidth = QuickPickerView.widthOptions.first!
        let smallest = window.toolbarModel.widthDotDiameter
        window.toolbarModel.currentWidth = QuickPickerView.widthOptions.last!
        let largest = window.toolbarModel.widthDotDiameter

        XCTAssertEqual(smallest, 4)
        XCTAssertEqual(largest, 14)
        XCTAssertGreaterThan(largest, smallest)
    }

    func testToolbarActionsUseExistingToolFadePickerAndCanvasAuthorities() {
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy

        window.performToolbarAction(.tool(.rectangle))
        window.performToolbarAction(.toggleFade)
        XCTAssertEqual(spy.selectedTool, .rectangle)
        XCTAssertTrue(spy.didToggleFade)

        window.performToolbarAction(.colorPicker)
        XCTAssertTrue(window.isQuickPickerOpen)
        window.cancelQuickPicker()
        window.performToolbarAction(.widthPicker)
        XCTAssertTrue(window.isQuickPickerOpen)
        window.cancelQuickPicker()

        let path = TestFactory.createDrawingPath(
            points: [TestFactory.createTimedPoint(x: 20, y: 20)]
        )
        window.overlayView.currentTool = .pen
        window.overlayView.paths.append(path)
        window.performToolbarAction(.deleteLast)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        window.overlayView.paths.append(path)
        window.performToolbarAction(.clearAll)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        window.undoManager?.removeAllActions()

        window.overlayView.registerUndo(action: .addPath(path))
        window.overlayView.paths.append(path)
        window.performToolbarAction(.undo)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        AppDelegate.shared = appDelegate
    }

    func testQuickPickerPlacementAndFeedbackClearVisibleToolbar() throws {
        let clearance = window.toolbarClearance
        XCTAssertGreaterThan(clearance, 0)

        window.beginQuickPicker(.color, anchor: NSPoint(x: 600, y: 0))
        let picker = try XCTUnwrap(
            window.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first
        )

        XCTAssertGreaterThanOrEqual(picker.frame.minY, clearance)
        XCTAssertEqual(window.feedbackBottomPadding, clearance + 8)
        window.cancelQuickPicker()
    }

    func testQuickPickerClearsAToolbarParkedAtTheTop() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        panel.setFrameOrigin(
            NSPoint(
                x: window.frame.midX - panel.frame.width / 2,
                y: window.frame.maxY - panel.frame.height - 20))
        let bar = window.toolbarFrame
        XCTAssertGreaterThan(bar.minY, window.frame.height / 2)

        window.beginQuickPicker(.color, anchor: NSPoint(x: 600, y: 780))
        defer { window.cancelQuickPicker() }
        let picker = try XCTUnwrap(
            window.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first
        )

        XCTAssertLessThanOrEqual(
            picker.frame.maxY, bar.minY,
            "The picker has to clear the bar wherever the user parked it, not just at the bottom")
    }

    func testFeedbackKeepsItsUsualLiftWhenTheBarIsAwayFromTheBottom() throws {
        let panel = try XCTUnwrap(window.toolbarPanel)
        panel.setFrameOrigin(NSPoint(x: 100, y: window.frame.minY + 400))

        XCTAssertEqual(
            window.toolbarClearance, 0,
            "A bar parked mid-canvas is nowhere near the feedback pill")
        XCTAssertEqual(window.feedbackBottomPadding, 20)
    }

    func testOptionCommandTTogglesPersistedVisibility() throws {
        window.sendEvent(try XCTUnwrap(toolbarToggleEvent()))

        XCTAssertFalse(appDelegate.toolbarVisible)
    }

    func testHoldingOptionCommandTTogglesOnlyOnce() throws {
        window.sendEvent(try XCTUnwrap(toolbarToggleEvent()))
        XCTAssertFalse(appDelegate.toolbarVisible)

        window.sendEvent(try XCTUnwrap(toolbarToggleEvent(isARepeat: true)))

        XCTAssertEqual(
            defaults.object(forKey: UserDefaults.toolbarVisibleKey) as? Bool, false,
            "An auto-repeat of the held chord must not toggle the toolbar back on")
        XCTAssertFalse(appDelegate.toolbarVisible)
    }

    func testCommandTAloneLeavesTheToolbarAlone() throws {
        window.sendEvent(try XCTUnwrap(toolbarToggleEvent(modifierFlags: [.command])))

        XCTAssertTrue(
            appDelegate.toolbarVisible,
            "The toggle is Option+Command+T; Command+T alone must not claim it")
    }

    func testToolbarToggleDoesNotFireWhileEditingAnnotationText() throws {
        _ = try XCTUnwrap(startEditingAnnotationText())

        XCTAssertTrue(appDelegate.toolbarVisible)

        window.sendEvent(try XCTUnwrap(toolbarToggleEvent()))
        XCTAssertTrue(
            appDelegate.toolbarVisible,
            "Option+Command+T must not toggle the toolbar from sendEvent while editing")
    }

    func testEscapeKeepsClosingTheOverlay() throws {
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy

        window.sendEvent(try XCTUnwrap(escapeEvent()))

        XCTAssertTrue(spy.didToggleOverlay, "Escape closes the overlay, as it always has")
    }

    func testToolbarHostAcceptsFirstMouse() throws {
        let host = try XCTUnwrap(window.toolbarPanel?.hostingView)

        XCTAssertTrue(
            host.acceptsFirstMouse(for: nil),
            "Chips live in a nonactivating panel; the host must take the first click")
    }

    func testAlwaysOnModePassesClicksThroughAndHidesToolbar() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        appDelegate.overlayWindows[screen] = window
        appDelegate.alwaysOnMode = false
        window.overlayView.currentTool = .pen
        appDelegate.toggleAlwaysOnMode()
        defer {
            if appDelegate.alwaysOnMode {
                appDelegate.toggleAlwaysOnMode()
            }
        }
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(
            window.ignoresMouseEvents,
            "Always-On is a read-only overlay; every click belongs to the app underneath")
        XCTAssertTrue(window.overlayView.isReadOnlyMode)
        XCTAssertFalse(
            window.toolbarPanel?.isAttached ?? true,
            "A parent that ignores mouse events does not make a child click-through, so "
                + "Always-On has to take the bar out of the window group entirely")
        XCTAssertFalse(window.toolbarPanel?.isVisible ?? true)

        let canvasStart = NSPoint(x: 100, y: 300)
        let canvasEnd = NSPoint(x: 180, y: 360)
        sendMouse(.leftMouseDown, at: canvasStart)
        sendMouse(.leftMouseDragged, at: canvasEnd)
        sendMouse(.leftMouseUp, at: canvasEnd)

        XCTAssertTrue(window.overlayView.paths.isEmpty, "Always-On must never draw")
        XCTAssertEqual(window.anchorPoint, .zero)

        appDelegate.toggleAlwaysOnMode()

        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertFalse(window.overlayView.isReadOnlyMode)
        XCTAssertTrue(
            window.toolbarPanel?.isAttached ?? false,
            "Leaving Always-On restores the toolbar")
    }

    func testToolbarActionFinalizesActiveTextAnnotation() throws {
        let field = try XCTUnwrap(startEditingAnnotationText())
        field.stringValue = "Keep me"
        field.currentEditor()?.string = "Keep me"

        window.performToolbarAction(.tool(.pen))

        XCTAssertNil(window.overlayView.activeTextField)
        XCTAssertEqual(window.overlayView.textAnnotations.last?.text, "Keep me")
    }

    func testCanvasStrokeCrossingToolbarIsNotCaptured() throws {
        window.overlayView.currentTool = .pen
        let canvasStart = NSPoint(x: 100, y: 300)
        let overBar = NSPoint(x: window.toolbarFrame.midX, y: window.toolbarFrame.midY)

        sendMouse(.leftMouseDown, at: canvasStart)
        XCTAssertEqual(window.anchorPoint, canvasStart)

        sendMouse(.leftMouseDragged, at: overBar)
        sendMouse(.leftMouseUp, at: overBar)

        XCTAssertFalse(
            window.overlayView.paths.isEmpty,
            "A canvas-origin stroke must finish even if drag/up cross the toolbar")
        XCTAssertEqual(window.anchorPoint, canvasStart)
    }

    func testToolbarViewWrapsToASecondRowWhenWidthIsTight() {
        let wide = NSHostingController(rootView: ToolbarView(model: window.toolbarModel) { _ in })
            .sizeThatFits(in: CGSize(width: 1_200, height: 200))
        let narrow = NSHostingController(rootView: ToolbarView(model: window.toolbarModel) { _ in })
            .sizeThatFits(in: CGSize(width: 700, height: 200))

        XCTAssertGreaterThan(
            narrow.height, wide.height,
            "A narrow proposal must take the stacked ViewThatFits layout")
    }

    func testToolbarWrapsToASecondRowInANarrowWindow() throws {
        let narrowWindow = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { narrowWindow.close() }

        let wideFrame = try realizedToolbarFrame(window)
        let narrowFrame = try realizedToolbarFrame(narrowWindow)

        XCTAssertEqual(narrowWindow.frame.width, 700, accuracy: 0.5)
        XCTAssertLessThanOrEqual(
            narrowFrame.width, 700 - 40,
            "Toolbar width \(narrowFrame.width) must stay inside the 20pt margins")
        XCTAssertGreaterThan(
            narrowFrame.height, wideFrame.height,
            "Narrow height \(narrowFrame.height) must exceed wide height \(wideFrame.height)")

        let panel = try XCTUnwrap(window.toolbarPanel)
        XCTAssertGreaterThan(
            panel.measuredSize(availableWidth: 700).height,
            panel.measuredSize(availableWidth: 1_880).height,
            "The production measurer must still wrap after a wide proposal")
    }

    func testAttachedToolbarStaysSingleRowOnA1920Overlay() throws {
        let wideWindow = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_920, height: 1_080),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { wideWindow.close() }
        let panel = try XCTUnwrap(wideWindow.toolbarPanel)
        let host = try XCTUnwrap(panel.hostingView)
        let wideFrame = try realizedToolbarFrame(wideWindow)

        XCTAssertTrue(
            host.sizingOptions.isEmpty,
            "The displayed host must not publish stacked min/ideal/max sizes to the panel")
        XCTAssertEqual(
            host.frame.size.width, wideFrame.width, accuracy: 0.5,
            "The attached host has to occupy the measured panel, not a leftover stacked frame")
        XCTAssertEqual(host.frame.size.height, wideFrame.height, accuracy: 0.5)

        let available = 1_920 - ToolbarPanel.edgeInset * 2
        let measured = panel.measuredSize(availableWidth: available)
        XCTAssertEqual(
            wideFrame.width, measured.width, accuracy: 1,
            "Live panel width \(wideFrame.width) must match production measurement \(measured.width)")
        XCTAssertEqual(
            wideFrame.height, measured.height, accuracy: 1,
            "Live panel height \(wideFrame.height) must match production measurement \(measured.height)")

        let oneRow = NSHostingController(rootView: ToolbarView(model: wideWindow.toolbarModel) { _ in })
            .sizeThatFits(in: CGSize(width: available, height: 200))
        let stacked = NSHostingController(rootView: ToolbarView(model: wideWindow.toolbarModel) { _ in })
            .sizeThatFits(in: CGSize(width: 700, height: 200))

        XCTAssertEqual(
            wideFrame.height, oneRow.height, accuracy: 1,
            "A 1920pt overlay must keep the one-row height \(oneRow.height), not stacked \(stacked.height)")
        XCTAssertLessThan(wideFrame.height, stacked.height)
        XCTAssertGreaterThan(
            wideFrame.width, stacked.width,
            "One-row width \(wideFrame.width) must exceed the stacked width \(stacked.width)")
        XCTAssertLessThanOrEqual(wideFrame.width, available)
        // Do not assert `host.fittingSize` here: with `sizingOptions = []` it reports
        // 0×0. The live frame vs `measuredSize` / `sizeThatFits` checks above are the
        // production path.
    }

    func testToolbarFollowsOverlayWidthAfterAttachAndResize() throws {
        let wideWindow = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_920, height: 1_080),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer { wideWindow.close() }

        let initial = try realizedToolbarFrame(wideWindow)
        wideWindow.setFrame(NSRect(x: 0, y: 0, width: 700, height: 800), display: true)
        let wrapped = try realizedToolbarFrame(wideWindow)
        wideWindow.setFrame(NSRect(x: 0, y: 0, width: 1_920, height: 1_080), display: true)
        let restored = try realizedToolbarFrame(wideWindow)

        XCTAssertGreaterThan(
            wrapped.height, initial.height,
            "Resizing to 700pt must take the stacked layout")
        XCTAssertLessThanOrEqual(wrapped.width, 700 - ToolbarPanel.edgeInset * 2)
        XCTAssertEqual(
            restored.height, initial.height, accuracy: 1,
            "Growing back to 1920pt must return to one row, not keep the stacked height")
        XCTAssertGreaterThan(restored.width, wrapped.width)
    }

    func testPlacementBoundsPicksTheLargestSlabLeftByTheBar() {
        let bounds = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let gap: CGFloat = 8
        let cases: [(name: String, bar: NSRect, expected: NSRect)] = [
            (
                "a bar resting at the bottom leaves the canvas above it",
                NSRect(x: 400, y: 20, width: 400, height: 60),
                NSRect(x: 0, y: 88, width: 1_200, height: 712)
            ),
            (
                "a bar parked at the top leaves the canvas below it",
                NSRect(x: 400, y: 720, width: 400, height: 60),
                NSRect(x: 0, y: 0, width: 1_200, height: 712)
            ),
            (
                "a bar against the left edge leaves the canvas to its right",
                NSRect(x: 0, y: 300, width: 200, height: 60),
                NSRect(x: 208, y: 0, width: 992, height: 800)
            ),
            (
                "a bar against the right edge leaves the canvas to its left",
                NSRect(x: 1_000, y: 300, width: 200, height: 60),
                NSRect(x: 0, y: 0, width: 992, height: 800)
            ),
            (
                "a bar somewhere else entirely costs the bounds nothing",
                NSRect(x: 2_000, y: 2_000, width: 400, height: 60),
                bounds
            ),
            ("a hidden bar costs the bounds nothing", .zero, bounds),
            ("a bar that covers everything leaves the bounds as they were", bounds, bounds),
        ]

        for testCase in cases {
            XCTAssertEqual(
                OverlayWindow.placementBounds(bounds, clearing: testCase.bar, gap: gap),
                testCase.expected,
                testCase.name)
        }
    }

    func testAToolbarActionNeverSwitchesToSelectAfterCommittingText() throws {
        defaults.selectAfterPlacingText = true
        let field = try XCTUnwrap(startEditingAnnotationText())
        field.stringValue = "Keep me"
        field.currentEditor()?.string = "Keep me"

        window.performToolbarAction(.undo)

        XCTAssertNil(window.overlayView.activeTextField)
        XCTAssertEqual(
            window.overlayView.currentTool, .text,
            "Pressing a toolbar button is not the user finishing a label, so the opt-in switch "
                + "to Select must not fire here")
    }

    func testRemappedFadeAndToolbarReplaceTheirOldKeys() throws {
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy
        let shortcuts = ShortcutManager.shared
        XCTAssertTrue(shortcuts.setShortcut("j", for: .toggleFade))
        XCTAssertTrue(shortcuts.setShortcut(ShortcutBinding("u", modifiers: [.command, .shift]), for: .toggleToolbar))

        window.sendEvent(try shortcutEvent(" ", keyCode: 49))
        XCTAssertFalse(spy.didToggleFade)
        window.sendEvent(try shortcutEvent("j", keyCode: 38))
        XCTAssertTrue(spy.didToggleFade)
        window.sendEvent(try XCTUnwrap(toolbarToggleEvent()))
        XCTAssertTrue(spy.toolbarVisible)
        window.sendEvent(try shortcutEvent("u", keyCode: 32, modifiers: [.command, .shift]))
        XCTAssertFalse(spy.toolbarVisible)
        window.sendEvent(try shortcutEvent("u", keyCode: 32, modifiers: [.command, .shift], repeatKey: true))
        XCTAssertFalse(spy.toolbarVisible, "Holding the new toolbar binding must only toggle once")

        spy.didToggleFade = false
        shortcuts.clearShortcut(tool: .toggleFade)
        window.sendEvent(try shortcutEvent("j", keyCode: 38))
        XCTAssertFalse(spy.didToggleFade)
    }

    func testRemappedClearAllDoesNotLeaveOptionDeleteActive() throws {
        let shortcuts = ShortcutManager.shared
        XCTAssertTrue(shortcuts.setShortcut(ShortcutBinding("j", modifiers: .option), for: .clearAll))
        window.overlayView.fadeMode = false
        window.overlayView.currentTool = .pen
        window.overlayView.paths.append(TestFactory.createDrawingPath())
        window.overlayView.paths.append(TestFactory.createDrawingPath())
        window.sendEvent(try shortcutEvent("", keyCode: 51, modifiers: .option))
        XCTAssertEqual(window.overlayView.paths.count, 2)
        window.sendEvent(try shortcutEvent("j", keyCode: 38, modifiers: .option))
        XCTAssertTrue(window.overlayView.paths.isEmpty)
        window.overlayView.undo()
        XCTAssertEqual(window.overlayView.paths.count, 2)
        window.keyDown(with: try shortcutEvent("", keyCode: 51))
        XCTAssertEqual(window.overlayView.paths.count, 1, "Bare Delete stays fixed")
    }

    func testRemappedSizeStepsRepeatAndUseTheActiveToolLadder() throws {
        XCTAssertTrue(ShortcutManager.shared.setShortcut("j", for: .decreaseSize))
        XCTAssertTrue(ShortcutManager.shared.setShortcut(ShortcutBinding("u", modifiers: .option), for: .increaseSize))
        window.overlayView.currentTool = .pen
        window.overlayView.currentLineWidth = 3
        window.sendEvent(try shortcutEvent("[", keyCode: 33))
        XCTAssertEqual(window.overlayView.currentLineWidth, 3)
        window.sendEvent(try shortcutEvent("j", keyCode: 38))
        XCTAssertEqual(window.overlayView.currentLineWidth, 2)
        window.sendEvent(try shortcutEvent("u", keyCode: 32, modifiers: .option))
        window.sendEvent(try shortcutEvent("u", keyCode: 32, modifiers: .option, repeatKey: true))
        XCTAssertEqual(window.overlayView.currentLineWidth, 5)

        window.overlayView.currentTool = .text
        defaults.textToolFontSize = QuickPickerView.fontSizeOptions[1]
        window.sendEvent(try shortcutEvent("j", keyCode: 38))
        XCTAssertEqual(defaults.textToolFontSize, QuickPickerView.fontSizeOptions[0])
        window.overlayView.currentTool = .counter
        defaults.counterToolFontSize = QuickPickerView.counterSizeOptions[1]
        window.sendEvent(try shortcutEvent("u", keyCode: 32, modifiers: .option))
        XCTAssertEqual(defaults.counterToolFontSize, QuickPickerView.counterSizeOptions[2])
    }

    func testRemappedActionsYieldToPickerAndTextEditing() throws {
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy
        XCTAssertTrue(ShortcutManager.shared.setShortcut("j", for: .toggleFade))
        XCTAssertTrue(ShortcutManager.shared.setShortcut("u", for: .clearAll))
        XCTAssertTrue(ShortcutManager.shared.setShortcut("i", for: .increaseSize))
        window.overlayView.paths.append(TestFactory.createDrawingPath())
        let originalWidth = window.overlayView.currentLineWidth
        window.beginQuickPicker(.color)
        for (key, code): (String, UInt16) in [("j", 38), ("u", 32), ("i", 34)] {
            window.sendEvent(try shortcutEvent(key, keyCode: code))
        }
        XCTAssertTrue(window.isQuickPickerOpen)
        XCTAssertFalse(spy.didToggleFade)
        XCTAssertEqual(window.overlayView.paths.count, 1)
        XCTAssertEqual(window.overlayView.currentLineWidth, originalWidth)
        window.cancelQuickPicker()

        _ = try XCTUnwrap(startEditingAnnotationText())
        for (key, code): (String, UInt16) in [("j", 38), ("u", 32), ("i", 34)] {
            window.sendEvent(try shortcutEvent(key, keyCode: code))
        }
        XCTAssertFalse(spy.didToggleFade)
        XCTAssertEqual(window.overlayView.paths.count, 1)
        XCTAssertEqual(window.overlayView.currentLineWidth, originalWidth)
    }

    func testPickerChordReleaseWorksAfterModifierRelease() async throws {
        XCTAssertTrue(ShortcutManager.shared.setShortcut(ShortcutBinding("{", modifiers: .shift), for: .colorPicker))
        window.sendEvent(try shortcutEvent("{", keyCode: 33, modifiers: .shift))
        XCTAssertTrue(window.isQuickPickerOpen)
        try await Task.sleep(for: .milliseconds(300))
        // Releasing Shift first changes "{" to "[" on key-up; the physical key is unchanged.
        window.sendEvent(try XCTUnwrap(TestEvents.createKeyEvent(type: .keyUp, keyCode: 33,
            characters: "[", windowNumber: window.windowNumber)))
        let dismissDeadline = Date().addingTimeInterval(10)
        while window.isQuickPickerOpen && Date() < dismissDeadline {
            // Yield the main actor so the picker's main-queue dismissal can run.
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(window.isQuickPickerOpen, "The held picker must commit on release of its activation key")
    }

    func testMenuAndToolbarReflectChordsClearingAndRestoring() throws {
        appDelegate.setupStatusBarItem()
        installedStatusItem = true
        let shortcuts = ShortcutManager.shared
        let cases: [(ShortcutKey, Selector, ShortcutBinding)] = [
            (.toggleFade, #selector(AppDelegate.toggleFadeMode(_:)), ShortcutBinding("j", modifiers: .option)),
            (.toggleToolbar, #selector(AppDelegate.toggleToolbar), ShortcutBinding("u", modifiers: .command)),
            (.clearAll, #selector(AppDelegate.clearAllAnnotations), ShortcutBinding("i", modifiers: [.control, .shift]))
        ]
        for (action, selector, binding) in cases {
            XCTAssertTrue(shortcuts.setShortcut(binding, for: action))
            appDelegate.refreshMenuKeyEquivalents()
            let item = try XCTUnwrap(appDelegate.statusItem.menu?.items.first { $0.action == selector })
            XCTAssertEqual(item.keyEquivalent, binding.menuKeyEquivalent)
            XCTAssertEqual(item.keyEquivalentModifierMask, binding.modifiers)
            XCTAssertEqual(window.toolbarModel.shortcuts[action], binding.displayValue)
            shortcuts.clearShortcut(tool: action)
            appDelegate.refreshMenuKeyEquivalents()
            XCTAssertEqual(item.keyEquivalent, "")
            XCTAssertEqual(item.keyEquivalentModifierMask, [])
            XCTAssertEqual(window.toolbarModel.shortcuts[action], "")
            XCTAssertTrue(shortcuts.resetToDefault(tool: action))
            appDelegate.refreshMenuKeyEquivalents()
            XCTAssertEqual(item.keyEquivalent, action.defaultBinding.menuKeyEquivalent)
            XCTAssertEqual(item.keyEquivalentModifierMask, action.defaultBinding.modifiers)
        }
    }

    /// Orders the overlay and its toolbar on screen and lays out the displayed host, which is
    /// the production path the 1200/700 wrap tests used to skip. Off-screen `toolbarFrame`
    /// reads the measurer's `setFrame` result and never sees NSHostingView snap the panel
    /// back to a stacked size.
    private func realizedToolbarFrame(_ overlay: OverlayWindow) throws -> NSRect {
        let panel = try XCTUnwrap(overlay.toolbarPanel)
        let host = try XCTUnwrap(panel.hostingView)
        overlay.orderFrontRegardless()
        panel.orderFrontRegardless()
        overlay.contentView?.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(0.15)
        while Date() < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        return overlay.toolbarFrame
    }

    private func shortcutEvent(_ key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [],
                               repeatKey: Bool = false) throws -> NSEvent {
        try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: keyCode,
            modifierFlags: modifiers, characters: key, windowNumber: window.windowNumber, isARepeat: repeatKey))
    }

    private func toolbarToggleEvent(
        modifierFlags: NSEvent.ModifierFlags = [.command, .option],
        isARepeat: Bool = false
    ) -> NSEvent? {
        TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 17,
            modifierFlags: modifierFlags,
            characters: modifierFlags.contains(.option) ? "\u{2020}" : "t",
            charactersIgnoringModifiers: "t",
            windowNumber: window.windowNumber,
            isARepeat: isARepeat
        )
    }

    private func escapeEvent() -> NSEvent? {
        TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 53,
            characters: "\u{1b}",
            windowNumber: window.windowNumber
        )
    }

    private func sendMouse(_ type: NSEvent.EventType, at location: NSPoint) {
        window.sendEvent(
            TestEvents.createMouseEvent(
                type: type, location: location, windowNumber: window.windowNumber)!)
    }

    private func startEditingAnnotationText() throws -> NSTextField? {
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
            at: NSPoint(x: 120, y: 120), withText: "", width: 200)
        let field = try XCTUnwrap(
            window.overlayView.activeTextField, "Expected an annotation text field")
        if window.firstResponder !== field && window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
        if field.currentEditor() == nil {
            field.becomeFirstResponder()
        }
        return field
    }
}

@MainActor
private final class ToolbarAppDelegateSpy: AppDelegate {
    var selectedTool: ToolType?
    var didToggleFade = false
    var didToggleOverlay = false

    override func toggleOverlay() {
        didToggleOverlay = true
    }

    override func switchTool(to tool: ToolType, persist: Bool = true) {
        selectedTool = tool
    }

    override func toggleFadeMode(_ sender: Any?) {
        didToggleFade = true
    }
}

@MainActor
final class ToolbarPressTests: XCTestCase {
    func testAStationaryPressIsAClick() {
        let press = ToolbarPress()
        press.begin(screenPoint: NSPoint(x: 100, y: 80), windowOrigin: NSPoint(x: 40, y: 20))
        press.consider(screenPoint: NSPoint(x: 100, y: 80), windowOrigin: NSPoint(x: 40, y: 20))
        XCTAssertFalse(press.isDrag)
    }

    func testPointerTravelAtTheThresholdIsADrag() {
        let press = ToolbarPress()
        press.begin(screenPoint: .zero, windowOrigin: .zero)
        press.consider(
            screenPoint: NSPoint(x: ToolbarPress.dragThreshold, y: 0), windowOrigin: .zero)
        XCTAssertTrue(press.isDrag)
    }

    func testPointerTravelJustBelowTheThresholdIsAClick() {
        let press = ToolbarPress()
        press.begin(screenPoint: .zero, windowOrigin: .zero)
        press.consider(
            screenPoint: NSPoint(x: ToolbarPress.dragThreshold - 0.5, y: 0), windowOrigin: .zero)
        XCTAssertFalse(press.isDrag)
    }

    func testTheBarMovingAtTheThresholdIsADragEvenIfThePointerStaysInTheChip() {
        let press = ToolbarPress()
        let pointer = NSPoint(x: 50, y: 20)
        press.begin(screenPoint: pointer, windowOrigin: NSPoint(x: 100, y: 80))
        press.consider(
            screenPoint: pointer,
            windowOrigin: NSPoint(x: 100 + ToolbarPress.dragThreshold, y: 80))
        XCTAssertTrue(
            press.isDrag,
            "The chip rides with the bar, so a drag cannot be judged by the pointer staying inside it")
    }

    func testEndClearsTheDragSoTheNextClickCanFire() {
        let press = ToolbarPress()
        press.begin(screenPoint: .zero, windowOrigin: .zero)
        press.consider(screenPoint: NSPoint(x: 40, y: 0), windowOrigin: .zero)
        XCTAssertTrue(press.isDrag)

        press.end()
        XCTAssertFalse(press.isDrag)

        press.begin(screenPoint: .zero, windowOrigin: .zero)
        press.consider(screenPoint: .zero, windowOrigin: .zero)
        XCTAssertFalse(press.isDrag)
    }

    func testDeliverSkipsTheActionDuringADragAndRunsItOnAClick() {
        let press = ToolbarPress()
        var delivered: ToolType?

        press.begin(screenPoint: .zero, windowOrigin: .zero)
        press.consider(screenPoint: NSPoint(x: 40, y: 0), windowOrigin: .zero)
        press.deliver { delivered = .highlighter }
        XCTAssertNil(delivered)

        press.end()
        press.begin(screenPoint: .zero, windowOrigin: .zero)
        press.deliver { delivered = .arrow }
        XCTAssertEqual(delivered, .arrow)
    }
}
