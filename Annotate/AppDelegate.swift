import Carbon
import Cocoa
import Sparkle
import SwiftUI

extension NSUserInterfaceItemIdentifier {
    /// The status menu's Show Overlay / Hide Overlay item.
    static let overlay = Self("statusMenu.overlay")
    /// The status menu's Tool item, whose submenu lists the tools.
    static let currentTool = Self("statusMenu.tool")
    /// One tool in the Tool submenu.
    static func tool(_ tool: ToolType) -> Self { Self("statusMenu.tool.\(tool.rawValue)") }
    static let board = Self("statusMenu.board")
    static let cursorHighlight = Self("statusMenu.cursorHighlight")
    static let fadeMode = Self("statusMenu.fadeMode")
    static let alwaysOnMode = Self("statusMenu.alwaysOnMode")
    static let toolbar = Self("statusMenu.toolbar")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    static weak var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var currentColor: NSColor = .systemRed
    var hotkeyMonitor: Any?
    var overlayWindows: [NSScreen: OverlayWindow] = [:]
    var alwaysOnMode: Bool = false
    var aboutWindow: NSWindow?
    var updaterController: SPUStandardUpdaterController!
    let settings: SettingsStore

    // Cursor Highlight
    var cursorHighlightWindows: [NSScreen: CursorHighlightWindow] = [:]
    var globalMouseMoveMonitor: Any?
    var globalMouseClickMonitor: Any?
    var globalMouseUpMonitor: Any?
    var localMouseMoveMonitor: Any?
    var localMouseClickMonitor: Any?
    var localMouseUpMonitor: Any?
    var localFlagsChangedMonitor: Any?

    /// Links that arrive before launch finishes, run once it does.
    var pendingCommandURLs: [URL] = []
    private(set) var hasFinishedLaunching = false
    /// Created as launch starts, before launch or any link can activate the app.
    var linkFocusHandoff: LinkFocusHandoff?

    /// Makes Capture Screen's and Capture Area's images. Tests swap in one with a stub source,
    /// a temporary folder, and a private pasteboard.
    lazy var captureService = CaptureService(
        source: ScreenSampler.shared,
        sinks: Self.captureSinks(chosenFolder: captureFolders))
    /// The folder chosen for captures in Settings.
    lazy var captureFolders = CaptureFolderStore(settings: settings)
    /// Sends the notification a finished capture gets. Tests swap in a stub.
    lazy var captureNotifier: CaptureNotifying = SystemCaptureNotifier.forThisProcess { [weak self] file in
        self?.showCaptureInFinder(file)
    }
    /// The latest capture. The next one waits for it, and tests await it.
    var captureTask: Task<Void, Never>?
    /// Capture problems waiting for their alert, oldest first. See `queueCaptureProblemAlert`.
    var pendingCaptureProblems: [CaptureProblem] = []
    /// Whether a run-loop pass is scheduled, or running, to show `pendingCaptureProblems`.
    /// Tests wait for it to clear.
    var isPresentingCaptureProblems = false
    /// How long the Screen Recording HUD stays up before the overlay closes for Settings.
    var screenRecordingNoticeDelay: TimeInterval = 1.5
    /// Reports a capture problem when no overlay HUD can show it. Tests replace it.
    var showCaptureProblemAlert: (_ message: String, _ detail: String) -> Void = { message, detail in
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        // With Hide Tool Feedback on, an overlay can be open, and it sits above modal panels.
        // `runModal` resets the level as it starts; the main queue drains inside the modal
        // session, so the raise lands after that.
        DispatchQueue.main.async {
            alert.window.level = NSWindow.Level(rawValue: OverlayWindow.elevatedLevel.rawValue + 1)
        }
        alert.runModal()
    }
    /// Whether a macOS privacy prompt is on screen. Tests replace it.
    var isPrivacyPromptOnScreen: () -> Bool = { SystemPrivacyPrompt.isOnScreen }
    /// How often Always-On overlays waiting on a privacy prompt check whether it has closed.
    var privacyPromptPollInterval: TimeInterval = 0.5
    /// Always-On overlays ordered out so Settings and the Screen Recording prompt show above
    /// them. They come back once both are gone.
    var overlaysAwaitingPermission: [OverlayWindow] = []
    /// Whether a Settings window opened for Screen Recording is still open.
    var isSettingsOpenForPermission = false
    var isPollingForPrivacyPrompt = false
    /// Overlays closed by the app rather than the user, which keep their drawings the next
    /// time they open even with Clear Drawings on Start.
    var overlaysKeepingDrawings: Set<ObjectIdentifier> = []
    /// The circle color `updateStatusBarIcon(with:)` was last given, which the pencil comes
    /// back in when a capture's confirmation icon ends.
    private(set) var statusIconColor: NSColor = .gray
    /// The status item's confirmation icon after a capture. Tests shorten it or run its expiry
    /// by hand.
    lazy var captureConfirmation = StatusIconConfirmation { [weak self] in self?.renderStatusIcon() }
    /// What the confirmation icon showing now confirms.
    var shownCaptureConfirmation: CaptureConfirmation?
    /// Speaks a capture's confirmation to VoiceOver. Tests replace it.
    var announceForAccessibility: (String) -> Void = { message in
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }
    /// Opens, copies, and shows saved captures, and opens the capture folder. Tests replace
    /// its system calls so Finder and the default apps stay put.
    var captureFileActions = CaptureFileActions()
    /// The saved captures the status menu's Recent Captures lists.
    lazy var recentCaptures = RecentCaptureStore(settings: settings) { [unowned self] in
        (self.captureFolders, self.captureDefaultFolder ?? FileSink.defaultFolder)
    }
    /// The Recent Captures submenu, made with the status menu.
    var recentCapturesMenu: RecentCapturesMenu?
    /// The latest Copy from Recent Captures. Tests await it.
    var recentCaptureCopyTask: Task<Void, Never>?
    /// Overlays Capture Area opened from Always-On. They keep Always-On's Persist fade until
    /// the picker closes, so drawings Always-On still shows past their fade stay for the pick
    /// and the capture.
    var overlaysHoldingAlwaysOnFade: Set<ObjectIdentifier> = []
    /// Opens Settings to a pane. `requestingScreenRecording` asks for access once the pane
    /// shows, and `onClose` runs when the Settings window closes. Tests replace it so no
    /// Settings window opens.
    var openSettingsPane:
        (SettingsPane, _ requestingScreenRecording: Bool, _ onClose: @escaping @MainActor () -> Void) -> Void = {
            SettingsWindowManager.shared.show(pane: $0, requestingScreenRecording: $1, onClose: $2)
        }

