import XCTest

@testable import Annotate

@MainActor
final class LinkFocusHandoffTests: XCTestCase {
    private var workspaceCenter: NotificationCenter!
    private var appCenter: NotificationCenter!
    private var clock: Date!
    private var isActive = true
    private var activated: [NSRunningApplication] = []
    private var handoff: LinkFocusHandoff!
    /// Stands in for the app the user was in. The handoff only reads its process identifier.
    private let previousApp = NSRunningApplication.current

    override func setUp() {
        super.setUp()
        workspaceCenter = NotificationCenter()
        appCenter = NotificationCenter()
        clock = Date(timeIntervalSinceReferenceDate: 0)
        isActive = true
        activated = []
        handoff = LinkFocusHandoff(
            workspaceCenter: workspaceCenter,
            appCenter: appCenter,
            ownProcessIdentifier: -1,
            now: { [unowned self] in clock },
            isActive: { [unowned self] in isActive },
            activate: { [unowned self] in activated.append($0) })
    }

    override func tearDown() {
        handoff = nil
        workspaceCenter = nil
        appCenter = nil
        super.tearDown()
    }

    /// What Launch Services does before delivering a link opened with plain `open`: the
    /// workspace reports the previous app's deactivation, then AppKit reports activation.
    private func activateAnnotate(from app: NSRunningApplication) {
        workspaceCenter.post(
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app])
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func testALinkThatActivatedAnnotateHandsFocusBack() {
        activateAnnotate(from: previousApp)
        clock += 0.02

        XCTAssertEqual(handoff.linksDidRun(keepsFocus: false), previousApp)
        XCTAssertEqual(activated, [previousApp])
    }

    func testALinkThatLeavesAnOverlayOpenKeepsFocus() {
        activateAnnotate(from: previousApp)

        XCTAssertNil(handoff.linksDidRun(keepsFocus: true))
        XCTAssertTrue(activated.isEmpty)
    }

    func testOneActivationHandsBackOnce() {
        activateAnnotate(from: previousApp)
        handoff.linksDidRun(keepsFocus: false)

        XCTAssertNil(handoff.linksDidRun(keepsFocus: false))
        XCTAssertEqual(activated.count, 1)
    }

    func testAnOverlayLinkUsesUpTheActivation() {
        // A tool link opens the overlay; a color link right after must not send focus away.
        activateAnnotate(from: previousApp)
        handoff.linksDidRun(keepsFocus: true)

        XCTAssertNil(handoff.linksDidRun(keepsFocus: false))
    }

    func testAnOlderActivationIsLeftAlone() {
        // The user switched to Annotate on purpose, then a link arrived.
        activateAnnotate(from: previousApp)
        clock += LinkFocusHandoff.activationWindow + 0.1

        XCTAssertNil(handoff.linksDidRun(keepsFocus: false))
    }

    func testABackgroundLinkHasNothingToHandBack() {
        // `open -g` delivers the link without activating Annotate.
        isActive = false

        XCTAssertNil(handoff.linksDidRun(keepsFocus: false))
        activateAnnotate(from: previousApp)
        isActive = false
        XCTAssertNil(handoff.linksDidRun(keepsFocus: false))
    }

    func testResigningActiveDropsTheActivation() {
        activateAnnotate(from: previousApp)
        appCenter.post(name: NSApplication.didResignActiveNotification, object: nil)

        XCTAssertNil(handoff.linksDidRun(keepsFocus: false))
    }

    func testAnnotatesOwnDeactivationIsNotAPreviousApp() {
        let ownApp = NSRunningApplication.current
        let handoff = LinkFocusHandoff(
            workspaceCenter: workspaceCenter,
            appCenter: appCenter,
            ownProcessIdentifier: ownApp.processIdentifier,
            now: { [unowned self] in clock },
            isActive: { true },
            activate: { [unowned self] in activated.append($0) })

        activateAnnotate(from: ownApp)

        XCTAssertNil(handoff.linksDidRun(keepsFocus: false))
    }

    // MARK: - Links that launched the app

    func testLaunchLinksHandBackWhenTheLaunchActivationLandsAfterThem() {
        handoff.noteLaunch(frontmostApp: previousApp)
        isActive = false
        XCTAssertNil(handoff.linksDidRun(keepsFocus: false, launched: true))

        clock += 0.3
        isActive = true
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(activated, [previousApp])
    }

    func testALateLaunchActivationIsLeftAlone() {
        handoff.noteLaunch(frontmostApp: previousApp)
        isActive = false
        handoff.linksDidRun(keepsFocus: false, launched: true)

        clock += LinkFocusHandoff.launchActivationWindow + 0.1
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(activated.isEmpty)
    }

    func testLaunchLinksHandBackAfterAnEarlierLaunchActivation() {
        // Launch can activate the app well before the queued links run. No workspace
        // notification arrived, so the app frontmost during launch is the one to go back to.
        handoff.noteLaunch(frontmostApp: previousApp)
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        clock += LinkFocusHandoff.activationWindow + 0.5

        XCTAssertEqual(handoff.linksDidRun(keepsFocus: false, launched: true), previousApp)
    }

    func testLaunchLinksThatOpenTheOverlayKeepFocus() {
        handoff.noteLaunch(frontmostApp: previousApp)
        isActive = false
        handoff.linksDidRun(keepsFocus: true, launched: true)
        isActive = true
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(activated.isEmpty)
    }

    func testLaunchingFromAnnotateItselfRecordsNoPreviousApp() {
        let handoff = LinkFocusHandoff(
            workspaceCenter: workspaceCenter,
            appCenter: appCenter,
            ownProcessIdentifier: previousApp.processIdentifier,
            now: { [unowned self] in clock },
            isActive: { true },
            activate: { [unowned self] in activated.append($0) })
        handoff.noteLaunch(frontmostApp: previousApp)
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertNil(handoff.linksDidRun(keepsFocus: false, launched: true))
    }
}
