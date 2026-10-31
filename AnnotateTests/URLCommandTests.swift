import XCTest

@testable import Annotate

@MainActor
final class URLCommandTests: XCTestCase {
    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!
    var screen: NSScreen!

    override func setUp() {
        super.setUp()
        TestWindows.recordOpenWindows()
        testDefaults = TestUserDefaults.create()
        BoardManager.shared = BoardManager(userDefaults: testDefaults)
        ShortcutManager.shared = ShortcutManager(userDefaults: testDefaults)

        appDelegate = AppDelegate(userDefaults: testDefaults)
        // Commands that open the overlay use the display under the pointer.
        screen = NSScreen.screens.first
        appDelegate.pointerLocationOverride = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    override func tearDown() {
        appDelegate.overlayWindows.values.forEach { $0.stopFadeLoop() }
        appDelegate.tearDownAfterLaunch()
        appDelegate = nil
        screen = nil
        assertNoLeakedWindows()
        TestUserDefaults.removeSuite()
        testDefaults = nil
        super.tearDown()
    }

    private func launch() {
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
    }

    private var overlay: OverlayWindow? { appDelegate.overlayWindows[screen] }

    private var visibleOverlays: [OverlayWindow] {
        appDelegate.overlayWindows.values.filter(\.isVisible)
    }

    private func link(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), string)
    }

    /// Opens links the way Launch Services delivers them.
    private func open(_ strings: String...) throws {
        appDelegate.application(NSApplication.shared, open: try strings.map(link))
    }

    // MARK: - Parsing

    func testDebugBuildsUseTheirOwnScheme() {
        // `swift test` and Xcode's test action both build Debug.
        XCTAssertEqual(AnnotateCommand.urlScheme, "annotate-debug")
    }

    func testEveryCommandRoundTripsThroughALink() throws {
        for command in AnnotateCommandTests.everyCommand {
            for scheme in ["annotate", "annotate-debug"] {
                let url = try link("\(scheme):/\(command.path)")
                XCTAssertEqual(AnnotateCommand(url: url, scheme: scheme), command, url.absoluteString)
            }
        }
    }

    func testLinksUseTheHostAsTheCommand() throws {
        XCTAssertEqual(AnnotateCommand(url: try link("annotate://show"), scheme: "annotate"), .show)
        XCTAssertEqual(AnnotateCommand(url: try link("annotate://show/"), scheme: "annotate"), .show)
        XCTAssertEqual(AnnotateCommand(url: try link("annotate://tool/arrow"), scheme: "annotate"), .tool(.arrow))
        XCTAssertEqual(AnnotateCommand(url: try link("annotate://toolbar/off"), scheme: "annotate"), .toolbar(.off))
        XCTAssertEqual(AnnotateCommand(url: try link("ANNOTATE://Color/Red"), scheme: "annotate"), .color(.red))
    }

    func testLinksOnlyMatchTheBuildsScheme() throws {
        XCTAssertNil(AnnotateCommand(url: try link("annotate-debug://show"), scheme: "annotate"))
        XCTAssertNil(AnnotateCommand(url: try link("annotate://show"), scheme: "annotate-debug"))
        XCTAssertNil(AnnotateCommand(url: try link("annotate://show")), "Debug builds ignore release links")
        XCTAssertEqual(AnnotateCommand(url: try link("annotate-debug://show")), .show)
    }

    func testMalformedLinksParseAsNothing() throws {
        let invalid = [
            "annotate://", "annotate:///show", "annotate:show", "annotate://nope",
            "annotate://tool", "annotate://tool/brush", "annotate://color/purple",
            "annotate://toolbar/maybe", "annotate://show/now", "annotate://tool/arrow/extra",
            "annotate://show?now=1", "annotate://show?", "annotate://show#top",
            "annotate://user@show", "annotate://user:pass@show", "annotate://show:80",
            "https://show", "file:///show", "annotatex://show",
        ]
        for string in invalid {
            XCTAssertNil(AnnotateCommand(url: try link(string), scheme: "annotate"), string)
        }
    }

    // MARK: - Opening links

    func testURLCommandsAreOnByDefault() {
        XCTAssertTrue(testDefaults.settings[.urlCommandsEnabled])
    }

    func testToolLinkOpensTheOverlayWithItsHUD() throws {
        launch()
        let overlay = try XCTUnwrap(overlay)

        try open("annotate-debug://tool/arrow")

        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.overlayView.currentTool, .arrow)
        let hud = overlay.currentFeedbackView?.subviews.lazy.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(hud?.stringValue.contains("Arrow"), true)
    }

    func testColorAndToolbarLinksDoNotOpenTheOverlay() throws {
        launch()

        try open("annotate-debug://color/green", "annotate-debug://toolbar/off")

        XCTAssertTrue(visibleOverlays.isEmpty)
        XCTAssertEqual(appDelegate.currentColor, .systemGreen)
        XCTAssertFalse(appDelegate.toolbarVisible)
    }

    func testOpeningALinkReportsWhatItsCommandDid() throws {
        launch()

        XCTAssertEqual(appDelegate.openCommandURL(try link("annotate-debug://show")), .ran)
        XCTAssertEqual(appDelegate.openCommandURL(try link("annotate-debug://show")), .noOp)
    }

    func testLinksAreIgnoredWhenURLCommandsAreOff() throws {
        testDefaults.settings[.urlCommandsEnabled] = false
        launch()
        let colorBefore = appDelegate.currentColor

        XCTAssertNil(appDelegate.openCommandURL(try link("annotate-debug://show")))
        try open("annotate-debug://tool/arrow", "annotate-debug://color/green", "annotate-debug://toolbar/off")

        XCTAssertTrue(visibleOverlays.isEmpty)
        XCTAssertEqual(appDelegate.currentColor, colorBefore)
        XCTAssertTrue(appDelegate.toolbarVisible)

        testDefaults.settings[.urlCommandsEnabled] = true
        try open("annotate-debug://show")
        XCTAssertEqual(overlay?.isVisible, true, "Links run again once the setting is back on")
    }

    func testMalformedLinksChangeNothing() throws {
        launch()
        let colorBefore = appDelegate.currentColor

        XCTAssertNil(appDelegate.openCommandURL(try link("annotate-debug://tool/brush")))
        try open("annotate-debug://", "annotate-debug://show?x=1", "annotate://show", "https://example.com")

        XCTAssertTrue(visibleOverlays.isEmpty)
        XCTAssertEqual(appDelegate.currentColor, colorBefore)
        XCTAssertTrue(appDelegate.toolbarVisible)
    }

    func testALinkThatLaunchesTheAppRunsOnceLaunchFinishes() throws {
        // Launch Services can deliver the link that launched the app before launch finishes.
        try open("annotate-debug://tool/rectangle")
        XCTAssertTrue(appDelegate.overlayWindows.isEmpty)

        launch()
        wait(for: 0.05)

        let overlay = try XCTUnwrap(overlay)
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.overlayView.currentTool, .rectangle)
        XCTAssertTrue(appDelegate.pendingCommandURLs.isEmpty)
    }
}
