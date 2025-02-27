import XCTest

@testable import Annotate

final class ShortcutManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset all shortcuts to their defaults before each test.
        ShortcutManager.shared.resetAllToDefault()
    }

    func testDefaultShortcuts() {
        // Verify that every tool returns its default shortcut.
        for tool in ShortcutKey.allCases {
            XCTAssertEqual(
                ShortcutManager.shared.getShortcut(for: tool), tool.defaultKey,
                "Default shortcut for \(tool.displayName) should be \(tool.defaultKey)")
        }
    }

    func testSetNewShortcut() {
        // Set a new shortcut for Pen (provided it doesn't conflict).
        ShortcutManager.shared.setShortcut("x", for: .pen)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .pen), "x", "Pen shortcut should update to 'x'")
    }

    func testDuplicateShortcutNotAllowed() {
        // Given the default for Arrow is "a", attempt to set Pen to "a".
        ShortcutManager.shared.setShortcut("a", for: .pen)
        // The set should be rejected and Pen remains its default ("p").
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .pen), ShortcutKey.pen.defaultKey,
            "Pen shortcut should not update to 'a' because Arrow already uses it")
    }

    func testResetToDefault() {
        // Change a shortcut and then reset it.
        ShortcutManager.shared.setShortcut("x", for: .pen)
        XCTAssertEqual(ShortcutManager.shared.getShortcut(for: .pen), "x")
        ShortcutManager.shared.resetToDefault(tool: .pen)
        XCTAssertEqual(ShortcutManager.shared.getShortcut(for: .pen), ShortcutKey.pen.defaultKey)
    }

    func testResetAllToDefault() {
        // Change a few shortcuts and then reset all.
        ShortcutManager.shared.setShortcut("x", for: .pen)
        ShortcutManager.shared.setShortcut("y", for: .arrow)
        ShortcutManager.shared.resetAllToDefault()
        for tool in ShortcutKey.allCases {
            XCTAssertEqual(ShortcutManager.shared.getShortcut(for: tool), tool.defaultKey)
        }
    }

    func testIsShortcutTaken() {
        // With defaults in place, Arrow is "a" and Pen is "p".
        XCTAssertTrue(
            ShortcutManager.shared.isShortcutTaken("a", excluding: .pen),
            "The shortcut 'a' is taken by Arrow")
        XCTAssertFalse(
            ShortcutManager.shared.isShortcutTaken("a", excluding: .arrow),
            "Excluding Arrow, 'a' should not be taken")
    }

    func testCounterShortcut() {
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .counter),
            ShortcutKey.counter.defaultKey,
            "Default shortcut for Counter should be 'n'"
        )

        // Set a custom shortcut
        ShortcutManager.shared.setShortcut("m", for: .counter)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .counter),
            "m",
            "Counter shortcut should be updated to 'm'"
        )

        // Reset to default
        ShortcutManager.shared.resetToDefault(tool: .counter)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .counter),
            ShortcutKey.counter.defaultKey,
            "Counter shortcut should be reset to default"
        )
    }

}
