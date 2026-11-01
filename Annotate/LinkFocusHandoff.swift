import Cocoa

/// Gives focus back to the app the user was in after links that leave no interactive overlay
/// open.
///
/// Opening a link with plain `open` makes Launch Services activate Annotate just before the link
/// arrives, about 10 to 25 ms earlier in its own run-loop pass. Tool and show links open the
/// overlay and need that focus. Color, toolbar, and the other links don't, and would otherwise
/// leave the user's app in the background. `open -g` never activates a running Annotate, so
/// there is nothing to hand back.
///
/// A link that launches Annotate is different: launch activates the app (`updateDockIconVisibility`
/// does, even under `open -g`), and that activation can land before or after the queued links
/// run. Call `noteLaunch(frontmostApp:)` before launch finishes so the previous app is known
/// either way.
@MainActor
final class LinkFocusHandoff: NSObject {
    /// How long before a link Annotate's activation still counts as Launch Services activating
    /// it for that link. Wide enough for a busy main thread, short enough that a user who
    /// switched to Annotate on purpose isn't sent away by a link that arrives later.
    static let activationWindow: TimeInterval = 0.5
    /// How long after links that arrived with the launch a launch activation still hands focus
    /// back, when it lands after the links ran.
    static let launchActivationWindow: TimeInterval = 2

    private let ownProcessIdentifier: pid_t
    private let now: @MainActor () -> Date
    private let isActive: @MainActor () -> Bool
    private let activate: @MainActor (NSRunningApplication) -> Void

    /// The app that most recently gave up focus to another app.
    private var lastDeactivatedApp: NSRunningApplication?
    /// When Annotate last became active, and the app that was active before it.
    private var activation: (previousApp: NSRunningApplication?, date: Date)?
    /// The app that was frontmost while Annotate was launching.
    private var launchPreviousApp: NSRunningApplication?
    /// Links from the launch ran before the launch activation, which should hand focus back when
    /// it lands.
    private var pendingHandBack: (app: NSRunningApplication, deadline: Date)?

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        appCenter: NotificationCenter = .default,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        now: @escaping @MainActor () -> Date = Date.init,
        isActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        activate: @escaping @MainActor (NSRunningApplication) -> Void = LinkFocusHandoff.giveFocus
    ) {
        self.ownProcessIdentifier = ownProcessIdentifier
        self.now = now
        self.isActive = isActive
        self.activate = activate
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

    /// Call before launch finishes, while the app the user was in is still frontmost.
    func noteLaunch(frontmostApp: NSRunningApplication?) {
        guard let app = frontmostApp, app.processIdentifier != ownProcessIdentifier else { return }
        launchPreviousApp = app
    }

    /// Call once after a batch of links has run, whether their commands ran or were ignored.
    /// Pass `keepsFocus` when the batch left an interactive overlay open. Otherwise, if opening
    /// the links activated Annotate, the previous app gets focus back. Pass `launched` for links
    /// that arrived with the launch. Returns the app given focus now.
    @discardableResult
    func linksDidRun(keepsFocus: Bool, launched: Bool = false) -> NSRunningApplication? {
        // One activation hands back once, whatever the links did.
        let activation = self.activation
        self.activation = nil
        pendingHandBack = nil
        guard !keepsFocus else { return nil }

        guard isActive() else {
            // The launch activation hasn't landed yet.
            if launched, let app = launchPreviousApp ?? lastDeactivatedApp {
                pendingHandBack = (app, now().addingTimeInterval(Self.launchActivationWindow))
            }
            return nil
        }
        guard let activation else { return nil }
        // Any activation since launch is the launch's own. Otherwise it must be recent enough to
        // be Launch Services activating the app for these links.
        let previousApp: NSRunningApplication?
        if launched {
            previousApp = activation.previousApp ?? launchPreviousApp
        } else if now().timeIntervalSince(activation.date) <= Self.activationWindow {
            previousApp = activation.previousApp
        } else {
            previousApp = nil
        }
        return handBack(to: previousApp)
    }

    private func handBack(to app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, !app.isTerminated else { return nil }
        activate(app)
        return app
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
            if now() <= pending.deadline, handBack(to: pending.app) != nil { return }
        }
        activation = (lastDeactivatedApp, now())
    }

    @objc private func didResignActive() {
        activation = nil
    }

    private static func giveFocus(to app: NSRunningApplication) {
        // Cooperative activation (macOS 14): the active app yields, then the target activates.
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }
}
