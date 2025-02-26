import SwiftUI
import XCTest

@testable import Annotate

final class SettingsViewTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: UserDefaults.clearDrawingsOnStartKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.hideDockIconKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.clearDrawingsOnStartKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.hideDockIconKey)
        super.tearDown()
    }

    func testSettingsViewInitialState() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.clearDrawingsOnStartKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey))
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
        let appDelegateSpy = AppDelegateSpy()
        AppDelegate.shared = appDelegateSpy

        class ViewModel: ObservableObject {
            @AppStorage(UserDefaults.hideDockIconKey) var hideDockIcon = false

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

class AppDelegateSpy: AppDelegate {
    var updateDockIconVisibilityCalled = false

    override func updateDockIconVisibility() {
        updateDockIconVisibilityCalled = true
    }
}
