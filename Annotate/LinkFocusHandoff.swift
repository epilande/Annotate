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

    /// When Annotate became active, and the app that was active before it.
    private struct Activation {
        let previousApp: NSRunningApplication?
        let date: Date
    }

    /// Links waiting for focus to be decided.
    private struct Burst {
        let start: Date
        /// Whether any of the links came with the launch.
        var launched: Bool
        /// The latest `linksDidRun` call. Only its scheduled settle decides.
        var latest: Int
        /// Asks whether an interactive overlay is open. The latest call's.
        var keepsFocus: @MainActor () -> Bool
        /// The activation that opening these links caused. Taken when the burst starts, so an
        /// activation that comes later (the user switching back on purpose) never counts.
        var activation: Activation?
        /// Annotate resigned active while the burst settled. The user went elsewhere, so
        /// nothing is handed back.
        var resigned = false
    }

    /// The app that most recently gave up focus to another app.
    private var lastDeactivatedApp: NSRunningApplication?
    /// The latest activation that no burst has taken yet.
    private var activation: Activation?
    /// The app the user was in when Annotate launched.
    private var launchPreviousApp: NSRunningApplication?
    private var burst: Burst?
    private var callCount = 0
    /// A launch burst settled before the launch activation landed. When it lands, the burst
    /// settles again, unless a newer link has replaced it.
    private var deferredLaunch: (keepsFocus: @MainActor () -> Bool, deadline: Date)?

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
    /// A newer link always supersedes any decision still waiting.
    func linksDidRun(launched: Bool = false, keepsFocus: @escaping @MainActor () -> Bool) {
        deferredLaunch = nil
        if var burst {
            burst.launched = burst.launched || launched
            burst.keepsFocus = keepsFocus
            startSettling(&burst)
            self.burst = burst
        } else {
            let start = now()
            var burst = Burst(
                start: start,
                launched: launched,
                latest: 0,
                keepsFocus: keepsFocus,
                activation: takeActivation(forBurstAt: start, launched: launched))
            startSettling(&burst)
            self.burst = burst
        }
    }

    /// Whether links are still waiting for focus to be decided.
    var isSettling: Bool { burst != nil }

    /// Takes the activation that opening a burst's links caused. One activation hands back
    /// once, whatever the links did. Any activation since launch is the launch's own. Otherwise
    /// it must come shortly before the first link, as Launch Services activates the app just
    /// before it delivers the link.
    private func takeActivation(forBurstAt start: Date, launched: Bool) -> Activation? {
        guard let activation else { return nil }
        self.activation = nil
        if launched { return activation }
        let age = start.timeIntervalSince(activation.date)
        return age >= 0 && age <= Self.activationWindow ? activation : nil
    }

    /// Makes this burst's latest call the one whose settle decides, and schedules it.
    private func startSettling(_ burst: inout Burst) {
        callCount += 1
        let call = callCount
        burst.latest = call
        schedule(Self.settleDelay) { [weak self] in
            guard let self, self.burst?.latest == call else { return }
            self.settle()
        }
    }

    private func settle() {
        guard let burst else { return }
        self.burst = nil
        guard !burst.resigned, !burst.keepsFocus() else { return }

        guard isActive() else {
            // The launch activation hasn't landed yet. Decide again once it does.
            if burst.launched {
                deferredLaunch = (burst.keepsFocus, now().addingTimeInterval(Self.launchActivationWindow))
            }
            return
        }
        guard let activation = burst.activation else { return }
        handBack(to: activation.previousApp ?? (burst.launched ? launchPreviousApp : nil))
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
        let activation = Activation(previousApp: lastDeactivatedApp, date: now())
        // A launch burst still settling takes the launch activation, whenever it lands.
        if var burst, burst.launched, !burst.resigned, burst.activation == nil {
            burst.activation = activation
            self.burst = burst
            return
        }
        // A launch burst that settled first settles again, as a burst of its own, so a link that
        // arrives with or after this activation still supersedes it.
        if let deferred = deferredLaunch {
            deferredLaunch = nil
            if activation.date <= deferred.deadline {
                var burst = Burst(
                    start: activation.date,
                    launched: true,
                    latest: 0,
                    keepsFocus: deferred.keepsFocus,
                    activation: activation)
                startSettling(&burst)
                self.burst = burst
                return
            }
        }
        self.activation = activation
    }

    /// The user went elsewhere, so neither an untaken activation nor a settling burst hands
    /// focus back, even if the user comes back before the burst settles.
    @objc private func didResignActive() {
        activation = nil
        if var burst {
            burst.activation = nil
            burst.resigned = true
            self.burst = burst
        }
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
