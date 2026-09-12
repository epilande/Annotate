import XCTest

@testable import Annotate

@MainActor
final class BackgroundDimmingShortcutTests: XCTestCase {
    private var window: OverlayWindow!
    private var originalCursorManager: CursorHighlightManager!
    private var originalShortcutManager: ShortcutManager!

    override func setUp() {
        super.setUp()
        let defaults = TestUserDefaults.create()
        originalCursorManager = CursorHighlightManager.shared
        originalShortcutManager = ShortcutManager.shared
        CursorHighlightManager.shared = CursorHighlightManager(userDefaults: defaults)
        ShortcutManager.shared = ShortcutManager(userDefaults: defaults)
        window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.overlayView.pickerUserDefaultsOverride = defaults
    }

    override func tearDown() {
        window.stopFadeLoop()
        window.orderOut(nil)
        window = nil
        CursorHighlightManager.shared = originalCursorManager
        ShortcutManager.shared = originalShortcutManager
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testAssignedKeyTogglesDimmingAndClearedKeyDoesNothing() throws {
        let manager = CursorHighlightManager.shared
        let key = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 38, characters: "j"))
        window.keyDown(with: key)
        XCTAssertFalse(manager.cursorHighlightEnabled)

        ShortcutManager.shared.setShortcut("j", for: .toggleBackgroundDimming)
        window.keyDown(with: key)
        XCTAssertTrue(manager.cursorHighlightEnabled)
        XCTAssertTrue(manager.spotlightDimmingEnabled)

        window.keyDown(with: key)
        XCTAssertFalse(manager.spotlightDimmingEnabled)
        XCTAssertTrue(manager.cursorHighlightEnabled)

        ShortcutManager.shared.resetToDefault(tool: .toggleBackgroundDimming)
        window.keyDown(with: key)
        XCTAssertFalse(manager.spotlightDimmingEnabled)
    }

    func testEmptyKeyDoesNotMatchUnassignedShortcut() throws {
        let key = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 0, characters: ""))
        window.keyDown(with: key)
        XCTAssertFalse(CursorHighlightManager.shared.cursorHighlightEnabled)
        XCTAssertFalse(CursorHighlightManager.shared.spotlightDimmingEnabled)
    }

    func testBracketBindingsTakePrecedenceOverSizeStepping() throws {
        let manager = CursorHighlightManager.shared
        window.overlayView.currentTool = .pen

        for (characters, keyCode): (String, UInt16) in [("[", 33), ("]", 30)] {
            ShortcutManager.shared.setShortcut(characters, for: .toggleBackgroundDimming)
            for useSendEvent in [false, true] {
                manager.cursorHighlightEnabled = false
                manager.spotlightDimmingEnabled = false
                window.overlayView.currentLineWidth = 3
                let key = try XCTUnwrap(TestEvents.createKeyEvent(
                    type: .keyDown, keyCode: keyCode, characters: characters,
                    windowNumber: window.windowNumber))
                let repeatKey = try XCTUnwrap(TestEvents.createKeyEvent(
                    type: .keyDown, keyCode: keyCode, characters: characters,
                    windowNumber: window.windowNumber, isARepeat: true))

                if useSendEvent {
                    window.sendEvent(key)
                    window.sendEvent(repeatKey)
                } else {
                    window.keyDown(with: key)
                    window.keyDown(with: repeatKey)
                }

                XCTAssertTrue(manager.cursorHighlightEnabled)
                XCTAssertTrue(manager.spotlightDimmingEnabled)
                XCTAssertEqual(window.overlayView.currentLineWidth, 3)

                if useSendEvent {
                    window.sendEvent(key)
                } else {
                    window.keyDown(with: key)
                }
                XCTAssertFalse(manager.spotlightDimmingEnabled)
                XCTAssertTrue(manager.cursorHighlightEnabled)
                XCTAssertEqual(window.overlayView.currentLineWidth, 3)
            }
        }
    }

    func testRepeatsAndModifiedKeysDoNotToggleDimming() throws {
        ShortcutManager.shared.setShortcut("j", for: .toggleBackgroundDimming)
        let repeatKey = try XCTUnwrap(TestEvents.createKeyEvent(
            type: .keyDown, keyCode: 38, characters: "j", isARepeat: true))
        window.keyDown(with: repeatKey)
        XCTAssertFalse(CursorHighlightManager.shared.spotlightDimmingEnabled)

        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            let key = try XCTUnwrap(TestEvents.createKeyEvent(
                type: .keyDown, keyCode: 38, modifierFlags: modifiers, characters: "j"))
            window.keyDown(with: key)
            XCTAssertFalse(CursorHighlightManager.shared.spotlightDimmingEnabled)
        }
    }

    func testShortcutDoesNotToggleWhileEditingAnnotationText() throws {
        window.overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "Label")
        XCTAssertNotNil(window.overlayView.activeTextField)
        for (characters, keyCode): (String, UInt16) in [("j", 38), ("[", 33), ("]", 30)] {
            ShortcutManager.shared.setShortcut(characters, for: .toggleBackgroundDimming)
            let key = try XCTUnwrap(TestEvents.createKeyEvent(
                type: .keyDown, keyCode: keyCode, characters: characters))

            window.keyDown(with: key)

            XCTAssertFalse(CursorHighlightManager.shared.spotlightDimmingEnabled)
        }
    }
}
