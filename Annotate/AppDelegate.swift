import Carbon
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var colorPopover: NSPopover!
    var currentColor: NSColor = .systemRed
    var hotkeyMonitor: Any?
    var overlayWindows: [NSScreen: OverlayWindow] = [:]
    var settingsWindow: NSWindow?

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

        setupScreenNotifications()
    }

    func updateDockIconVisibility() {
        if UserDefaults.standard.bool(forKey: UserDefaults.hideDockIconKey) {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
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

            let textModeItem = NSMenuItem(
                title: "Text",
                action: #selector(enableTextMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .text))
            textModeItem.keyEquivalentModifierMask = []
            menu.addItem(textModeItem)

            menu.addItem(NSMenuItem.separator())

            let persistedFadeMode =
                UserDefaults.standard.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
            let currentDrawingModeItem = NSMenuItem(
                title: persistedFadeMode ? "Current Mode: Fade" : "Current Mode: Persist",
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
                title: "Settings",
                action: #selector(showSettings),
                keyEquivalent: ",")
            settingsItem.keyEquivalentModifierMask = [.command]
            menu.addItem(settingsItem)

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

    func setupScreenNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
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
            colorPopover.contentViewController = ColorPickerViewController()
            colorPopover.behavior = .transient
        }

        if let button = statusItem.button {
            colorPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            if let popoverWindow = colorPopover.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
            }
        }
    }

    @objc func toggleOverlay() {
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
            // Clear drawings if the setting is enabled
            if UserDefaults.standard.bool(forKey: UserDefaults.clearDrawingsOnStartKey) {
                overlayWindow.overlayView.clearAll()
            }

            updateStatusBarIcon(with: currentColor)
            let screenFrame = currentScreen.frame
            // Update window frame and position
            overlayWindow.setFrame(screenFrame, display: true)
            overlayWindow.makeKeyAndOrderFront(nil)
            // Bring app forward
            NSApp.activate(ignoringOtherApps: true)
        }
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

    @objc func showOverlay() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            !overlayWindow.isVisible
        {
            updateStatusBarIcon(with: currentColor)
            let screenFrame = currentScreen.frame
            // Update window frame and position
            overlayWindow.setFrame(screenFrame, display: true)
            overlayWindow.makeKeyAndOrderFront(nil)
            // Bring app forward
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func switchTool(to tool: ToolType) {
        overlayWindows.values.forEach { window in
            window.overlayView.currentTool = tool
        }
        showOverlay()
    }

    @objc func enableArrowMode(_ sender: NSMenuItem) {
        switchTool(to: .arrow)
        if let menu = statusItem.menu {
            let currentToolItem = menu.item(at: 2)
            currentToolItem?.title = "Current Tool: Arrow"
        }
    }

    @objc func enablePenMode(_ sender: NSMenuItem) {
        switchTool(to: .pen)
        if let menu = statusItem.menu {
            let currentToolItem = menu.item(at: 2)
            currentToolItem?.title = "Current Tool: Pen"
        }
    }

    @objc func enableHighlighterMode(_ sender: NSMenuItem) {
        switchTool(to: .highlighter)
        if let menu = statusItem.menu {
            let currentToolItem = menu.item(at: 2)
            currentToolItem?.title = "Current Tool: Highlighter"
        }
    }

    @objc func enableRectangleMode(_ sender: NSMenuItem) {
        switchTool(to: .rectangle)
        if let menu = statusItem.menu {
            let currentToolItem = menu.item(at: 2)
            currentToolItem?.title = "Current Tool: Rectangle"
        }
    }

    @objc func enableCircleMode(_ sender: NSMenuItem) {
        switchTool(to: .circle)
        if let menu = statusItem.menu {
            let currentToolItem = menu.item(at: 2)
            currentToolItem?.title = "Current Tool: Circle"
        }
    }

    @objc func enableTextMode(_ sender: NSMenuItem) {
        switchTool(to: .text)
        if let menu = statusItem.menu {
            let currentToolItem = menu.item(at: 2)
            currentToolItem?.title = "Current Tool: Text"
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

    @objc func toggleFadeMode(_ sender: Any?) {
        let isCurrentlyFadeMode = overlayWindows.values.first?.overlayView.fadeMode ?? true

        for window in overlayWindows.values {
            window.overlayView.fadeMode.toggle()
        }

        UserDefaults.standard.set(!isCurrentlyFadeMode, forKey: UserDefaults.fadeModeKey)

        if let menu = statusItem.menu {
            let currentDrawingModeItem = menu.item(at: 10)
            let toggleDrawingModeItem = menu.item(at: 11)

            currentDrawingModeItem?.title =
                isCurrentlyFadeMode
                ? "Current Mode: Persist"
                : "Current Mode: Fade"

            toggleDrawingModeItem?.title =
                isCurrentlyFadeMode
                ? "Fade"
                : "Persist"
        }
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

    func updateMenuKeyEquivalents() {
        guard let menu = statusItem.menu else { return }
        for item in menu.items {
            switch item.title {
            case "Pen":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .pen)
            case "Arrow":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .arrow)
            case "Highlighter":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .highlighter)
            case "Rectangle":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .rectangle)
            case "Circle":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .circle)
            case "Text":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .text)
            case "Color":
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .colorPicker)
            default:
                break
            }
        }
    }

}
