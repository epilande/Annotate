import SwiftUI
import XCTest

@testable import Annotate

@MainActor
final class SettingsViewTests: XCTestCase {
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: UserDefaults.clearDrawingsOnStartKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.hideDockIconKey)
        testDefaults = UserDefaults.standard
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.clearDrawingsOnStartKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.hideDockIconKey)
        super.tearDown()
    }

    func testSettingsViewInitialState() {
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.hideDockIconKey))
    }

    func testHideDockIconToggle() {
        UserDefaults.standard.set(false, forKey: UserDefaults.hideDockIconKey)

        class ViewModel: ObservableObject {
            @AppStorage(UserDefaults.hideDockIconKey) var hideDockIcon = false
        }

        let viewModel = ViewModel()

        XCTAssertFalse(viewModel.hideDockIcon)

        viewModel.hideDockIcon = true

        // Verify the toggle updated the UserDefaults
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey))

        // Toggle back
        viewModel.hideDockIcon = false

        // Verify the toggle updated the UserDefaults
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey))
    }

    func testToggleCallsUpdateDockIconVisibility() {
        let appDelegateSpy = AppDelegateSpy(userDefaults: testDefaults)
        AppDelegate.shared = appDelegateSpy

        class ViewModel: ObservableObject {
            @AppStorage(UserDefaults.hideDockIconKey) var hideDockIcon = false

            @MainActor
            func toggleHideDockIcon() {
                hideDockIcon.toggle()
                AppDelegate.shared?.updateDockIconVisibility()
            }
        }

        let viewModel = ViewModel()

        viewModel.toggleHideDockIcon()

        XCTAssertTrue(appDelegateSpy.updateDockIconVisibilityCalled)

        AppDelegate.shared = nil
    }
}

@MainActor
class AppDelegateSpy: AppDelegate {
    var updateDockIconVisibilityCalled = false

    override func updateDockIconVisibility() {
        updateDockIconVisibilityCalled = true
    }
}
