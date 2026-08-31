import XCTest

@testable import Annotate

@MainActor
final class CursorHighlightWindowTests: XCTestCase {
    func testAnimationLoopOwnsWindowDisplayLinkOnlyWhileRunning() {
        let window = CursorHighlightWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.startAnimationLoop()
        let displayLink = window.animationDisplayLink

        XCTAssertNotNil(displayLink)

        window.startAnimationLoop()
        XCTAssertTrue(window.animationDisplayLink === displayLink)

        window.stopAnimationLoop()
        XCTAssertNil(window.animationDisplayLink)
    }

    func testUpdateVisibilityHidesSpotlightImmediatelyWhenClickEffectsKeepWindowAlive() throws {
        let defaults = TestUserDefaults.create()
        let originalShared = CursorHighlightManager.shared
        let manager = CursorHighlightManager(userDefaults: defaults)
        CursorHighlightManager.shared = manager
        let window = CursorHighlightWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        defer {
            window.stopAnimationLoop()
            window.orderOut(nil)
            CursorHighlightManager.shared = originalShared
            TestUserDefaults.removeSuite()
        }

        manager.clickEffectsEnabled = true
        manager.cursorHighlightEnabled = false
        manager.spotlightRequiresOverlay = false

        let spotlight = try XCTUnwrap(window.highlightView.layer?.sublayers?.first)
        spotlight.opacity = 1

        window.updateVisibility()

        XCTAssertEqual(
            spotlight.opacity,
            0,
            "Spotlight should hide as soon as it is disabled, even if click effects keep the window ordered in"
        )
    }
}
