import AppKit
import XCTest
@testable import Annotate

@MainActor
final class KeyChordTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ShortcutManager!

    override func setUp() {
        super.setUp()
        defaults = TestUserDefaults.create()
        manager = ShortcutManager(userDefaults: defaults) { _ in nil }
    }

    override func tearDown() {
        manager = nil
        TestUserDefaults.removeSuite()
        defaults = nil
        super.tearDown()
    }

    // MARK: - Construction

    func testPlainKeyUsesTheBaseLayerAndHasNoCommandLayer() throws {
        let chord = try keyChord("p", keyCode: 35)
        XCTAssertEqual(chord.key, "p")
        XCTAssertNil(chord.commandKey)
        XCTAssertEqual(chord.modifiers, [])
        XCTAssertEqual(chord.characters, "p")
        XCTAssertEqual(chord.keyCode, 35)
        XCTAssertFalse(chord.isRepeat)
    }

    func testCommandLayerComesFromCharactersOnlyWhileCommandIsHeld() throws {
        let command = try keyChord("W", keyCode: 13, modifiers: .command, ignoring: "w")
        XCTAssertEqual(command.key, "w")
        XCTAssertEqual(command.commandKey, "w")

        let control = try keyChord("\u{17}", keyCode: 13, modifiers: .control, ignoring: "w")
        XCTAssertEqual(control.key, "w")
        XCTAssertNil(control.commandKey, "Without Command there is no Command layer")
    }

    func testDvorakQwertyCommandSplitsTheLayers() throws {
        // Dvorak - QWERTY ⌘: the QWERTY W key types "," but Command+it reports "w".
        let chord = try keyChord("w", keyCode: 13, modifiers: .command, ignoring: ",")
        XCTAssertEqual(chord.key, ",")
        XCTAssertEqual(chord.commandKey, "w")
    }

    func testNonLatinLayoutsReportLatinLettersOnTheCommandLayer() throws {
        for (layout, character, base): (String, String, String) in [
            ("Russian", "z", "я"), ("Greek", "z", "ζ"), ("Hebrew", "z", "ז")
        ] {
            let chord = try keyChord(character, keyCode: 6, modifiers: .command, ignoring: base)
            XCTAssertEqual(chord.key, base, layout)
            XCTAssertEqual(chord.commandKey, "z", layout)
        }
    }

    func testShiftedKeysKeepTheirBaseLayerSymbolAndAreLowercased() throws {
        let bracket = try keyChord("{", keyCode: 33, modifiers: .shift)
        XCTAssertEqual(bracket.key, "{")
        XCTAssertEqual(bracket.modifiers, .shift)

        let letter = try keyChord("P", keyCode: 35, modifiers: .shift)
        XCTAssertEqual(letter.key, "p")
        XCTAssertEqual(letter.characters, "P", "Typed text keeps its case")

        // Measured on a U.S. layout: Command drops Shift from `characters` but not the base layer.
        let plus = try keyChord("=", keyCode: 24, modifiers: [.command, .shift], ignoring: "+")
        XCTAssertEqual(plus.key, "+")
        XCTAssertEqual(plus.commandKey, "=")
        let redo = try keyChord("z", keyCode: 6, modifiers: [.command, .shift], ignoring: "Z")
        XCTAssertEqual(redo.key, "z")
        XCTAssertEqual(redo.commandKey, "z")
    }

    func testOptionLayerCharactersDoNotLeakIntoTheBaseKey() throws {
        // Measured on a U.S. layout: Option+Command+T reports "†" in `characters`.
        let chord = try keyChord("†", keyCode: 17, modifiers: [.option, .command], ignoring: "t")
        XCTAssertEqual(chord.key, "t")
        XCTAssertEqual(chord.commandKey, "†")
    }

    func testOnlyShortcutModifiersAreKept() throws {
        let chord = try keyChord(
            "t", keyCode: 17, modifiers: [.command, .option, .control, .shift, .capsLock, .function, .numericPad])
        XCTAssertEqual(chord.modifiers, [.command, .option, .control, .shift])
    }

    func testKeysThatTypeNothingUsefulAreMappedByKeyCode() throws {
        for (keyCode, raw, expected): (UInt16, String, String) in [
            (49, "", " "), (51, "\u{7f}", "\u{7f}"), (117, "\u{f728}", "\u{7f}"), (53, "\u{1b}", "\u{1b}"),
            (36, "\r", "\r"), (76, "\u{3}", "\r"), (48, "\t", "\t")
        ] {
            XCTAssertEqual(try keyChord(raw, keyCode: keyCode).key, expected, "key code \(keyCode)")
        }
        XCTAssertEqual(try keyChord("\u{8}", keyCode: 0).key, "\u{7f}", "Backspace characters normalize like bindings")
    }

    func testKeyUpAndRepeatsParseButOtherEventsDoNot() throws {
        let keyUp = try XCTUnwrap(KeyChord(event: try keyEvent("c", keyCode: 8, type: .keyUp)))
        XCTAssertEqual(keyUp.key, "c")
        XCTAssertTrue(try keyChord("c", keyCode: 8, isARepeat: true).isRepeat)

        let click = try XCTUnwrap(TestEvents.createMouseEvent(type: .leftMouseDown, location: .zero))
        XCTAssertNil(KeyChord(event: click))
        XCTAssertNil(ShortcutBinding(event: click))
    }

    func testBindingFromChordRequiresASingleKey() throws {
        XCTAssertEqual(
            ShortcutBinding(chord: try keyChord("∆", keyCode: 38, modifiers: [.option, .command], ignoring: "j")),
            ShortcutBinding("j", modifiers: [.option, .command]))
        XCTAssertNil(ShortcutBinding(chord: try keyChord("", keyCode: 0)))
        XCTAssertNil(ShortcutBinding(chord: try keyChord("ab", keyCode: 0)))
    }

    // MARK: - Matching

    func testDefaultMatchingIsExactOnTheBaseLayer() throws {
        let pen = ShortcutBinding("p")
        XCTAssertTrue(pen.matches(try keyChord("p", keyCode: 35)))
        XCTAssertFalse(pen.matches(try keyChord("P", keyCode: 35, modifiers: .shift)))
        XCTAssertFalse(pen.matches(try keyChord("p", keyCode: 35, modifiers: .command)))
        XCTAssertFalse(pen.matches(try keyChord("o", keyCode: 31)))
    }

    func testIgnoringAllowsOnlyTheListedExtraModifiers() throws {
        let close = ShortcutBinding("w", modifiers: .command)
        let shifted = try keyChord("w", keyCode: 13, modifiers: [.command, .shift], ignoring: "W")
        XCTAssertFalse(close.matches(shifted, on: .command))
        XCTAssertTrue(close.matches(shifted, on: .command, ignoring: .shift))
        XCTAssertFalse(close.matches(
            try keyChord("w", keyCode: 13, modifiers: [.command, .option]), on: .command, ignoring: .shift))

        let undo = ShortcutBinding("z", modifiers: .command)
        let redo = ShortcutBinding("z", modifiers: [.command, .shift])
        let shiftZ = try keyChord("z", keyCode: 6, modifiers: [.command, .shift, .option], ignoring: "Z")
        XCTAssertFalse(undo.matches(shiftZ, on: .command, ignoring: [.option, .control]))
        XCTAssertTrue(redo.matches(shiftZ, on: .command, ignoring: [.option, .control]))
    }

    // MARK: - #99 regressions: fixed Command shortcuts follow the Command layer

    func testDvorakQwertyCommandMatchesFixedCommandsOnTheCommandLayer() throws {
        let close = ShortcutBinding("w", modifiers: .command)
        let commandW = try keyChord("w", keyCode: 13, modifiers: .command, ignoring: ",")
        XCTAssertTrue(close.matches(commandW, on: .command))
        XCTAssertFalse(close.matches(commandW), "The base layer misses Command+W on Dvorak - QWERTY ⌘")
    }

    func testDvorakQwertyCommandBaseLayerAliasesDoNotMatchFixedCommands() throws {
        // The base letter behind Command+, Command+/ and Command+O is "w", "z" and "r".
        for (binding, character, keyCode, base): (String, String, UInt16, String) in [
            ("w", ",", 43, "w"), ("z", "/", 44, "z"), ("r", "o", 31, "r")
        ] {
            let chord = try keyChord(character, keyCode: keyCode, modifiers: .command, ignoring: base)
            let fixed = ShortcutBinding(binding, modifiers: .command)
            XCTAssertFalse(fixed.matches(chord, on: .command), "Command+\(character) must not alias Command+\(binding)")
            XCTAssertTrue(fixed.matches(chord), "The base layer would alias Command+\(character)")
        }
    }

    func testRussianCommandLayerMatchesUndoAndCounterReset() throws {
        XCTAssertTrue(ShortcutBinding("z", modifiers: .command)
            .matches(try keyChord("z", keyCode: 6, modifiers: .command, ignoring: "я"), on: .command))
        XCTAssertTrue(ShortcutBinding("r", modifiers: .command)
            .matches(try keyChord("r", keyCode: 15, modifiers: .command, ignoring: "к"), on: .command))
    }

    func testPlainDvorakLettersAtQwertyPositionsDoNotMatch() throws {
        for (binding, character, keyCode): (String, String, UInt16) in [("z", ";", 6), ("w", ",", 13), ("r", "p", 15)] {
            let chord = try keyChord(character, keyCode: keyCode, modifiers: .command)
            XCTAssertFalse(ShortcutBinding(binding, modifiers: .command).matches(chord, on: .command))
        }
    }

    func testCommandLayerNeverMatchesWithoutCommand() throws {
        let chord = try keyChord("z", keyCode: 6, modifiers: .control)
        XCTAssertFalse(ShortcutBinding("z", modifiers: .control).matches(chord, on: .command))
        XCTAssertTrue(ShortcutBinding("z", modifiers: .control).matches(chord))
    }

    // MARK: - #94 regressions: cleared shortcuts never fire

    func testUnassignedBindingMatchesNoChord() throws {
        for chord in [
            try keyChord("", keyCode: 0), try keyChord("", keyCode: 49), try keyChord("p", keyCode: 35),
            try keyChord("w", keyCode: 13, modifiers: .command)
        ] {
            XCTAssertFalse(ShortcutBinding.unassigned.matches(chord))
            XCTAssertFalse(ShortcutBinding.unassigned.matches(chord, on: .command))
        }
    }

    func testClearedToolNoLongerClaimsItsKey() throws {
        let p = try keyChord("p", keyCode: 35)
        XCTAssertEqual(manager.action(for: p), .pen)
        manager.clearShortcut(tool: .pen)
        XCTAssertNil(manager.action(for: p))
        XCTAssertFalse(manager.matches(p, tool: .pen))
        XCTAssertNil(manager.action(for: try keyChord("", keyCode: 0)), "An empty key must not match Not Set")
    }

    // MARK: - #100 regressions: customizable chords match exact modifiers on the base layer

    func testCustomModifierChordMatchesExactlyDespiteOptionLayerCharacters() throws {
        XCTAssertTrue(manager.setShortcut(ShortcutBinding("p", modifiers: .option), for: .pen))
        XCTAssertEqual(manager.action(for: try keyChord("π", keyCode: 35, modifiers: .option, ignoring: "p")), .pen)
        XCTAssertNil(manager.action(for: try keyChord("p", keyCode: 35)))
        XCTAssertNil(manager.action(for: try keyChord("π", keyCode: 35, modifiers: [.option, .control], ignoring: "p")))
    }

    func testDefaultToolbarChordMatchesOnTheBaseLayer() throws {
        let chord = try keyChord("†", keyCode: 17, modifiers: [.option, .command], ignoring: "t")
        XCTAssertEqual(manager.action(for: chord), .toggleToolbar)
        XCTAssertNil(manager.action(for: try keyChord("†", keyCode: 17, modifiers: .option, ignoring: "t")))
    }

    func testCustomCommandShiftPunctuationMatchesTheRecordedSymbol() throws {
        // Measured on a U.S. layout: recorded from the base layer as "{", while the Command layer
        // reports "[" for the same press.
        let chord = try keyChord("[", keyCode: 33, modifiers: [.command, .shift], ignoring: "{")
        let recorded = try XCTUnwrap(ShortcutBinding(chord: chord))
        XCTAssertEqual(recorded, ShortcutBinding("{", modifiers: [.command, .shift]))
        XCTAssertTrue(manager.setShortcut(recorded, for: .toggleFade))
        XCTAssertEqual(manager.action(for: chord), .toggleFade)
    }

    func testOptionDeleteMatchesBackspaceAndForwardDelete() throws {
        XCTAssertEqual(manager.action(for: try keyChord("\u{7f}", keyCode: 51, modifiers: .option)), .clearAll)
        XCTAssertEqual(
            manager.action(for: try keyChord("\u{f728}", keyCode: 117, modifiers: [.option, .function])), .clearAll)
        XCTAssertNil(manager.action(for: try keyChord("\u{7f}", keyCode: 51)))
    }

    // MARK: - Helpers

    private func keyEvent(
        _ characters: String, keyCode: UInt16, type: NSEvent.EventType = .keyDown,
        modifiers: NSEvent.ModifierFlags = [], ignoring: String? = nil, isARepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(TestEvents.createKeyEvent(
            type: type, keyCode: keyCode, modifierFlags: modifiers, characters: characters,
            charactersIgnoringModifiers: ignoring, isARepeat: isARepeat))
    }

    private func keyChord(
        _ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [],
        ignoring: String? = nil, isARepeat: Bool = false
    ) throws -> KeyChord {
        try XCTUnwrap(KeyChord(event: try keyEvent(
            characters, keyCode: keyCode, modifiers: modifiers, ignoring: ignoring, isARepeat: isARepeat)))
    }
}
