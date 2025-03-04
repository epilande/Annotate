import Foundation
import XCTest

@testable import Annotate

final class AppDelegateTests: XCTestCase {
    var appDelegate: AppDelegate!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        UserDefaults.standard.removeObject(forKey: UserDefaults.clearDrawingsOnStartKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.clearDrawingsOnStartKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.hideDockIconKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.fadeModeKey)
        appDelegate = nil
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
    }

    func testCounterToolSwitching() {
        appDelegate.enableCounterMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .counter)
        }

        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 2)
        {
            XCTAssertEqual(currentToolItem.title, "Current Tool: Counter")
        }
    }

    func testColorPicker() {
        appDelegate.showColorPicker(nil)
        XCTAssertNotNil(appDelegate.colorPopover)
        XCTAssertTrue(appDelegate.colorPopover.isShown)
    }

    // MARK: - Clear Drawings Tests

    func testToggleOverlayClearsDrawingsWhenEnabled() {
        UserDefaults.standard.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        guard let currentScreen = NSScreen.main,
            let overlayWindow = appDelegate.overlayWindows[currentScreen]
        else {
            XCTFail("Failed to get overlay window")
            return
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue)
        overlayWindow.overlayView.arrows.append(testArrow)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)

        // Toggle overlay
        appDelegate.toggleOverlay()

        // Toggle it back on
        appDelegate.toggleOverlay()

        // Verify drawings were cleared
        XCTAssertEqual(overlayWindow.overlayView.paths.count, 0)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 0)
    }

    func testToggleOverlayPreservesDrawingsWhenDisabled() {
        UserDefaults.standard.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)
        guard let currentScreen = NSScreen.main,
            let overlayWindow = appDelegate.overlayWindows[currentScreen]
        else {
            XCTFail("Failed to get overlay window")
            return
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue)
        overlayWindow.overlayView.arrows.append(testArrow)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)

        // Toggle overlay
        appDelegate.toggleOverlay()

        // Toggle it back on
        appDelegate.toggleOverlay()

        // Verify drawings were preserved
        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
    }

    func testClearDrawingsSettingPersistence() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        UserDefaults.standard.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        UserDefaults.standard.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.clearDrawingsOnStartKey))
    }

    // MARK: - Dock Icon Tests

    func testHideDockIconDefaultValue() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey))
    }

    func testDockIconVisibilityPersistence() {
        UserDefaults.standard.set(true, forKey: UserDefaults.hideDockIconKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey))

        UserDefaults.standard.set(false, forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey))
    }

    // MARK: - Persist Fade Mode Tests

    func testDefaultFadeModePersistence() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.fadeModeKey)
        let persistedFadeMode =
            UserDefaults.standard.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
        XCTAssertTrue(persistedFadeMode, "Default fade mode should be true (fade mode active).")
    }

    func testToggleFadeModeUpdatesPersistence() {
        let appDelegate = AppDelegate()
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
        let persistedFadeMode = UserDefaults.standard.bool(forKey: UserDefaults.fadeModeKey)
        XCTAssertFalse(persistedFadeMode, "UserDefaults should now store false for fade mode.")
    }

    func testOverlayWindowsRestorePersistedFadeMode() {
        UserDefaults.standard.set(false, forKey: UserDefaults.fadeModeKey)

        let appDelegate = AppDelegate()
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
        let initialState = UserDefaults.standard.bool(forKey: UserDefaults.enableBoardKey)

        appDelegate.toggleBoardVisibility(nil)

        let newState = UserDefaults.standard.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertNotEqual(initialState, newState, "Board visibility should be toggled")

        appDelegate.toggleBoardVisibility(nil)
        let finalState = UserDefaults.standard.bool(forKey: UserDefaults.enableBoardKey)
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
}
