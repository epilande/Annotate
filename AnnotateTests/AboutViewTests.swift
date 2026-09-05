import XCTest
import SwiftUI
import Sparkle
@testable import Annotate

@MainActor
final class AboutViewTests: XCTestCase {
    nonisolated(unsafe) var mockUpdaterController: SPUStandardUpdaterController!

    override func setUp() {
        super.setUp()
        mockUpdaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    override func tearDown() {
        mockUpdaterController = nil
        super.tearDown()
    }

    // MARK: - Bundle Information Tests

    func testBundleVersionInformationIsAvailable() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String

        if let version = appVersion {
            XCTAssertFalse(version.isEmpty)
        }

        if let build = buildNumber {
            XCTAssertFalse(build.isEmpty)
        }

        if let name = appName {
            XCTAssertFalse(name.isEmpty)
        }
    }

    // MARK: - View Initialization Tests

    func testAboutViewInitialization() {
        let aboutView = AboutView(updaterController: mockUpdaterController)
        XCTAssertNotNil(aboutView)
    }

    // MARK: - Sparkle Integration Tests

    func testUpdaterControllerIsInjected() {
        let aboutView = AboutView(updaterController: mockUpdaterController)
        let mirror = Mirror(reflecting: aboutView)
        let updaterProperty = mirror.children.first { $0.label == "updaterController" }

        XCTAssertNotNil(updaterProperty)

        if let updater = updaterProperty?.value as? SPUStandardUpdaterController {
            XCTAssertTrue(updater === mockUpdaterController)
        } else {
            XCTFail("updaterController property should be of type SPUStandardUpdaterController")
        }
    }

    func testUpdaterControllerIsNotStartedAutomatically() {
        // Create a controller with startingUpdater: false
        let nonAutoStartController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let aboutView = AboutView(updaterController: nonAutoStartController)

        // Extract the updater controller from the view
        let mirror = Mirror(reflecting: aboutView)
        let updaterProperty = mirror.children.first { $0.label == "updaterController" }

        XCTAssertNotNil(updaterProperty, "updaterController property should exist")

        guard let controller = updaterProperty?.value as? SPUStandardUpdaterController else {
            XCTFail("updaterController should be of type SPUStandardUpdaterController")
            return
        }

        // Never call `startUpdater()` here. Under xctest there is no app bundle with a feed
        // URL or EdDSA key, so the start fails and Sparkle schedules a modal "Unable to Check
        // For Updates" alert on the main queue four seconds later. On CI nobody can dismiss
        // it, which wedged `swift test` for the full job limit. An unstarted updater reports
        // that it cannot check for updates, which is the property this test cares about.
        XCTAssertFalse(
            controller.updater.canCheckForUpdates,
            "Updater should not be started until startUpdater() is called explicitly")
    }

    // MARK: - View Body Tests

    func testViewBodyReturnsNonNilView() {
        let aboutView = AboutView(updaterController: mockUpdaterController)
        let body = aboutView.body

        XCTAssertNotNil(body)
    }

    // MARK: - Preview Tests

    func testPreviewConfiguration() {
        let previewUpdater = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let aboutView = AboutView(updaterController: previewUpdater)

        XCTAssertNotNil(aboutView)

        let mirror = Mirror(reflecting: aboutView)
        let updaterProperty = mirror.children.first { $0.label == "updaterController" }
        XCTAssertNotNil(updaterProperty)
    }

    // MARK: - Integration Tests

    func testAboutViewCanBeEmbeddedInHostingController() {
        let aboutView = AboutView(updaterController: mockUpdaterController)
        let hostingController = NSHostingController(rootView: aboutView)

        XCTAssertNotNil(hostingController)
        XCTAssertNotNil(hostingController.view)
    }

    func testMultipleAboutViewInstancesCanCoexist() {
        let aboutView1 = AboutView(updaterController: mockUpdaterController)
        let aboutView2 = AboutView(updaterController: mockUpdaterController)

        XCTAssertNotNil(aboutView1)
        XCTAssertNotNil(aboutView2)
    }
}
