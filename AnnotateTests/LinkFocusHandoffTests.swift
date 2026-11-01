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

        XCTAssertEqual(handoff.linkDidRun(keepsFocus: false), previousApp)
        XCTAssertEqual(activated, [previousApp])
    }

    func testALinkThatLeavesAnOverlayOpenKeepsFocus() {
        activateAnnotate(from: previousApp)

        XCTAssertNil(handoff.linkDidRun(keepsFocus: true))
        XCTAssertTrue(activated.isEmpty)
    }

    func testOneActivationHandsBackOnce() {
        activateAnnotate(from: previousApp)
        handoff.linkDidRun(keepsFocus: false)

        XCTAssertNil(handoff.linkDidRun(keepsFocus: false))
        XCTAssertEqual(activated.count, 1)
    }

    func testAnOverlayLinkUsesUpTheActivation() {
        // A tool link opens the overlay; a color link right after must not send focus away.
        activateAnnotate(from: previousApp)
        handoff.linkDidRun(keepsFocus: true)

        XCTAssertNil(handoff.linkDidRun(keepsFocus: false))
    }

    func testAnOlderActivationIsLeftAlone() {
        // The user switched to Annotate on purpose, then a link arrived.
        activateAnnotate(from: previousApp)
        clock += LinkFocusHandoff.activationWindow + 0.1

        XCTAssertNil(handoff.linkDidRun(keepsFocus: false))
    }

    func testABackgroundLinkHasNothingToHandBack() {
        // `open -g` delivers the link without activating Annotate.
        isActive = false

        XCTAssertNil(handoff.linkDidRun(keepsFocus: false))
        activateAnnotate(from: previousApp)
        isActive = false
        XCTAssertNil(handoff.linkDidRun(keepsFocus: false))
    }

    func testResigningActiveDropsTheActivation() {
        activateAnnotate(from: previousApp)
        appCenter.post(name: NSApplication.didResignActiveNotification, object: nil)

        XCTAssertNil(handoff.linkDidRun(keepsFocus: false))
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

        XCTAssertNil(handoff.linkDidRun(keepsFocus: false))
    }
}
