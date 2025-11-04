import XCTest

@testable import Annotate

@MainActor
final class BoardManagerTests: XCTestCase {
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = TestUserDefaults.create()
        BoardManager.shared = BoardManager(userDefaults: testDefaults)
    }

    override func tearDown() {
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testBoardManagerInitialization() {
        XCTAssertFalse(BoardManager.shared.isEnabled, "Board should be disabled by default")

        let defaultOpacity = BoardManager.shared.opacity
        XCTAssertEqual(defaultOpacity, 0.9, "Default opacity should be 0.9")
    }

    func testBoardToggle() {
        XCTAssertFalse(BoardManager.shared.isEnabled, "Board should start disabled")

        BoardManager.shared.toggle()
        XCTAssertTrue(BoardManager.shared.isEnabled, "Board should be enabled after toggle")

        BoardManager.shared.toggle()
        XCTAssertFalse(
            BoardManager.shared.isEnabled, "Board should be disabled after second toggle")
    }

    func testOpacitySetting() {
        let testOpacity = 0.5
        BoardManager.shared.opacity = testOpacity
        XCTAssertEqual(BoardManager.shared.opacity, testOpacity, "Opacity should be updated to 0.5")

        let persistedOpacity = testDefaults.double(forKey: UserDefaults.boardOpacityKey)
        XCTAssertEqual(persistedOpacity, testOpacity, "Opacity should be persisted to UserDefaults")
    }

    func testOpacityClamping() {
        BoardManager.shared.opacity = 1.5  // Above max
        XCTAssertEqual(BoardManager.shared.opacity, 1.0, "Opacity should be clamped to 1.0 maximum")

        BoardManager.shared.opacity = 0.05  // Below min
        XCTAssertEqual(BoardManager.shared.opacity, 0.1, "Opacity should be clamped to 0.1 minimum")

        BoardManager.shared.opacity = 0.75  // Valid value
        XCTAssertEqual(BoardManager.shared.opacity, 0.75, "Valid opacity should be set correctly")
    }
}
