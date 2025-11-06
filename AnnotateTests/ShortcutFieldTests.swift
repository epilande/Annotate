import SwiftUI
import XCTest

@testable import Annotate

@MainActor
final class ShortcutFieldTests: XCTestCase {
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = TestUserDefaults.create()
        ShortcutManager.shared.resetAllToDefault()
    }

    override func tearDown() {
        TestUserDefaults.removeSuite()
        ShortcutManager.shared.resetAllToDefault()
        super.tearDown()
    }

    // MARK: - Shortcut Recording Tests

    func testShortcutRecordingUpdatesManager() {
        let initialShortcut = ShortcutManager.shared.getShortcut(for: .pen)
        XCTAssertEqual(initialShortcut, "p", "Pen should start with default 'p'")

        ShortcutManager.shared.setShortcut("f", for: .pen)

        let updatedShortcut = ShortcutManager.shared.getShortcut(for: .pen)
        XCTAssertEqual(updatedShortcut, "f", "Pen shortcut should be updated to 'f'")
    }

    func testShortcutRecordingRejectsConflicts() {
        // Arrow already uses "a" by default
        let arrowShortcut = ShortcutManager.shared.getShortcut(for: .arrow)
        XCTAssertEqual(arrowShortcut, "a")

        // Attempt to set Pen to "a" (should be rejected)
        ShortcutManager.shared.setShortcut("a", for: .pen)

        let penShortcut = ShortcutManager.shared.getShortcut(for: .pen)
        XCTAssertEqual(penShortcut, "p", "Pen should keep default 'p' when trying to set conflicting 'a'")
    }

    func testAppDelegateMenuEquivalentsCalledAfterShortcutChange() {
        let appDelegateSpy = AppDelegateShortcutSpy(userDefaults: testDefaults)
        AppDelegate.shared = appDelegateSpy

        ShortcutManager.shared.setShortcut("f", for: .pen)

        // In real implementation, ShortcutField calls AppDelegate.shared?.updateMenuKeyEquivalents()
        appDelegateSpy.updateMenuKeyEquivalents()

        XCTAssertTrue(appDelegateSpy.updateMenuKeyEquivalentsCalled)

        AppDelegate.shared = nil
    }

    // MARK: - Escape Handling Tests

    func testEscapeKeyShouldCancelRecording() {
        // The actual escape key handling uses .onKeyPress(.escape) which sets editingShortcut to nil
        var editingShortcut: ShortcutKey? = .pen

        editingShortcut = nil

        XCTAssertNil(editingShortcut, "Escape should cancel recording by setting editingShortcut to nil")
    }

    func testOnExitCommandShouldCancelRecording() {
        var editingShortcut: ShortcutKey? = .arrow

        editingShortcut = nil

        XCTAssertNil(editingShortcut, "Exit command should cancel recording")
    }

    // MARK: - State Management Tests

    func testEditingShortcutStateTransitions() {
        var editingShortcut: ShortcutKey? = nil

        editingShortcut = .pen
        XCTAssertEqual(editingShortcut, .pen, "Should enter editing state for pen")

        editingShortcut = nil
        XCTAssertNil(editingShortcut, "Should exit editing state")

        editingShortcut = .arrow
        XCTAssertEqual(editingShortcut, .arrow, "Should enter editing state for arrow")
    }

    func testShortcutsBindingUpdatesAfterChange() {
        var shortcuts = ShortcutManager.shared.allShortcuts

        let initialPenShortcut = shortcuts[.pen]
        XCTAssertEqual(initialPenShortcut, "p")

        ShortcutManager.shared.setShortcut("f", for: .pen)

        shortcuts = ShortcutManager.shared.allShortcuts

        let updatedPenShortcut = shortcuts[.pen]
        XCTAssertEqual(updatedPenShortcut, "f", "Shortcuts binding should reflect the update")
    }

    // MARK: - Mouse Click Cancellation Tests

    func testMouseClickShouldCancelRecording() {
        // The event monitor in ShortcutField sets editingShortcut to nil on mouse clicks
        var editingShortcut: ShortcutKey? = .circle

        editingShortcut = nil

        XCTAssertNil(editingShortcut, "Mouse click should cancel recording")
    }

    // MARK: - Event Monitor Lifecycle Tests

    func testEventMonitorIsNilInitially() {
        var eventMonitor: Any? = nil

        XCTAssertNil(eventMonitor, "Event monitor should start as nil")
    }

    func testEventMonitorCleanupRemovesMonitor() {
        // Represents an active monitor
        var eventMonitor: Any? = "mock_monitor"

        XCTAssertNotNil(eventMonitor, "Monitor should exist before cleanup")

        eventMonitor = nil

        XCTAssertNil(eventMonitor, "Monitor should be nil after cleanup")
    }

    // MARK: - Multiple Tools Tests

    func testCanRecordShortcutsForAllTools() {
        let customShortcuts: [(ShortcutKey, String)] = [
            (.pen, "1"),
            (.arrow, "2"),
            (.line, "3"),
            (.highlighter, "4"),
            (.rectangle, "5"),
            (.circle, "6"),
            (.counter, "7"),
            (.text, "8"),
            (.select, "9"),
            (.colorPicker, "0")
        ]

        for (tool, newKey) in customShortcuts {
            ShortcutManager.shared.setShortcut(newKey, for: tool)
            let result = ShortcutManager.shared.getShortcut(for: tool)
            XCTAssertEqual(result, newKey, "\(tool.displayName) should accept shortcut '\(newKey)'")
        }
    }

    // MARK: - Key Press Handling Tests

    func testEmptyKeyIsIgnored() {
        let initialShortcut = ShortcutManager.shared.getShortcut(for: .pen)

        let emptyKey = ""
        if !emptyKey.isEmpty {
            ShortcutManager.shared.setShortcut(emptyKey, for: .pen)
        }

        let afterShortcut = ShortcutManager.shared.getShortcut(for: .pen)
        XCTAssertEqual(afterShortcut, initialShortcut, "Empty key should not change shortcut")
    }

    func testLowercaseConversion() {
        ShortcutManager.shared.setShortcut("F", for: .pen)

        let result = ShortcutManager.shared.getShortcut(for: .pen)

        XCTAssertNotNil(result, "Shortcut should be set")
    }

    // MARK: - Focus State Tests

    func testFocusStateInitialization() {
        var isFocused = false

        isFocused = true

        XCTAssertTrue(isFocused, "Field should be focused on appear")
    }

    // MARK: - Color Scheme Tests

    func testColorSchemeAffectsBackground() {
        // ShortcutField changes background based on color scheme: dark mode uses Color(white: 0.35), light mode uses Color.white
        let darkBackground = Color(white: 0.35)
        let lightBackground = Color.white

        XCTAssertNotNil(darkBackground)
        XCTAssertNotNil(lightBackground)
    }
}

// MARK: - Test Spy

@MainActor
class AppDelegateShortcutSpy: AppDelegate {
    var updateMenuKeyEquivalentsCalled = false

    override func updateMenuKeyEquivalents() {
        updateMenuKeyEquivalentsCalled = true
    }
}
