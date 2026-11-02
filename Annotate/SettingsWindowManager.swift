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

    /// The pane the open window shows. Each new window starts fresh, on General.
    private(set) var navigation = SettingsNavigation()

    private init() {}

    /// Shows the settings window, creating it on first use and re-fronting
    /// the existing one on subsequent calls. With a `pane`, switches to it.
    /// `requestingScreenRecording` has the Capture pane ask for Screen Recording access.
    func show(pane: SettingsPane? = nil, requestingScreenRecording: Bool = false) {
        if settingsWindow == nil {
            navigation = SettingsNavigation()
        }
        if let pane {
            navigation.selection = pane
        }
        if requestingScreenRecording {
            navigation.requestsScreenRecording = true
        }
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Annotate Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: SettingsView(navigation: navigation))
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
