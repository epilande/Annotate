import Carbon
import Cocoa
import Sparkle
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    static weak var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var colorPopover: NSPopover?
    var lineWidthPopover: NSPopover?
    var currentColor: NSColor = .systemRed
    var hotkeyMonitor: Any?
    var overlayWindows: [NSScreen: OverlayWindow] = [:]
    var settingsWindow: NSWindow?
    var alwaysOnMode: Bool = false
    var aboutWindow: NSWindow?
    var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        updateDockIconVisibility()

        if let colorData = UserDefaults.standard.data(forKey: "SelectedColor"),
            let unarchivedColor = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self, from: colorData)
        {
            currentColor = unarchivedColor
        }

        setupStatusBarItem()
        setupOverlayWindows()

        let persistedFadeMode =
            UserDefaults.standard.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
        overlayWindows.values.forEach { $0.overlayView.fadeMode = persistedFadeMode }
        
        // Restore always-on mode if it was enabled when app last quit
        let shouldStartInAlwaysOnMode = UserDefaults.standard.bool(forKey: UserDefaults.alwaysOnModeKey)
        if shouldStartInAlwaysOnMode {
            DispatchQueue.main.async {
                self.toggleAlwaysOnMode()
            }
        }

        let persistedLineWidth = UserDefaults.standard.object(forKey: UserDefaults.lineWidthKey) as? Double ?? 3.0
        overlayWindows.values.forEach { $0.overlayView.currentLineWidth = CGFloat(persistedLineWidth) }

        let enableBoard = UserDefaults.standard.bool(forKey: UserDefaults.enableBoardKey)
        overlayWindows.values.forEach {
            $0.boardView.isHidden = !enableBoard
            $0.overlayView.updateAdaptColors(boardEnabled: enableBoard)
        }

        setupBoardObservers()
        
        // Initialize Sparkle updater (uses Info.plist configuration)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Override the default About menu item
        setupApplicationMenu()
    }

    @MainActor
    func updateDockIconVisibility() {
        // Skip NSApplication operations during testing
        guard NSApplication.shared.delegate != nil else { return }

        if UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey) {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if statusItem.button != nil {
            updateStatusBarIcon(with: .gray)

            let menu = NSMenu()

            let colorItem = NSMenuItem(
                title: "Color",
                action: #selector(showColorPicker(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .colorPicker))
            colorItem.keyEquivalentModifierMask = []
            menu.addItem(colorItem)

            let lineWidthItem = NSMenuItem(
                title: "Line Width",
                action: #selector(showLineWidthPicker(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .lineWidthPicker))
            lineWidthItem.keyEquivalentModifierMask = []
            menu.addItem(lineWidthItem)

            menu.addItem(NSMenuItem.separator())

            let currentToolItem = NSMenuItem(
                title: "Current Tool: Pen",
                action: nil,
                keyEquivalent: ""
            )
            currentToolItem.isEnabled = false
            menu.addItem(currentToolItem)

            let arrowModeItem = NSMenuItem(
                title: "Arrow",
                action: #selector(enableArrowMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .arrow))
            arrowModeItem.keyEquivalentModifierMask = []
            menu.addItem(arrowModeItem)

            let lineModeItem = NSMenuItem(
                title: "Line",
                action: #selector(enableLineMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .line))
            lineModeItem.keyEquivalentModifierMask = []
            menu.addItem(lineModeItem)

            let penModeItem = NSMenuItem(
                title: "Pen",
                action: #selector(enablePenMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .pen))
            penModeItem.keyEquivalentModifierMask = []
            menu.addItem(penModeItem)

            let highlighterModeItem = NSMenuItem(
                title: "Highlighter",
                action: #selector(enableHighlighterMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .highlighter))
            highlighterModeItem.keyEquivalentModifierMask = []
            menu.addItem(highlighterModeItem)

            let rectangleModeItem = NSMenuItem(
                title: "Rectangle",
                action: #selector(enableRectangleMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .rectangle))
            rectangleModeItem.keyEquivalentModifierMask = []
            menu.addItem(rectangleModeItem)

            let circleModeItem = NSMenuItem(
                title: "Circle",
                action: #selector(enableCircleMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .circle))
            circleModeItem.keyEquivalentModifierMask = []
            menu.addItem(circleModeItem)

            let counterModeItem = NSMenuItem(
                title: "Counter",
                action: #selector(enableCounterMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .counter))
            counterModeItem.keyEquivalentModifierMask = []
            menu.addItem(counterModeItem)

            let textModeItem = NSMenuItem(
                title: "Text",
                action: #selector(enableTextMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .text))
            textModeItem.keyEquivalentModifierMask = []
            menu.addItem(textModeItem)
            
            let selectModeItem = NSMenuItem(
                title: "Select",
                action: #selector(enableSelectMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .select))
            selectModeItem.keyEquivalentModifierMask = []
            menu.addItem(selectModeItem)

            menu.addItem(NSMenuItem.separator())

            let isDarkMode =
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let boardType = isDarkMode ? "Blackboard" : "Whiteboard"
            let boardEnabled = UserDefaults.standard.bool(forKey: UserDefaults.enableBoardKey)
            let toggleBoardItem = NSMenuItem(
                title: boardEnabled ? "Hide \(boardType)" : "Show \(boardType)",
                action: #selector(toggleBoardVisibility(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .toggleBoard))
            toggleBoardItem.keyEquivalentModifierMask = []
            menu.addItem(toggleBoardItem)

            menu.addItem(NSMenuItem.separator())

            let persistedFadeMode =
                UserDefaults.standard.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
            let currentDrawingModeItem = NSMenuItem(
                title: persistedFadeMode ? "Drawing Mode: Fade" : "Drawing Mode: Persist",
                action: nil,
                keyEquivalent: ""
            )
            currentDrawingModeItem.isEnabled = false
            menu.addItem(currentDrawingModeItem)

            let toggleDrawingModeItem = NSMenuItem(
                title: persistedFadeMode ? "Persist" : "Fade",
                action: #selector(toggleFadeMode(_:)),
                keyEquivalent: " "
            )
            toggleDrawingModeItem.keyEquivalentModifierMask = []
            menu.addItem(toggleDrawingModeItem)

            menu.addItem(NSMenuItem.separator())
            
            let currentOverlayModeItem = NSMenuItem(
                title: alwaysOnMode ? "Overlay Mode: Always-On" : "Overlay Mode: Interactive",
                action: nil,
                keyEquivalent: ""
            )
            currentOverlayModeItem.isEnabled = false
            menu.addItem(currentOverlayModeItem)
            
            let toggleAlwaysOnModeItem = NSMenuItem(
                title: alwaysOnMode ? "Exit Always-On Mode" : "Always-On Mode",
                action: #selector(toggleAlwaysOnMode),
                keyEquivalent: ""
            )
            menu.addItem(toggleAlwaysOnModeItem)

            menu.addItem(NSMenuItem.separator())

            let clearAllItem = NSMenuItem(
                title: "Clear All",
                action: #selector(clearAllAnnotations),
                keyEquivalent: "\u{8}"
            )
            clearAllItem.keyEquivalentModifierMask = [.option]
            menu.addItem(clearAllItem)

            let undoItem = NSMenuItem(
                title: "Undo",
                action: #selector(undo),
                keyEquivalent: "z")
            menu.addItem(undoItem)

            let redoItem = NSMenuItem(
                title: "Redo",
                action: #selector(redo),
                keyEquivalent: "Z")
            menu.addItem(redoItem)

            menu.addItem(NSMenuItem.separator())

            let settingsItem = NSMenuItem(
                title: "Settings...",
                action: #selector(showSettings),
                keyEquivalent: ",")
            settingsItem.keyEquivalentModifierMask = [.command]
            menu.addItem(settingsItem)

            let checkForUpdatesItem = NSMenuItem(
                title: "Check for Updates...",
                action: #selector(checkForUpdates),
                keyEquivalent: "")
            menu.addItem(checkForUpdatesItem)

            menu.addItem(NSMenuItem.separator())

            menu.addItem(
                NSMenuItem(
                    title: "Close",
                    action: #selector(closeOverlay),
                    keyEquivalent: "w"))

            menu.addItem(
                NSMenuItem(
                    title: "Quit", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q"))

            statusItem.menu = menu
        }
    }

    @objc func screenParametersChanged() {
        // Remove windows for screens that no longer exist
        overlayWindows = overlayWindows.filter { screen, _ in
            NSScreen.screens.contains(screen)
        }

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
                
                let savedLineWidth = UserDefaults.standard.object(forKey: UserDefaults.lineWidthKey) as? Double ?? 3.0
                overlayWindow.overlayView.currentLineWidth = CGFloat(savedLineWidth)
                
                overlayWindows[screen] = overlayWindow
            }
        }
    }

    func getCurrentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
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
        if colorPopover == nil {
            colorPopover = NSPopover()
            colorPopover?.contentViewController = ColorPickerViewController()
            colorPopover?.behavior = .transient
            colorPopover?.delegate = self
        }

        if let button = statusItem.button {
            colorPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            if let popoverWindow = colorPopover?.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
            }
        }
    }

    @objc func showLineWidthPicker(_ sender: Any?) {
        if lineWidthPopover == nil {
            lineWidthPopover = NSPopover()
            lineWidthPopover?.contentViewController = LineWidthPickerViewController()
            lineWidthPopover?.behavior = .transient
            lineWidthPopover?.delegate = self
        }

        if let button = statusItem.button {
            lineWidthPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            if let popoverWindow = lineWidthPopover?.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
            }
        }
    }

    func popoverWillClose(_ notification: Notification) {
        if let popover = notification.object as? NSPopover {
            if popover == colorPopover {
                colorPopover = nil
            } else if popover == lineWidthPopover {
                lineWidthPopover = nil
            }
        }
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
            updateStatusBarIcon(with: .gray)
            overlayWindow.orderOut(nil)
            NSApp.hide(nil)
        } else {
            configureWindowForNormalMode(overlayWindow)
            
            // Clear drawings if the setting is enabled
            if UserDefaults.standard.bool(forKey: UserDefaults.clearDrawingsOnStartKey) {
                overlayWindow.overlayView.clearAll()
            }

            updateStatusBarIcon(with: currentColor)
            let screenFrame = currentScreen.frame
            overlayWindow.setFrame(screenFrame, display: true)
            overlayWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func toggleAlwaysOnMode() {
        alwaysOnMode.toggle()
        
        overlayWindows.values.forEach { overlayWindow in
            if alwaysOnMode {
                configureWindowForAlwaysOnMode(overlayWindow)
            } else {
                configureWindowForNormalMode(overlayWindow)
                overlayWindow.orderOut(nil)
            }
        }
        
        let iconColor = alwaysOnMode 
            ? currentColor.withAlphaComponent(0.7)  // Semi-transparent to indicate read-only
            : .gray
        updateStatusBarIcon(with: iconColor)
        
        UserDefaults.standard.set(alwaysOnMode, forKey: UserDefaults.alwaysOnModeKey)
        updateAlwaysOnMenuItems()
    }

    @objc func closeOverlay() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            updateStatusBarIcon(with: .gray)
            overlayWindow.orderOut(nil)
        }
    }
    
    @objc func closeOverlayAndEnableAlwaysOn() {
        // Transition directly to always-on mode to preserve annotations (avoids hiding overlay first)
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
            updateStatusBarIcon(with: currentColor)
            let screenFrame = currentScreen.frame
            overlayWindow.setFrame(screenFrame, display: true)
            overlayWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func switchTool(to tool: ToolType) {
        // Tool switching requires interactive mode
        if alwaysOnMode {
            toggleAlwaysOnMode()
        }
        
        overlayWindows.values.forEach { window in
            // Clear selection when switching away from select mode
            if window.overlayView.currentTool == .select && tool != .select {
                window.overlayView.selectedObjects.removeAll()
                window.overlayView.needsDisplay = true
            }
            window.overlayView.currentTool = tool
            window.showToolFeedback(tool)
        }
        showOverlay()
    }

    @objc func enableArrowMode(_ sender: NSMenuItem) {
        switchTool(to: .arrow)
        updateCurrentToolMenuItem(to: "Arrow")
    }

    @objc func enableLineMode(_ sender: NSMenuItem) {
        switchTool(to: .line)
        updateCurrentToolMenuItem(to: "Line")
    }

    @objc func enablePenMode(_ sender: NSMenuItem) {
        switchTool(to: .pen)
        updateCurrentToolMenuItem(to: "Pen")
    }

    @objc func enableHighlighterMode(_ sender: NSMenuItem) {
        switchTool(to: .highlighter)
        updateCurrentToolMenuItem(to: "Highlighter")
    }

    @objc func enableRectangleMode(_ sender: NSMenuItem) {
        switchTool(to: .rectangle)
        updateCurrentToolMenuItem(to: "Rectangle")
    }

    @objc func enableCircleMode(_ sender: NSMenuItem) {
        switchTool(to: .circle)
        updateCurrentToolMenuItem(to: "Circle")
    }

    @objc func enableCounterMode(_ sender: NSMenuItem) {
        switchTool(to: .counter)
        updateCurrentToolMenuItem(to: "Counter")
    }

    @objc func enableTextMode(_ sender: NSMenuItem) {
        switchTool(to: .text)
        updateCurrentToolMenuItem(to: "Text")
    }
    
    @objc func enableSelectMode(_ sender: NSMenuItem) {
        switchTool(to: .select)
        updateCurrentToolMenuItem(to: "Select")
    }

    @objc func toggleBoardVisibility(_ sender: Any?) {
        BoardManager.shared.toggle()
        updateBoardMenuItems()
    }

    func updateBoardMenuItems() {
        guard let menu = statusItem.menu else { return }

        let boardType = BoardManager.shared.displayName
        let boardEnabled = BoardManager.shared.isEnabled

        let toggleBoardItem = menu.items.first { $0.action == #selector(toggleBoardVisibility(_:)) }

        if let item = toggleBoardItem {
            item.title = boardEnabled ? "Hide \(boardType)" : "Show \(boardType)"
        }
    }
    
    func updateAlwaysOnMenuItems() {
        guard let menu = statusItem.menu else { return }
        
        let currentOverlayModeItem = menu.items.first { 
            $0.title.hasPrefix("Overlay Mode:")
        }
        if let item = currentOverlayModeItem {
            item.title = alwaysOnMode ? "Overlay Mode: Always-On" : "Overlay Mode: Interactive"
        }
        
        let toggleAlwaysOnModeItem = menu.items.first { $0.action == #selector(toggleAlwaysOnMode) }
        if let item = toggleAlwaysOnModeItem {
            item.title = alwaysOnMode ? "Exit Always-On Mode" : "Always-On Mode"
        }
    }
    
    func updateCurrentToolMenuItem(to toolName: String) {
        guard let menu = statusItem.menu else { return }
        
        let currentToolItem = menu.items.first { $0.title.hasPrefix("Current Tool:") }
        currentToolItem?.title = "Current Tool: \(toolName)"
    }
    
    private func configureWindowForNormalMode(_ overlayWindow: OverlayWindow) {
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.level = .normal
        overlayWindow.overlayView.isReadOnlyMode = false
        
        let persistedFadeMode = UserDefaults.standard.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
        overlayWindow.overlayView.fadeMode = persistedFadeMode
    }
    
    private func configureWindowForAlwaysOnMode(_ overlayWindow: OverlayWindow) {
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = .floating
        overlayWindow.overlayView.fadeMode = false  // Persistent annotations for always-on display
        overlayWindow.overlayView.isReadOnlyMode = true
        
        let screenFrame = overlayWindow.screen?.frame ?? NSScreen.main?.frame ?? .zero
        overlayWindow.setFrame(screenFrame, display: true)
        overlayWindow.orderFront(nil)
        overlayWindow.stopFadeLoop()  // Prevent fade conflicts with persistent mode
    }
    
    private func updateFadeModeMenuItems(isCurrentlyFadeMode: Bool) {
        guard let menu = statusItem.menu else { return }
        
        let currentDrawingModeItem = menu.items.first { 
            $0.title.hasPrefix("Drawing Mode:") 
        }
        let toggleDrawingModeItem = menu.items.first { 
            $0.action == #selector(toggleFadeMode(_:)) 
        }

        currentDrawingModeItem?.title = isCurrentlyFadeMode
            ? "Drawing Mode: Persist"
            : "Drawing Mode: Fade"

        toggleDrawingModeItem?.title = isCurrentlyFadeMode
            ? "Fade"
            : "Persist"
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
    }

    @objc func boardStateChanged() {
        updateBoardMenuItems()
    }

    @objc func boardAppearanceChanged() {
        updateBoardMenuItems()
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
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            overlayWindow.overlayView.clearAll()
        }
    }

    @objc func toggleFadeMode(_ sender: Any?) {
        let isCurrentlyFadeMode = overlayWindows.values.first?.overlayView.fadeMode ?? true

        for window in overlayWindows.values {
            window.overlayView.fadeMode.toggle()
        }

        UserDefaults.standard.set(!isCurrentlyFadeMode, forKey: UserDefaults.fadeModeKey)

        updateFadeModeMenuItems(isCurrentlyFadeMode: isCurrentlyFadeMode)
    }

    @objc func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Settings"
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.delegate = self

        let hostingController = NSHostingController(rootView: SettingsView())
        newWindow.contentView = hostingController.view

        self.settingsWindow = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }

    /// Updates the status bar icon by layering a colored circle with a pencil.
    /// - Parameter color: The color to apply to the circle.
    func updateStatusBarIcon(with color: NSColor) {
        let pencilSymbolName = "pencil"
        let iconSize = NSSize(width: 18, height: 18)

        let compositeImage = NSImage(size: iconSize)
        compositeImage.lockFocus()

        // Draw the circle outline
        let circleFrame = NSRect(origin: NSPoint(x: 1, y: 1), size: NSSize(width: 16, height: 16))  // Slight inset for stroke
        let circlePath = NSBezierPath(ovalIn: circleFrame)
        color.setStroke()
        circlePath.lineWidth = 1.5
        circlePath.stroke()

        // Load the pencil image
        guard
            let pencilImage = NSImage(
                systemSymbolName: pencilSymbolName, accessibilityDescription: "Pencil")
        else {
            print("Failed to load system symbol: \(pencilSymbolName)")
            return
        }

        let coloredPencil = pencilImage.copy() as! NSImage
        coloredPencil.lockFocus()
        NSColor.white.set()
        let pencilBounds = NSRect(origin: .zero, size: pencilImage.size)
        pencilBounds.fill(using: .sourceIn)  // Tint the image white
        coloredPencil.unlockFocus()

        // Center and draw the white pencil icon
        let pencilSize = NSSize(width: 11, height: 11)
        let pencilOrigin = NSPoint(
            x: (iconSize.width - pencilSize.width) / 2, y: (iconSize.height - pencilSize.height) / 2
        )
        coloredPencil.draw(
            in: NSRect(origin: pencilOrigin, size: pencilSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0)

        compositeImage.unlockFocus()
        compositeImage.isTemplate = false

        // Set the composite image to the status bar button
        statusItem.button?.image = compositeImage
    }
    
    func setupApplicationMenu() {
        // Find the application menu (first submenu in the main menu bar)
        guard let mainMenu = NSApp.mainMenu,
              let appMenuItem = mainMenu.items.first,
              let appMenu = appMenuItem.submenu else {
            return
        }
        
        // Find and replace the About menu item
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
        
        // Center after the window is shown to ensure proper sizing
        DispatchQueue.main.async {
            self.aboutWindow?.center()
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func updateMenuKeyEquivalents() {
        guard let menu = statusItem.menu else { return }
        for item in menu.items {
            switch item.title {
            case "Pen":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .pen)
            case "Arrow":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .arrow)
            case "Line":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .line)
            case "Highlighter":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .highlighter)
            case "Rectangle":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .rectangle)
            case "Circle":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .circle)
            case "Text":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .text)
            case "Select":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .select)
            case "Color":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .colorPicker)
            case "Line Width":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .lineWidthPicker)
            case let title where title.hasPrefix("Show") || title.hasPrefix("Hide"):
                if item.action == #selector(toggleBoardVisibility(_:)) {
                    item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .toggleBoard)
                }
            default:
                break
            }
        }
    }
}