    override init() {
        self.settings = .standard
        super.init()
    }

    init(userDefaults: UserDefaults) {
        self.settings = SettingsStore(defaults: userDefaults)
        super.init()
    }

    /// Runs before launch activates the app and before any link that launched it arrives.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let handoff = LinkFocusHandoff()
        // By now macOS has made this process frontmost, so `frontmostApplication` names Annotate.
        handoff.noteLaunch(previousApp: LinkFocusHandoff.appOwningTopmostWindow())
        linkFocusHandoff = handoff
        // A click on a capture's notification can be what launched the app, and is dropped
        // unless the notification center's delegate is set by the time launch finishes.
        _ = captureNotifier
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        SoundPlayer.preload()
        updateDockIconVisibility()

        currentColor = settings[.selectedColor]

        // Sync annotation color to cursor highlight manager
        CursorHighlightManager.shared.annotationColor = currentColor

        setupStatusBarItem()
        setupOverlayWindows()

        let persistedFadeMode = settings[.fadeMode]
        overlayWindows.values.forEach { $0.overlayView.fadeMode = persistedFadeMode }
        applyFadeDelay()

        let shouldStartInAlwaysOnMode = settings[.alwaysOnMode]
        if shouldStartInAlwaysOnMode {
            DispatchQueue.main.async {
                self.toggleAlwaysOnMode()
            }
        }

        let persistedLineWidth = settings[.lineWidth]
        overlayWindows.values.forEach { $0.overlayView.currentLineWidth = persistedLineWidth }

        let persistedTool = settings[.lastUsedTool]
        overlayWindows.values.forEach { $0.overlayView.currentTool = persistedTool }
        updateCurrentToolMenuItem(to: persistedTool)

        let enableBoard = settings[.enableBoard]
        overlayWindows.values.forEach {
            $0.boardView.isHidden = !enableBoard
            $0.overlayView.updateAdaptColors(boardEnabled: enableBoard)
        }

        setupBoardObservers()

        #if DEBUG
        let startUpdater = false
        #else
        let startUpdater = true
        #endif

        updaterController = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        setupApplicationMenu()

        setupCursorHighlightWindows()
        setupGlobalMouseMonitors()
        setupCursorHighlightObservers()

