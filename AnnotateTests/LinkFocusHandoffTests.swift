import XCTest

@testable import Annotate

/// Runs scheduled work only when a test says so, with a clock the test moves.
@MainActor
final class ManualScheduler {
    var now = Date(timeIntervalSinceReferenceDate: 0)
    private var queue: [(due: Date, work: @MainActor () -> Void)] = []

    var schedule: LinkFocusHandoff.Schedule {
        { [unowned self] delay, work in queue.append((now.addingTimeInterval(delay), work)) }
    }

    /// Moves the clock forward and runs whatever came due, in order.
    func advance(by interval: TimeInterval) {
        now += interval
        let due = queue.filter { $0.due <= now }
        queue.removeAll { $0.due <= now }
        due.forEach { $0.work() }
    }
}

@MainActor
final class LinkFocusHandoffTests: XCTestCase {
    private var workspaceCenter: NotificationCenter!
    private var appCenter: NotificationCenter!
    private var scheduler: ManualScheduler!
    private var isActive = true
    private var overlayOpen = false
    private var activated: [NSRunningApplication] = []
    private var handoff: LinkFocusHandoff!
    /// Stands in for the app the user was in. The handoff only reads its process identifier.
    private let previousApp = NSRunningApplication.current

    override func setUp() {
        super.setUp()
        workspaceCenter = NotificationCenter()
        appCenter = NotificationCenter()
        scheduler = ManualScheduler()
        isActive = true
        overlayOpen = false
        activated = []
        handoff = makeHandoff(ownProcessIdentifier: -1)
    }

    override func tearDown() {
        handoff = nil
        scheduler = nil
        workspaceCenter = nil
        appCenter = nil
        super.tearDown()
    }

    private func makeHandoff(ownProcessIdentifier: pid_t) -> LinkFocusHandoff {
        LinkFocusHandoff(
            workspaceCenter: workspaceCenter,
            appCenter: appCenter,
            ownProcessIdentifier: ownProcessIdentifier,
            now: { [unowned self] in scheduler.now },
            isActive: { [unowned self] in isActive },
            activate: { [unowned self] in activated.append($0) },
            schedule: scheduler.schedule)
    }

