import AppKit
import SwiftUI

/// Owns the AppKit window that hosts `SettingsView`.
///
/// The window is built by hand (rather than through the SwiftUI `Settings`
/// scene) so its chrome can be configured for a seamless sidebar: a hidden
/// title, a transparent unified toolbar, and full-size content let the
/// sidebar material run to the very top of the window with the traffic
/// lights sitting on it.
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    /// The settings window, if it has been created. Cleared when it closes.
    fileprivate(set) var settingsWindow: NSWindow?

    /// Strong reference to the delegate; `NSWindow.delegate` is weak.
    fileprivate var windowDelegate: SettingsWindowDelegate?

    private init() {}

    /// Shows the settings window, creating it on first use and re-fronting
    /// the existing one on subsequent calls.
    func show() {
        if let window = settingsWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Annotate Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        windowDelegate = SettingsWindowDelegate()
        window.delegate = windowDelegate
    }
}

/// Clears the manager's references when the window closes so the next
/// `show()` builds a fresh window.
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_: Notification) {
        SettingsWindowManager.shared.settingsWindow = nil
        SettingsWindowManager.shared.windowDelegate = nil
    }
}
