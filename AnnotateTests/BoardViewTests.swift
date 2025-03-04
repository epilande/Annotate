import XCTest

@testable import Annotate

final class BoardViewTests: XCTestCase {
    var boardView: BoardView!

    override func setUp() {
        super.setUp()
        boardView = BoardView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
    }

    override func tearDown() {
        boardView = nil
        super.tearDown()
    }

    func testBoardViewInitialization() {
        XCTAssertTrue(boardView.wantsLayer, "BoardView should have wantsLayer set to true")
        XCTAssertNotNil(boardView.layer, "BoardView should have a layer")
        XCTAssertEqual(boardView.layer?.cornerRadius, 8, "BoardView should have rounded corners")
        XCTAssertTrue(boardView.layer?.masksToBounds ?? false, "BoardView should mask to bounds")
        XCTAssertEqual(boardView.layer?.borderWidth, 1, "BoardView should have a border")
    }

    func testBoardBackgroundColor() {
        let backgroundColor = boardView.layer?.backgroundColor

        XCTAssertNotNil(backgroundColor, "Background color should be set")

        let originalOpacity = BoardManager.shared.opacity
        BoardManager.shared.opacity = 0.5

        boardView.updateForAppearance()

        let newBackgroundColor = boardView.layer?.backgroundColor
        XCTAssertNotEqual(
            backgroundColor, newBackgroundColor, "Background color should change with opacity")

        BoardManager.shared.opacity = originalOpacity
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
