import XCTest

@testable import Annotate

@MainActor
final class CursorHighlightManagerTests: XCTestCase {
    var testDefaults: UserDefaults!
    var manager: CursorHighlightManager!

    override func setUp() {
        super.setUp()
        testDefaults = TestUserDefaults.create()
        manager = CursorHighlightManager(userDefaults: testDefaults)
    }

    override func tearDown() {
        TestUserDefaults.removeSuite()
        manager = nil
        super.tearDown()
    }

    // MARK: - cursorHighlightEnabled Tests

    func testCursorHighlightEnabledDefaultsToFalse() {
        XCTAssertFalse(manager.cursorHighlightEnabled, "cursorHighlightEnabled should default to false")
    }

    func testCursorHighlightEnabledSetToTruePersistsToUserDefaults() {
        manager.cursorHighlightEnabled = true

        XCTAssertTrue(manager.cursorHighlightEnabled, "cursorHighlightEnabled should be true after setting")
        let persistedValue = testDefaults.bool(forKey: UserDefaults.cursorHighlightEnabledKey)
        XCTAssertTrue(persistedValue, "cursorHighlightEnabled should be persisted to UserDefaults")
    }

    func testCursorHighlightEnabledSetToFalsePersistsToUserDefaults() {
        manager.cursorHighlightEnabled = true
        manager.cursorHighlightEnabled = false

        XCTAssertFalse(manager.cursorHighlightEnabled, "cursorHighlightEnabled should be false after setting")
        let persistedValue = testDefaults.bool(forKey: UserDefaults.cursorHighlightEnabledKey)
        XCTAssertFalse(persistedValue, "cursorHighlightEnabled should be persisted to UserDefaults as false")
    }

    // MARK: - shouldShowCursorHighlight Computed Property Tests

    func testShouldShowCursorHighlightReturnsFalseWhenDisabled() {
        manager.cursorHighlightEnabled = false
        manager.isMouseDown = false

        XCTAssertFalse(
            manager.shouldShowCursorHighlight,
            "shouldShowCursorHighlight should return false when cursorHighlightEnabled is false"
        )
    }

    func testShouldShowCursorHighlightReturnsFalseWhenMouseIsDown() {
        manager.cursorHighlightEnabled = true
        manager.isMouseDown = true

        XCTAssertFalse(
            manager.shouldShowCursorHighlight,
            "shouldShowCursorHighlight should return false when isMouseDown is true (even if enabled)"
        )
    }

    func testShouldShowCursorHighlightReturnsTrueWhenEnabledAndMouseUp() {
        manager.cursorHighlightEnabled = true
        manager.isMouseDown = false

        XCTAssertTrue(
            manager.shouldShowCursorHighlight,
            "shouldShowCursorHighlight should return true when cursorHighlightEnabled is true AND isMouseDown is false"
        )
    }

    func testShouldShowCursorHighlightReturnsFalseWhenBothDisabledAndMouseDown() {
        manager.cursorHighlightEnabled = false
        manager.isMouseDown = true

        XCTAssertFalse(
            manager.shouldShowCursorHighlight,
            "shouldShowCursorHighlight should return false when both conditions are not met"
        )
    }

    // MARK: - clickEffectsEnabled Tests

    func testClickEffectsEnabledDefaultsToFalse() {
        XCTAssertFalse(manager.clickEffectsEnabled, "clickEffectsEnabled should default to false")
    }

    func testClickEffectsEnabledSetToTruePersistsToUserDefaults() {
        manager.clickEffectsEnabled = true

        XCTAssertTrue(manager.clickEffectsEnabled, "clickEffectsEnabled should be true after setting")
        let persistedValue = testDefaults.bool(forKey: UserDefaults.clickRippleEnabledKey)
        XCTAssertTrue(persistedValue, "clickEffectsEnabled should be persisted to UserDefaults")
    }

    func testClickEffectsEnabledSetToFalsePersistsToUserDefaults() {
        manager.clickEffectsEnabled = true
        manager.clickEffectsEnabled = false

        XCTAssertFalse(manager.clickEffectsEnabled, "clickEffectsEnabled should be false after setting")
        let persistedValue = testDefaults.bool(forKey: UserDefaults.clickRippleEnabledKey)
        XCTAssertFalse(persistedValue, "clickEffectsEnabled should be persisted to UserDefaults as false")
    }

