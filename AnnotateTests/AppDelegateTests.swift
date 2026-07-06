import Foundation
import XCTest

@testable import Annotate

@MainActor
final class AppDelegateTests: XCTestCase, Sendable {
    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!

    nonisolated override func setUp() {
        super.setUp()

        MainActor.assumeIsolated {
            testDefaults = TestUserDefaults.create()
            BoardManager.shared = BoardManager(userDefaults: testDefaults)
            ShortcutManager.shared = ShortcutManager(userDefaults: testDefaults)

            appDelegate = AppDelegate(userDefaults: testDefaults)
            appDelegate.applicationDidFinishLaunching(
                Notification(name: NSApplication.didFinishLaunchingNotification))
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            appDelegate = nil
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(appDelegate.statusItem)
        XCTAssertNotNil(appDelegate.statusItem.menu)
        XCTAssertEqual(appDelegate.currentColor, .systemRed)
        XCTAssertNotNil(AppDelegate.shared)
    }

    func testStatusBarMenu() {
        guard let menu = appDelegate.statusItem.menu else {
            XCTFail("Status bar menu not initialized")
            return
        }

        // Verify menu structure
        XCTAssertGreaterThan(menu.items.count, 0)

        // Test color picker item
        let colorItem = menu.items.first { $0.action == #selector(AppDelegate.showColorPicker(_:)) }
        XCTAssertNotNil(colorItem)

        // Test tool items
        let penItem = menu.items.first { $0.action == #selector(AppDelegate.enablePenMode(_:)) }
        XCTAssertNotNil(penItem)
    }

    func testOverlayWindows() {
        // Test initial setup
        XCTAssertFalse(appDelegate.overlayWindows.isEmpty)

        // Test screen handling
        appDelegate.screenParametersChanged()
        XCTAssertEqual(appDelegate.overlayWindows.count, NSScreen.screens.count)
    }

    func testToolSwitching() {
        appDelegate.enablePenMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .pen)
        }

        appDelegate.enableArrowMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .arrow)
        }
        
