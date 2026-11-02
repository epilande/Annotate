import XCTest

@testable import Annotate

/// A Clear All that empties several displays links their undo steps (`LinkedClear`). These
/// tests stand two overlays side by side, so they need no second display.
@MainActor
final class LinkedClearTests: XCTestCase {
    var first: OverlayWindow!
    var second: OverlayWindow!

    override func setUp() {
        super.setUp()
        TestWindows.recordOpenWindows()
        AppDelegate.shared = nil
        first = makeOverlay(x: 0)
        second = makeOverlay(x: 800)
    }

    override func tearDown() {
        for window in [first, second] {
            window?.stopFadeLoop()
            window?.close()
        }
        first = nil
        second = nil
        assertNoLeakedWindows()
        super.tearDown()
    }

    private func makeOverlay(x: CGFloat) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: NSRect(x: x, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        // Undo drops annotations past their fade, and a CI stall could outlast it.
        window.overlayView.fadeMode = false
        return window
    }

    /// Ends the run-loop pass, which closes the undo group AppKit opens per event, so each
    /// call below is a step of its own.
    private func endEvent() {
        wait(for: 0.01)
    }

    /// Draws an arrow as one undoable step.
    @discardableResult
    private func draw(on window: OverlayWindow, x: CGFloat = 10) -> Arrow {
        let arrow = TestFactory.createArrow(
            start: NSPoint(x: x, y: 10), end: NSPoint(x: x + 50, y: 60))
        window.overlayView.arrows.append(arrow)
        window.overlayView.registerUndo(action: .addArrow(arrow))
        endEvent()
        return arrow
    }

    private func clear(_ windows: [OverlayWindow]) -> Bool {
        let cleared = OverlayWindow.performClearAll(on: windows)
        endEvent()
        return cleared
    }

    private func arrows(on window: OverlayWindow) -> [Arrow] {
        window.overlayView.arrows
    }

    // MARK: - Undo and Redo

    func testOneUndoOnEitherDisplayRestoresEveryDisplayTheClearEmptied() {
        for undoing in [first!, second!] {
            let firstArrow = draw(on: first)
            let secondArrow = draw(on: second)
            XCTAssertTrue(clear([first, second]))
            XCTAssertTrue(arrows(on: first).isEmpty)
            XCTAssertTrue(arrows(on: second).isEmpty)

            undoing.overlayView.undo()

            XCTAssertEqual(arrows(on: first), [firstArrow])
            XCTAssertEqual(arrows(on: second), [secondArrow])
            first.overlayView.arrows.removeAll()
            second.overlayView.arrows.removeAll()
        }
    }

    func testOneRedoOnAnyDisplayClearsThemAllAgain() {
        let firstArrow = draw(on: first)
        let secondArrow = draw(on: second)
        XCTAssertTrue(clear([first, second]))

        first.overlayView.undo()
        endEvent()
        second.overlayView.redo()
        endEvent()

        XCTAssertTrue(arrows(on: first).isEmpty)
        XCTAssertTrue(arrows(on: second).isEmpty)

        // The link holds for more rounds.
        second.overlayView.undo()
        endEvent()
        XCTAssertEqual(arrows(on: first), [firstArrow])
        XCTAssertEqual(arrows(on: second), [secondArrow])
        first.overlayView.redo()
        XCTAssertTrue(arrows(on: first).isEmpty)
        XCTAssertTrue(arrows(on: second).isEmpty)
    }

    func testEachDisplayKeepsTheHistoryItHadBeforeTheClear() {
        let firstArrow = draw(on: first)
        let older = draw(on: second, x: 10)
        let newer = draw(on: second, x: 100)
        XCTAssertTrue(clear([first, second]))

        first.overlayView.undo()
        endEvent()
        XCTAssertEqual(arrows(on: first), [firstArrow])
        XCTAssertEqual(arrows(on: second), [older, newer])

        // Past the clear, Undo steps through one display's own history.
        first.overlayView.undo()
        endEvent()
        XCTAssertTrue(arrows(on: first).isEmpty)
        XCTAssertEqual(arrows(on: second), [older, newer])

        second.overlayView.undo()
        endEvent()
        XCTAssertTrue(arrows(on: first).isEmpty)
        XCTAssertEqual(arrows(on: second), [older])

        // Redo walks back up. Each display's own step comes back alone, then the clear's
        // empties both.
        second.overlayView.redo()
        endEvent()
        XCTAssertEqual(arrows(on: second), [older, newer])
        XCTAssertTrue(arrows(on: first).isEmpty)

        first.overlayView.redo()
        endEvent()
        XCTAssertEqual(arrows(on: first), [firstArrow])
        XCTAssertEqual(arrows(on: second), [older, newer])

        first.overlayView.redo()
        XCTAssertTrue(arrows(on: first).isEmpty)
        XCTAssertTrue(arrows(on: second).isEmpty)
    }

