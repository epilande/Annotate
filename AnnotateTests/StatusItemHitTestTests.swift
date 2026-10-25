import XCTest

@testable import Annotate

/// Geometry from a two display Mac: a 1920x1080 primary display, and a portrait display to its
/// right whose menu bar hosts the status item.
@MainActor
final class StatusItemHitTestTests: XCTestCase {
    private let primaryScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let hostScreen = NSRect(x: 1920, y: -693, width: 1440, height: 2560)
    private let buttonFrame = NSRect(x: 2495, y: 1837, width: 70, height: 30)
    private let hostMenuBar = NSRect(x: 1920, y: 1837, width: 1440, height: 30)
    private let primaryMenuBar = NSRect(x: 0, y: 1050, width: 1920, height: 30)

    private func hit(at point: NSPoint, menuBars: [NSRect]) -> StatusItemHitTest.Hit? {
        StatusItemHitTest.hit(
            at: point,
            buttonFrame: buttonFrame,
            hostScreenFrame: hostScreen,
            screenFrames: [primaryScreen, hostScreen]
        ) { menuBars }
    }

    func testPressOnTheItemInTheHostMenuBarHitsTheButton() {
        XCTAssertEqual(
            hit(at: NSPoint(x: 2530, y: 1850), menuBars: [hostMenuBar]),
            StatusItemHitTest.Hit(frame: buttonFrame, isOnHostMenuBar: true)
        )
    }

    func testPressBesideTheItemIsNotAHit() {
        XCTAssertNil(hit(at: NSPoint(x: 2494, y: 1850), menuBars: [hostMenuBar]))
        XCTAssertNil(hit(at: NSPoint(x: 2565, y: 1850), menuBars: [hostMenuBar]))
    }

    func testPressUnderTheMenuBarIsNotAHit() {
        XCTAssertNil(hit(at: NSPoint(x: 2530, y: 1830), menuBars: [hostMenuBar]))
    }

    func testPressWhereTheMenuBarIsHiddenIsNotAHit() {
        // A full screen app, or an auto-hidden menu bar: the drawing gets the press.
        XCTAssertNil(hit(at: NSPoint(x: 2530, y: 1850), menuBars: []))
    }

    func testAnotherDisplaysMenuBarShowsTheItemAtTheSameDistanceFromTheRightEdge() {
        // The button ends 795 pt from the host display's right edge.
        XCTAssertEqual(
            hit(at: NSPoint(x: 1080, y: 1065), menuBars: [hostMenuBar, primaryMenuBar]),
            StatusItemHitTest.Hit(
                frame: NSRect(x: 1055, y: 1050, width: 70, height: 30),
                isOnHostMenuBar: false
            )
        )
    }

    func testDisplayWithoutAMenuBarIsNotAHit() {
        XCTAssertNil(hit(at: NSPoint(x: 1080, y: 1065), menuBars: [hostMenuBar]))
    }

    func testPressesAwayFromTheTopNeverReadTheWindowList() {
        var reads = 0
        let result = StatusItemHitTest.hit(
            at: NSPoint(x: 2530, y: 900),
            buttonFrame: buttonFrame,
            hostScreenFrame: hostScreen,
            screenFrames: [primaryScreen, hostScreen]
        ) {
            reads += 1
            return [self.hostMenuBar]
        }

        XCTAssertNil(result)
        XCTAssertEqual(reads, 0)
    }

    func testMenuBarFramesConvertWindowServerCoordinates() {
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        func window(pid: pid_t, layer: Int, bounds: CGRect) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: pid,
                kCGWindowLayer as String: layer,
                kCGWindowBounds as String: bounds.dictionaryRepresentation,
            ]
        }

        let frames = StatusItemHitTest.menuBarFrames(
            in: [
                window(pid: 88, layer: menuBarLevel, bounds: CGRect(x: 1920, y: -787, width: 1440, height: 30)),
                window(pid: 88, layer: menuBarLevel, bounds: CGRect(x: 0, y: 0, width: 1920, height: 30)),
                window(pid: 88, layer: 0, bounds: CGRect(x: 0, y: 30, width: 800, height: 600)),
                window(pid: 42, layer: menuBarLevel, bounds: CGRect(x: 0, y: 0, width: 1920, height: 30)),
            ],
            menuBarLevel: menuBarLevel,
            primaryScreenHeight: 1080,
            excludingPID: 42
        )

        XCTAssertEqual(frames, [hostMenuBar, primaryMenuBar])
    }
}