    // MARK: - isActive Computed Property Tests

    func testIsActiveReturnsFalseWhenClickEffectsDisabled() {
        manager.clickEffectsEnabled = false

        XCTAssertFalse(manager.isActive, "isActive should return false when clickEffectsEnabled is false")
    }

    func testIsActiveReturnsTrueWhenClickEffectsEnabled() {
        manager.clickEffectsEnabled = true

        XCTAssertTrue(manager.isActive, "isActive should return true when clickEffectsEnabled is true")
    }

    // MARK: - shouldShowRing Computed Property Tests

    func testShouldShowRingReturnsFalseWhenNotActive() {
        manager.clickEffectsEnabled = false
        manager.isMouseDown = true

        XCTAssertFalse(manager.shouldShowRing, "shouldShowRing should return false when not active")
    }

    func testShouldShowRingReturnsFalseWhenMouseIsUp() {
        manager.clickEffectsEnabled = true
        manager.isMouseDown = false

        XCTAssertFalse(manager.shouldShowRing, "shouldShowRing should return false when mouse is not down")
    }

    func testShouldShowRingReturnsTrueWhenActiveAndMouseDown() {
        manager.clickEffectsEnabled = true
        manager.isMouseDown = true

        XCTAssertTrue(manager.shouldShowRing, "shouldShowRing should return true when active and mouse is down")
    }

    // MARK: - effectSize Tests

    func testEffectSizeDefaultsTo70() {
        XCTAssertEqual(manager.effectSize, 70.0, "effectSize should default to 70.0")
    }

    func testEffectSizePersistsToUserDefaults() {
        manager.effectSize = 120.0

        XCTAssertEqual(manager.effectSize, 120.0, "effectSize should be updated")
        let persistedValue = testDefaults.double(forKey: UserDefaults.clickRippleSizeKey)
        XCTAssertEqual(persistedValue, 120.0, "effectSize should be persisted to UserDefaults")
    }

    // MARK: - spotlightSize Tests

    func testSpotlightSizeDefaultsTo50() {
        XCTAssertEqual(manager.spotlightSize, 50.0, "spotlightSize should default to 50.0")
    }

    func testSpotlightSizePersistsToUserDefaults() {
        manager.spotlightSize = 150.0

        XCTAssertEqual(manager.spotlightSize, 150.0, "spotlightSize should be updated")
        let persistedValue = testDefaults.double(forKey: UserDefaults.spotlightSizeKey)
        XCTAssertEqual(persistedValue, 150.0, "spotlightSize should be persisted to UserDefaults")
    }

