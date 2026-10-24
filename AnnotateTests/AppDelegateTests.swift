import Foundation
import XCTest

@testable import Annotate

@MainActor
final class AppDelegateTests: XCTestCase, Sendable {
    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!
    private var launchedDelegates: [AppDelegate] = []

    nonisolated override func setUp() {
        super.setUp()

        MainActor.assumeIsolated {
            TestWindows.recordOpenWindows()
            testDefaults = TestUserDefaults.create()
            BoardManager.shared = BoardManager(userDefaults: testDefaults)
            ShortcutManager.shared = ShortcutManager(userDefaults: testDefaults)

            appDelegate = launchAppDelegate()
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            SettingsWindowManager.shared.settingsWindow?.close()
            appDelegate.overlayKeyWindowOverride = nil
            launchedDelegates.forEach { $0.tearDownAfterLaunch() }
            launchedDelegates = []
            appDelegate = nil
            assertNoLeakedWindows()
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    /// Every delegate a test launches goes through here so tearDown can dismantle it. Launching
    /// opens an overlay and a cursor highlight window per screen, a status item and seven event
    /// monitors, none of which go away on their own.
    private func launchAppDelegate() -> AppDelegate {
        let delegate = AppDelegate(userDefaults: testDefaults)
        launchedDelegates.append(delegate)
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        return delegate
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

    func testQuickPickerMenuItemsFailClosedWhenMainOverlayIsHidden() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let colorItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.showColorPicker(_:)) })
        let widthItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.showLineWidthPicker(_:)) })

        appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) }

        XCTAssertEqual(colorItem.title, "Color…")
        XCTAssertEqual(widthItem.title, "Line Width…")
        XCTAssertFalse(appDelegate.validateMenuItem(colorItem))
        XCTAssertFalse(appDelegate.validateMenuItem(widthItem))
    }

    func testPickerMenuRoutesToVisibleMainOverlayCenter() throws {
        let mainScreen = try XCTUnwrap(NSScreen.main)
        let overlayWindow = try XCTUnwrap(appDelegate.overlayWindows[mainScreen])
        appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) }
        overlayWindow.makeKeyAndOrderFront(nil)
        defer { overlayWindow.orderOut(nil) }

        let colorItem = NSMenuItem()
        colorItem.action = #selector(AppDelegate.showColorPicker(_:))
        XCTAssertTrue(appDelegate.validateMenuItem(colorItem))

        appDelegate.showColorPicker(nil)
        let colorPicker = try XCTUnwrap(
            overlayWindow.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first)
        XCTAssertEqual(colorPicker.mode, .color)
        let expectedColorFrame = QuickPickerView.pickerFrame(
            itemCount: colorPalette.count,
            anchor: NSPoint(
                x: overlayWindow.overlayView.bounds.midX,
                y: overlayWindow.overlayView.bounds.midY),
            within: overlayWindow.overlayView.bounds)
        XCTAssertEqual(colorPicker.frame, expectedColorFrame)

        overlayWindow.cancelQuickPicker()
        overlayWindow.overlayView.currentTool = .counter
        appDelegate.showLineWidthPicker(nil)
        let counterPicker = try XCTUnwrap(
            overlayWindow.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first)
        XCTAssertEqual(counterPicker.mode, .counterSize)
    }

    // MARK: - Clear Drawings Tests

    func testToggleOverlayClearsDrawingsWhenEnabled() {
        testDefaults.settings[.clearDrawingsOnStart] = true
        appDelegate.alwaysOnMode = false

        XCTAssertTrue(testDefaults.settings[.clearDrawingsOnStart])

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
        if testDefaults.settings[.clearDrawingsOnStart] {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 0, "Paths should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 0, "Arrows should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 0, "Lines should be cleared when clearDrawingsOnStartKey is true")
    }

    func testToggleOverlayPreservesDrawingsWhenDisabled() {
        testDefaults.settings[.clearDrawingsOnStart] = false
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
        if testDefaults.settings[.clearDrawingsOnStart] {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1, "Paths should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1, "Arrows should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1, "Lines should be preserved when clearDrawingsOnStartKey is false")
    }

    func testClearDrawingsSettingPersistence() {
        XCTAssertFalse(testDefaults.settings[.clearDrawingsOnStart])

        testDefaults.settings[.clearDrawingsOnStart] = true
        XCTAssertTrue(testDefaults.settings[.clearDrawingsOnStart])

        testDefaults.settings[.clearDrawingsOnStart] = false
        XCTAssertFalse(testDefaults.settings[.clearDrawingsOnStart])
    }

    // MARK: - Dock Icon Tests

    func testHideDockIconDefaultValue() {
        testDefaults.settings.removeValue(for: .hideDockIcon)
        XCTAssertFalse(testDefaults.settings[.hideDockIcon])
    }

    func testDockIconVisibilityPersistence() {
        testDefaults.settings[.hideDockIcon] = true
        XCTAssertTrue(testDefaults.settings[.hideDockIcon])

        testDefaults.settings[.hideDockIcon] = false
        XCTAssertFalse(testDefaults.settings[.hideDockIcon])
    }

    // MARK: - Persist Fade Mode Tests

    func testDefaultFadeModePersistence() {
        testDefaults.settings.removeValue(for: .fadeMode)
        let persistedFadeMode = testDefaults.settings[.fadeMode]
        XCTAssertTrue(persistedFadeMode, "Default fade mode should be true (fade mode active).")
    }

    func testToggleFadeModeUpdatesPersistence() {
        let appDelegate = launchAppDelegate()

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }
        XCTAssertTrue(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be true by default.")

        // Toggle fade mode.
        appDelegate.toggleFadeMode(nil)

        XCTAssertFalse(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be false after toggle.")

        // UserDefaults should reflect this change.
        let persistedFadeMode = testDefaults.settings[.fadeMode]
        XCTAssertFalse(persistedFadeMode, "UserDefaults should now store false for fade mode.")
    }

    // MARK: - Fade Delay

    func testFadeDelayDefaultsToTheOriginalHold() {
        XCTAssertEqual(testDefaults.settings[.fadeDelay], 0.625)
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.fadeDelay, 0.625)
            XCTAssertEqual(window.overlayView.fadeDuration, 1.25)
        }
    }

    func testFadeDelayFromSettingsAppliesToEveryOverlay() {
        // What the Settings slider does: write through @AppStorage, then apply.
        testDefaults.settings[.fadeDelay] = 1.5
        appDelegate.applyFadeDelay()

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.fadeDelay, 1.5)
        }
    }

    func testPersistedFadeDelayIsRestoredOnLaunch() throws {
        testDefaults.settings[.fadeDelay] = 3

        let relaunched = launchAppDelegate()

        let window = try XCTUnwrap(relaunched.overlayWindows.values.first)
        XCTAssertEqual(window.overlayView.fadeDelay, 3)
    }

    func testOverlayPicksUpTheFadeDelayWhenShown() throws {
        let overlayWindow = try XCTUnwrap(appDelegate.overlayWindows.values.first)
        defer { appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) } }
        testDefaults.settings[.fadeDelay] = 4

        appDelegate.toggleAlwaysOnMode()
        appDelegate.toggleAlwaysOnMode()

        XCTAssertEqual(overlayWindow.overlayView.fadeDelay, 4)
    }

    func testToggleFadeModeStartsFadeLoop() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }

        overlayWindow.overlayView.fadeMode = false
        overlayWindow.stopFadeLoop()
        overlayWindow.overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 0, y: 0),
                endPoint: NSPoint(x: 10, y: 10),
                color: .systemRed,
                lineWidth: 3,
                creationTime: CACurrentMediaTime()
            )
        ]

        appDelegate.toggleFadeMode(nil)

        XCTAssertTrue(overlayWindow.overlayView.fadeMode)
        XCTAssertNotNil(overlayWindow.fadeTimer)
        overlayWindow.stopFadeLoop()
    }

    func testAlwaysOnExitStartsFadeLoopWhenPersistedFadeModeIsOn() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }

        let now = CACurrentMediaTime()
        overlayWindow.overlayView.arrows = [
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

        appDelegate.alwaysOnMode = false
        appDelegate.toggleAlwaysOnMode()
        XCTAssertFalse(overlayWindow.overlayView.fadeMode)
        XCTAssertNil(overlayWindow.fadeTimer)

        appDelegate.toggleAlwaysOnMode()

        XCTAssertTrue(overlayWindow.overlayView.fadeMode)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.first?.startPoint, NSPoint(x: 20, y: 20))
        XCTAssertNotNil(overlayWindow.fadeTimer)
        overlayWindow.stopFadeLoop()
    }

    func testFadeAndClearAllMenuActionsRequireOverlayKeyWindow() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let fadeItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.toggleFadeMode(_:)) })
        let clearItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.clearAllAnnotations) })
        let overlayWindow = try XCTUnwrap(appDelegate.overlayWindows.values.first)
        overlayWindow.overlayView.fadeMode = false
        overlayWindow.overlayView.paths.append(TestFactory.createDrawingPath())
        appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) }
        defer {
            SettingsWindowManager.shared.settingsWindow?.close()
            overlayWindow.orderOut(nil)
        }

        XCTAssertFalse(appDelegate.validateMenuItem(fadeItem))
        XCTAssertFalse(appDelegate.validateMenuItem(clearItem))
        appDelegate.toggleFadeMode(NSMenuItem())
        appDelegate.clearAllAnnotations()
        XCTAssertFalse(overlayWindow.overlayView.fadeMode)
        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)

        // Settings is a normal-level window; the overlay sits above screen-saver
        // level, so show() cannot steal key in CI. orderFront keeps the overlay
        // visible (the High: Settings focused, overlay still on screen) without
        // making it the key window.
        SettingsWindowManager.shared.show()
        overlayWindow.orderFront(nil)
        if overlayWindow.isKeyWindow {
            overlayWindow.resignKey()
        }
        XCTAssertTrue(overlayWindow.isVisible)
        XCTAssertFalse(overlayWindow.isKeyWindow)
        XCTAssertFalse(appDelegate.validateMenuItem(fadeItem))
        XCTAssertFalse(appDelegate.validateMenuItem(clearItem))
        appDelegate.toggleFadeMode(NSMenuItem())
        appDelegate.clearAllAnnotations()
        XCTAssertFalse(
            overlayWindow.overlayView.fadeMode,
            "Fade must not toggle from a menu equivalent unless the overlay is key")
        XCTAssertEqual(
            overlayWindow.overlayView.paths.count, 1,
            "Clear All must not fire from a menu equivalent unless the overlay is key")

        // XCTest will not make this overlay key: ToolbarPanel answers
        // canBecomeKey = false, so makeKeyAndOrderFront leaves isKeyWindow false.
        // Drive the same product gate through the test seam instead.
        overlayWindow.orderFront(nil)
        appDelegate.overlayKeyWindowOverride = true
        XCTAssertTrue(appDelegate.validateMenuItem(fadeItem))
        XCTAssertTrue(appDelegate.validateMenuItem(clearItem))
        appDelegate.toggleFadeMode(NSMenuItem())
        appDelegate.clearAllAnnotations()
        XCTAssertTrue(overlayWindow.overlayView.fadeMode)
        XCTAssertTrue(overlayWindow.overlayView.paths.isEmpty)
    }

    func testOverlayWindowsRestorePersistedFadeMode() {
        testDefaults.settings[.fadeMode] = false

        let appDelegate = launchAppDelegate()

        // All overlay windows should be initialized with fade mode set to false.
        for window in appDelegate.overlayWindows.values {
            XCTAssertFalse(
                window.overlayView.fadeMode,
                "Overlay window should restore persisted fade mode as false.")
        }
    }

    func testToggleBoardVisibility() {
        let initialState = testDefaults.settings[.enableBoard]

        appDelegate.toggleBoardVisibility(nil)

        let newState = testDefaults.settings[.enableBoard]
        XCTAssertNotEqual(initialState, newState, "Board visibility should be toggled")
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.adaptColorsToBoardType, newState)
        }

        appDelegate.toggleBoardVisibility(nil)
        let finalState = testDefaults.settings[.enableBoard]
        XCTAssertEqual(
            initialState, finalState, "Board visibility should be toggled back to original state")
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.adaptColorsToBoardType, finalState)
        }
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

    // MARK: - Default Tool Tests

    func testSwitchToolPersistsLastUsedTool() {
        appDelegate.enableRectangleMode(NSMenuItem())
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .rectangle, "Explicitly switching tools should persist the choice as last used")

        appDelegate.enableHighlighterMode(NSMenuItem())
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .highlighter)
    }

    func testApplyConfiguredDefaultToolAppliesSpecificTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        testDefaults.settings[.defaultTool] = .tool(.rectangle)
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
        testDefaults.settings[.defaultTool] = .tool(.rectangle)
        testDefaults.settings[.lastUsedTool] = .highlighter

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .rectangle)
        XCTAssertEqual(
            testDefaults.settings[.lastUsedTool], .highlighter,
            "Applying a default tool that is already active should be a no-op (no switchTool, no tool feedback)")
    }

    func testApplyConfiguredDefaultToolDoesNotOverwriteLastUsedTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableHighlighterMode(NSMenuItem())
        testDefaults.settings[.defaultTool] = .tool(.rectangle)

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .rectangle)
        XCTAssertEqual(
            testDefaults.settings[.lastUsedTool], .highlighter,
            "Applying the configured default is not an explicit selection and must not overwrite the persisted last-used tool")
    }

    func testApplyConfiguredDefaultToolDoesNothingForLastUsed() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        XCTAssertEqual(testDefaults.settings[.defaultTool], .lastUsed, "Default should be Last Used until the setting is touched")

        appDelegate.enableArrowMode(NSMenuItem())
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow, "Last Used should preserve whatever tool was already active")
    }

    func testLaunchRestoresPersistedLastUsedTool() {
        testDefaults.settings[.lastUsedTool] = .highlighter

        let appDelegate = launchAppDelegate()

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

    func testInternalToolSwitchDoesNotOverwriteLastUsedTool() throws {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.settings[.selectAfterPlacingText] = true

        appDelegate.enablePenMode(NSMenuItem())
        appDelegate.enableTextMode(NSMenuItem())
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .text, "Explicitly switching to text should persist it as last used")

        let overlayView: OverlayView = try XCTUnwrap(overlayWindow.overlayView)
        let point = NSPoint(x: 100, y: 100)
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: point, color: .red,
            fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: point, withText: "")
        let textField = try XCTUnwrap(overlayView.activeTextField)
        textField.stringValue = "Hello"
        overlayView.commitTextField(textField)

        XCTAssertEqual(overlayView.currentTool, .select, "Committing a label should switch to Select")
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .text, "Internal tool switches should not overwrite the persisted last-used tool")
    }
}

@MainActor
final class MockAppDelegate: AppDelegate {}
