import Cocoa

/// Gives focus back to the app the user was in after links that leave no interactive overlay
/// open.
///
/// Opening a link with plain `open` makes Launch Services activate Annotate just before the link
/// arrives, about 10 to 40 ms earlier in its own run-loop pass. Tool and show links open the
/// overlay and need that focus. Color, toolbar, and the other links don't, and would otherwise
/// leave the user's app in the background. `open -g` never activates a running Annotate, so
/// there is nothing to hand back.
///
/// `open` with several links delivers each in its own `application(_:open:)` call, 10 to 60 ms
/// apart. Links that arrive within `settleDelay` of each other count as one burst, and focus is
/// decided once, after the last one, from whether an interactive overlay is open then.
///
/// A link that launches Annotate is different. macOS makes the new process frontmost before any
/// app delegate code runs, and launch activates it again (`updateDockIconVisibility`). The
/// previous app's deactivation is posted before anything can observe it, and
/// `NSWorkspace.frontmostApplication` already names Annotate. What still names the previous app
/// is the window list: Annotate has no normal windows yet, so the topmost one belongs to the app
/// the user was in. `AppDelegate.applicationWillFinishLaunching` passes it to
/// `noteLaunch(previousApp:)`.
@MainActor
final class LinkFocusHandoff: NSObject {
    /// How long before a burst of links Annotate's activation still counts as Launch Services
    /// activating it for them. Wide enough for a busy main thread, short enough that a user who
    /// switched to Annotate on purpose isn't sent away by a link that arrives later.
    static let activationWindow: TimeInterval = 0.5
    /// How long after links that arrived with the launch a launch activation still hands focus
    /// back, when it lands after the burst settled.
    static let launchActivationWindow: TimeInterval = 2
    /// How long the handoff waits for another link before deciding. `open` delivers the links of
    /// one call 10 to 60 ms apart.
    static let settleDelay: TimeInterval = 0.25

    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

    private let ownProcessIdentifier: pid_t
    private let now: @MainActor () -> Date
    private let isActive: @MainActor () -> Bool
    private let activate: @MainActor (NSRunningApplication) -> Void
    private let schedule: Schedule

    /// The app that most recently gave up focus to another app.
    private var lastDeactivatedApp: NSRunningApplication?
    /// When Annotate last became active, and the app that was active before it.
    private var activation: (previousApp: NSRunningApplication?, date: Date)?
    /// The app the user was in when Annotate launched.
    private var launchPreviousApp: NSRunningApplication?
    /// Links from the launch settled before the launch activation, which should hand focus back
    /// when it lands.
    private var pendingHandBack: (app: NSRunningApplication, deadline: Date)?
    /// The links still settling: when the first arrived, whether any came with the launch, and
    /// which `linksDidRun` call is the latest.
    private var burst: (start: Date, launched: Bool, latest: Int)?
    private var callCount = 0

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        appCenter: NotificationCenter = .default,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        now: @escaping @MainActor () -> Date = Date.init,
        isActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        activate: @escaping @MainActor (NSRunningApplication) -> Void = LinkFocusHandoff.giveFocus,
        schedule: @escaping Schedule = LinkFocusHandoff.afterDelay
    ) {
        self.ownProcessIdentifier = ownProcessIdentifier
        self.now = now
        self.isActive = isActive
        self.activate = activate
        self.schedule = schedule
        super.init()
        // Selector observers are dropped when the object is freed, so there is no deinit.
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil)
        appCenter.addObserver(
            self, selector: #selector(didBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        appCenter.addObserver(
            self, selector: #selector(didResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }

    /// Call as launch starts with the app the user was in, from `appOwningTopmostWindow()`.
    func noteLaunch(previousApp: NSRunningApplication?) {
        guard let app = previousApp, app.processIdentifier != ownProcessIdentifier else { return }
        launchPreviousApp = app
    }

    /// Call after each `application(_:open:)` call's links have run, whether their commands ran
    /// or were ignored. Pass `launched` for links that arrived with the launch. Once no link has
    /// arrived for `settleDelay`, the handoff asks `keepsFocus` whether an interactive overlay is
    /// open. If not, and opening the links activated Annotate, the previous app gets focus back.
    func linksDidRun(launched: Bool = false, keepsFocus: @escaping @MainActor () -> Bool) {
        callCount += 1
        let call = callCount
        if let burst {
            self.burst = (burst.start, burst.launched || launched, call)
        } else {
            burst = (now(), launched, call)
        }
        schedule(Self.settleDelay) { [weak self] in
            guard let self, self.burst?.latest == call else { return }
            self.settle(keepsFocus: keepsFocus())
        }
    }

    /// Whether links are still waiting for focus to be decided.
    var isSettling: Bool { burst != nil }

    private func settle(keepsFocus: Bool) {
        guard let burst else { return }
        self.burst = nil
        // One activation hands back once, whatever the links did.
        let activation = self.activation
        self.activation = nil
        pendingHandBack = nil
        guard !keepsFocus else { return }

        guard isActive() else {
            // The launch activation hasn't landed yet.
            if burst.launched, let app = launchPreviousApp ?? lastDeactivatedApp {
                pendingHandBack = (app, now().addingTimeInterval(Self.launchActivationWindow))
            }
            return
        }
        guard let activation else { return }
        // Any activation since launch is the launch's own. Otherwise it must be close enough to
        // the first link to be Launch Services activating the app for these links.
        let previousApp: NSRunningApplication?
        if burst.launched {
            previousApp = activation.previousApp ?? launchPreviousApp
        } else if burst.start.timeIntervalSince(activation.date) <= Self.activationWindow {
            previousApp = activation.previousApp
        } else {
            previousApp = nil
        }
        handBack(to: previousApp)
    }

    @discardableResult
    private func handBack(to app: NSRunningApplication?) -> Bool {
        guard let app, !app.isTerminated else { return false }
        activate(app)
        return true
    }

    @objc private func applicationDidDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.processIdentifier != ownProcessIdentifier
        else { return }
        lastDeactivatedApp = app
    }

    /// The workspace posts the other app's deactivation before AppKit posts this.
    @objc private func didBecomeActive() {
        if let pending = pendingHandBack {
            pendingHandBack = nil
            if now() <= pending.deadline, handBack(to: pending.app) { return }
        }
        activation = (lastDeactivatedApp, now())
    }

    @objc private func didResignActive() {
        activation = nil
    }

    // MARK: - System

    /// The regular app that owns the topmost normal window on screen, other than Annotate.
    /// Window owners need no Screen Recording permission. Nil if no such window is on screen.
    static func appOwningTopmostWindow(
        excluding ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> NSRunningApplication? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // Front to back. Layer 0 holds normal app windows, above the desktop and below the menu
        // bar, the Dock, and overlays such as Annotate's own.
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownProcessIdentifier,
                let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { continue }
            return app
        }
        return nil
    }

    private static func giveFocus(to app: NSRunningApplication) {
        // Cooperative activation (macOS 14): the active app yields, then the target activates.
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }

    private static func afterDelay(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { work() }
        }
    }
}
