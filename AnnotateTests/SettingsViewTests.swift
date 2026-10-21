import SwiftUI
import XCTest

@testable import Annotate

@MainActor
final class SettingsViewTests: XCTestCase {
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        SettingsStore.standard.removeValue(for: .clearDrawingsOnStart)
        SettingsStore.standard.removeValue(for: .hideDockIcon)
        testDefaults = SettingsStore.standard.defaults
        SettingsStore.standard.removeValue(for: .textBackground)
        SettingsStore.standard.removeValue(for: .textFontSize)
    }

    override func tearDown() {
        SettingsStore.standard.removeValue(for: .clearDrawingsOnStart)
        SettingsStore.standard.removeValue(for: .hideDockIcon)
        SettingsStore.standard.removeValue(for: .textBackground)
        SettingsStore.standard.removeValue(for: .textFontSize)
        super.tearDown()
    }

    func testSettingsViewInitialState() {
        XCTAssertFalse(testDefaults.settings[.clearDrawingsOnStart])
        XCTAssertFalse(testDefaults.settings[.hideDockIcon])
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
        SettingsStore.standard[.hideDockIcon] = false

        class ViewModel: ObservableObject {
            @AppStorage(.hideDockIcon) var hideDockIcon: Bool
        }

        let viewModel = ViewModel()

        XCTAssertFalse(viewModel.hideDockIcon)

        viewModel.hideDockIcon = true

        // Verify the toggle updated the UserDefaults
        XCTAssertTrue(SettingsStore.standard[.hideDockIcon])

        // Toggle back
        viewModel.hideDockIcon = false

        // Verify the toggle updated the UserDefaults
        XCTAssertFalse(SettingsStore.standard[.hideDockIcon])
    }

    func testToggleCallsUpdateDockIconVisibility() {
        let appDelegateSpy = AppDelegateSpy(userDefaults: testDefaults)
        AppDelegate.shared = appDelegateSpy

        class ViewModel: ObservableObject {
            @AppStorage(.hideDockIcon) var hideDockIcon: Bool

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

    func testTextToolDefaultsKeepSizeAtEighteenAndPersistBackgroundChoice() {
        XCTAssertEqual(testDefaults.settings[.textFontSize], 18)
        XCTAssertFalse(testDefaults.settings[.textBackground])

        testDefaults.settings[.textBackground] = true
        XCTAssertTrue(testDefaults.settings[.textBackground])
    }
}

@MainActor
class AppDelegateSpy: AppDelegate {
    var updateDockIconVisibilityCalled = false

    override func updateDockIconVisibility() {
        updateDockIconVisibilityCalled = true
    }
}
