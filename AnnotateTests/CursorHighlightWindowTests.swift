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
}