        if linkFocusHandoff == nil {
            linkFocusHandoff = LinkFocusHandoff()
        }
        hasFinishedLaunching = true
        runPendingCommandURLs()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let monitors: [Any?] = [
            globalMouseMoveMonitor,
            globalMouseClickMonitor,
            globalMouseUpMonitor,
            localMouseMoveMonitor,
            localMouseClickMonitor,
            localMouseUpMonitor,
            localFlagsChangedMonitor
        ]
        monitors.compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }

        globalMouseMoveMonitor = nil
        globalMouseClickMonitor = nil
        globalMouseUpMonitor = nil
        localMouseMoveMonitor = nil
        localMouseClickMonitor = nil
        localMouseUpMonitor = nil
        localFlagsChangedMonitor = nil
        captureConfirmation.end()
    }

    @MainActor
    func updateDockIconVisibility() {
        guard NSApplication.shared.delegate != nil else { return }

        if settings[.hideDockIcon] {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        visibleSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The settings window, if it is currently on screen.
    private var visibleSettingsWindow: NSWindow? {
        guard let window = SettingsWindowManager.shared.settingsWindow, window.isVisible else {
            return nil
        }
        return window
    }

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if statusItem?.button != nil {
            updateStatusBarIcon(with: .gray)

            let menu = NSMenu()
            menu.delegate = self

            menu.addItem(makeStatusMenuItem("Show Overlay", #selector(toggleOverlay), .overlay))

            menu.addItem(NSMenuItem.separator())

            menu.addItem(NSMenuItem(title: "Color…", action: #selector(showColorPicker(_:)), keyEquivalent: ""))
            menu.addItem(
                NSMenuItem(title: "Line Width…", action: #selector(showLineWidthPicker(_:)), keyEquivalent: ""))
            menu.addItem(makeToolMenuItem())

            menu.addItem(NSMenuItem.separator())

            menu.addItem(makeStatusMenuItem("Show Whiteboard", #selector(toggleBoardVisibility(_:)), .board))
            menu.addItem(makeStatusMenuItem("Cursor Highlight", #selector(toggleClickEffects(_:)), .cursorHighlight))
            menu.addItem(makeStatusMenuItem("Fade Mode", #selector(toggleFadeMode(_:)), .fadeMode))
            menu.addItem(makeStatusMenuItem("Always-On Mode", #selector(toggleAlwaysOnMode), .alwaysOnMode))
            menu.addItem(makeStatusMenuItem("Show Toolbar", #selector(toggleToolbar), .toolbar))

            menu.addItem(NSMenuItem.separator())

            menu.addItem(NSMenuItem(title: "Undo", action: #selector(undo), keyEquivalent: "z"))
            menu.addItem(NSMenuItem(title: "Redo", action: #selector(redo), keyEquivalent: "Z"))
            menu.addItem(NSMenuItem(title: "Clear All", action: #selector(clearAllAnnotations), keyEquivalent: ""))

            menu.addItem(NSMenuItem.separator())

            menu.addItem(NSMenuItem(title: "Capture Screen", action: #selector(captureScreen), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: ""))
            menu.addItem(makeRecentCapturesItem())

            menu.addItem(NSMenuItem.separator())

            menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))

            menu.addItem(NSMenuItem.separator())

            menu.addItem(
                NSMenuItem(title: "Quit Annotate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

            statusItem?.menu = menu
            refreshMenuKeyEquivalents()
            refreshStatusMenu()
        }
    }

    /// The tools in the order the status menu's Tool submenu lists them, with the action each
    /// row sends.
    static let statusMenuTools: [(tool: ToolType, action: Selector)] = [
        (.arrow, #selector(enableArrowMode(_:))),
        (.line, #selector(enableLineMode(_:))),
        (.pen, #selector(enablePenMode(_:))),
        (.highlighter, #selector(enableHighlighterMode(_:))),
        (.rectangle, #selector(enableRectangleMode(_:))),
        (.oval, #selector(enableOvalMode(_:))),
        (.solidRectangle, #selector(enableSolidRectangleMode(_:))),
        (.solidOval, #selector(enableSolidOvalMode(_:))),
        (.redact, #selector(enableRedactMode(_:))),
        (.counter, #selector(enableCounterMode(_:))),
        (.text, #selector(enableTextMode(_:))),
        (.select, #selector(enableSelectMode(_:))),
        (.eraser, #selector(enableEraserMode(_:))),
    ]

    /// The Tool item, titled with the current tool, whose submenu lists every tool with the
    /// current one checked. The submenu has no delegate: the status menu's delegate drops every
    /// overlay back above menus when its menu closes (#122), and a submenu closes while the
    /// status menu is still open.
    private func makeToolMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Tool")
        for (tool, action) in Self.statusMenuTools {
            let item = makeStatusMenuItem(tool.displayName, action, .tool(tool))
            item.target = self
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Tool", action: nil, keyEquivalent: "")
        item.identifier = .currentTool
        item.submenu = submenu
        return item
    }

    private func makeStatusMenuItem(
        _ title: String, _ action: Selector, _ identifier: NSUserInterfaceItemIdentifier
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.identifier = identifier
        return item
    }

    @objc func screenParametersChanged() {
        // Remove windows for screens that no longer exist. Dropping them from the dictionary is
        // not enough: the toolbar is a child window of its own, and only `close()` tears it down.
        let removedWindows = overlayWindows.filter { screen, _ in
            !NSScreen.screens.contains(screen)
        }.values
        overlayWindows = overlayWindows.filter { screen, _ in
            NSScreen.screens.contains(screen)
        }
        removedWindows.forEach { $0.close() }

        // Add new overlays for newly added screens
        for screen in NSScreen.screens {
            if overlayWindows[screen] == nil {
                let overlayWindow = OverlayWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                overlayWindow.currentColor = currentColor

                overlayWindow.overlayView.currentLineWidth = settings[.lineWidth]
                overlayWindow.overlayView.currentTool = settings[.lastUsedTool]

                overlayWindows[screen] = overlayWindow
            }
        }

        updateCursorHighlightWindowsForScreenChange()
        CursorHighlightManager.shared.overlayVisibilityChanged()
    }

    /// Tests set this because XCTest can't move the pointer.
    var pointerLocationOverride: NSPoint?

    func getCurrentScreen() -> NSScreen? {
        let mouseLocation = pointerLocationOverride ?? NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    func setupOverlayWindows() {
        for screen in NSScreen.screens {
            // Convert screen coordinates to global coordinates
            let globalFrame = screen.frame

            let overlayWindow = OverlayWindow(
                contentRect: globalFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            overlayWindow.setFrameOrigin(globalFrame.origin)
            overlayWindow.currentColor = currentColor
            overlayWindows[screen] = overlayWindow
        }
    }

    @objc func showColorPicker(_ sender: Any?) {
        showQuickPicker(.color)
    }

    @objc func showLineWidthPicker(_ sender: Any?) {
        showQuickPicker(.width)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showColorPicker(_:)), #selector(showLineWidthPicker(_:)):
            return pickerOverlayWindow != nil
        case #selector(toggleFadeMode(_:)), #selector(clearAllAnnotations):
            // Space / Option-Delete become menu equivalents and must not fire
            // while Settings (or any other window) is key.
            return isOverlayKeyWindow
        default:
            return true
        }
    }

    // The overlay sits above pop-up menus, so the status menu would open under it (#122).
    // Every display's overlay yields, since the menu bar can be on any of them. Only the status
    // menu itself counts: a submenu closes while the status menu is still open.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        overlayWindows.values.forEach { $0.setYieldsToMenus(true) }
        recentCaptures.refresh()
        refreshStatusMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        overlayWindows.values.forEach { $0.setYieldsToMenus(false) }
    }

    /// Opens the status menu when a press on an overlay lands on the status item (#122), and
    /// returns whether it did. The overlay covers the menu bar, so the item never gets the press.
    /// On the menu bar that hosts the item, this clicks the button, which looks and behaves like a
    /// real click. Another display's menu bar shows a copy of the item, and clicking the button
    /// would open the menu on the host display, so the menu opens under the copy instead.
    func openStatusMenu(forPressAt point: NSPoint) -> Bool {
        guard let button = statusItem?.button,
              let menu = statusItem?.menu,
              let buttonWindow = button.window,
              let hostScreen = buttonWindow.screen,
              let hit = StatusItemHitTest.hit(
                  at: point,
                  buttonFrame: buttonWindow.frame,
                  hostScreenFrame: hostScreen.frame,
                  screenFrames: NSScreen.screens.map(\.frame),
                  menuBarFrames: StatusItemHitTest.visibleMenuBarFrames
              )
        else { return false }

        if hit.isOnHostMenuBar {
            button.performClick(nil)
        } else {
            menu.popUp(positioning: nil, at: StatusItemHitTest.popUpMenuLocation(for: hit), in: nil)
        }
        return true
    }

    /// Status-menu key equivalents are app-wide. Overlay-owned actions only
    /// run when an overlay itself is the key window.
    ///
    /// Tests can set `overlayKeyWindowOverride` because XCTest will not make
    /// the overlay key while its ToolbarPanel child reports `canBecomeKey = false`.
    var overlayKeyWindowOverride: Bool?

    private var isOverlayKeyWindow: Bool {
        overlayKeyWindowOverride
            ?? overlayWindows.values.contains { $0.isVisible && $0.isKeyWindow }
    }

    /// The overlays in the order the status menu reads them: the one on the display under the
    /// pointer, then the key overlay, then the one on the main screen, then the rest in display
    /// order. Opening the status menu or choosing one of its items leaves the pointer on the
    /// menu's display, which is the overlay the menu opened from. `NSScreen.main` can't come
    /// first: on macOS 27 it names the display with the menu bar even while the key window is an
    /// overlay on another display, so a menu opened from that other display's overlay greyed out
    /// the pickers (#122).
    private var overlaysByMenuPreference: [OverlayWindow] {
        Self.overlaysByMenuPreference(
            in: overlayWindows, pointerScreen: getCurrentScreen(), mainScreen: NSScreen.main, screens: NSScreen.screens)
    }

    /// `overlaysByMenuPreference` for any kind of screen key, so tests can stand in for displays
    /// a single-display Mac doesn't have.
    static func overlaysByMenuPreference<Screen: Hashable>(
        in overlays: [Screen: OverlayWindow], pointerScreen: Screen?, mainScreen: Screen?, screens: [Screen]
    ) -> [OverlayWindow] {
        let keyOverlay = overlays.values.first { $0.isKeyWindow }
        let candidates = [pointerScreen.flatMap { overlays[$0] }, keyOverlay, mainScreen.flatMap { overlays[$0] }]
            + screens.map { overlays[$0] }
        return candidates.compactMap { $0 }
    }

    /// The visible overlay the quick pickers open on, the first in `overlaysByMenuPreference`.
    private var pickerOverlayWindow: OverlayWindow? {
        overlaysByMenuPreference.first { $0.isVisible }
    }

    private func showQuickPicker(_ mode: QuickPickerView.Mode) {
        guard let overlayWindow = pickerOverlayWindow else { return }
        // The picker reads Escape and the number keys from its own overlay, and another
        // display's overlay may still be key.
        overlayWindow.makeKeyAndOrderFront(nil)
        let anchor = NSPoint(
            x: overlayWindow.overlayView.bounds.midX,
            y: overlayWindow.overlayView.bounds.midY)
        overlayWindow.beginQuickPicker(mode, anchor: anchor)
    }

    @objc func toggleOverlay() {
        // Always-on mode is incompatible with interactive overlay
        if alwaysOnMode {
            toggleAlwaysOnMode()
        }

        guard let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen]
        else {
            return
        }

        if overlayWindow.isVisible {
            hideOverlays([overlayWindow])
        } else {
            activateOverlay(overlayWindow, on: currentScreen)
        }
    }

    /// Opens the interactive overlay on the display under the pointer, as the overlay shortcut
    /// does. Leaves Always-On first, since its overlays are already visible but read-only.
    /// Does nothing if an interactive overlay is already open.
    func showInteractiveOverlay() {
        if alwaysOnMode || !overlayWindows.values.contains(where: \.isVisible) {
            toggleOverlay()
        }
    }

    /// Whether an overlay that takes input is open. Always-On overlays are read-only.
    var isInteractiveOverlayOpen: Bool {
        !alwaysOnMode && overlayWindows.values.contains(where: \.isVisible)
    }

    /// Closes every open overlay, wherever the pointer is, and leaves Always-On.
    func hideAllOverlays() {
        if alwaysOnMode {
            toggleAlwaysOnMode()
        } else {
            hideOverlays(overlayWindows.values.filter(\.isVisible))
        }
    }

    private func activateOverlay(_ overlayWindow: OverlayWindow, on screen: NSScreen) {
        configureWindowForNormalMode(overlayWindow)

        if settings[.clearDrawingsOnStart] && !consumeKeptDrawings(of: overlayWindow) {
            overlayWindow.overlayView.clearAll()
        }

        updateStatusBarIcon(with: currentColor)
        SoundPlayer.shared.playOverlayOn()
        overlayWindow.setFrame(screen.frame, display: true)
        overlayWindow.makeKeyAndOrderFront(nil)
        CursorHighlightManager.shared.annotationColor = currentColor
        CursorHighlightManager.shared.overlayVisibilityChanged()
        applyConfiguredDefaultTool()
    }

    private func hideOverlays(_ windows: [OverlayWindow]) {
        guard !windows.isEmpty else { return }
        for overlayWindow in windows {
            if let activeField = overlayWindow.overlayView.activeTextField {
                overlayWindow.overlayView.finalizeTextAnnotation(activeField)
            }
            overlayWindow.orderOut(nil)
        }
        updateStatusBarIcon(with: .gray)
        SoundPlayer.shared.playOverlayOff()
        CursorHighlightManager.shared.overlayVisibilityChanged()
    }

    @objc func toggleAlwaysOnMode() {
        alwaysOnMode.toggle()

        overlayWindows.values.forEach { overlayWindow in
            if let activeField = overlayWindow.overlayView.activeTextField {
                overlayWindow.overlayView.finalizeTextAnnotation(activeField)
            }
            if alwaysOnMode {
                consumeKeptDrawings(of: overlayWindow)
                configureWindowForAlwaysOnMode(overlayWindow)
            } else {
                configureWindowForNormalMode(overlayWindow)
                overlayWindow.orderOut(nil)
            }
        }
        CursorHighlightManager.shared.overlayVisibilityChanged()

        let iconColor = alwaysOnMode
            ? currentColor.withAlphaComponent(0.7)
            : .gray
        updateStatusBarIcon(with: iconColor)

        settings[.alwaysOnMode] = alwaysOnMode
        updateAlwaysOnMenuItems()
    }

    @objc func closeOverlay() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            if let activeField = overlayWindow.overlayView.activeTextField {
                overlayWindow.overlayView.finalizeTextAnnotation(activeField)
            }
            updateStatusBarIcon(with: .gray)
            SoundPlayer.shared.playOverlayOff()
            overlayWindow.orderOut(nil)
            CursorHighlightManager.shared.overlayVisibilityChanged()
        }
    }

    @objc func closeOverlayAndEnableAlwaysOn() {
        if !alwaysOnMode {
            toggleAlwaysOnMode()
        }
    }

    @objc func showOverlay() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            !overlayWindow.isVisible
        {
            configureWindowForNormalMode(overlayWindow)
            consumeKeptDrawings(of: overlayWindow)
            updateStatusBarIcon(with: currentColor)
            SoundPlayer.shared.playOverlayOn()
            let screenFrame = currentScreen.frame
            overlayWindow.setFrame(screenFrame, display: true)
            overlayWindow.makeKeyAndOrderFront(nil)
            CursorHighlightManager.shared.annotationColor = currentColor
            CursorHighlightManager.shared.overlayVisibilityChanged()
        }
    }

    func switchTool(to tool: ToolType, persist: Bool = true) {
        if alwaysOnMode {
            toggleAlwaysOnMode()
        }

        if persist {
            settings[.lastUsedTool] = tool
        }

        overlayWindows.values.forEach { window in
            if window.overlayView.currentTool == .select && tool != .select {
                window.overlayView.selectedObjects.removeAll()
            }
            window.overlayView.currentTool = tool
            window.showToolFeedback(tool)
            window.invalidateCursorRects(for: window.overlayView)
            window.overlayView.updateCursor()
        }
        updateCurrentToolMenuItem(to: tool)
        showOverlay()
    }

    /// Makes `color` the annotation color: stored, on every overlay, and on the cursor highlight.
    /// The status item only takes it while an overlay is up; gray means the overlay is hidden.
    func setColor(_ color: NSColor) {
        settings[.selectedColor] = color
        currentColor = color
        overlayWindows.values.forEach { $0.currentColor = color }
        if alwaysOnMode {
            updateStatusBarIcon(with: color.withAlphaComponent(0.7))
        } else if overlayWindows.values.contains(where: \.isVisible) {
            updateStatusBarIcon(with: color)
        }
        CursorHighlightManager.shared.annotationColor = color
    }

    /// Applies the configured default tool when the overlay activates. Does nothing when the
    /// setting is "Last used", leaving whatever tool is already current in place, or when
    /// every window is already on the configured tool (avoids showing tool feedback on
    /// every activation). Applying the default is not an explicit tool selection, so it does
    /// not overwrite the persisted last-used tool.
    func applyConfiguredDefaultTool() {
        guard case .tool(let tool) = settings[.defaultTool] else { return }
        guard overlayWindows.values.contains(where: { $0.overlayView.currentTool != tool }) else { return }
        switchTool(to: tool, persist: false)
    }

    @objc func enableArrowMode(_ sender: NSMenuItem) {
        switchTool(to: .arrow)
    }

    @objc func enableLineMode(_ sender: NSMenuItem) {
        switchTool(to: .line)
    }

    @objc func enablePenMode(_ sender: NSMenuItem) {
        switchTool(to: .pen)
    }

    @objc func enableHighlighterMode(_ sender: NSMenuItem) {
        switchTool(to: .highlighter)
    }

    @objc func enableRectangleMode(_ sender: NSMenuItem) {
        switchTool(to: .rectangle)
    }

    @objc func enableOvalMode(_ sender: NSMenuItem) {
        switchTool(to: .oval)
    }

    @objc func enableSolidRectangleMode(_ sender: NSMenuItem) {
        switchTool(to: .solidRectangle)
    }

    @objc func enableSolidOvalMode(_ sender: NSMenuItem) {
        switchTool(to: .solidOval)
    }

    @objc func enableRedactMode(_ sender: NSMenuItem) {
        switchTool(to: .redact)
    }

    @objc func enableCounterMode(_ sender: NSMenuItem) {
        switchTool(to: .counter)
    }

    @objc func enableTextMode(_ sender: NSMenuItem) {
        switchTool(to: .text)
    }

    @objc func enableSelectMode(_ sender: NSMenuItem) {
        switchTool(to: .select)
    }

    @objc func enableEraserMode(_ sender: NSMenuItem) {
        switchTool(to: .eraser)
    }

    @objc func toggleBoardVisibility(_ sender: Any?) {
        setBoardEnabled(!BoardManager.shared.isEnabled)
    }

    func setBoardEnabled(_ enabled: Bool) {
        BoardManager.shared.isEnabled = enabled
        updateBoardMenuItems()
        overlayWindows.values.forEach {
            $0.overlayView.updateAdaptColors(boardEnabled: enabled)
        }
    }

    func updateBoardMenuItems() {
        let boardType = BoardManager.shared.displayName
        statusMenuItem(.board)?.title = BoardManager.shared.isEnabled ? "Hide \(boardType)" : "Show \(boardType)"
    }

    @objc func toggleClickEffects(_ sender: Any?) {
        let newState = !CursorHighlightManager.shared.clickEffectsEnabled
        CursorHighlightManager.shared.clickEffectsEnabled = newState
        CursorHighlightManager.shared.cursorHighlightEnabled = newState
        updateClickEffectsMenuItems()

        showToggleFeedback(
            newState ? "Cursor Highlight On" : "Cursor Highlight Off",
            icon: newState ? "👆" : "🚫")
    }

    /// Shows the on-screen HUD on every open overlay. With none open there is nowhere to draw it.
    func showToggleFeedback(_ text: String, icon: String) {
        for window in overlayWindows.values where window.isVisible {
            window.showToggleFeedback(text, icon: icon)
        }
    }

    func updateClickEffectsMenuItems() {
        statusMenuItem(.cursorHighlight)?.state = CursorHighlightManager.shared.clickEffectsEnabled ? .on : .off
    }

    func updateAlwaysOnMenuItems() {
        statusMenuItem(.alwaysOnMode)?.state = alwaysOnMode ? .on : .off
        updateOverlayMenuItem()
    }

    /// Titles the overlay item for what `toggleOverlay` would do: hide the interactive overlay
    /// on the display under the pointer, or show it, leaving Always-On first.
    func updateOverlayMenuItem() {
        let isShowing = !alwaysOnMode && getCurrentScreen().flatMap { overlayWindows[$0] }?.isVisible == true
        statusMenuItem(.overlay)?.title = isShowing ? "Hide Overlay" : "Show Overlay"
    }

    /// Titles the Tool item with `tool` and checks it in the Tool submenu. OverlayView also
    /// changes the tool without `switchTool`, and calls this itself.
    func updateCurrentToolMenuItem(to tool: ToolType) {
        guard let toolItem = statusMenuItem(.currentTool) else { return }
        toolItem.title = "Tool: \(tool.displayName)"
        toolItem.submenu?.items.forEach { $0.state = $0.identifier == .tool(tool) ? .on : .off }
    }

    /// Brings every state the status menu shows up to date. Runs as the menu opens, since the
    /// overlay, the cursor highlight, and the tool also change from shortcuts, Settings, and links.
    func refreshStatusMenu() {
        updateOverlayMenuItem()
        // Overlays can disagree: a display connected later starts on the last-used tool, while
        // the others may be on a default tool that isn't stored.
        updateCurrentToolMenuItem(
            to: overlaysByMenuPreference.first?.overlayView.currentTool ?? settings[.lastUsedTool])
        updateBoardMenuItems()
        updateClickEffectsMenuItems()
        updateFadeModeMenuItems()
        updateAlwaysOnMenuItems()
        updateToolbarMenuItem()
    }

    /// The status menu's top-level item with `identifier`.
    func statusMenuItem(_ identifier: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        statusItem?.menu?.items.first { $0.identifier == identifier }
    }
    
    private func configureWindowForNormalMode(_ overlayWindow: OverlayWindow) {
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.overlayView.isReadOnlyMode = false
        overlayWindow.updateToolbarVisibility()

        overlayWindow.overlayView.fadeMode =
            overlaysHoldingAlwaysOnFade.contains(ObjectIdentifier(overlayWindow)) ? false : settings[.fadeMode]
        overlayWindow.overlayView.fadeDelay = settings[.fadeDelay]
        overlayWindow.overlayView.startFadeLoopIfNeeded()
    }

    private func configureWindowForAlwaysOnMode(_ overlayWindow: OverlayWindow) {
        overlayWindow.prepareForAlwaysOnMode()
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.overlayView.fadeMode = false
        overlayWindow.overlayView.isReadOnlyMode = true
        overlayWindow.updateToolbarVisibility()

        let screenFrame = overlayWindow.screen?.frame ?? NSScreen.main?.frame ?? .zero
        overlayWindow.setFrame(screenFrame, display: true)
        overlayWindow.orderFront(nil)
    }
    
    /// Pushes the stored Fade Delay to every overlay. Annotations already on screen follow the
    /// new delay from the next fade tick.
    func applyFadeDelay() {
        let delay = settings[.fadeDelay]
        overlayWindows.values.forEach { $0.overlayView.fadeDelay = delay }
    }

    /// Checks Fade Mode from the stored setting. Always-On turns its overlays' fade off without
    /// changing the setting, which they go back to when they leave it.
    private func updateFadeModeMenuItems() {
        statusMenuItem(.fadeMode)?.state = settings[.fadeMode] ? .on : .off
    }

    func setupBoardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boardStateChanged),
            name: .boardStateChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boardAppearanceChanged),
            name: .boardAppearanceChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: .shortcutsDidChange,
            object: nil
        )
    }

    @objc func boardStateChanged() {
        updateBoardMenuItems()
    }

    @objc func boardAppearanceChanged() {
        updateBoardMenuItems()
    }

    @objc func shortcutsDidChange() {
        refreshMenuKeyEquivalents()
    }

    /// Gives the status menu's items, and the Tool submenu's, the key equivalents bound in
    /// Settings. Recent Captures has none (see `RecentCapturesMenu`).
    func refreshMenuKeyEquivalents() {
        guard let menu = statusItem?.menu else { return }
        let toolItems = statusMenuItem(.currentTool)?.submenu?.items ?? []

        for item in menu.items + toolItems {
            let action: ShortcutKey
            switch item.action {
            case #selector(showColorPicker(_:)):
                action = .colorPicker
            case #selector(showLineWidthPicker(_:)):
                action = .lineWidthPicker
            case #selector(enableArrowMode(_:)):
                action = .arrow
            case #selector(enableLineMode(_:)):
                action = .line
            case #selector(enablePenMode(_:)):
                action = .pen
            case #selector(enableHighlighterMode(_:)):
                action = .highlighter
            case #selector(enableRectangleMode(_:)):
                action = .rectangle
            case #selector(enableOvalMode(_:)):
                action = .oval
            case #selector(enableSolidRectangleMode(_:)):
                action = .solidRectangle
            case #selector(enableSolidOvalMode(_:)):
                action = .solidOval
            case #selector(enableRedactMode(_:)):
                action = .redact
            case #selector(enableCounterMode(_:)):
                action = .counter
            case #selector(enableTextMode(_:)):
                action = .text
            case #selector(enableSelectMode(_:)):
                action = .select
            case #selector(enableEraserMode(_:)):
                action = .eraser
            case #selector(toggleBoardVisibility(_:)):
                action = .toggleBoard
            case #selector(toggleClickEffects(_:)):
                action = .toggleClickEffects
            case #selector(toggleFadeMode(_:)): action = .toggleFade
            case #selector(toggleToolbar): action = .toggleToolbar
            case #selector(clearAllAnnotations): action = .clearAll
            case #selector(captureScreen): action = .captureScreen
            case #selector(captureArea): action = .captureArea
            default:
                continue
            }
            let binding = ShortcutManager.shared.binding(for: action)
            item.keyEquivalent = binding.menuKeyEquivalent
            item.keyEquivalentModifierMask = binding.modifiers
        }
    }

    @objc func undo() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            overlayWindow.overlayView.undo()
        }
    }

    @objc func redo() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            overlayWindow.overlayView.redo()
        }
    }

    @objc func clearAllAnnotations() {
        guard isOverlayKeyWindow,
            let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen]
        else { return }
        overlayWindow.performClearAll()
    }

    /// Clears every open overlay, key or not, which in Always-On is every display's. One Undo
    /// on any display brings back everything this cleared. Returns whether there was anything
    /// to clear.
    @discardableResult
    func clearVisibleOverlays() -> Bool {
        let cleared = OverlayWindow.performClearAll(on: overlayWindows.values.filter(\.isVisible))
        if cleared {
            SoundPlayer.shared.playClearAll()
        }
        return cleared
    }

    @objc func toggleFadeMode(_ sender: Any?) {
        if sender is NSMenuItem && !isOverlayKeyWindow { return }
        let isCurrentlyFadeMode = overlayWindows.values.first?.overlayView.fadeMode ?? true
        setFadeMode(!isCurrentlyFadeMode)
    }

    var fadeModeEnabled: Bool {
        settings[.fadeMode]
    }

    func setFadeMode(_ enabled: Bool) {
        settings[.fadeMode] = enabled

        // Each overlay starts or stops its own fade loop when its mode changes. Always-On never
        // fades; its overlays pick the stored mode up when they leave it.
        if !alwaysOnMode {
            overlayWindows.values.forEach { $0.overlayView.fadeMode = enabled }
        }

        updateFadeModeMenuItems()

        showToggleFeedback(enabled ? "Fade Mode" : "Persist Mode", icon: enabled ? "⏳" : "📌")
    }

    var toolbarVisible: Bool {
        settings[.toolbarVisible]
    }

    @objc func toggleToolbar() {
        setToolbarVisible(!toolbarVisible)
    }

    func setToolbarVisible(_ visible: Bool) {
        settings[.toolbarVisible] = visible
        overlayWindows.values.forEach { $0.updateToolbarVisibility() }
        updateToolbarMenuItem()
    }

    private func updateToolbarMenuItem() {
        statusMenuItem(.toolbar)?.title = toolbarVisible ? "Hide Toolbar" : "Show Toolbar"
    }

    /// Re-reads the toolbar's keycap visibility and layout into every overlay's bar.
    func applyToolbarAppearance() {
        overlayWindows.values.forEach { $0.refreshToolbarAppearance() }
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowManager.shared.show()
    }

    /// Makes `color` the status item's circle color: the annotation color while an overlay is
    /// up, gray while it is hidden. A capture's confirmation icon keeps showing, in this color,
    /// until it ends, and the pencil then comes back in the latest color.
    func updateStatusBarIcon(with color: NSColor) {
        statusIconColor = color
        renderStatusIcon()
    }

    /// Draws the status item from the current state: the pencil, or a capture's confirmation
    /// icon while it is up.
    func renderStatusIcon() {
        guard let button = statusItem?.button else { return }
        let confirmation = captureConfirmation.isShowing ? shownCaptureConfirmation : nil
        // Without the symbol, the icon already showing beats an empty status item.
        guard let image = Self.statusIcon(color: statusIconColor, showing: confirmation) else { return }
        button.image = image
    }

    /// The status item's icon: the pencil in a `color` ring, or `confirmation`'s glyph in a
    /// filled `color` ring (see `CaptureConfirmation.statusIcon(ringColor:)`).
    static func statusIcon(color: NSColor, showing confirmation: CaptureConfirmation?) -> NSImage? {
        guard let confirmation else {
            return statusIcon(color: color, symbolName: "pencil", description: "Annotate")
        }
        return confirmation.statusIcon(ringColor: color)
    }

    /// A colored circle with a white symbol in it.
    static func statusIcon(color: NSColor, symbolName: String, description: String) -> NSImage? {
        guard
            let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
            let tinted = symbol.copy() as? NSImage
        else {
            return nil
        }
        let iconSize = NSSize(width: 18, height: 18)
        let compositeImage = NSImage(size: iconSize)
        compositeImage.lockFocus()

        // Slight inset for the stroke.
        let circlePath = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
        color.setStroke()
        circlePath.lineWidth = 1.5
        circlePath.stroke()

        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceIn)
        tinted.unlockFocus()

        let symbolSize = NSSize(width: 11, height: 11)
        let symbolOrigin = NSPoint(
            x: (iconSize.width - symbolSize.width) / 2, y: (iconSize.height - symbolSize.height) / 2)
        tinted.draw(
            in: NSRect(origin: symbolOrigin, size: symbolSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0)

        compositeImage.unlockFocus()
        compositeImage.isTemplate = false
        compositeImage.accessibilityDescription = description
        return compositeImage
    }

    func setupApplicationMenu() {
        guard let mainMenu = NSApp.mainMenu,
              let appMenuItem = mainMenu.items.first,
              let appMenu = appMenuItem.submenu else {
            return
        }

        for item in appMenu.items {
            if item.title.hasPrefix("About") {
                item.target = self
                item.action = #selector(showAbout)
                break
            }
        }
    }
    
    @objc func showAbout() {
        if aboutWindow == nil {
            let aboutView = AboutView(updaterController: updaterController)
            let hostingController = NSHostingController(rootView: aboutView)
            
            aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            aboutWindow?.contentViewController = hostingController
            aboutWindow?.title = "About Annotate"
            aboutWindow?.isReleasedWhenClosed = false
            aboutWindow?.delegate = self
        }
        
        aboutWindow?.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async {
            self.aboutWindow?.center()
        }

        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - Cursor Highlighting

    private func createCursorHighlightWindow(for screen: NSScreen) -> CursorHighlightWindow {
        let window = CursorHighlightWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(screen.frame.origin)
        return window
    }

    func setupCursorHighlightWindows() {
        for screen in NSScreen.screens {
            let window = createCursorHighlightWindow(for: screen)
            cursorHighlightWindows[screen] = window
            window.updateVisibility()
        }
    }

    func setupGlobalMouseMonitors() {
        // Global monitors - receive events when app is NOT frontmost
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.handleGlobalMouseMove(event)
        }

        globalMouseClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleGlobalMouseDown(event)
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.handleGlobalMouseUp(event)
        }

        // Local monitors - receive events when app IS frontmost (e.g., Settings window open)
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.handleGlobalMouseMove(event)
            return event
        }

        localMouseClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleGlobalMouseDown(event)
            return event
        }

        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.handleGlobalMouseUp(event)
            return event
        }

        // Modifier keys from hotkeys can trigger cursor resets
        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged]
        ) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func handleFlagsChanged(_ event: NSEvent) {
        CursorHighlightManager.shared.updateCursorVisibility()
    }

    func setupCursorHighlightObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cursorHighlightStateChanged),
            name: .cursorHighlightStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cursorHighlightNeedsUpdate),
            name: .cursorHighlightNeedsUpdate,
            object: nil
        )
    }

    @objc func cursorHighlightNeedsUpdate() {
        triggerCursorHighlightUpdate()
    }

    @objc func cursorHighlightStateChanged() {
        updateAllCursorHighlightWindows()
        CursorHighlightManager.shared.updateCursorVisibility()
        // Every overlay sets the one system cursor, whichever display it is on, so the last
        // one wins. An overlay with a cursor override, as Capture Area's picker sets, goes
        // last: otherwise another display's I-beam or hidden cursor would replace the crosshair.
        let windows = Array(overlayWindows.values)
        let overriding = windows.filter { $0.overlayView.cursorOverride != nil }
        for window in windows.filter({ $0.overlayView.cursorOverride == nil }) + overriding {
            window.overlayView.updateCursor()
            window.overlayView.window?.invalidateCursorRects(for: window.overlayView)
        }
    }

    /// Called from OverlayWindow to trigger cursor highlight updates for local mouse events
    func triggerCursorHighlightUpdate() {
        cursorHighlightWindows.values.forEach { $0.highlightView.updateHoldRingPosition() }

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.startAnimationLoop()
        }
    }

    func handleGlobalMouseMove(_ event: NSEvent) {
        let manager = CursorHighlightManager.shared
        manager.mouseEventReceived()
        manager.cursorPosition = NSEvent.mouseLocation
        manager.updateCursorVisibility()

        let shouldUpdateSpotlight = manager.shouldShowCursorHighlight
        let shouldUpdateHoldRing = manager.isActive && manager.isMouseDown

        guard shouldUpdateSpotlight || shouldUpdateHoldRing else { return }

        cursorHighlightWindows.values.forEach { window in
            if shouldUpdateSpotlight { window.highlightView.updateSpotlightPosition() }
            if shouldUpdateHoldRing { window.highlightView.updateHoldRingPosition() }
        }

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.startAnimationLoop()
        }
    }

    func handleGlobalMouseDown(_ event: NSEvent) {
        let manager = CursorHighlightManager.shared
        manager.mouseEventReceived()
        guard manager.isActive else { return }

        manager.isMouseDown = true
        manager.mouseDownTime = CACurrentMediaTime()
        manager.cursorPosition = NSEvent.mouseLocation

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.highlightView.updateHoldRingPosition()
            window.startAnimationLoop()
        }
    }

    func handleGlobalMouseUp(_ event: NSEvent) {
        let manager = CursorHighlightManager.shared
        manager.mouseEventReceived()

        guard manager.isActive else {
            manager.isMouseDown = false
            return
        }

        manager.startReleaseAnimation()
        manager.isMouseDown = false

        cursorHighlightWindows.values.forEach { $0.highlightView.updateHoldRingPosition() }

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.startAnimationLoop()
        }
    }

    func updateAllCursorHighlightWindows() {
        cursorHighlightWindows.values.forEach { $0.updateVisibility() }
    }

    func updateCursorHighlightWindowsForScreenChange() {
        // Remove windows for disconnected screens
        cursorHighlightWindows = cursorHighlightWindows.filter { screen, window in
            let exists = NSScreen.screens.contains(screen)
            if !exists {
                window.stopAnimationLoop()
                window.orderOut(nil)
            }
            return exists
        }

        // Add windows for newly connected screens
        for screen in NSScreen.screens where cursorHighlightWindows[screen] == nil {
            let window = createCursorHighlightWindow(for: screen)
            cursorHighlightWindows[screen] = window
            window.updateVisibility()
        }
    }
}
