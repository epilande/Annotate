import Cocoa

/// Gives focus back to the app the user was in after a link that leaves no overlay open.
///
/// Opening a link with plain `open` makes Launch Services activate Annotate just before the link
/// arrives, about 10 to 25 ms earlier in its own run-loop pass. Tool and show links open the
/// overlay and need that focus. Color, toolbar, and the other links don't, and would otherwise
/// leave the user's app in the background. `open -g` never activates Annotate, so there is
/// nothing to hand back.
@MainActor
final class LinkFocusHandoff: NSObject {
    /// How long before a link Annotate's activation still counts as Launch Services activating
    /// it for that link. Wide enough for a busy main thread, short enough that a user who
    /// switched to Annotate on purpose isn't sent away by a link that arrives later.
    static let activationWindow: TimeInterval = 0.5

    private let ownProcessIdentifier: pid_t
    private let now: @MainActor () -> Date
    private let isActive: @MainActor () -> Bool
    private let activate: @MainActor (NSRunningApplication) -> Void

    /// The app that most recently gave up focus to another app.
    private var lastDeactivatedApp: NSRunningApplication?
    /// When Annotate last became active, and the app that was active before it.
    private var activation: (previousApp: NSRunningApplication?, date: Date)?

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

    /// Call after a link's command runs. Pass `keepsFocus` when the command left an overlay
    /// that takes keyboard input. Otherwise, if Launch Services activated Annotate for this link,
    /// the previous app gets focus back. Returns that app.
    @discardableResult
    func linkDidRun(keepsFocus: Bool) -> NSRunningApplication? {
        // One activation hands back once, whatever the command did.
        let activation = self.activation
        self.activation = nil
        guard !keepsFocus, isActive(),
            let activation, now().timeIntervalSince(activation.date) <= Self.activationWindow,
            let app = activation.previousApp, !app.isTerminated
        else { return nil }
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
