import XCTest

@testable import Annotate

@MainActor
final class BoardViewTests: XCTestCase, Sendable {
    var boardView: BoardView!
    var testDefaults: UserDefaults!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            // Unique suite so leftover BoardOpacity from other classes
            // (or a prior 0.5 write on .standard) cannot make both colors identical.
            testDefaults = TestUserDefaults.create()
            BoardManager.shared = BoardManager(userDefaults: testDefaults)
            boardView = BoardView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            boardView = nil
            BoardManager.shared = BoardManager()
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testBoardViewInitialization() {
        XCTAssertTrue(boardView.wantsLayer, "BoardView should have wantsLayer set to true")
        XCTAssertNotNil(boardView.layer, "BoardView should have a layer")
        XCTAssertEqual(boardView.layer?.borderWidth, 1, "BoardView should have a border")
    }

    func testBoardBackgroundColor() {
        // Pin a known start opacity. Shared BoardManager state from other
        // suites can already be 0.5, which would make the next write a no-op.
        BoardManager.shared.opacity = 0.9
        boardView.updateForAppearance()

        let backgroundColor = boardView.layer?.backgroundColor
        XCTAssertNotNil(backgroundColor, "Background color should be set")

        BoardManager.shared.opacity = 0.5
        boardView.updateForAppearance()

        let newBackgroundColor = boardView.layer?.backgroundColor
        XCTAssertNotEqual(
            backgroundColor, newBackgroundColor, "Background color should change with opacity")
    }

    func testVisibilityChangeNotification() {
        BoardManager.shared.isEnabled = !BoardManager.shared.isEnabled

        NotificationCenter.default.post(name: .boardStateChanged, object: nil)

        XCTAssertEqual(
            boardView.isHidden, !BoardManager.shared.isEnabled,
            "BoardView hidden state should match !isEnabled")

        BoardManager.shared.isEnabled = !BoardManager.shared.isEnabled
    }
}
