import AppKit
import KeyboardShortcuts
import XCTest
@testable import Annotate

@MainActor
final class ShortcutBindingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ShortcutManager!
    private var globalShortcuts: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut] = [:]

    override func setUp() {
        super.setUp()
        defaults = TestUserDefaults.create()
        globalShortcuts = [:]
        manager = ShortcutManager(userDefaults: defaults) { [weak self] in self?.globalShortcuts[$0] }
    }

    override func tearDown() {
        manager = nil
        TestUserDefaults.removeSuite()
        defaults = nil
        super.tearDown()
    }

    func testLegacyBindingsAndClearedValuesSurviveReload() {
        defaults.set("j", forKey: "shortcut.p")
        defaults.set("", forKey: "shortcut.a")
        defaults.set("]", forKey: "shortcut.e")
        defaults.set(" ", forKey: "shortcut.k")
        let migrated = ShortcutManager(userDefaults: defaults)
        XCTAssertEqual(migrated.binding(for: .pen), ShortcutBinding("j"))
        XCTAssertEqual(migrated.binding(for: .arrow), .unassigned)
        XCTAssertEqual(migrated.binding(for: .eraser), ShortcutBinding("]"))
        XCTAssertEqual(migrated.binding(for: .increaseSize), .unassigned)
        XCTAssertEqual(migrated.binding(for: .toggleFade), .unassigned)
        XCTAssertEqual(migrated.binding(for: .decreaseSize), ShortcutBinding("["))
        XCTAssertFalse(migrated.resetToDefault(tool: .increaseSize))
        migrated.clearShortcut(tool: .eraser)
        XCTAssertEqual(ShortcutManager(userDefaults: defaults).binding(for: .increaseSize), .unassigned)
        XCTAssertTrue(migrated.resetToDefault(tool: .increaseSize))
        XCTAssertEqual(migrated.binding(for: .increaseSize), ShortcutBinding("]"))
    }

    func testModifierBindingsPersistAndCompareWholeChord() {
        let chord = ShortcutBinding("p", modifiers: [.command, .option])
        XCTAssertTrue(manager.setShortcut(chord, for: .toggleFade))
        XCTAssertEqual(ShortcutManager(userDefaults: defaults).binding(for: .toggleFade), chord)
        XCTAssertEqual(manager.binding(for: .pen), ShortcutBinding("p"))
        XCTAssertFalse(manager.setShortcut(chord, for: .toggleToolbar))
        XCTAssertEqual(manager.binding(for: .toggleToolbar), ShortcutKey.toggleToolbar.defaultBinding)
    }

    func testModifierBindingsSurvivePlistRoundTrip() throws {
        let writeSuite = "com.annotate.tests.modifiers-write.\(UUID().uuidString)"
        let readSuite = "com.annotate.tests.modifiers-read.\(UUID().uuidString)"
        let chord = ShortcutBinding("j", modifiers: [.option, .command])

        let writer = UserDefaults(suiteName: writeSuite)!
        defer {
            writer.removePersistentDomain(forName: writeSuite)
            writer.synchronize()
        }
        XCTAssertTrue(ShortcutManager(userDefaults: writer).setShortcut(chord, for: .toggleFade))
        XCTAssertTrue(writer.synchronize())

        // Persist through the plist format UserDefaults uses on disk, then
        // load the result in a *new* suite so we are not reading the writer's
        // in-memory cache. Decode the same way production does: NSNumber.
        let stored = try XCTUnwrap(writer.dictionary(forKey: "shortcut.toggleFade"))
        let data = try PropertyListSerialization.data(fromPropertyList: stored, format: .xml, options: 0)
        let roundTripped = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(
            (roundTripped["modifiers"] as? NSNumber)?.uintValue, chord.modifiers.rawValue)

        let reader = UserDefaults(suiteName: readSuite)!
        defer {
            reader.removePersistentDomain(forName: readSuite)
            reader.synchronize()
        }
        reader.set(roundTripped, forKey: "shortcut.toggleFade")
        XCTAssertEqual(ShortcutManager(userDefaults: reader).binding(for: .toggleFade), chord)
    }

    func testClearRestoreAndResetAllPreserveTheirDistinctMeanings() {
        manager.clearShortcut(tool: .clearAll)
        XCTAssertEqual(manager.binding(for: .clearAll), .unassigned)
        XCTAssertEqual(ShortcutManager(userDefaults: defaults).binding(for: .clearAll), .unassigned)
        XCTAssertTrue(manager.setShortcut(ShortcutKey.clearAll.defaultBinding, for: .toggleFade))
        XCTAssertFalse(manager.resetToDefault(tool: .clearAll))
        manager.clearShortcut(tool: .toggleFade)
        XCTAssertTrue(manager.resetToDefault(tool: .clearAll))
        manager.resetAllToDefault()
        for action in ShortcutKey.allCases {
            XCTAssertEqual(manager.binding(for: action), action.defaultBinding)
        }
        XCTAssertEqual(manager.binding(for: .toggleBackgroundDimming), .unassigned)
    }

    func testEventNormalizationUsesLogicalKeyAndExactModifiers() throws {
        let chord = try event("†", keyCode: 17, modifiers: [.option, .command, .capsLock], ignoring: "T")
        XCTAssertEqual(ShortcutBinding(event: chord), ShortcutKey.toggleToolbar.defaultBinding)
        XCTAssertEqual(manager.action(for: chord), .toggleToolbar)
        XCTAssertNil(manager.action(for: try event("t", keyCode: 17, modifiers: [.option, .command, .shift])))
        XCTAssertEqual(manager.action(for: try event("", keyCode: 49)), .toggleFade)
        XCTAssertEqual(manager.action(for: try event("", keyCode: 51, modifiers: .option)), .clearAll)
        XCTAssertEqual(manager.action(for: try event("", keyCode: 117, modifiers: [.option, .function])), .clearAll)
        XCTAssertNil(manager.action(for: try event("", keyCode: 0)))
        XCTAssertFalse(manager.matches("", tool: .toggleBackgroundDimming))
    }

    func testRecordingCapturesChordsAndConsumesTheEvent() throws {
        let result = ShortcutRecordingEventHandler.handle(
            try event("∆", keyCode: 38, modifiers: [.option, .command], ignoring: "j"),
            editingShortcut: .toggleFade, manager: manager)
        XCTAssertNil(result.editingShortcut)
        XCTAssertTrue(result.consumesEvent)
        XCTAssertNil(result.error)
        XCTAssertEqual(manager.binding(for: .toggleFade), ShortcutBinding("j", modifiers: [.option, .command]))
        XCTAssertEqual(manager.allShortcuts[.toggleFade], "⌥⌘J")
    }

    func testRecordingCapturesSpaceAndOptionDeleteWithoutTextEntry() throws {
        manager.clearShortcut(tool: .toggleFade)
        let space = ShortcutRecordingEventHandler.handle(
            try event("", keyCode: 49), editingShortcut: .toggleFade, manager: manager)
        XCTAssertNil(space.error)
        XCTAssertEqual(manager.binding(for: .toggleFade), ShortcutBinding(" "))
        manager.clearShortcut(tool: .clearAll)
        let delete = ShortcutRecordingEventHandler.handle(
            try event("", keyCode: 51, modifiers: .option), editingShortcut: .clearAll, manager: manager)
        XCTAssertNil(delete.error)
        XCTAssertEqual(manager.binding(for: .clearAll), ShortcutKey.clearAll.defaultBinding)
        XCTAssertEqual(manager.binding(for: .clearAll).menuKeyEquivalent, "\u{8}")
    }

    func testConflictingAndReservedEventsKeepRecordingAndPreserveBinding() throws {
        let events = [
            try event("p", keyCode: 35),
            try event("", keyCode: 51),
            try event("z", keyCode: 6, modifiers: .command),
            try event("z", keyCode: 6, modifiers: [.command, .shift]),
            try event("c", keyCode: 8, modifiers: .command),
            try event("b", keyCode: 11, modifiers: .command),
            try event("r", keyCode: 15, modifiers: .command),
            try event("w", keyCode: 13, modifiers: .command)
        ]
        for event in events {
            let result = ShortcutRecordingEventHandler.handle(event, editingShortcut: .toggleFade, manager: manager)
            XCTAssertEqual(result.editingShortcut, .toggleFade)
            XCTAssertNotNil(result.error)
            XCTAssertTrue(result.consumesEvent)
            XCTAssertEqual(manager.binding(for: .toggleFade), ShortcutKey.toggleFade.defaultBinding)
        }
    }

    func testFixedCommandValidationLeavesUnrelatedChordsAvailable() {
        XCTAssertFalse(manager.setShortcut(ShortcutBinding("b", modifiers: .command), for: .toggleFade))
        XCTAssertTrue(manager.setShortcut(ShortcutBinding("b", modifiers: [.command, .option]), for: .toggleFade))
        XCTAssertFalse(manager.setShortcut(ShortcutBinding("r", modifiers: .command), for: .toggleFade))
        XCTAssertTrue(manager.setShortcut(ShortcutBinding("r", modifiers: [.command, .shift]), for: .toggleFade))
        XCTAssertFalse(manager.setShortcut(ShortcutBinding("\u{7f}", modifiers: .shift), for: .toggleFade))
    }

    func testEscapeAndOutsideClickCancelWithoutChangingBinding() throws {
        let escape = ShortcutRecordingEventHandler.handle(
            try event("", keyCode: 53), editingShortcut: .toggleToolbar, manager: manager)
        XCTAssertNil(escape.editingShortcut)
        XCTAssertTrue(escape.consumesEvent)
        let click = try XCTUnwrap(TestEvents.createMouseEvent(type: .leftMouseDown, location: .zero))
        let outside = ShortcutRecordingEventHandler.handle(click, editingShortcut: .toggleToolbar, manager: manager)
        XCTAssertNil(outside.editingShortcut)
        XCTAssertFalse(outside.consumesEvent)
        XCTAssertEqual(manager.binding(for: .toggleToolbar), ShortcutKey.toggleToolbar.defaultBinding)
    }

    func testGlobalConflictsKeepRecordingAndPreserveTheLocalBinding() throws {
        globalShortcuts = [
            .toggleOverlay: .init(.j, modifiers: [.command, .option]),
            .toggleAlwaysOnMode: .init(.u, modifiers: [.command, .option])
        ]
        let wasEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
        defer { KeyboardShortcuts.isEnabled = wasEnabled }

        for (key, code, label): (String, UInt16, String) in [
            ("j", 38, "Activation Shortcut"), ("u", 32, "Always-On Mode")
        ] {
            let chord = ShortcutBinding(key, modifiers: [.command, .option])
            XCTAssertFalse(manager.setShortcut(chord, for: .toggleFade))
            let result = ShortcutRecordingEventHandler.handle(
                try event(key, keyCode: code, modifiers: [.command, .option]),
                editingShortcut: .toggleFade, manager: manager)
            XCTAssertEqual(result.editingShortcut, .toggleFade)
            XCTAssertTrue(result.consumesEvent)
            XCTAssertTrue(try XCTUnwrap(result.error).contains(label))
            XCTAssertEqual(manager.binding(for: .toggleFade), ShortcutKey.toggleFade.defaultBinding)
        }
    }

    func testGlobalConflictsUseExactModifiersAndAllowClearing() {
        globalShortcuts[.toggleOverlay] = .init(.j, modifiers: [.command, .option])
        XCTAssertTrue(manager.setShortcut(ShortcutBinding("j", modifiers: .command), for: .toggleFade))
        manager.clearShortcut(tool: .toggleFade)
        XCTAssertEqual(manager.binding(for: .toggleFade), .unassigned)
        globalShortcuts[.toggleOverlay] = nil
        XCTAssertTrue(manager.setShortcut(ShortcutBinding("j", modifiers: [.command, .option]), for: .toggleFade))
    }

    func testGlobalConflictNormalizationIncludesShiftPunctuationAndDeleteAliases() {
        globalShortcuts[.toggleOverlay] = .init(.leftBracket, modifiers: [.control, .shift])
        XCTAssertFalse(manager.setShortcut(ShortcutBinding("{", modifiers: [.control, .shift]), for: .toggleFade))
        XCTAssertTrue(manager.setShortcut(ShortcutBinding("[", modifiers: .control), for: .toggleFade))
        globalShortcuts[.toggleAlwaysOnMode] = .init(.deleteForward, modifiers: [.command, .option])
        XCTAssertFalse(manager.setShortcut(ShortcutBinding("\u{7f}", modifiers: [.command, .option]), for: .clearAll))
    }

    func testGlobalRecorderRestoresThePreviousBindingOnLocalConflict() {
        let name = KeyboardShortcuts.Name("testGlobalShortcutConflict")
        defer { KeyboardShortcuts.setShortcut(nil, for: name) }
        let candidate = KeyboardShortcuts.Shortcut(.j, modifiers: [.command, .option])
        XCTAssertTrue(manager.setShortcut(ShortcutBinding("j", modifiers: [.command, .option]), for: .toggleFade))

        for previous: KeyboardShortcuts.Shortcut? in [nil, .init(.u, modifiers: [.command, .option])] {
            // The library saves the candidate before invoking the recorder's callback.
            KeyboardShortcuts.setShortcut(candidate, for: name)
            let error = GlobalShortcutRecordingHandler.handle(
                candidate, for: name, previousShortcut: previous, manager: manager)
            XCTAssertTrue(error?.contains("Toggle Fade Mode") == true)
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), previous)
            XCTAssertEqual(manager.binding(for: .toggleFade), ShortcutBinding("j", modifiers: [.command, .option]))
        }
    }

    func testGlobalRecorderAcceptsAnAvailableBindingAndClearing() {
        let name = KeyboardShortcuts.Name("testAvailableGlobalShortcut")
        defer { KeyboardShortcuts.setShortcut(nil, for: name) }
        let candidate = KeyboardShortcuts.Shortcut(.j, modifiers: [.command, .option])
        KeyboardShortcuts.setShortcut(candidate, for: name)
        XCTAssertNil(GlobalShortcutRecordingHandler.handle(
            candidate, for: name, previousShortcut: nil, manager: manager))
        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), candidate)
        KeyboardShortcuts.setShortcut(nil, for: name)
        XCTAssertNil(GlobalShortcutRecordingHandler.handle(
            nil, for: name, previousShortcut: candidate, manager: manager))
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
    }

    func testGlobalRecorderChecksOtherGlobalActionsButExcludesItself() {
        let candidate = KeyboardShortcuts.Shortcut(.j, modifiers: [.command, .option])
        globalShortcuts[.toggleOverlay] = candidate
        XCTAssertEqual(manager.conflictForGlobalShortcut(candidate, excluding: .toggleAlwaysOnMode), "Activation Shortcut")
        XCTAssertNil(manager.conflictForGlobalShortcut(candidate, excluding: .toggleOverlay))
    }

    func testMigrationAndResetDoNotReintroduceGlobalConflicts() {
        globalShortcuts[.toggleOverlay] = .init(.t, modifiers: [.command, .option])
        manager = ShortcutManager(userDefaults: defaults) { [weak self] in self?.globalShortcuts[$0] }
        XCTAssertEqual(manager.binding(for: .toggleToolbar), .unassigned)
        XCTAssertFalse(manager.resetToDefault(tool: .toggleToolbar))
        manager.resetAllToDefault()
        XCTAssertEqual(manager.binding(for: .toggleToolbar), .unassigned)
        XCTAssertEqual(manager.binding(for: .toggleFade), ShortcutKey.toggleFade.defaultBinding)
        globalShortcuts[.toggleOverlay] = nil
        XCTAssertTrue(manager.resetToDefault(tool: .toggleToolbar))
        XCTAssertEqual(manager.binding(for: .toggleToolbar), ShortcutKey.toggleToolbar.defaultBinding)
    }

    private func event(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [],
                       ignoring: String? = nil) throws -> NSEvent {
        try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: keyCode,
            modifierFlags: modifiers, characters: characters, charactersIgnoringModifiers: ignoring))
    }
}
