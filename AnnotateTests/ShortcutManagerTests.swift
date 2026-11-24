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
            "Default shortcut for Toggle Cursor Highlight should be 'k'"
        )

        // Set a custom shortcut for toggle cursor highlight
        ShortcutManager.shared.setShortcut("z", for: .toggleClickEffects)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .toggleClickEffects),
            "z",
            "Toggle Cursor Highlight shortcut should be updated to 'z'"
        )

        // Reset to default
        ShortcutManager.shared.resetToDefault(tool: .toggleClickEffects)
        XCTAssertEqual(
            ShortcutManager.shared.getShortcut(for: .toggleClickEffects),
            ShortcutKey.toggleClickEffects.defaultKey,
            "Toggle Cursor Highlight shortcut should be reset to default"
        )
    }

    // MARK: - Default Shortcut Tests

    func testClearShortcutUnbindsWithoutRestoringDefault() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults)

        XCTAssertEqual(manager.getShortcut(for: .pen), "p")
        manager.setShortcut("f", for: .pen)
        manager.clearShortcut(tool: .pen)
        XCTAssertEqual(manager.getShortcut(for: .pen), "")
        XCTAssertFalse(manager.isShortcutTaken("", excluding: .arrow))
        XCTAssertFalse(manager.matches("p", tool: .pen))
        XCTAssertFalse(manager.matches("", tool: .pen))

        manager.setShortcut("p", for: .arrow)
        XCTAssertEqual(manager.getShortcut(for: .arrow), "p")
        XCTAssertEqual(manager.getShortcut(for: .pen), "")
    }

    func testResetToDefaultRestoresLetterAfterClear() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults)

        manager.clearShortcut(tool: .pen)
        XCTAssertEqual(manager.getShortcut(for: .pen), "")
        XCTAssertTrue(manager.resetToDefault(tool: .pen))
        XCTAssertEqual(manager.getShortcut(for: .pen), ShortcutKey.pen.defaultKey)
        XCTAssertTrue(manager.matches("p", tool: .pen))
    }

    func testResetToDefaultRejectsAReassignedDefault() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults)

        manager.clearShortcut(tool: .pen)
        manager.setShortcut("p", for: .arrow)

        XCTAssertFalse(manager.resetToDefault(tool: .pen))
        XCTAssertEqual(manager.getShortcut(for: .pen), "")
        XCTAssertEqual(manager.getShortcut(for: .arrow), "p")
    }

    func testResetAllRestoresLetterDefaultsAndLeavesDimmingUnset() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults)

        manager.clearShortcut(tool: .pen)
        manager.setShortcut("y", for: .arrow)
        manager.setShortcut("j", for: .toggleBackgroundDimming)
        manager.resetAllToDefault()

        XCTAssertEqual(manager.getShortcut(for: .pen), "p")
        XCTAssertEqual(manager.getShortcut(for: .arrow), "a")
        XCTAssertEqual(manager.getShortcut(for: .toggleBackgroundDimming), "")
        XCTAssertEqual(ShortcutKey.toggleBackgroundDimming.defaultKey, "")
    }

    func testDimmingShortcutIsUnassignedUntilConfiguredAndCanBeCleared() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults)

        XCTAssertEqual(manager.getShortcut(for: .toggleBackgroundDimming), "")
        manager.setShortcut("j", for: .toggleBackgroundDimming)
        XCTAssertEqual(
            ShortcutManager(userDefaults: defaults).getShortcut(for: .toggleBackgroundDimming), "j")

        manager.setShortcut("p", for: .toggleBackgroundDimming)
        XCTAssertEqual(manager.getShortcut(for: .toggleBackgroundDimming), "j", "Pen already uses p")

        manager.clearShortcut(tool: .toggleBackgroundDimming)
        XCTAssertEqual(manager.getShortcut(for: .toggleBackgroundDimming), "")
        manager.setShortcut("j", for: .toggleBackgroundDimming)
        manager.resetToDefault(tool: .toggleBackgroundDimming)
        XCTAssertEqual(manager.getShortcut(for: .toggleBackgroundDimming), "")
        manager.setShortcut("j", for: .toggleBackgroundDimming)
        manager.resetAllToDefault()
        XCTAssertEqual(manager.getShortcut(for: .toggleBackgroundDimming), "")
    }

    func testMatchesIgnoresEmptyBindingsAndEmptyKeys() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults)

        XCTAssertTrue(manager.matches("p", tool: .pen))
        XCTAssertFalse(manager.matches("", tool: .pen))
        XCTAssertFalse(manager.matches("p", tool: .arrow))

        manager.clearShortcut(tool: .pen)
        XCTAssertFalse(manager.matches("p", tool: .pen))
        XCTAssertFalse(manager.matches("", tool: .pen))
        XCTAssertFalse(manager.matches("", tool: .toggleBackgroundDimming))
    }

    func testUnassignedShortcutsDoNotConflict() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults)

        XCTAssertFalse(manager.isShortcutTaken("", excluding: .pen))
        manager.setShortcut("", for: .pen)
        manager.setShortcut("", for: .arrow)
        XCTAssertEqual(manager.getShortcut(for: .pen), "")
        XCTAssertEqual(manager.getShortcut(for: .arrow), "")
    }
    
    func testColorShortcutsAreUnassignedAndFollowThePalette() {
        XCTAssertEqual(ShortcutKey.colorActions.compactMap(\.paletteColor), PaletteColor.allCases)
        for action in ShortcutKey.colorActions {
            XCTAssertEqual(action.defaultBinding, .unassigned, action.displayName)
            XCTAssertTrue(ShortcutKey.newlyEditable.contains(action), action.displayName)
        }
        XCTAssertEqual(ShortcutKey.color(.indigo).displayName, "Indigo Color")
        XCTAssertNil(ShortcutKey.colorPicker.paletteColor)
    }

    func testUseDigitsForColorsBindsThePaletteInOrder() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults) { _ in nil }

        XCTAssertEqual(manager.assignDigitsToColors(), [])

        for (index, color) in PaletteColor.allCases.enumerated() {
            XCTAssertEqual(manager.binding(for: .color(color)), ShortcutBinding(String(index + 1)), "\(color)")
        }
    }

    func testUseDigitsForColorsLeavesExistingDigitBindingsAlone() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults) { _ in nil }
        XCTAssertTrue(manager.setShortcut("3", for: .pen))
        XCTAssertTrue(manager.setShortcut("j", for: .color(.yellow)))
        // A digit another color holds moves to its own color.
        XCTAssertTrue(manager.setShortcut("1", for: .color(.orange)))

        let skipped = manager.assignDigitsToColors()

        XCTAssertEqual(skipped, [.init(color: .yellow, digit: "3", owner: "Pen")])
        XCTAssertEqual(manager.binding(for: .pen), ShortcutBinding("3"))
        XCTAssertEqual(manager.binding(for: .color(.yellow)), ShortcutBinding("j"), "Yellow keeps its binding")
        XCTAssertEqual(manager.binding(for: .color(.red)), ShortcutBinding("1"))
        XCTAssertEqual(manager.binding(for: .color(.orange)), ShortcutBinding("2"))
        XCTAssertEqual(manager.binding(for: .color(.black)), ShortcutBinding("9"))
        XCTAssertEqual(
            ColorShortcutsRow.message(forSkipped: skipped),
            "Left 3 (Pen) alone because it's already assigned.")
    }

    func testTheColorsRowSortsLikeAKeyboard() {
        let cases: [(String, [PaletteColor: ShortcutBinding], [PaletteColor])] = [
            ("no bindings keep palette order", [:], PaletteColor.allCases),
            (
                "digits run 1 to 9, then 0",
                [.red: ShortcutBinding("0"), .orange: ShortcutBinding("9"), .yellow: ShortcutBinding("1")],
                [.yellow, .orange, .red, .green, .cyan, .indigo, .magenta, .white, .black]
            ),
            (
                "other bare keys follow the 0 in ASCII order, Shift+letter as its capital",
                [
                    .red: ShortcutBinding("j"), .orange: ShortcutBinding("J", modifiers: .shift),
                    .yellow: ShortcutBinding(";"), .green: ShortcutBinding("0"), .cyan: ShortcutBinding("2"),
                ],
                [.cyan, .green, .yellow, .orange, .red, .indigo, .magenta, .white, .black]
            ),
            (
                "other chords come after every bare key, then colors with no key",
                [
                    .red: ShortcutBinding("1", modifiers: .command), .orange: ShortcutBinding("z"),
                    .yellow: ShortcutBinding("1", modifiers: .shift), .green: ShortcutBinding("a", modifiers: .option),
                ],
                [.orange, .yellow, .red, .green, .cyan, .indigo, .magenta, .white, .black]
            ),
        ]
        for (name, bindings, expected) in cases {
            XCTAssertEqual(ColorShortcutsRow.keyboardOrder(of: bindings), expected, name)
        }
    }

    func testColorPickerNumbersFollowTheColorShortcuts() {
        func numbers(_ keys: [PaletteColor: ShortcutBinding]) -> [Int] {
            ShortcutManager.colorPickerNumbers(for: PaletteColor.allCases.map { keys[$0] ?? .unassigned })
        }
        let cases: [(String, [PaletteColor: ShortcutBinding], [Int])] = [
            ("no bindings", [:], [1, 2, 3, 4, 5, 6, 7, 8, 9]),
            ("one rebind", [.green: ShortcutBinding("7")], [1, 2, 3, 7, 5, 6, 4, 8, 9]),
            ("a chain", [.red: ShortcutBinding("2"), .orange: ShortcutBinding("3")], [2, 3, 1, 4, 5, 6, 7, 8, 9]),
            ("two left over", [.red: ShortcutBinding("9"), .orange: ShortcutBinding("8")], [9, 8, 3, 4, 5, 6, 7, 1, 2]),
            ("every color moved", [
                .red: ShortcutBinding("7"), .orange: ShortcutBinding("3"), .yellow: ShortcutBinding("6"),
                .green: ShortcutBinding("8"), .cyan: ShortcutBinding("4"), .indigo: ShortcutBinding("9"),
                .magenta: ShortcutBinding("5"), .white: ShortcutBinding("2"), .black: ShortcutBinding("1"),
            ], [7, 3, 6, 8, 4, 9, 5, 2, 1]),
            ("a letter", [.red: ShortcutBinding("j")], [1, 2, 3, 4, 5, 6, 7, 8, 9]),
            ("a modified digit", [.red: ShortcutBinding("7", modifiers: .option)], [1, 2, 3, 4, 5, 6, 7, 8, 9]),
            ("zero", [.red: ShortcutBinding("0")], [1, 2, 3, 4, 5, 6, 7, 8, 9]),
        ]
        for (name, keys, expected) in cases {
            let result = numbers(keys)
            XCTAssertEqual(result, expected, name)
            XCTAssertEqual(result.sorted(), Array(1...9), "\(name): nine unique numbers")
        }
    }

    func testADigitBoundToAnotherActionLeavesThePickerNumbersAlone() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults) { _ in nil }
        XCTAssertTrue(manager.setShortcut("3", for: .pen))

        XCTAssertEqual(manager.colorPickerNumbers(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
    }

    func testRecordingAKeyAnotherColorHasSwapsTheTwo() throws {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults) { _ in nil }
        manager.assignDigitsToColors()

        let seven = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 26, characters: "7"))
        let swapped = ShortcutRecordingEventHandler.handle(seven, editingShortcut: .color(.red), manager: manager)

        XCTAssertNil(swapped.error)
        XCTAssertNil(swapped.editingShortcut)
        XCTAssertEqual(manager.binding(for: .color(.red)), ShortcutBinding("7"))
        XCTAssertEqual(manager.binding(for: .color(.magenta)), ShortcutBinding("1"))
        XCTAssertEqual(manager.colorPickerNumbers(), [7, 2, 3, 4, 5, 6, 1, 8, 9])

        // A key another kind of action has is still rejected.
        let pen = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 35, characters: "p"))
        let rejected = ShortcutRecordingEventHandler.handle(pen, editingShortcut: .color(.red), manager: manager)

        XCTAssertNotNil(rejected.error)
        XCTAssertEqual(manager.binding(for: .color(.red)), ShortcutBinding("7"))
        XCTAssertEqual(manager.binding(for: .pen), ShortcutBinding("p"))
    }

    func testUseDigitsForColorsRestoresPaletteOrderAfterASwap() {
        let defaults = TestUserDefaults.create()
        defer { TestUserDefaults.removeSuite() }
        let manager = ShortcutManager(userDefaults: defaults) { _ in nil }
        manager.assignDigitsToColors()
        XCTAssertTrue(manager.setColorShortcut(ShortcutBinding("7"), for: .color(.red)))
        XCTAssertTrue(manager.setColorShortcut(ShortcutBinding("2"), for: .color(.magenta)))

        XCTAssertEqual(manager.assignDigitsToColors(), [])

        for (index, color) in PaletteColor.allCases.enumerated() {
            XCTAssertEqual(manager.binding(for: .color(color)), ShortcutBinding(String(index + 1)), "\(color)")
        }
    }

    func testAllDefaultShortcuts() {
        // Test all default keyboard shortcuts
        XCTAssertEqual(ShortcutKey.pen.defaultKey, "p", "Pen should be 'p'")
        XCTAssertEqual(ShortcutKey.arrow.defaultKey, "a", "Arrow should be 'a'")
        XCTAssertEqual(ShortcutKey.line.defaultKey, "l", "Line should be 'l'")
        XCTAssertEqual(ShortcutKey.highlighter.defaultKey, "h", "Highlighter should be 'h'")
        XCTAssertEqual(ShortcutKey.rectangle.defaultKey, "r", "Rectangle should be 'r'")
        XCTAssertEqual(ShortcutKey.circle.defaultKey, "o", "Circle should be 'o'")
        XCTAssertEqual(ShortcutKey.redact.defaultKey, "x", "Redact should be 'x'")
        XCTAssertEqual(ShortcutKey.counter.defaultKey, "n", "Counter should be 'n'")
        XCTAssertEqual(ShortcutKey.text.defaultKey, "t", "Text should be 't'")
        XCTAssertEqual(ShortcutKey.select.defaultKey, "v", "Select should be 'v'")
        XCTAssertEqual(ShortcutKey.colorPicker.defaultKey, "c", "Color Picker should be 'c'")
        XCTAssertEqual(ShortcutKey.lineWidthPicker.defaultKey, "w", "Line Width should be 'w'")
        XCTAssertEqual(ShortcutKey.toggleBoard.defaultKey, "b", "Board should be 'b'")
        XCTAssertEqual(ShortcutKey.toggleClickEffects.defaultKey, "k", "Toggle Cursor Highlight should be 'k'")
        XCTAssertEqual(ShortcutKey.toggleBackgroundDimming.defaultKey, "")
    }
    
    func testNoShortcutConflicts() {
        // Only assigned defaults reserve a key.
        var shortcuts = Set<ShortcutBinding>()
        let assignedTools = ShortcutKey.allCases.filter { !$0.defaultKey.isEmpty }
        for tool in assignedTools {
            let shortcut = tool.defaultBinding
            XCTAssertFalse(
                shortcuts.contains(shortcut),
                "Shortcut '\(shortcut)' is used by multiple tools"
            )
            shortcuts.insert(shortcut)
        }
        
        XCTAssertEqual(shortcuts.count, assignedTools.count, "All assigned shortcuts should be unique")
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