    func testSettingSpotlightSizePostsNotification() {
        let expectation = expectation(forNotification: .cursorHighlightStateChanged, object: nil)

        manager.spotlightSize = 100.0

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - holdRingSize Computed Properties Tests

    func testHoldRingStartSizeIsProportionalToEffectSize() {
        manager.effectSize = 100.0

        XCTAssertEqual(manager.holdRingStartSize, 20.0, "holdRingStartSize should be 20% of effectSize")
    }

    func testHoldRingEndSizeIsProportionalToEffectSize() {
        manager.effectSize = 100.0

        XCTAssertEqual(manager.holdRingEndSize, 65.0, "holdRingEndSize should be 65% of effectSize")
    }

    // MARK: - State Independence Tests

    func testCursorHighlightAndClickEffectsAreIndependent() {
        manager.cursorHighlightEnabled = true
        manager.clickEffectsEnabled = false

        XCTAssertTrue(manager.cursorHighlightEnabled, "cursorHighlightEnabled should be true")
        XCTAssertFalse(manager.clickEffectsEnabled, "clickEffectsEnabled should be false")

        manager.cursorHighlightEnabled = false
        manager.clickEffectsEnabled = true

        XCTAssertFalse(manager.cursorHighlightEnabled, "cursorHighlightEnabled should be false")
        XCTAssertTrue(manager.clickEffectsEnabled, "clickEffectsEnabled should be true")
    }

    // MARK: - Rapid Toggle Tests

    func testRapidCursorHighlightToggling() {
        for _ in 0..<10 {
            manager.cursorHighlightEnabled = true
            XCTAssertTrue(manager.cursorHighlightEnabled)

            manager.cursorHighlightEnabled = false
            XCTAssertFalse(manager.cursorHighlightEnabled)
        }

        XCTAssertFalse(manager.cursorHighlightEnabled, "Final state should be false")
    }

    func testRapidClickEffectsToggling() {
        for _ in 0..<10 {
            manager.clickEffectsEnabled = true
            XCTAssertTrue(manager.clickEffectsEnabled)

            manager.clickEffectsEnabled = false
            XCTAssertFalse(manager.clickEffectsEnabled)
        }

        XCTAssertFalse(manager.clickEffectsEnabled, "Final state should be false")
    }

    // MARK: - Notification Tests

    func testSettingCursorHighlightEnabledPostsNotification() {
        let expectation = expectation(forNotification: .cursorHighlightStateChanged, object: nil)

        manager.cursorHighlightEnabled = true

        wait(for: [expectation], timeout: 1.0)
    }

    func testSettingClickEffectsEnabledPostsNotification() {
        let expectation = expectation(forNotification: .cursorHighlightStateChanged, object: nil)

        manager.clickEffectsEnabled = true

        wait(for: [expectation], timeout: 1.0)
    }

    func testSettingEffectSizePostsNotification() {
        let expectation = expectation(forNotification: .cursorHighlightStateChanged, object: nil)

        manager.effectSize = 100.0

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Release Animation Tests

    func testHasActiveAnimationReturnsFalseWhenNoAnimation() {
        manager.releaseAnimation = nil

        XCTAssertFalse(manager.hasActiveAnimation, "hasActiveAnimation should return false when no animation exists")
    }

    func testCleanupExpiredAnimationRemovesExpiredAnimation() {
        manager.releaseAnimation = ReleaseAnimation(
            center: .zero,
            startTime: CACurrentMediaTime() - 10.0,
            startSize: 20.0,
            maxSize: 80.0,
            duration: 0.2
        )

        manager.cleanupExpiredAnimation()

        XCTAssertNil(manager.releaseAnimation, "Expired animation should be cleaned up")
    }

    func testStartReleaseAnimationDoesNothingWhenNotActive() {
        manager.clickEffectsEnabled = false

        manager.startReleaseAnimation()

        XCTAssertNil(manager.releaseAnimation, "releaseAnimation should not be created when not active")
    }

    func testStartReleaseAnimationCreatesAnimationWhenActive() {
        manager.clickEffectsEnabled = true
        manager.cursorPosition = NSPoint(x: 100, y: 200)

        manager.startReleaseAnimation()

        XCTAssertNotNil(manager.releaseAnimation, "releaseAnimation should be created when active")
        XCTAssertEqual(manager.releaseAnimation?.center, NSPoint(x: 100, y: 200), "Animation center should match cursor position")
    }

    // MARK: - Active Cursor Style Tests

    func testActiveCursorStyleDefaultsToNone() {
        XCTAssertEqual(manager.activeCursorStyle, .none, "activeCursorStyle should default to .none")
    }

    func testActiveCursorStylePersistsToUserDefaults() {
        manager.activeCursorStyle = .outline

        XCTAssertEqual(manager.activeCursorStyle, .outline, "activeCursorStyle should be updated")
        let persistedValue = testDefaults.string(forKey: UserDefaults.activeCursorStyleKey)
        XCTAssertEqual(persistedValue, "outline", "activeCursorStyle should be persisted to UserDefaults")
    }

    // MARK: - Per-Screen Active Cursor Tests

    func testShouldShowActiveCursorOnScreenReturnsFalseWhenStyleIsNone() {
        manager.activeCursorStyle = .none

        // Even with a valid screen, should return false when style is .none
        if let screen = NSScreen.main {
            XCTAssertFalse(
                manager.shouldShowActiveCursorOnScreen(screen),
                "shouldShowActiveCursorOnScreen should return false when activeCursorStyle is .none"
            )
        }
    }

    func testShouldShowActiveCursorOnScreenReturnsFalseWhenNoOverlayOnScreen() {
        manager.activeCursorStyle = .outline

        // With no overlay windows set up, should return false
        if let screen = NSScreen.main {
            XCTAssertFalse(
                manager.shouldShowActiveCursorOnScreen(screen),
                "shouldShowActiveCursorOnScreen should return false when no overlay is active on screen"
            )
        }
    }
}