    /// What Launch Services does before delivering a link opened with plain `open`: the
    /// workspace reports the previous app's deactivation, then AppKit reports activation.
    private func activateAnnotate(from app: NSRunningApplication) {
        workspaceCenter.post(
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app])
        becomeActive()
    }

    private func becomeActive() {
        isActive = true
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    /// One `application(_:open:)` call whose links leave the overlay open or closed.
    private func deliver(leavingOverlayOpen open: Bool, launched: Bool = false) {
        overlayOpen = open
        handoff.linksDidRun(launched: launched) { [unowned self] in overlayOpen }
    }

    private func settle() {
        scheduler.advance(by: LinkFocusHandoff.settleDelay)
    }

    // MARK: - One link

    func testALinkThatActivatedAnnotateHandsFocusBackOnceItSettles() {
        activateAnnotate(from: previousApp)
        scheduler.advance(by: 0.02)
        deliver(leavingOverlayOpen: false)
        XCTAssertTrue(activated.isEmpty, "Waits in case another link follows")
        XCTAssertTrue(handoff.isSettling)

        settle()

        XCTAssertEqual(activated, [previousApp])
        XCTAssertFalse(handoff.isSettling)
    }

    func testALinkThatLeavesAnOverlayOpenKeepsFocus() {
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: true)
        settle()

        XCTAssertTrue(activated.isEmpty)
    }

    func testOneActivationHandsBackOnce() {
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: false)
        settle()
        deliver(leavingOverlayOpen: false)
        settle()

        XCTAssertEqual(activated.count, 1)
    }

    func testAnOverlayLinkUsesUpTheActivation() {
        // A tool link opens the overlay; a color link a while later must not send focus away.
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: true)
        settle()
        deliver(leavingOverlayOpen: false)
        settle()

        XCTAssertTrue(activated.isEmpty)
    }

    func testAnOlderActivationIsLeftAlone() {
        // The user switched to Annotate on purpose, then a link arrived.
        activateAnnotate(from: previousApp)
        scheduler.advance(by: LinkFocusHandoff.activationWindow + 0.1)
        deliver(leavingOverlayOpen: false)
        settle()

        XCTAssertTrue(activated.isEmpty)
    }

    func testABackgroundLinkHasNothingToHandBack() {
        // `open -g` delivers the link without activating Annotate.
        isActive = false
        deliver(leavingOverlayOpen: false)
        settle()

        XCTAssertTrue(activated.isEmpty)
    }

    func testResigningActiveWhileSettlingDropsTheActivation() {
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: false)
        appCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
        settle()

        XCTAssertTrue(activated.isEmpty)
    }

    func testAnnotatesOwnDeactivationIsNotAPreviousApp() {
        handoff = makeHandoff(ownProcessIdentifier: previousApp.processIdentifier)
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: false)
        settle()

        XCTAssertTrue(activated.isEmpty)
    }

    // MARK: - Several links from one `open`

    // `open` with two links makes two `application(_:open:)` calls 10 to 60 ms apart.

    func testShowThenHideDeliveredSeparatelyHandsFocusBack() {
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: true)
        scheduler.advance(by: 0.04)
        deliver(leavingOverlayOpen: false)
        settle()

        XCTAssertEqual(activated, [previousApp], "Decided after the last link, not the first")
    }

    func testColorThenToolDeliveredSeparatelyKeepsFocus() {
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: false)
        scheduler.advance(by: 0.04)
        XCTAssertTrue(activated.isEmpty, "The color link alone must not hand focus back yet")
        deliver(leavingOverlayOpen: true)
        settle()
        scheduler.advance(by: 1)

        XCTAssertTrue(activated.isEmpty, "The tool link's overlay needs focus")
    }

    func testABurstLongerThanTheActivationWindowStillCounts() {
        // The window is measured to the burst's first link, not to when it settles.
        activateAnnotate(from: previousApp)
        for _ in 0..<5 {
            deliver(leavingOverlayOpen: false)
            scheduler.advance(by: 0.2)
        }
        settle()

        XCTAssertEqual(activated, [previousApp])
    }

    func testLinksFartherApartThanTheSettleDelayDecideSeparately() {
        activateAnnotate(from: previousApp)
        deliver(leavingOverlayOpen: false)
        settle()
        XCTAssertEqual(activated, [previousApp])

        // A later tool link starts its own burst. Focus already went back, so nothing changes.
        deliver(leavingOverlayOpen: true)
        settle()
        XCTAssertEqual(activated, [previousApp])
    }

    // MARK: - Links that launched the app

    func testLaunchLinksHandBackWhenTheLaunchActivationLandsAfterThem() {
        handoff.noteLaunch(previousApp: previousApp)
        isActive = false
        deliver(leavingOverlayOpen: false, launched: true)
        settle()
        XCTAssertTrue(activated.isEmpty)

        scheduler.advance(by: 0.3)
        becomeActive()

        XCTAssertEqual(activated, [previousApp])
    }

    func testALateLaunchActivationIsLeftAlone() {
        handoff.noteLaunch(previousApp: previousApp)
        isActive = false
        deliver(leavingOverlayOpen: false, launched: true)
        settle()

        scheduler.advance(by: LinkFocusHandoff.launchActivationWindow + 0.1)
        becomeActive()

        XCTAssertTrue(activated.isEmpty)
    }

    func testLaunchLinksHandBackAfterAnEarlierLaunchActivation() {
        // What a live cold launch does: macOS activates the new process before any delegate
        // code runs, so no workspace notification names the previous app. The window list does.
        handoff.noteLaunch(previousApp: previousApp)
        becomeActive()
        scheduler.advance(by: LinkFocusHandoff.activationWindow + 0.5)
        deliver(leavingOverlayOpen: false, launched: true)
        settle()

        XCTAssertEqual(activated, [previousApp])
    }

    func testLaunchLinksThatOpenTheOverlayKeepFocus() {
        handoff.noteLaunch(previousApp: previousApp)
        isActive = false
        deliver(leavingOverlayOpen: true, launched: true)
        settle()
        becomeActive()

        XCTAssertTrue(activated.isEmpty)
    }

    func testLaunchingWithAnnotateAsThePreviousAppHandsNothingBack() {
        handoff = makeHandoff(ownProcessIdentifier: previousApp.processIdentifier)
        handoff.noteLaunch(previousApp: previousApp)
        becomeActive()
        deliver(leavingOverlayOpen: false, launched: true)
        settle()

        XCTAssertTrue(activated.isEmpty)
    }

    // MARK: - Window list

    func testTheTopmostWindowOwnerIsNeverAnnotateItself() {
        let me = ProcessInfo.processInfo.processIdentifier
        let app = LinkFocusHandoff.appOwningTopmostWindow(excluding: me)
        XCTAssertNotEqual(app?.processIdentifier, me)
        if let app {
            XCTAssertEqual(app.activationPolicy, .regular)
        }
    }
}
