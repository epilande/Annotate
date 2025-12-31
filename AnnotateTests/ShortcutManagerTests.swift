import XCTest

@testable import Annotate

@MainActor
final class ShortcutManagerTests: XCTestCase, Sendable {
    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            ShortcutManager.shared.resetAllToDefault()
        }
    }

    func testDefaultShortcuts() {
        for tool in ShortcutKey.allCases {
            XCTAssertEqual(
                ShortcutManager.shared.getShortcut(for: tool), tool.defaultKey,
                "Default shortcut for \(tool.displayName) should be \(tool.defaultKey)")
        }
    }

    func testSetNewShortcut() {
        // Set a new shortcut for Pen (provided it doesn't conflict).
        ShortcutManager.shared.setShortcut("f", for: .pen)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .pen), "f", "Pen shortcut should update to 'f'")
    }

    func testDuplicateShortcutNotAllowed() {
        // Given the default for Arrow is "a", attempt to set Pen to "a".
        ShortcutManager.shared.setShortcut("a", for: .pen)
        // The set should be rejected and Pen remains its default ("q").
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .pen), ShortcutKey.pen.defaultKey,
            "Pen shortcut should not update to 'a' because Arrow already uses it")
    }

    func testResetToDefault() {
        // Change a shortcut and then reset it.
        ShortcutManager.shared.setShortcut("f", for: .pen)
        XCTAssertEqual(ShortcutManager.shared.getShortcut(for: .pen), "f")
        ShortcutManager.shared.resetToDefault(tool: .pen)
        XCTAssertEqual(ShortcutManager.shared.getShortcut(for: .pen), ShortcutKey.pen.defaultKey)
    }

    func testResetAllToDefault() {
        // Change a few shortcuts and then reset all.
        ShortcutManager.shared.setShortcut("f", for: .pen)
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
    
    func testLineShortcut() {
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .line),
            ShortcutKey.line.defaultKey,
            "Default shortcut for Line should be 'l'"
        )

        // Set a custom shortcut for line (use a key not taken by toggleClickEffects)
        ShortcutManager.shared.setShortcut("z", for: .line)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .line),
            "z",
            "Line shortcut should be updated to 'z'"
        )

        // Reset to default
        ShortcutManager.shared.resetToDefault(tool: .line)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .line),
            ShortcutKey.line.defaultKey,
            "Line shortcut should be reset to default"
        )
    }

    func testToggleClickEffectsShortcut() {
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .toggleClickEffects),
            ShortcutKey.toggleClickEffects.defaultKey,
            "Default shortcut for Toggle Click Effects should be 'k'"
        )

        // Set a custom shortcut for toggle click effects
        ShortcutManager.shared.setShortcut("z", for: .toggleClickEffects)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .toggleClickEffects),
            "z",
            "Toggle Click Effects shortcut should be updated to 'z'"
        )

        // Reset to default
        ShortcutManager.shared.resetToDefault(tool: .toggleClickEffects)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .toggleClickEffects),
            ShortcutKey.toggleClickEffects.defaultKey,
            "Toggle Click Effects shortcut should be reset to default"
        )
    }

    // MARK: - Default Shortcut Tests
    
    func testAllDefaultShortcuts() {
        // Test all default keyboard shortcuts
        XCTAssertEqual(ShortcutKey.pen.defaultKey, "p", "Pen should be 'p'")
        XCTAssertEqual(ShortcutKey.arrow.defaultKey, "a", "Arrow should be 'a'")
        XCTAssertEqual(ShortcutKey.line.defaultKey, "l", "Line should be 'l'")
        XCTAssertEqual(ShortcutKey.highlighter.defaultKey, "h", "Highlighter should be 'h'")
        XCTAssertEqual(ShortcutKey.rectangle.defaultKey, "r", "Rectangle should be 'r'")
        XCTAssertEqual(ShortcutKey.circle.defaultKey, "o", "Circle should be 'o'")
        XCTAssertEqual(ShortcutKey.counter.defaultKey, "n", "Counter should be 'n'")
        XCTAssertEqual(ShortcutKey.text.defaultKey, "t", "Text should be 't'")
        XCTAssertEqual(ShortcutKey.select.defaultKey, "v", "Select should be 'v'")
        XCTAssertEqual(ShortcutKey.colorPicker.defaultKey, "c", "Color Picker should be 'c'")
        XCTAssertEqual(ShortcutKey.lineWidthPicker.defaultKey, "w", "Line Width should be 'w'")
        XCTAssertEqual(ShortcutKey.toggleBoard.defaultKey, "b", "Board should be 'b'")
        XCTAssertEqual(ShortcutKey.toggleClickEffects.defaultKey, "k", "Toggle Click Effects should be 'k'")
    }
    
    func testNoShortcutConflicts() {
        // Verify all default shortcuts are unique
        var shortcuts = Set<String>()
        for tool in ShortcutKey.allCases {
            let shortcut = tool.defaultKey
            XCTAssertFalse(
                shortcuts.contains(shortcut),
                "Shortcut '\(shortcut)' is used by multiple tools"
            )
            shortcuts.insert(shortcut)
        }
        
        // Should have 12 unique shortcuts
        XCTAssertEqual(shortcuts.count, ShortcutKey.allCases.count, "All shortcuts should be unique")
    }
    
    func testFirstLetterShortcuts() {
        // Test that shortcuts generally match the first letter of the tool
        XCTAssertEqual(ShortcutKey.pen.defaultKey, "p", "Pen starts with 'p'")
        XCTAssertEqual(ShortcutKey.arrow.defaultKey, "a", "Arrow starts with 'a'")
        XCTAssertEqual(ShortcutKey.line.defaultKey, "l", "Line starts with 'l'")
        XCTAssertEqual(ShortcutKey.highlighter.defaultKey, "h", "Highlighter starts with 'h'")
        XCTAssertEqual(ShortcutKey.rectangle.defaultKey, "r", "Rectangle starts with 'r'")
        XCTAssertEqual(ShortcutKey.counter.defaultKey, "n", "Counter uses 'n' (Number)")
        XCTAssertEqual(ShortcutKey.text.defaultKey, "t", "Text starts with 't'")
        XCTAssertEqual(ShortcutKey.toggleBoard.defaultKey, "b", "Board starts with 'b'")
    }
    
    func testShortcutCustomization() {
        // Verify users can still customize shortcuts
        let customShortcuts = [
            (ShortcutKey.pen, "1"),
            (ShortcutKey.line, "2"),
            (ShortcutKey.highlighter, "3")
        ]
        
        for (tool, customKey) in customShortcuts {
            ShortcutManager.shared.setShortcut(customKey, for: tool)
            XCTAssertEqual(
                ShortcutManager.shared.getShortcut(for: tool),
                customKey,
                "\(tool.displayName) should accept custom shortcut '\(customKey)'"
            )
        }
        
        // Reset and verify defaults are restored
        ShortcutManager.shared.resetAllToDefault()
        XCTAssertEqual(ShortcutManager.shared.getShortcut(for: .pen), "p")
        XCTAssertEqual(ShortcutManager.shared.getShortcut(for: .line), "l")
        XCTAssertEqual(ShortcutManager.shared.getShortcut(for: .highlighter), "h")
    }
}
