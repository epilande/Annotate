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

    // MARK: - View Structure Tests

    func testSettingsPaneHasFiveCases() {
        XCTAssertEqual(SettingsPane.allCases.count, 5)
        XCTAssertEqual(
            SettingsPane.allCases,
            [.general, .tools, .board, .cursor, .shortcuts]
        )
    }

    func testSettingsPaneCasesCarrySidebarMetadata() {
        for pane in SettingsPane.allCases {
            XCTAssertFalse(pane.title.isEmpty)
            XCTAssertFalse(pane.subtitle.isEmpty)
            XCTAssertFalse(pane.symbol.isEmpty)
        }
    }

    func testPaneHeaderBodyBuilds() {
        let header = PaneHeader(pane: .general)
        XCTAssertEqual(header.pane, .general)
        XCTAssertNotNil(header.body)
    }

    func testSettingsViewBodyBuilds() {
        let settingsView = SettingsView()
        XCTAssertNotNil(settingsView.body)
    }

    func testSettingsViewCanBeEmbeddedInHostingController() {
        let hostingController = NSHostingController(rootView: SettingsView())
        XCTAssertNotNil(hostingController.view)
    }

    func testToolsSettingsViewCanBeEmbeddedInHostingController() {
        let hostingController = NSHostingController(rootView: ToolsSettingsView())
        XCTAssertNotNil(hostingController.view)
    }

    func testBoardSettingsViewCanBeEmbeddedInHostingController() {
        let hostingController = NSHostingController(rootView: BoardSettingsView())
        XCTAssertNotNil(hostingController.view)
    }

    func testCursorSettingsViewCanBeEmbeddedInHostingController() {
        let hostingController = NSHostingController(rootView: CursorSettingsView())
        XCTAssertNotNil(hostingController.view)
    }

    func testSettingsHeaderHoldsIconTitleAndSubtitle() {
        let header = SettingsHeader(
            icon: "gearshape",
            color: .blue,
            title: "General",
            subtitle: "General settings"
        )
        XCTAssertEqual(header.icon, "gearshape")
        XCTAssertEqual(header.title, "General")
        XCTAssertEqual(header.subtitle, "General settings")
        XCTAssertNotNil(header.body)
    }

    // MARK: - Settings Window Manager Tests

    func testShowCreatesConfiguredSettingsWindow() {
        SettingsWindowManager.shared.show()

        let window = SettingsWindowManager.shared.settingsWindow
        XCTAssertNotNil(window, "show() must create the settings window")
        XCTAssertEqual(window?.title, "Annotate Settings")
        XCTAssertEqual(window?.titleVisibility, .hidden)
        XCTAssertEqual(window?.titlebarAppearsTransparent, true)
        XCTAssertEqual(window?.styleMask.contains(.fullSizeContentView), true)

        window?.close()
        XCTAssertNil(
            SettingsWindowManager.shared.settingsWindow,
            "closing the window must clear the manager's reference"
        )
    }

    func testShowReusesExistingSettingsWindow() {
        SettingsWindowManager.shared.show()
        let firstWindow = SettingsWindowManager.shared.settingsWindow

        SettingsWindowManager.shared.show()
        let secondWindow = SettingsWindowManager.shared.settingsWindow

        XCTAssertNotNil(firstWindow)
        XCTAssertTrue(
            firstWindow === secondWindow,
            "a second show() must re-front the existing window, not build a new one"
        )

        firstWindow?.close()
    }

    // MARK: - Dock Icon Tests

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
