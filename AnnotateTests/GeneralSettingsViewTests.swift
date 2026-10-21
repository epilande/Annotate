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
        let initialValue = testDefaults.settings[.clearDrawingsOnStart]
        XCTAssertFalse(initialValue, "clearDrawingsOnStart should default to false")

        testDefaults.settings[.clearDrawingsOnStart] = true
        let updatedValue = testDefaults.settings[.clearDrawingsOnStart]
        XCTAssertTrue(updatedValue, "clearDrawingsOnStart should be true after setting")

        testDefaults.settings[.clearDrawingsOnStart] = false
        let finalValue = testDefaults.settings[.clearDrawingsOnStart]
        XCTAssertFalse(finalValue, "clearDrawingsOnStart should be false after resetting")
    }

    func testHideDockIconBinding() {
        let initialValue = testDefaults.settings[.hideDockIcon]
        XCTAssertFalse(initialValue, "hideDockIcon should default to false")

        testDefaults.settings[.hideDockIcon] = true
        let updatedValue = testDefaults.settings[.hideDockIcon]
        XCTAssertTrue(updatedValue, "hideDockIcon should be true after setting")
    }

    func testHideToolFeedbackBinding() {
        let initialValue = testDefaults.settings[.hideToolFeedback]
        XCTAssertFalse(initialValue, "hideToolFeedback should default to false")

        testDefaults.settings[.hideToolFeedback] = true
        let updatedValue = testDefaults.settings[.hideToolFeedback]
        XCTAssertTrue(updatedValue, "hideToolFeedback should be true after setting")

        testDefaults.settings[.hideToolFeedback] = false
        let finalValue = testDefaults.settings[.hideToolFeedback]
        XCTAssertFalse(finalValue, "hideToolFeedback should be false after resetting")
    }

    func testSoundsEnabledDefaultsToFalseWhenAbsent() {
        testDefaults.settings.removeValue(for: .soundsEnabled)

        XCTAssertFalse(testDefaults.settings[.soundsEnabled])
    }

    func testSoundsEnabledPersistsExplicitValue() {
        testDefaults.settings[.soundsEnabled] = false
        XCTAssertFalse(testDefaults.settings[.soundsEnabled])

        testDefaults.settings[.soundsEnabled] = true
        XCTAssertTrue(testDefaults.settings[.soundsEnabled])
    }

    func testSoundThemeDefaultsToChalkWhenAbsent() {
        testDefaults.settings.removeValue(for: .soundTheme)

        XCTAssertEqual(testDefaults.settings[.soundTheme], .chalk)
    }

    func testSoundThemePersistsExplicitValue() {
        testDefaults.settings[.soundTheme] = .paper
        XCTAssertEqual(testDefaults.settings[.soundTheme], .paper)

        testDefaults.settings[.soundTheme] = .chalk
        XCTAssertEqual(testDefaults.settings[.soundTheme], .chalk)
    }

    func testSoundThemeFallsBackToChalkForUnknownValue() {
        testDefaults.setRawValue("granite", for: .soundTheme)

        XCTAssertEqual(testDefaults.settings[.soundTheme], .chalk)
    }

    func testEnableBoardBinding() {
        let initialValue = testDefaults.settings[.enableBoard]
        XCTAssertFalse(initialValue, "enableBoard should default to false")

        testDefaults.settings[.enableBoard] = true
        let updatedValue = testDefaults.settings[.enableBoard]
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

        let persistedOpacity = testDefaults.settings[.boardOpacity]
        XCTAssertEqual(persistedOpacity, newOpacity, "Opacity should be persisted to UserDefaults")
    }

    func testEnableBoardToggleUpdatesBoardManager() {
        XCTAssertFalse(BoardManager.shared.isEnabled)

        BoardManager.shared.isEnabled = true
        XCTAssertTrue(BoardManager.shared.isEnabled, "BoardManager should be enabled")

        let persistedValue = testDefaults.settings[.enableBoard]
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

        testDefaults.settings[.hideDockIcon] = true
        appDelegateSpy.updateDockIconVisibility()

        XCTAssertTrue(appDelegateSpy.updateDockIconVisibilityCalled)

        AppDelegate.shared = nil
    }

    func testShowInDockToggleInverted() {
        // GeneralSettingsView uses inverted binding: Show in Dock = !hideDockIcon
        testDefaults.settings[.hideDockIcon] = false
        let showInDock1 = !testDefaults.settings[.hideDockIcon]
        XCTAssertTrue(showInDock1, "Show in Dock should be true when hideDockIcon is false")

        testDefaults.settings[.hideDockIcon] = true
        let showInDock2 = !testDefaults.settings[.hideDockIcon]
        XCTAssertFalse(showInDock2, "Show in Dock should be false when hideDockIcon is true")
    }

    // MARK: - State Synchronization Tests

    func testBoardManagerAndUserDefaultsStaySynchronized() {
        BoardManager.shared.opacity = 0.7
        let userDefaultsValue = testDefaults.settings[.boardOpacity]
        XCTAssertEqual(userDefaultsValue, 0.7, "UserDefaults should match BoardManager")

        testDefaults.settings[.boardOpacity] = 0.8
        let boardManagerValue = BoardManager.shared.opacity
        XCTAssertEqual(boardManagerValue, 0.8, "BoardManager should reflect UserDefaults change")
    }

    func testEnableBoardSynchronization() {
        BoardManager.shared.isEnabled = true
        let userDefaultsEnabled = testDefaults.settings[.enableBoard]
        XCTAssertTrue(userDefaultsEnabled, "UserDefaults should match BoardManager enabled state")

        testDefaults.settings[.enableBoard] = false
        let boardManagerEnabled = BoardManager.shared.isEnabled
        XCTAssertFalse(boardManagerEnabled, "BoardManager should reflect UserDefaults change")
    }

    // MARK: - Multiple Setting Changes Tests

    func testMultipleSettingsCanBeChangedIndependently() {
        testDefaults.settings[.clearDrawingsOnStart] = true
        testDefaults.settings[.hideToolFeedback] = true
        BoardManager.shared.isEnabled = true
        BoardManager.shared.opacity = 0.5

        XCTAssertTrue(testDefaults.settings[.clearDrawingsOnStart])
        XCTAssertTrue(testDefaults.settings[.hideToolFeedback])
        XCTAssertTrue(BoardManager.shared.isEnabled)
        XCTAssertEqual(BoardManager.shared.opacity, 0.5)

        testDefaults.settings[.clearDrawingsOnStart] = false

        XCTAssertFalse(testDefaults.settings[.clearDrawingsOnStart])
        XCTAssertTrue(testDefaults.settings[.hideToolFeedback])
        XCTAssertTrue(BoardManager.shared.isEnabled)
    }

    // MARK: - Default Value Tests

    func testAllSettingsHaveCorrectDefaults() {
        XCTAssertFalse(
            testDefaults.settings[.clearDrawingsOnStart],
            "clearDrawingsOnStart should default to false"
        )
        XCTAssertFalse(
            testDefaults.settings[.hideDockIcon],
            "hideDockIcon should default to false"
        )
        XCTAssertFalse(
            testDefaults.settings[.hideToolFeedback],
            "hideToolFeedback should default to false"
        )
        XCTAssertFalse(
            testDefaults.settings[.enableBoard],
            "enableBoard should default to false"
        )
        XCTAssertEqual(
            BoardManager.shared.opacity, 0.9,
            "Board opacity should default to 0.9"
        )
    }

    // MARK: - Select After Placing Text Toggle Tests

    func testSelectAfterPlacingTextDefaultsToFalse() {
        testDefaults.settings.removeValue(for: .selectAfterPlacingText)

        XCTAssertFalse(testDefaults.settings[.selectAfterPlacingText], "selectAfterPlacingText should default to false")
    }

    func testSelectAfterPlacingTextPersistsValue() {
        testDefaults.settings[.selectAfterPlacingText] = true
        XCTAssertTrue(testDefaults.settings[.selectAfterPlacingText], "selectAfterPlacingText should be true after setting to true")

        testDefaults.settings[.selectAfterPlacingText] = false
        XCTAssertFalse(testDefaults.settings[.selectAfterPlacingText], "selectAfterPlacingText should be false after setting to false")
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

    // MARK: - View Structure Tests

    func testGeneralSettingsViewCanBeEmbeddedInHostingController() {
        let hostingController = NSHostingController(rootView: GeneralSettingsView())
        XCTAssertNotNil(hostingController.view)
    }

    func testShortcutsSettingsViewCanBeEmbeddedInHostingController() {
        let hostingController = NSHostingController(rootView: ShortcutsSettingsView())
        XCTAssertNotNil(hostingController.view)
    }

    func testBuiltInShortcutsOnlyListFixedActions() {
        XCTAssertEqual(ShortcutsSettingsView.builtInShortcuts.map(\.keys), ["Delete", "⌘Z", "⇧⌘Z", "Esc"])
    }

    // MARK: - Persistence Tests

    func testSettingsPersistAcrossViewLifecycle() {
        testDefaults.settings[.clearDrawingsOnStart] = true
        BoardManager.shared.opacity = 0.65
        BoardManager.shared.isEnabled = true

        let clearedDrawings = testDefaults.settings[.clearDrawingsOnStart]
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
