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

}
