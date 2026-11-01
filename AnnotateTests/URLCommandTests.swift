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

    func testRejectedLinksReportWhy() throws {
        let cases: [(String, AnnotateCommand.LinkRejection)] = [
            ("https://show", .otherScheme),
            ("annotatex://show", .otherScheme),
            ("annotate://", .missingCommand),
            ("annotate:show", .missingCommand),
            ("annotate://show?token=s3cret", .extraParts),
            ("annotate://show#top", .extraParts),
            ("annotate://me:hunter2@show", .extraParts),
            ("annotate://show:80", .extraParts),
            ("annotate://nope", .unknownCommand),
            ("annotate://tool/brush", .unknownCommand),
            ("annotate://tool/arrow/extra", .unknownCommand),
        ]
        for (string, reason) in cases {
            guard case .failure(let rejection) = AnnotateCommand.parse(url: try link(string), scheme: "annotate") else {
                XCTFail("\(string) parsed as a command")
                continue
            }
            XCTAssertEqual(rejection, reason, string)
        }
    }

    // MARK: - Logging

    func testLogDescriptionKeepsOnlyTheSchemeAndCommand() throws {
        XCTAssertEqual(AnnotateCommand.logDescription(of: try link("annotate://tool/arrow")), "annotate://tool/arrow")
        XCTAssertEqual(AnnotateCommand.logDescription(of: try link("annotate:show")), "annotate:show")
        XCTAssertEqual(
            AnnotateCommand.logDescription(of: try link("annotate://show?token=s3cret#frag")),
            "annotate://show (dropped query, fragment)")
        XCTAssertEqual(
            AnnotateCommand.logDescription(of: try link("annotate://me:hunter2@show:8080/now")),
            "annotate://show/now (dropped user, password, port)")
    }

    func testLogDescriptionKeepsPercentEncodingOnOneLine() throws {
        XCTAssertEqual(
            AnnotateCommand.logDescription(of: try link("annotate://tool/arr%0Aow")), "annotate://tool/arr%0Aow")
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

    /// The focus tests' clock. Frozen, so a slow CI pass between the activation and the links
    /// can't push them out of the handoff's time windows. `LinkFocusHandoffTests` covers those.
    private static let frozenNow = Date(timeIntervalSinceReferenceDate: 0)

    /// Runs the run loop until the links queued during launch have run. Polls with a deadline
    /// instead of waiting a fixed time, since CI can stall a single run-loop pass for seconds.
    private func waitForLaunchLinks(timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while !appDelegate.pendingCommandURLs.isEmpty && Date() < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        XCTAssertTrue(appDelegate.pendingCommandURLs.isEmpty, "The queued links never ran")
    }

    /// Installs a handoff that sees Launch Services activate Annotate for the next link, and
    /// returns the apps it gave focus to.
    private func activateForNextLink() -> () -> [NSRunningApplication] {
        let workspaceCenter = NotificationCenter()
        let appCenter = NotificationCenter()
        var activated: [NSRunningApplication] = []
        appDelegate.linkFocusHandoff = LinkFocusHandoff(
            workspaceCenter: workspaceCenter,
            appCenter: appCenter,
            ownProcessIdentifier: -1,
            now: { Self.frozenNow },
            isActive: { true },
            activate: { activated.append($0) })
        workspaceCenter.post(
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        return { activated }
    }

    func testAColorLinkHandsFocusBackToThePreviousApp() throws {
        launch()
        let activated = activateForNextLink()

        try open("annotate-debug://color/green")

        XCTAssertEqual(activated(), [NSRunningApplication.current])
    }

    func testALinkThatOpensTheOverlayKeepsFocus() throws {
        launch()
        let activated = activateForNextLink()

        try open("annotate-debug://tool/arrow")

        XCTAssertEqual(overlay?.isVisible, true)
        XCTAssertTrue(activated().isEmpty)
    }

    func testAColorLinkInAlwaysOnHandsFocusBack() throws {
        launch()
        appDelegate.toggleAlwaysOnMode()
        let activated = activateForNextLink()

        try open("annotate-debug://color/green")

        XCTAssertEqual(activated(), [NSRunningApplication.current], "Always-On overlays take no input")
    }

    func testAnIgnoredLinkHandsFocusBackToo() throws {
        launch()
        var activated = activateForNextLink()
        try open("annotate-debug://tool/brush")
        XCTAssertEqual(activated(), [NSRunningApplication.current], "Rejected link")

        testDefaults.settings[.urlCommandsEnabled] = false
        activated = activateForNextLink()
        try open("annotate-debug://color/green")
        XCTAssertEqual(activated(), [NSRunningApplication.current], "URL commands off")
    }

    // MARK: - Focus for a batch of links

    func testShowThenHideInOneOpenHandsFocusBack() throws {
        launch()
        let activated = activateForNextLink()

        try open("annotate-debug://show", "annotate-debug://hide")

        XCTAssertTrue(visibleOverlays.isEmpty)
        XCTAssertEqual(activated(), [NSRunningApplication.current], "Decided after the last link, not the first")
    }

    func testColorThenToolInOneOpenKeepsFocus() throws {
        launch()
        let activated = activateForNextLink()

        try open("annotate-debug://color/green", "annotate-debug://tool/arrow")

        XCTAssertEqual(overlay?.isVisible, true)
        XCTAssertEqual(appDelegate.currentColor, .systemGreen)
        XCTAssertTrue(activated().isEmpty, "The tool link's overlay needs focus")
    }

    func testABatchDecidesFocusOnce() throws {
        launch()
        let activated = activateForNextLink()

        try open("annotate-debug://color/green", "annotate-debug://toolbar/off", "annotate-debug://fade/off")

        XCTAssertEqual(activated(), [NSRunningApplication.current])
    }

    // MARK: - Focus for links that launch the app

    /// A handoff as `applicationWillFinishLaunching` makes one, with the launch activation still
    /// to come. Returns a way to post that activation and the apps given focus.
    private func prepareLaunchHandoff() -> (activate: () -> Void, activated: () -> [NSRunningApplication]) {
        let appCenter = NotificationCenter()
        var isActive = false
        var activated: [NSRunningApplication] = []
        let handoff = LinkFocusHandoff(
            workspaceCenter: NotificationCenter(),
            appCenter: appCenter,
            ownProcessIdentifier: -1,
            now: { Self.frozenNow },
            isActive: { isActive },
            activate: { activated.append($0) })
        handoff.noteLaunch(frontmostApp: NSRunningApplication.current)
        appDelegate.linkFocusHandoff = handoff
        let activateApp = {
            isActive = true
            appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        }
        return (activateApp, { activated })
    }

    func testAColorLinkThatLaunchesTheAppHandsFocusBackWhenLaunchActivatesIt() throws {
        let launchHandoff = prepareLaunchHandoff()
        try open("annotate-debug://color/green")
        launch()
        waitForLaunchLinks()
        XCTAssertEqual(appDelegate.currentColor, .systemGreen)
        XCTAssertTrue(launchHandoff.activated().isEmpty, "Not active yet, so nothing to hand back")

        launchHandoff.activate()

        XCTAssertEqual(launchHandoff.activated(), [NSRunningApplication.current])
    }

    func testAColorLinkThatLaunchesTheAppHandsFocusBackWhenLaunchActivatedItFirst() throws {
        let launchHandoff = prepareLaunchHandoff()
        try open("annotate-debug://color/green")
        launchHandoff.activate()
        launch()
        waitForLaunchLinks()

        XCTAssertEqual(launchHandoff.activated(), [NSRunningApplication.current])
    }

    func testAToolLinkThatLaunchesTheAppKeepsFocus() throws {
        let launchHandoff = prepareLaunchHandoff()
        try open("annotate-debug://tool/arrow")
        launch()
        waitForLaunchLinks()
        launchHandoff.activate()

        XCTAssertEqual(overlay?.isVisible, true)
        XCTAssertTrue(launchHandoff.activated().isEmpty)
    }

    func testALinkThatLaunchesTheAppRunsOnceLaunchFinishes() throws {
        // Launch Services can deliver the link that launched the app before launch finishes.
        try open("annotate-debug://tool/rectangle")
        XCTAssertTrue(appDelegate.overlayWindows.isEmpty)

        launch()
        waitForLaunchLinks()

        let overlay = try XCTUnwrap(overlay)
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.overlayView.currentTool, .rectangle)
        XCTAssertTrue(appDelegate.pendingCommandURLs.isEmpty)
    }

    func testALinkThatArrivesBeforeTheLaunchLinksRunWaitsBehindThem() throws {
        try open("annotate-debug://tool/rectangle")
        launch()
        // Launch finished, but the queued link hasn't run yet.
        try open("annotate-debug://tool/arrow")
        XCTAssertNotEqual(overlay?.isVisible, true)

        waitForLaunchLinks()

        XCTAssertEqual(overlay?.overlayView.currentTool, .arrow, "The later link runs last")
    }
}
