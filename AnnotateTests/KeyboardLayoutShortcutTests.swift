import XCTest

@testable import Annotate

@MainActor
final class KeyboardLayoutShortcutTests: XCTestCase {
    private var window: OverlayWindow!
    private var appDelegate: KeyboardLayoutAppDelegateSpy!
    private var originalAppDelegate: AppDelegate?
    private var originalShortcutManager: ShortcutManager!

    override func setUp() {
        super.setUp()
        let defaults = TestUserDefaults.create()
        originalAppDelegate = AppDelegate.shared
        originalShortcutManager = ShortcutManager.shared
        appDelegate = KeyboardLayoutAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = appDelegate
        ShortcutManager.shared = ShortcutManager(userDefaults: defaults)
        window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.overlayView.fadeMode = false
        window.undoManager?.groupsByEvent = false
    }

    override func tearDown() {
        window.stopFadeLoop()
        window.close()
        window = nil
        AppDelegate.shared = originalAppDelegate
        ShortcutManager.shared = originalShortcutManager
        appDelegate = nil
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testUndoFollowsQwertyAzertyAndQwertzCharacters() throws {
        for (layout, keyCode): (String, UInt16) in [("QWERTY", 6), ("AZERTY", 13), ("QWERTZ", 16)] {
            addUndoableArrow()

            window.keyDown(with: try keyEvent("z", keyCode: keyCode))

            XCTAssertTrue(window.overlayView.arrows.isEmpty, "Cmd+Z must undo on \(layout)")
            XCTAssertTrue(window.undoManager?.canRedo == true, layout)
            XCTAssertEqual(appDelegate.closeCount, 0, "Cmd+Z must not close the overlay on \(layout)")
        }
    }

    func testRedoFollowsQwertyAzertyAndQwertzCharacters() throws {
        for (layout, keyCode): (String, UInt16) in [("QWERTY", 6), ("AZERTY", 13), ("QWERTZ", 16)] {
            addUndoableArrow()
            window.overlayView.undo()
            XCTAssertTrue(window.overlayView.arrows.isEmpty)

            window.keyDown(with: try keyEvent("Z", keyCode: keyCode, modifiers: [.command, .shift]))

            XCTAssertEqual(window.overlayView.arrows.count, 1, "Cmd+Shift+Z must redo on \(layout)")
            XCTAssertEqual(appDelegate.closeCount, 0, "Redo must not close the overlay on \(layout)")
        }
    }

    func testCloseFollowsQwertyAndAzertyCharactersWithoutUndoing() throws {
        for (layout, keyCode): (String, UInt16) in [("QWERTY", 13), ("AZERTY", 6)] {
            addUndoableArrow()

            window.keyDown(with: try keyEvent("w", keyCode: keyCode))

            XCTAssertEqual(appDelegate.closeCount, 1, "Cmd+W must close the overlay on \(layout)")
            XCTAssertEqual(window.overlayView.arrows.count, 1, "Cmd+W must not undo on \(layout)")
        }
    }

    func testCounterResetFollowsQwertyAndDvorakCharacters() throws {
        window.overlayView.currentTool = .counter
        for keyCode: UInt16 in [15, 31] {
            window.overlayView.nextCounterNumber = 5

            window.keyDown(with: try keyEvent("r", keyCode: keyCode))

            XCTAssertEqual(window.overlayView.nextCounterNumber, 1)
        }
    }

    func testAzertyUndoRedoAndCloseThroughSendEvent() throws {
        addUndoableArrow()

        window.sendEvent(try keyEvent("z", keyCode: 13))
        XCTAssertTrue(window.overlayView.arrows.isEmpty)
        XCTAssertEqual(appDelegate.closeCount, 0)

        window.sendEvent(try keyEvent("Z", keyCode: 13, modifiers: [.command, .shift]))
        XCTAssertEqual(window.overlayView.arrows.count, 1)
        XCTAssertEqual(appDelegate.closeCount, 0)

        window.sendEvent(try keyEvent("w", keyCode: 6))
        XCTAssertEqual(appDelegate.closeCount, 1)
        XCTAssertEqual(window.overlayView.arrows.count, 1)
    }

    func testDvorakKeysAtQwertyShortcutPositionsDoNotTriggerCommands() throws {
        addUndoableArrow()
        window.overlayView.currentTool = .counter
        window.overlayView.nextCounterNumber = 5

        for (character, keyCode): (String, UInt16) in [(";", 6), (",", 13), ("p", 15)] {
            window.keyDown(with: try keyEvent(character, keyCode: keyCode))
        }

        XCTAssertEqual(window.overlayView.arrows.count, 1)
        XCTAssertEqual(appDelegate.closeCount, 0)
        XCTAssertEqual(window.overlayView.nextCounterNumber, 5)
    }

    func testLayoutCharactersRequireCommandModifier() throws {
        addUndoableArrow()
        window.overlayView.currentTool = .counter
        window.overlayView.nextCounterNumber = 5

        for (character, keyCode): (String, UInt16) in [("z", 13), ("w", 6), ("r", 31)] {
            window.keyDown(with: try keyEvent(character, keyCode: keyCode, modifiers: .control))
        }

        XCTAssertEqual(window.overlayView.arrows.count, 1)
        XCTAssertEqual(appDelegate.closeCount, 0)
        XCTAssertEqual(window.overlayView.nextCounterNumber, 5)
    }

    private func addUndoableArrow() {
        appDelegate.closeCount = 0
        window.undoManager?.removeAllActions()
        let arrow = TestFactory.createArrow()
        window.overlayView.arrows = [arrow]
        window.undoManager?.beginUndoGrouping()
        window.overlayView.registerUndo(action: .addArrow(arrow))
        window.undoManager?.endUndoGrouping()
    }

    private func keyEvent(
        _ character: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = .command
    ) throws -> NSEvent {
        try XCTUnwrap(TestEvents.createKeyEvent(
            type: .keyDown, keyCode: keyCode, modifierFlags: modifiers,
            characters: character, windowNumber: window.windowNumber))
    }
}

@MainActor
private final class KeyboardLayoutAppDelegateSpy: AppDelegate {
    var closeCount = 0

    override func closeOverlay() {
        closeCount += 1
    }
}