        appDelegate.enableLineMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .line)
        }
        
        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(currentToolItem.title, "Current Tool: Line")
        }
    }

    func testCounterToolSwitching() {
        appDelegate.enableCounterMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .counter)
        }

        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(currentToolItem.title, "Current Tool: Counter")
        }
    }

    func testColorPicker() throws {
        appDelegate.showColorPicker(nil)
        let popover = try XCTUnwrap(appDelegate.colorPopover)
        XCTAssertNotNil(popover.contentViewController)
        XCTAssertEqual(popover.behavior, .transient)

        // Popover presentation is asynchronous relative to show(relativeTo:)
        // on macOS 26; spin the runloop briefly before checking.
        let deadline = Date(timeIntervalSinceNow: 2)
        while !popover.isShown && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        // Presentation additionally requires an on-screen status item, which
        // headless runners cannot provide; the popover wiring above is still
        // verified there.
        try XCTSkipUnless(
            popover.isShown,
            "Popover did not present; environment has no on-screen status item")
        XCTAssertTrue(popover.isShown)
    }

    // MARK: - Clear Drawings Tests

    func testToggleOverlayClearsDrawingsWhenEnabled() {
        testDefaults.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        appDelegate.alwaysOnMode = false

        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        if overlayWindow.isVisible {
            overlayWindow.orderOut(nil)
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red, lineWidth: 3.0)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue, lineWidth: 3.0)
        overlayWindow.overlayView.arrows.append(testArrow)

        let testLine = Line(startPoint: .zero, endPoint: NSPoint(x: 20, y: 20), color: .green, lineWidth: 3.0)
        overlayWindow.overlayView.lines.append(testLine)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1)

        // Simulate the show behavior from toggleOverlay - clear if setting is enabled
        if testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey) {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 0, "Paths should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 0, "Arrows should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 0, "Lines should be cleared when clearDrawingsOnStartKey is true")
    }

    func testToggleOverlayPreservesDrawingsWhenDisabled() {
        testDefaults.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)
        appDelegate.alwaysOnMode = false

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        if overlayWindow.isVisible {
            overlayWindow.orderOut(nil)
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red, lineWidth: 3.0)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue, lineWidth: 3.0)
        overlayWindow.overlayView.arrows.append(testArrow)

        let testLine = Line(startPoint: .zero, endPoint: NSPoint(x: 20, y: 20), color: .green, lineWidth: 3.0)
        overlayWindow.overlayView.lines.append(testLine)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1)

        // Simulate the show behavior from toggleOverlay - clear if setting is enabled
        if testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey) {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1, "Paths should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1, "Arrows should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1, "Lines should be preserved when clearDrawingsOnStartKey is false")
    }

    func testClearDrawingsSettingPersistence() {
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        testDefaults.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        testDefaults.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))
    }

    // MARK: - Dock Icon Tests

    func testHideDockIconDefaultValue() {
        testDefaults.removeObject(forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.hideDockIconKey))
    }

    func testDockIconVisibilityPersistence() {
        testDefaults.set(true, forKey: UserDefaults.hideDockIconKey)
        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.hideDockIconKey))

        testDefaults.set(false, forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.hideDockIconKey))
    }

    // MARK: - Persist Fade Mode Tests

    func testDefaultFadeModePersistence() {
        testDefaults.removeObject(forKey: UserDefaults.fadeModeKey)
        let persistedFadeMode =
            testDefaults.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
        XCTAssertTrue(persistedFadeMode, "Default fade mode should be true (fade mode active).")
    }

    func testToggleFadeModeUpdatesPersistence() {
        let appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }
        XCTAssertTrue(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be true by default.")

        // Toggle fade mode.
        appDelegate.toggleFadeMode(NSMenuItem())

        XCTAssertFalse(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be false after toggle.")

        // UserDefaults should reflect this change.
        let persistedFadeMode = testDefaults.bool(forKey: UserDefaults.fadeModeKey)
        XCTAssertFalse(persistedFadeMode, "UserDefaults should now store false for fade mode.")
    }

    func testOverlayWindowsRestorePersistedFadeMode() {
        testDefaults.set(false, forKey: UserDefaults.fadeModeKey)

        let appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))

        // All overlay windows should be initialized with fade mode set to false.
        for window in appDelegate.overlayWindows.values {
            XCTAssertFalse(
                window.overlayView.fadeMode,
                "Overlay window should restore persisted fade mode as false.")
        }
    }

    func testToggleBoardVisibility() {
        let initialState = testDefaults.bool(forKey: UserDefaults.enableBoardKey)

        appDelegate.toggleBoardVisibility(nil)

        let newState = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertNotEqual(initialState, newState, "Board visibility should be toggled")

        appDelegate.toggleBoardVisibility(nil)
        let finalState = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertEqual(
            initialState, finalState, "Board visibility should be toggled back to original state")
    }

    func testUpdateBoardMenuItems() {
        guard let menu = appDelegate.statusItem.menu else {
            XCTFail("Status bar menu not initialized")
            return
        }

        let toggleBoardItem = menu.items.first {
            $0.action == #selector(AppDelegate.toggleBoardVisibility(_:))
        }
        XCTAssertNotNil(toggleBoardItem, "Board toggle menu item should exist")

        let initialTitle = toggleBoardItem?.title

        let initialState = BoardManager.shared.isEnabled
        BoardManager.shared.isEnabled = !initialState

        appDelegate.updateBoardMenuItems()

        let newTitle = toggleBoardItem?.title
        XCTAssertNotEqual(
            initialTitle, newTitle, "Menu item title should change when board visibility changes")

        BoardManager.shared.isEnabled = initialState
    }

    // MARK: - Toggle Click Effects Tests

    func testToggleClickEffectsTogglesBothSettings() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager

        // Start with both disabled
        cursorManager.clickEffectsEnabled = false
        cursorManager.cursorHighlightEnabled = false

        XCTAssertFalse(cursorManager.clickEffectsEnabled)
        XCTAssertFalse(cursorManager.cursorHighlightEnabled)

        // Toggle on - should enable both
        appDelegate.toggleClickEffects(nil)

        XCTAssertTrue(
            CursorHighlightManager.shared.clickEffectsEnabled,
            "clickEffectsEnabled should be true after toggle")
        XCTAssertTrue(
            CursorHighlightManager.shared.cursorHighlightEnabled,
            "cursorHighlightEnabled should be true after toggle")

        // Toggle off - should disable both
        appDelegate.toggleClickEffects(nil)

        XCTAssertFalse(
            CursorHighlightManager.shared.clickEffectsEnabled,
            "clickEffectsEnabled should be false after second toggle")
        XCTAssertFalse(
            CursorHighlightManager.shared.cursorHighlightEnabled,
            "cursorHighlightEnabled should be false after second toggle")

        CursorHighlightManager.shared = CursorHighlightManager()
    }

    func testToggleClickEffectsPostsNotification() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager

        cursorManager.clickEffectsEnabled = false
        cursorManager.cursorHighlightEnabled = false

        let expectation = expectation(forNotification: .cursorHighlightStateChanged, object: nil)
        expectation.expectedFulfillmentCount = 2  // One for each property set

        appDelegate.toggleClickEffects(nil)

        wait(for: [expectation], timeout: 1.0)

        CursorHighlightManager.shared = CursorHighlightManager()
    }

    // MARK: - Previous Tool Tracking Tests

    func testSwitchToolSavesPreviousToolForTextMode() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableArrowMode(NSMenuItem())
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.enableTextMode(NSMenuItem())

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .text)
        XCTAssertEqual(overlayWindow.overlayView.previousTool, .arrow, "previousTool should be .arrow after switching from arrow to text")
    }

    func testSwitchToolDoesNotSavePreviousToolForOtherModes() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        overlayWindow.overlayView.previousTool = .pen
        appDelegate.enableArrowMode(NSMenuItem())

        let previousToolBefore = overlayWindow.overlayView.previousTool
        appDelegate.enableLineMode(NSMenuItem())

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .line)
        XCTAssertEqual(overlayWindow.overlayView.previousTool, previousToolBefore, "previousTool should remain unchanged when not switching to text mode")
    }

    // MARK: - Default Tool Tests

    func testSwitchToolPersistsLastUsedTool() {
        appDelegate.enableRectangleMode(NSMenuItem())
        XCTAssertEqual(testDefaults.lastUsedTool, .rectangle, "Explicitly switching tools should persist the choice as last used")

        appDelegate.enableHighlighterMode(NSMenuItem())
        XCTAssertEqual(testDefaults.lastUsedTool, .highlighter)
    }

    func testApplyConfiguredDefaultToolAppliesSpecificTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        testDefaults.defaultToolOption = .tool(.rectangle)
        appDelegate.enableArrowMode(NSMenuItem())  // start on a different tool than the configured default
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.applyConfiguredDefaultTool()

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .rectangle, "Activation should reset the tool to the configured default")
        }

        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(currentToolItem.title, "Current Tool: Rectangle")
        }
    }

    func testApplyConfiguredDefaultToolSkipsWhenToolAlreadyActive() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableRectangleMode(NSMenuItem())
        testDefaults.defaultToolOption = .tool(.rectangle)
        testDefaults.lastUsedTool = .highlighter

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .rectangle)
        XCTAssertEqual(
            testDefaults.lastUsedTool, .highlighter,
            "Applying a default tool that is already active should be a no-op (no switchTool, no tool feedback)")
    }

    func testApplyConfiguredDefaultToolDoesNothingForLastUsed() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        XCTAssertEqual(testDefaults.defaultToolOption, .lastUsed, "Default should be Last Used until the setting is touched")

        appDelegate.enableArrowMode(NSMenuItem())
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow, "Last Used should preserve whatever tool was already active")
    }

    func testLaunchRestoresPersistedLastUsedTool() {
        testDefaults.lastUsedTool = .highlighter

        let appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .highlighter, "Overlay windows should restore the persisted last-used tool on launch")
        }

        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(currentToolItem.title, "Current Tool: Highlighter", "Menu should reflect the restored tool, not the hardcoded default")
        }
    }

    func testLaunchDefaultsToPenWhenNoLastUsedToolSaved() {
        // testDefaults is a fresh suite with no LastUsedTool key set (see setUp).
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .pen, "Should fall back to .pen when no last-used tool was saved")
        }
    }

    func testInternalToolRestoreDoesNotOverwriteLastUsedTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        // restorePreviousTool reads persistTextMode from UserDefaults.standard, so pin it
        // to false for this test and restore whatever was there afterwards.
        let savedPersistTextMode = UserDefaults.standard.object(forKey: UserDefaults.persistTextModeKey)
        UserDefaults.standard.set(false, forKey: UserDefaults.persistTextModeKey)
        defer {
            if let saved = savedPersistTextMode {
                UserDefaults.standard.set(saved, forKey: UserDefaults.persistTextModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaults.persistTextModeKey)
            }
        }

        appDelegate.enablePenMode(NSMenuItem())
        appDelegate.enableTextMode(NSMenuItem())
        XCTAssertEqual(testDefaults.lastUsedTool, .text, "Explicitly switching to text should persist it as last used")
        XCTAssertEqual(overlayWindow.overlayView.previousTool, .pen)

        overlayWindow.overlayView.restorePreviousTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .pen, "Finishing a text annotation should restore the previous tool")
        XCTAssertEqual(testDefaults.lastUsedTool, .text, "Internal tool restores should not overwrite the persisted last-used tool")
    }
}