    func testRedoOnOneDisplaySkipsAnotherThatHasOwnStepsToRedoFirst() {
        let firstArrow = draw(on: first)
        let older = draw(on: second, x: 10)
        let newer = draw(on: second, x: 100)
        XCTAssertTrue(clear([first, second]))

        first.overlayView.undo()
        endEvent()
        second.overlayView.undo()
        endEvent()
        XCTAssertEqual(arrows(on: second), [older])

        // The second display's next Redo is its own arrow, so the clear's Redo leaves it be.
        first.overlayView.redo()
        endEvent()
        XCTAssertTrue(arrows(on: first).isEmpty)
        XCTAssertEqual(arrows(on: second), [older])

        second.overlayView.redo()
        endEvent()
        XCTAssertEqual(arrows(on: second), [older, newer])
        second.overlayView.redo()
        endEvent()
        XCTAssertTrue(arrows(on: second).isEmpty)
        XCTAssertTrue(arrows(on: first).isEmpty, "The first display had already redone its clear")

        // Both clears are done again and still linked.
        second.overlayView.undo()
        XCTAssertEqual(arrows(on: first), [firstArrow])
        XCTAssertEqual(arrows(on: second), [older, newer])
    }

    // MARK: - Leaving the link

    func testADisplayThatDrawsAfterTheClearKeepsItsClearAsItsOwnStep() {
        let firstArrow = draw(on: first)
        let cleared = draw(on: second, x: 10)
        XCTAssertTrue(clear([first, second]))
        let drawnAfter = draw(on: second, x: 200)

        first.overlayView.undo()
        endEvent()
        XCTAssertEqual(arrows(on: first), [firstArrow])
        XCTAssertEqual(arrows(on: second), [drawnAfter], "Undo must not reach under a newer step")

        second.overlayView.undo()
        endEvent()
        XCTAssertTrue(arrows(on: second).isEmpty)
        second.overlayView.undo()
        endEvent()
        XCTAssertEqual(arrows(on: second), [cleared])
        XCTAssertEqual(arrows(on: first), [firstArrow], "The first display was restored once")
    }

    func testADisplayThatDrawsAfterUndoingTheClearIsLeftOutOfItsRedo() {
        let firstArrow = draw(on: first)
        let secondArrow = draw(on: second, x: 10)
        XCTAssertTrue(clear([first, second]))

        first.overlayView.undo()
        endEvent()
        let drawnAfter = draw(on: second, x: 200)

        first.overlayView.redo()
        endEvent()
        XCTAssertTrue(arrows(on: first).isEmpty)
        XCTAssertEqual(arrows(on: second), [secondArrow, drawnAfter])

        second.overlayView.redo()
        XCTAssertEqual(arrows(on: second), [secondArrow, drawnAfter], "Drawing dropped its Redo")
        XCTAssertTrue(arrows(on: first).isEmpty)

        first.overlayView.undo()
        XCTAssertEqual(arrows(on: first), [firstArrow])
        XCTAssertEqual(arrows(on: second), [secondArrow, drawnAfter])
    }

    func testALaterClearReplacesTheLink() {
        draw(on: first)
        draw(on: second)
        XCTAssertTrue(clear([first, second]))

        let firstArrow = draw(on: first, x: 300)
        XCTAssertTrue(first.performClearAll())
        endEvent()

        first.overlayView.undo()
        XCTAssertEqual(arrows(on: first), [firstArrow])
        XCTAssertTrue(arrows(on: second).isEmpty, "Only the first display's own clear came back")
    }

    // MARK: - One display

    func testAClearThatEmptiesOneDisplayIsNotLinked() {
        let firstArrow = draw(on: first)
        XCTAssertTrue(clear([first, second]))
        XCTAssertNil(first.overlayView.clearLink)
        XCTAssertNil(second.overlayView.clearLink, "An empty display has no clear step to link")

        second.overlayView.undo()
        XCTAssertTrue(arrows(on: first).isEmpty)

        first.overlayView.undo()
        XCTAssertEqual(arrows(on: first), [firstArrow])
    }

    func testAClearOfOneDisplayStepsLikeAnyOtherClear() throws {
        let arrow = draw(on: first)
        XCTAssertTrue(clear([first]))
        XCTAssertNil(first.overlayView.clearLink)
        let manager = try XCTUnwrap(first.undoManager)
        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)

        first.overlayView.undo()
        endEvent()
        XCTAssertEqual(arrows(on: first), [arrow])
        XCTAssertTrue(manager.canRedo)

        first.overlayView.redo()
        endEvent()
        XCTAssertTrue(arrows(on: first).isEmpty)

        first.overlayView.undo()
        endEvent()
        first.overlayView.undo()
        XCTAssertTrue(arrows(on: first).isEmpty, "The step before the clear drew the arrow")
        XCTAssertFalse(manager.canUndo)
    }

    func testClearingNothingReportsNothingCleared() {
        XCTAssertFalse(clear([first, second]))
        XCTAssertNil(first.overlayView.clearLink)
        XCTAssertNil(second.overlayView.clearLink)
    }
}
