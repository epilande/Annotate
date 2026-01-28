import SwiftUI
import XCTest

@testable import Annotate

@MainActor
final class GeneralSettingsViewTests: XCTestCase {
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = TestUserDefaults.create()
        BoardManager.shared = BoardManager(userDefaults: testDefaults)
    }

    override func tearDown() {
        TestUserDefaults.removeSuite()
        BoardManager.shared = BoardManager()
        super.tearDown()
    }

    // MARK: - UserDefaults Binding Tests

    func testClearDrawingsOnStartBinding() {
        let initialValue = testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertFalse(initialValue, "clearDrawingsOnStart should default to false")

        testDefaults.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        let updatedValue = testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertTrue(updatedValue, "clearDrawingsOnStart should be true after setting")

        testDefaults.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)
        let finalValue = testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertFalse(finalValue, "clearDrawingsOnStart should be false after resetting")
    }

    func testHideDockIconBinding() {
        let initialValue = testDefaults.bool(forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(initialValue, "hideDockIcon should default to false")

        testDefaults.set(true, forKey: UserDefaults.hideDockIconKey)
        let updatedValue = testDefaults.bool(forKey: UserDefaults.hideDockIconKey)
        XCTAssertTrue(updatedValue, "hideDockIcon should be true after setting")
    }

    func testHideToolFeedbackBinding() {
        let initialValue = testDefaults.bool(forKey: UserDefaults.hideToolFeedbackKey)
        XCTAssertFalse(initialValue, "hideToolFeedback should default to false")

        testDefaults.set(true, forKey: UserDefaults.hideToolFeedbackKey)
        let updatedValue = testDefaults.bool(forKey: UserDefaults.hideToolFeedbackKey)
        XCTAssertTrue(updatedValue, "hideToolFeedback should be true after setting")

        testDefaults.set(false, forKey: UserDefaults.hideToolFeedbackKey)
        let finalValue = testDefaults.bool(forKey: UserDefaults.hideToolFeedbackKey)
        XCTAssertFalse(finalValue, "hideToolFeedback should be false after resetting")
    }

    func testEnableBoardBinding() {
        let initialValue = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertFalse(initialValue, "enableBoard should default to false")

        testDefaults.set(true, forKey: UserDefaults.enableBoardKey)
        let updatedValue = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertTrue(updatedValue, "enableBoard should be true after setting")
    }

    // MARK: - BoardManager Integration Tests

    func testBoardOpacitySliderUpdatesBoardManager() {
        let initialOpacity = 0.5
        BoardManager.shared.opacity = initialOpacity
        XCTAssertEqual(BoardManager.shared.opacity, initialOpacity)

        let newOpacity = 0.75
        BoardManager.shared.opacity = newOpacity
        XCTAssertEqual(BoardManager.shared.opacity, newOpacity, "BoardManager opacity should be updated")

        let persistedOpacity = testDefaults.double(forKey: UserDefaults.boardOpacityKey)
        XCTAssertEqual(persistedOpacity, newOpacity, "Opacity should be persisted to UserDefaults")
    }

    func testEnableBoardToggleUpdatesBoardManager() {
        XCTAssertFalse(BoardManager.shared.isEnabled)

        BoardManager.shared.isEnabled = true
        XCTAssertTrue(BoardManager.shared.isEnabled, "BoardManager should be enabled")

        let persistedValue = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertTrue(persistedValue, "Board state should be persisted to UserDefaults")

        BoardManager.shared.isEnabled = false
        XCTAssertFalse(BoardManager.shared.isEnabled, "BoardManager should be disabled")
    }

    func testBoardOpacityLoadedOnAppear() {
        let testOpacity = 0.6
        BoardManager.shared.opacity = testOpacity

        let loadedOpacity = BoardManager.shared.opacity
        XCTAssertEqual(loadedOpacity, testOpacity, "Opacity should be loaded from BoardManager")
    }

    func testBoardEnabledStateLoadedOnAppear() {
        BoardManager.shared.isEnabled = true

        let loadedState = BoardManager.shared.isEnabled
        XCTAssertTrue(loadedState, "Board enabled state should be loaded from BoardManager")
    }

    func testBoardOpacityClamping() {
        BoardManager.shared.opacity = 1.5
        XCTAssertEqual(BoardManager.shared.opacity, 1.0, "Opacity should be clamped to maximum 1.0")

        BoardManager.shared.opacity = 0.05
        XCTAssertEqual(BoardManager.shared.opacity, 0.1, "Opacity should be clamped to minimum 0.1")

        BoardManager.shared.opacity = 0.5
        XCTAssertEqual(BoardManager.shared.opacity, 0.5, "Valid opacity should be set correctly")
    }

    // MARK: - AppDelegate Integration Tests

    func testDockIconToggleCallsAppDelegate() {
        let appDelegateSpy = AppDelegateSettingsSpy(userDefaults: testDefaults)
        AppDelegate.shared = appDelegateSpy

        testDefaults.set(true, forKey: UserDefaults.hideDockIconKey)
        appDelegateSpy.updateDockIconVisibility()

        XCTAssertTrue(appDelegateSpy.updateDockIconVisibilityCalled)

        AppDelegate.shared = nil
    }

    func testShowInDockToggleInverted() {
        // GeneralSettingsView uses inverted binding: Show in Dock = !hideDockIcon
        testDefaults.set(false, forKey: UserDefaults.hideDockIconKey)
        let showInDock1 = !testDefaults.bool(forKey: UserDefaults.hideDockIconKey)
        XCTAssertTrue(showInDock1, "Show in Dock should be true when hideDockIcon is false")

        testDefaults.set(true, forKey: UserDefaults.hideDockIconKey)
        let showInDock2 = !testDefaults.bool(forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(showInDock2, "Show in Dock should be false when hideDockIcon is true")
    }

    // MARK: - State Synchronization Tests

    func testBoardManagerAndUserDefaultsStaySynchronized() {
        BoardManager.shared.opacity = 0.7
        let userDefaultsValue = testDefaults.double(forKey: UserDefaults.boardOpacityKey)
        XCTAssertEqual(userDefaultsValue, 0.7, "UserDefaults should match BoardManager")

        testDefaults.set(0.8, forKey: UserDefaults.boardOpacityKey)
        let boardManagerValue = BoardManager.shared.opacity
        XCTAssertEqual(boardManagerValue, 0.8, "BoardManager should reflect UserDefaults change")
    }

    func testEnableBoardSynchronization() {
        BoardManager.shared.isEnabled = true
        let userDefaultsEnabled = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertTrue(userDefaultsEnabled, "UserDefaults should match BoardManager enabled state")

        testDefaults.set(false, forKey: UserDefaults.enableBoardKey)
        let boardManagerEnabled = BoardManager.shared.isEnabled
        XCTAssertFalse(boardManagerEnabled, "BoardManager should reflect UserDefaults change")
    }

    // MARK: - Multiple Setting Changes Tests

    func testMultipleSettingsCanBeChangedIndependently() {
        testDefaults.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        testDefaults.set(true, forKey: UserDefaults.hideToolFeedbackKey)
        BoardManager.shared.isEnabled = true
        BoardManager.shared.opacity = 0.5

        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))
        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.hideToolFeedbackKey))
        XCTAssertTrue(BoardManager.shared.isEnabled)
        XCTAssertEqual(BoardManager.shared.opacity, 0.5)

        testDefaults.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)

        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))
        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.hideToolFeedbackKey))
        XCTAssertTrue(BoardManager.shared.isEnabled)
    }

    // MARK: - Default Value Tests

    func testAllSettingsHaveCorrectDefaults() {
        XCTAssertFalse(
            testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey),
            "clearDrawingsOnStart should default to false"
        )
        XCTAssertFalse(
            testDefaults.bool(forKey: UserDefaults.hideDockIconKey),
            "hideDockIcon should default to false"
        )
        XCTAssertFalse(
            testDefaults.bool(forKey: UserDefaults.hideToolFeedbackKey),
            "hideToolFeedback should default to false"
        )
        XCTAssertFalse(
            testDefaults.bool(forKey: UserDefaults.enableBoardKey),
            "enableBoard should default to false"
        )
        XCTAssertEqual(
            BoardManager.shared.opacity, 0.9,
            "Board opacity should default to 0.9"
        )
    }

    // MARK: - Persist Text Mode Toggle Tests

    func testPersistTextModeToggleDefaultsToFalse() {
        testDefaults.removeObject(forKey: UserDefaults.persistTextModeKey)

        let defaultValue = testDefaults.bool(forKey: UserDefaults.persistTextModeKey)
        XCTAssertFalse(defaultValue, "persistTextMode should default to false")
    }

    func testPersistTextModeTogglePersistsValue() {
        testDefaults.set(true, forKey: UserDefaults.persistTextModeKey)
        let onValue = testDefaults.bool(forKey: UserDefaults.persistTextModeKey)
        XCTAssertTrue(onValue, "persistTextMode should be true after setting to true")

        testDefaults.set(false, forKey: UserDefaults.persistTextModeKey)
        let offValue = testDefaults.bool(forKey: UserDefaults.persistTextModeKey)
        XCTAssertFalse(offValue, "persistTextMode should be false after setting to false")
    }

    // MARK: - Edge Cases

    func testBoardOpacityAtBoundaries() {
        BoardManager.shared.opacity = 0.1
        XCTAssertEqual(BoardManager.shared.opacity, 0.1)

        BoardManager.shared.opacity = 1.0
        XCTAssertEqual(BoardManager.shared.opacity, 1.0)
    }

    func testRapidBoardOpacityChanges() {
        let opacities = [0.1, 0.3, 0.5, 0.7, 0.9, 1.0, 0.6, 0.4, 0.2]

        for opacity in opacities {
            BoardManager.shared.opacity = opacity
            XCTAssertEqual(BoardManager.shared.opacity, opacity)
        }

        let finalOpacity = BoardManager.shared.opacity
        XCTAssertEqual(finalOpacity, 0.2)
    }

    func testTogglingBoardMultipleTimes() {
        for _ in 0..<10 {
            BoardManager.shared.isEnabled = true
            XCTAssertTrue(BoardManager.shared.isEnabled)

            BoardManager.shared.isEnabled = false
            XCTAssertFalse(BoardManager.shared.isEnabled)
        }

        XCTAssertFalse(BoardManager.shared.isEnabled)
    }

    // MARK: - Persistence Tests

    func testSettingsPersistAcrossViewLifecycle() {
        testDefaults.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        BoardManager.shared.opacity = 0.65
        BoardManager.shared.isEnabled = true

        let clearedDrawings = testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey)
        let opacity = BoardManager.shared.opacity
        let enabled = BoardManager.shared.isEnabled

        XCTAssertTrue(clearedDrawings)
        XCTAssertEqual(opacity, 0.65)
        XCTAssertTrue(enabled)
    }
}

// MARK: - Test Spy

@MainActor
class AppDelegateSettingsSpy: AppDelegate {
    var updateDockIconVisibilityCalled = false

    override func updateDockIconVisibility() {
        updateDockIconVisibilityCalled = true
    }
}
