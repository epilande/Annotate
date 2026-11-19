import Foundation
import XCTest

@testable import Annotate

@MainActor
final class AppDelegateTests: XCTestCase, Sendable {
    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!
    private var launchedDelegates: [AppDelegate] = []

    nonisolated override func setUp() {
        super.setUp()

        MainActor.assumeIsolated {
            TestWindows.recordOpenWindows()
            testDefaults = TestUserDefaults.create()
            BoardManager.shared = BoardManager(userDefaults: testDefaults)
            ShortcutManager.shared = ShortcutManager(userDefaults: testDefaults)

            appDelegate = launchAppDelegate()
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            SettingsWindowManager.shared.settingsWindow?.close()
            appDelegate.overlayKeyWindowOverride = nil
            launchedDelegates.forEach { $0.tearDownAfterLaunch() }
            launchedDelegates = []
            appDelegate = nil
            assertNoLeakedWindows()
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    /// Every delegate a test launches goes through here so tearDown can dismantle it. Launching
    /// opens an overlay and a cursor highlight window per screen, a status item and seven event
    /// monitors, none of which go away on their own.
    private func launchAppDelegate() -> AppDelegate {
        let delegate = AppDelegate(userDefaults: testDefaults)
        launchedDelegates.append(delegate)
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        return delegate
    }

    func testInitialization() {
        XCTAssertNotNil(appDelegate.statusItem)
        XCTAssertNotNil(appDelegate.statusItem.menu)
        XCTAssertEqual(appDelegate.currentColor, .systemRed)
        XCTAssertNotNil(AppDelegate.shared)
    }

    func testStatusBarMenu() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let board = BoardManager.shared.displayName

        XCTAssertEqual(
            menu.items.map { $0.isSeparatorItem ? "---" : $0.title },
            [
                "Show Overlay",
                "---",
                "Color…", "Line Width…", "Tool: Pen",
                "---",
                "Show \(board)", "Cursor Highlight", "Fade Mode", "Always-On Mode", "Hide Toolbar",
                "---",
                "Clear All", "Undo", "Redo",
                "---",
                "Capture Screen", "Capture Area", "Recent Captures",
                "---",
                "Settings...", "Check for Updates...",
                "---",
                "Quit Annotate",
            ])
        XCTAssertEqual(
            try toolSubmenu().items.map(\.title),
            [
                "Arrow", "Line", "Pen", "Highlighter", "Rectangle", "Circle", "Redact", "Counter", "Text",
                "Select", "Eraser",
            ])
    }

    // MARK: - Status menu helpers

    /// The status menu's top-level item with `identifier`, failing the test if it is missing.
    private func statusItem(
        _ identifier: NSUserInterfaceItemIdentifier,
        in delegate: AppDelegate? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSMenuItem {
        try XCTUnwrap(
            (delegate ?? appDelegate).statusMenuItem(identifier),
            "No status menu item \(identifier.rawValue)",
            file: file,
            line: line)
    }

    private func toolSubmenu(
        of delegate: AppDelegate? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSMenu {
        try XCTUnwrap(
            try statusItem(.currentTool, in: delegate, file: file, line: line).submenu,
            "The Tool item has no submenu",
            file: file,
            line: line)
    }

    private func toolItem(
        _ tool: ToolType,
        in delegate: AppDelegate? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSMenuItem {
        try XCTUnwrap(
            try toolSubmenu(of: delegate, file: file, line: line).items.first { $0.identifier == .tool(tool) },
            "No Tool submenu row for \(tool)",
            file: file,
            line: line)
    }

    /// Fails unless the Tool item names `tool` and only `tool`'s row is checked.
    private func assertToolMenuShows(
        _ tool: ToolType,
        in delegate: AppDelegate? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try statusItem(.currentTool, in: delegate, file: file, line: line).title,
            "Tool: \(tool.displayName)",
            file: file,
            line: line)
        let checked = try toolSubmenu(of: delegate, file: file, line: line).items
            .filter { $0.state == .on }.map(\.identifier)
        XCTAssertEqual(checked, [.tool(tool)], file: file, line: line)
    }

    /// Opens the status menu as a click does, with the recent captures scan kept off the real
    /// capture folders.
    private func openStatusMenu() throws {
        appDelegate.recentCaptures.scan = { _, _, _, _ in RecentCaptureScan(captures: []) }
        appDelegate.menuWillOpen(try XCTUnwrap(appDelegate.statusItem.menu))
    }

    /// Sends a menu item's action the way a click does. Top-level items have no target, and
    /// AppDelegate isn't NSApp's delegate under test.
    private func click(_ item: NSMenuItem, file: StaticString = #filePath, line: UInt = #line) throws {
        let action = try XCTUnwrap(item.action, "\(item.title) has no action", file: file, line: line)
        XCTAssertTrue(
            NSApp.sendAction(action, to: item.target ?? appDelegate, from: item),
            "\(item.title) did nothing",
            file: file,
            line: line)
    }

    // MARK: - Tool submenu

    func testToolSubmenuChecksTheCurrentTool() throws {
        try assertToolMenuShows(.pen)

        appDelegate.switchTool(to: .redact)
        try assertToolMenuShows(.redact)

        appDelegate.enableEraserMode(NSMenuItem())
        try assertToolMenuShows(.eraser)
    }

    /// The status menu reads the overlay on the pointer's display, then the key overlay, then the
    /// main screen's, then the rest in display order, never whichever the dictionary yields first.
    /// Integers stand in for displays.
    func testOverlaysByMenuPreferenceFavorThePointerThenTheKeyOverlay() throws {
        let overlays = (0..<5).map { _ in
            KeyReportingOverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: .borderless,
                backing: .buffered,
                defer: false)
        }
        defer { overlays.forEach { $0.close() } }
        let byScreen = Dictionary(uniqueKeysWithValues: overlays.enumerated().map { ($0.offset, $0.element) })
        func first(pointer: Int?, main: Int?, screens: [Int] = [4, 3, 2, 1, 0]) -> OverlayWindow? {
            AppDelegate.overlaysByMenuPreference(in: byScreen, pointerScreen: pointer, mainScreen: main, screens: screens)
                .first
        }

        XCTAssertTrue(first(pointer: 3, main: 0) === overlays[3], "The pointer's display comes first")
        overlays[1].reportsKey = true
        XCTAssertTrue(first(pointer: 3, main: 0) === overlays[3], "The pointer's display beats the key overlay")
        XCTAssertTrue(first(pointer: nil, main: 0) === overlays[1], "Off every display, the key overlay")
        XCTAssertTrue(first(pointer: 9, main: 0) === overlays[1], "A pointer display with no overlay falls through")
        overlays[1].reportsKey = false
        XCTAssertTrue(first(pointer: nil, main: 0) === overlays[0], "With none key, the main screen's")
        XCTAssertTrue(first(pointer: nil, main: nil) === overlays[4], "Then display order")
        XCTAssertNil(first(pointer: nil, main: nil, screens: []), "Nothing to fall back to")
    }

    /// The Tool item reads the overlays, not the stored tool, as the menu opens: OverlayView and
    /// the configured default tool change them without storing it.
    func testToolItemReadsThePointersOverlayAsTheMenuOpens() throws {
        let mainScreen = try XCTUnwrap(NSScreen.main)
        let overlay = try XCTUnwrap(appDelegate.overlayWindows[mainScreen])
        appDelegate.pointerLocationOverride = NSPoint(x: mainScreen.frame.midX, y: mainScreen.frame.midY)
        defer { appDelegate.pointerLocationOverride = nil }

        overlay.overlayView.currentTool = .circle
        try openStatusMenu()
        appDelegate.menuDidClose(try XCTUnwrap(appDelegate.statusItem.menu))

        try assertToolMenuShows(.circle)
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .pen)
    }

    func testPickingAToolFromTheSubmenuSwitchesToIt() throws {
        for tool in [ToolType.rectangle, .text, .arrow] {
            try click(try toolItem(tool))
            for window in appDelegate.overlayWindows.values {
                XCTAssertEqual(window.overlayView.currentTool, tool)
            }
            XCTAssertEqual(testDefaults.settings[.lastUsedTool], tool)
            try assertToolMenuShows(tool)
        }
    }

    func testToolSubmenuRowsShowTheirShortcuts() throws {
        for (tool, _) in AppDelegate.statusMenuTools {
            let item = try toolItem(tool)
            let binding = ShortcutManager.shared.binding(for: tool.shortcutKey)
            XCTAssertEqual(item.keyEquivalent, binding.menuKeyEquivalent, "\(tool)")
            XCTAssertEqual(item.keyEquivalentModifierMask, binding.modifiers, "\(tool)")
        }
    }

    /// The Tool submenu's rows follow a shortcut remapped in Settings, and the new key picks
    /// the tool from the status menu.
    func testRemappedToolShortcutShowsAndFiresFromTheToolSubmenu() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let binding = ShortcutBinding("y")
        XCTAssertTrue(ShortcutManager.shared.setShortcut(binding, for: .rectangle))
        defer { _ = ShortcutManager.shared.resetToDefault(tool: .rectangle) }
        appDelegate.refreshMenuKeyEquivalents()

        let rectangle = try toolItem(.rectangle)
        XCTAssertEqual(rectangle.keyEquivalent, "y")
        XCTAssertEqual(rectangle.keyEquivalentModifierMask, [])

        let event = try XCTUnwrap(TestEvents.createKeyEvent(
            type: .keyDown, keyCode: 16, characters: "y", charactersIgnoringModifiers: "y"))
        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .rectangle)
        }
        try assertToolMenuShows(.rectangle)
    }

    /// #122: the status menu's delegate drops every overlay back above menus when a menu
    /// closes, and the Tool submenu closes while the status menu is still open.
    func testClosingTheToolSubmenuLeavesOverlaysUnderTheStatusMenu() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let submenu = try toolSubmenu()
        XCTAssertNil(submenu.delegate, "The Tool submenu must not share the status menu's delegate")
        let overlays = Array(appDelegate.overlayWindows.values)
        XCTAssertFalse(overlays.isEmpty)

        try openStatusMenu()
        appDelegate.menuWillOpen(submenu)
        appDelegate.menuDidClose(submenu)
        for overlay in overlays {
            XCTAssertEqual(overlay.level, OverlayWindow.menuOpenLevel, "The status menu is still open over it")
        }

        appDelegate.menuDidClose(menu)
        for overlay in overlays {
            XCTAssertEqual(overlay.level, OverlayWindow.elevatedLevel)
        }
    }

    // MARK: - Checkmark rows

    func testFadeModeRowIsCheckedFromTheStoredSetting() throws {
        let fadeItem = try statusItem(.fadeMode)
        appDelegate.setFadeMode(true)
        XCTAssertEqual(fadeItem.state, .on)

        appDelegate.setFadeMode(false)
        XCTAssertEqual(fadeItem.state, .off)

        // The menu row toggles only while an overlay is key.
        appDelegate.overlayKeyWindowOverride = true
        try click(fadeItem)
        XCTAssertTrue(testDefaults.settings[.fadeMode])
        XCTAssertEqual(fadeItem.state, .on)

        // Always-On turns its overlays' fade off but keeps the setting the row shows.
        appDelegate.toggleAlwaysOnMode()
        defer { if appDelegate.alwaysOnMode { appDelegate.toggleAlwaysOnMode() } }
        XCTAssertFalse(try XCTUnwrap(appDelegate.overlayWindows.values.first).overlayView.fadeMode)
        try openStatusMenu()
        XCTAssertEqual(fadeItem.state, .on)
    }

    func testAlwaysOnModeRowIsCheckedWhileAlwaysOnIsOn() throws {
        let alwaysOnItem = try statusItem(.alwaysOnMode)
        XCTAssertEqual(alwaysOnItem.state, .off)

        try click(alwaysOnItem)
        defer { if appDelegate.alwaysOnMode { appDelegate.toggleAlwaysOnMode() } }
        XCTAssertTrue(appDelegate.alwaysOnMode)
        XCTAssertEqual(alwaysOnItem.state, .on)
        XCTAssertEqual(alwaysOnItem.title, "Always-On Mode")

        try click(alwaysOnItem)
        XCTAssertFalse(appDelegate.alwaysOnMode)
        XCTAssertEqual(alwaysOnItem.state, .off)
    }

    func testCursorHighlightRowIsCheckedWhileCursorHighlightIsOn() throws {
        let original = CursorHighlightManager.shared
        let manager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = manager
        defer { CursorHighlightManager.shared = original }
        manager.clickEffectsEnabled = false
        try openStatusMenu()
        let item = try statusItem(.cursorHighlight)
        XCTAssertEqual(item.state, .off)

        try click(item)
        XCTAssertTrue(manager.clickEffectsEnabled)
        XCTAssertEqual(item.state, .on)
        XCTAssertEqual(item.title, "Cursor Highlight")

        // Settings changes it without the menu; the row catches up as the menu opens.
        manager.clickEffectsEnabled = false
        try openStatusMenu()
        XCTAssertEqual(item.state, .off)
    }

    // MARK: - Show / Hide Overlay

    func testOverlayRowShowsAndHidesTheOverlayUnderThePointer() throws {
        let (screen, overlayWindow) = try XCTUnwrap(appDelegate.overlayWindows.first)
        appDelegate.pointerLocationOverride = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        defer {
            appDelegate.pointerLocationOverride = nil
            if appDelegate.alwaysOnMode { appDelegate.toggleAlwaysOnMode() }
            overlayWindow.orderOut(nil)
        }
        let item = try statusItem(.overlay)
        try openStatusMenu()
        XCTAssertEqual(item.title, "Show Overlay")

        try click(item)
        XCTAssertTrue(overlayWindow.isVisible)
        XCTAssertFalse(appDelegate.alwaysOnMode)
        try openStatusMenu()
        XCTAssertEqual(item.title, "Hide Overlay")

        try click(item)
        XCTAssertFalse(overlayWindow.isVisible)
        try openStatusMenu()
        XCTAssertEqual(item.title, "Show Overlay")

        // Always-On overlays are visible but read-only: the row offers the interactive one,
        // and leaves Always-On to show it.
        appDelegate.toggleAlwaysOnMode()
        XCTAssertEqual(item.title, "Show Overlay")
        try click(item)
        XCTAssertFalse(appDelegate.alwaysOnMode)
        XCTAssertTrue(overlayWindow.isVisible)
        XCTAssertTrue(appDelegate.isInteractiveOverlayOpen)
    }

    func testOverlayWindows() {
        // Test initial setup
        XCTAssertFalse(appDelegate.overlayWindows.isEmpty)

        // Test screen handling
        appDelegate.screenParametersChanged()
        XCTAssertEqual(appDelegate.overlayWindows.count, NSScreen.screens.count)
    }

    func testToolSwitching() throws {
        appDelegate.enablePenMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .pen)
        }

        appDelegate.enableArrowMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .arrow)
        }
        
        appDelegate.enableLineMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .line)
        }

        try assertToolMenuShows(.line)
    }

    func testCounterToolSwitching() throws {
        appDelegate.enableCounterMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .counter)
        }

        try assertToolMenuShows(.counter)
    }

    func testQuickPickerMenuItemsFailClosedWhenMainOverlayIsHidden() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let colorItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.showColorPicker(_:)) })
        let widthItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.showLineWidthPicker(_:)) })

        appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) }

        XCTAssertEqual(colorItem.title, "Color…")
        XCTAssertEqual(widthItem.title, "Line Width…")
        XCTAssertFalse(appDelegate.validateMenuItem(colorItem))
        XCTAssertFalse(appDelegate.validateMenuItem(widthItem))
    }

    func testStatusMenuOpensAboveEveryOverlay() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        XCTAssertTrue(menu.delegate === appDelegate)
        let overlays = Array(appDelegate.overlayWindows.values)
        XCTAssertFalse(overlays.isEmpty)
        let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        // Opening the menu scans for recent captures; keep it off the real capture folders.
        appDelegate.recentCaptures.scan = { _, _, _, _ in RecentCaptureScan(captures: []) }

        appDelegate.menuWillOpen(menu)
        for overlay in overlays {
            XCTAssertLessThan(overlay.level.rawValue, popUpLevel)
        }

        appDelegate.menuDidClose(menu)
        for overlay in overlays {
            XCTAssertEqual(overlay.level, OverlayWindow.elevatedLevel)
        }
    }

    func testPressAwayFromTheMenuBarLeavesTheStatusMenuClosed() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let point = NSPoint(x: screen.frame.midX, y: screen.frame.midY)

        XCTAssertFalse(appDelegate.openStatusMenu(forPressAt: point))
    }

    func testPickerMenuRoutesToVisibleMainOverlayCenter() throws {
        let mainScreen = try XCTUnwrap(NSScreen.main)
        let overlayWindow = try XCTUnwrap(appDelegate.overlayWindows[mainScreen])
        appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) }
        overlayWindow.makeKeyAndOrderFront(nil)
        defer { overlayWindow.orderOut(nil) }

        let colorItem = NSMenuItem()
        colorItem.action = #selector(AppDelegate.showColorPicker(_:))
        XCTAssertTrue(appDelegate.validateMenuItem(colorItem))

        appDelegate.showColorPicker(nil)
        let colorPicker = try XCTUnwrap(
            overlayWindow.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first)
        XCTAssertEqual(colorPicker.mode, .color)
        let expectedColorFrame = QuickPickerView.pickerFrame(
            itemCount: colorPalette.count,
            anchor: NSPoint(
                x: overlayWindow.overlayView.bounds.midX,
                y: overlayWindow.overlayView.bounds.midY),
            within: overlayWindow.overlayView.bounds)
        XCTAssertEqual(colorPicker.frame, expectedColorFrame)

        overlayWindow.cancelQuickPicker()
        overlayWindow.overlayView.currentTool = .counter
        appDelegate.showLineWidthPicker(nil)
        let counterPicker = try XCTUnwrap(
            overlayWindow.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first)
        XCTAssertEqual(counterPicker.mode, .counterSize)
    }

    /// `NSScreen.main` follows the menu bar, so a status menu opened from another display's
    /// overlay must still enable and open the pickers there (#122). Needs a second display.
    func testPickerMenuRoutesToTheVisibleOverlayOffTheMainScreen() throws {
        let mainScreen = try XCTUnwrap(NSScreen.main)
        let otherScreen = NSScreen.screens.first { $0 != mainScreen }
        try XCTSkipUnless(otherScreen != nil, "Needs a second display")
        let overlayWindow = try XCTUnwrap(otherScreen.flatMap { appDelegate.overlayWindows[$0] })
        appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) }
        overlayWindow.makeKeyAndOrderFront(nil)
        defer { overlayWindow.orderOut(nil) }

        for action in [#selector(AppDelegate.showColorPicker(_:)), #selector(AppDelegate.showLineWidthPicker(_:))] {
            let item = NSMenuItem()
            item.action = action
            XCTAssertTrue(appDelegate.validateMenuItem(item))
        }

        appDelegate.showColorPicker(nil)
        XCTAssertTrue(overlayWindow.isQuickPickerOpen)
        overlayWindow.cancelQuickPicker()
    }

    /// With an overlay visible on each display, the picker opens on the one under the pointer even
    /// when the other is key, and must take keyboard focus so Escape and the number keys reach it.
    /// Whether AppKit grants key status depends on the test host being allowed to activate, so
    /// the overlays record key requests instead of the test reading `NSApp.keyWindow`. Needs a
    /// second display.
    func testPickerTakesKeyboardFocusFromTheOtherDisplaysOverlay() throws {
        let screens = NSScreen.screens
        try XCTSkipUnless(screens.count > 1, "Needs a second display")
        let keyOverlay = replaceOverlayWithKeyRequestRecorder(on: screens[0])
        let pointerOverlay = replaceOverlayWithKeyRequestRecorder(on: screens[1])
        pointerOverlay.orderFront(nil)
        keyOverlay.makeKeyAndOrderFront(nil)
        defer { appDelegate.pointerLocationOverride = nil }
        appDelegate.pointerLocationOverride = NSPoint(x: screens[1].frame.midX, y: screens[1].frame.midY)

        keyOverlay.askedToBecomeKey = false
        appDelegate.showColorPicker(nil)
        XCTAssertTrue(pointerOverlay.isQuickPickerOpen)
        XCTAssertFalse(keyOverlay.isQuickPickerOpen)
        XCTAssertTrue(pointerOverlay.askedToBecomeKey, "The picker's overlay must ask for keyboard focus")
        XCTAssertFalse(keyOverlay.askedToBecomeKey)
        // AppKit sends key events to the key window, which is now the picker's overlay.
        pointerOverlay.sendEvent(try XCTUnwrap(TestEvents.createKeyEvent(
            type: .keyDown, keyCode: 53, windowNumber: pointerOverlay.windowNumber)))
        XCTAssertFalse(pointerOverlay.isQuickPickerOpen, "Escape must reach the picker's overlay")
        XCTAssertTrue(keyOverlay.isVisible && pointerOverlay.isVisible, "Escape must only close the picker")

        keyOverlay.makeKeyAndOrderFront(nil)
        keyOverlay.askedToBecomeKey = false
        pointerOverlay.askedToBecomeKey = false
        pointerOverlay.overlayView.currentTool = .pen
        appDelegate.showLineWidthPicker(nil)
        XCTAssertTrue(pointerOverlay.isQuickPickerOpen)
        XCTAssertTrue(pointerOverlay.askedToBecomeKey, "The picker's overlay must ask for keyboard focus")
        XCTAssertFalse(keyOverlay.askedToBecomeKey)
        let firstWidth = try XCTUnwrap(QuickPickerView.widthOptions.first)
        pointerOverlay.overlayView.currentLineWidth = firstWidth + 1
        pointerOverlay.sendEvent(try XCTUnwrap(TestEvents.createKeyEvent(
            type: .keyDown, keyCode: 18, characters: "1", windowNumber: pointerOverlay.windowNumber)))
        XCTAssertEqual(pointerOverlay.overlayView.currentLineWidth, firstWidth, "1 must pick the first width")
        pointerOverlay.cancelQuickPicker()
    }

    /// Swaps the launched overlay on `screen` for one that records key requests. tearDown closes
    /// it with the rest of `overlayWindows`.
    private func replaceOverlayWithKeyRequestRecorder(on screen: NSScreen) -> KeyRequestRecordingOverlayWindow {
        appDelegate.overlayWindows[screen]?.close()
        let overlay = KeyRequestRecordingOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        appDelegate.overlayWindows[screen] = overlay
        return overlay
    }

    // MARK: - Clear Drawings Tests

    func testToggleOverlayClearsDrawingsWhenEnabled() {
        testDefaults.settings[.clearDrawingsOnStart] = true
        appDelegate.alwaysOnMode = false

        XCTAssertTrue(testDefaults.settings[.clearDrawingsOnStart])

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        if overlayWindow.isVisible {
            overlayWindow.orderOut(nil)
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red, lineWidth: 3.0)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue, lineWidth: 3.0)
        overlayWindow.overlayView.arrows.append(testArrow)

        let testLine = Line(startPoint: .zero, endPoint: NSPoint(x: 20, y: 20), color: .green, lineWidth: 3.0)
        overlayWindow.overlayView.lines.append(testLine)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1)

        // Simulate the show behavior from toggleOverlay - clear if setting is enabled
        if testDefaults.settings[.clearDrawingsOnStart] {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 0, "Paths should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 0, "Arrows should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 0, "Lines should be cleared when clearDrawingsOnStartKey is true")
    }

    func testToggleOverlayPreservesDrawingsWhenDisabled() {
        testDefaults.settings[.clearDrawingsOnStart] = false
        appDelegate.alwaysOnMode = false

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        if overlayWindow.isVisible {
            overlayWindow.orderOut(nil)
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red, lineWidth: 3.0)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue, lineWidth: 3.0)
        overlayWindow.overlayView.arrows.append(testArrow)

        let testLine = Line(startPoint: .zero, endPoint: NSPoint(x: 20, y: 20), color: .green, lineWidth: 3.0)
        overlayWindow.overlayView.lines.append(testLine)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1)

        // Simulate the show behavior from toggleOverlay - clear if setting is enabled
        if testDefaults.settings[.clearDrawingsOnStart] {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1, "Paths should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1, "Arrows should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1, "Lines should be preserved when clearDrawingsOnStartKey is false")
    }

    func testClearDrawingsSettingPersistence() {
        XCTAssertFalse(testDefaults.settings[.clearDrawingsOnStart])

        testDefaults.settings[.clearDrawingsOnStart] = true
        XCTAssertTrue(testDefaults.settings[.clearDrawingsOnStart])

        testDefaults.settings[.clearDrawingsOnStart] = false
        XCTAssertFalse(testDefaults.settings[.clearDrawingsOnStart])
    }

    // MARK: - Dock Icon Tests

    func testHideDockIconDefaultValue() {
        testDefaults.settings.removeValue(for: .hideDockIcon)
        XCTAssertFalse(testDefaults.settings[.hideDockIcon])
    }

    func testDockIconVisibilityPersistence() {
        testDefaults.settings[.hideDockIcon] = true
        XCTAssertTrue(testDefaults.settings[.hideDockIcon])

        testDefaults.settings[.hideDockIcon] = false
        XCTAssertFalse(testDefaults.settings[.hideDockIcon])
    }

    // MARK: - Persist Fade Mode Tests

    func testDefaultFadeModePersistence() {
        testDefaults.settings.removeValue(for: .fadeMode)
        let persistedFadeMode = testDefaults.settings[.fadeMode]
        XCTAssertTrue(persistedFadeMode, "Default fade mode should be true (fade mode active).")
    }

    func testToggleFadeModeUpdatesPersistence() {
        let appDelegate = launchAppDelegate()

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }
        XCTAssertTrue(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be true by default.")

        // Toggle fade mode.
        appDelegate.toggleFadeMode(nil)

        XCTAssertFalse(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be false after toggle.")

        // UserDefaults should reflect this change.
        let persistedFadeMode = testDefaults.settings[.fadeMode]
        XCTAssertFalse(persistedFadeMode, "UserDefaults should now store false for fade mode.")
    }

    // MARK: - Fade Delay

    func testFadeDelayDefaultsToTheOriginalHold() {
        XCTAssertEqual(testDefaults.settings[.fadeDelay], 0.625)
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.fadeDelay, 0.625)
            XCTAssertEqual(window.overlayView.fadeDuration, 1.25)
        }
    }

    func testFadeDelayFromSettingsAppliesToEveryOverlay() {
        // What the Settings slider does: write through @AppStorage, then apply.
        testDefaults.settings[.fadeDelay] = 1.5
        appDelegate.applyFadeDelay()

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.fadeDelay, 1.5)
        }
    }

    func testPersistedFadeDelayIsRestoredOnLaunch() throws {
        testDefaults.settings[.fadeDelay] = 3

        let relaunched = launchAppDelegate()

        let window = try XCTUnwrap(relaunched.overlayWindows.values.first)
        XCTAssertEqual(window.overlayView.fadeDelay, 3)
    }

    func testOverlayPicksUpTheFadeDelayWhenShown() throws {
        let overlayWindow = try XCTUnwrap(appDelegate.overlayWindows.values.first)
        defer { appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) } }
        testDefaults.settings[.fadeDelay] = 4

        appDelegate.toggleAlwaysOnMode()
        appDelegate.toggleAlwaysOnMode()

        XCTAssertEqual(overlayWindow.overlayView.fadeDelay, 4)
    }

    func testToggleFadeModeStartsFadeLoop() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }

        overlayWindow.overlayView.fadeMode = false
        overlayWindow.stopFadeLoop()
        overlayWindow.overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 0, y: 0),
                endPoint: NSPoint(x: 10, y: 10),
                color: .systemRed,
                lineWidth: 3,
                creationTime: CACurrentMediaTime()
            )
        ]

        appDelegate.toggleFadeMode(nil)

        XCTAssertTrue(overlayWindow.overlayView.fadeMode)
        XCTAssertNotNil(overlayWindow.fadeTimer)
        overlayWindow.stopFadeLoop()
    }

    func testAlwaysOnExitStartsFadeLoopWhenPersistedFadeModeIsOn() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }

        let now = CACurrentMediaTime()
        overlayWindow.overlayView.arrows = [
            Arrow(
                startPoint: NSPoint(x: 0, y: 0),
                endPoint: NSPoint(x: 10, y: 10),
                color: .systemRed,
                lineWidth: 3,
                creationTime: now - 10
            ),
            Arrow(
                startPoint: NSPoint(x: 20, y: 20),
                endPoint: NSPoint(x: 30, y: 30),
                color: .systemBlue,
                lineWidth: 3,
                creationTime: now
            )
        ]

        appDelegate.alwaysOnMode = false
        appDelegate.toggleAlwaysOnMode()
        XCTAssertFalse(overlayWindow.overlayView.fadeMode)
        XCTAssertNil(overlayWindow.fadeTimer)

        appDelegate.toggleAlwaysOnMode()

        XCTAssertTrue(overlayWindow.overlayView.fadeMode)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.first?.startPoint, NSPoint(x: 20, y: 20))
        XCTAssertNotNil(overlayWindow.fadeTimer)
        overlayWindow.stopFadeLoop()
    }

    func testFadeAndClearAllMenuActionsRequireOverlayKeyWindow() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let fadeItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.toggleFadeMode(_:)) })
        let clearItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(AppDelegate.clearAllAnnotations) })
        // Clear All acts on the screen under the pointer. Pin the pointer to this overlay's
        // screen so the test doesn't depend on where the mouse is on a multi-display Mac.
        let (screen, overlayWindow) = try XCTUnwrap(appDelegate.overlayWindows.first)
        appDelegate.pointerLocationOverride = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        overlayWindow.overlayView.fadeMode = false
        overlayWindow.overlayView.paths.append(TestFactory.createDrawingPath())
        appDelegate.overlayWindows.values.forEach { $0.orderOut(nil) }
        defer {
            SettingsWindowManager.shared.settingsWindow?.close()
            overlayWindow.orderOut(nil)
            appDelegate.pointerLocationOverride = nil
        }

        XCTAssertFalse(appDelegate.validateMenuItem(fadeItem))
        XCTAssertFalse(appDelegate.validateMenuItem(clearItem))
        appDelegate.toggleFadeMode(NSMenuItem())
        appDelegate.clearAllAnnotations()
        XCTAssertFalse(overlayWindow.overlayView.fadeMode)
        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)

        // Settings is a normal-level window; the overlay sits above screen-saver
        // level, so show() cannot steal key in CI. orderFront keeps the overlay
        // visible (the High: Settings focused, overlay still on screen) without
        // making it the key window.
        SettingsWindowManager.shared.show()
        overlayWindow.orderFront(nil)
        if overlayWindow.isKeyWindow {
            overlayWindow.resignKey()
        }
        XCTAssertTrue(overlayWindow.isVisible)
        XCTAssertFalse(overlayWindow.isKeyWindow)
        XCTAssertFalse(appDelegate.validateMenuItem(fadeItem))
        XCTAssertFalse(appDelegate.validateMenuItem(clearItem))
        appDelegate.toggleFadeMode(NSMenuItem())
        appDelegate.clearAllAnnotations()
        XCTAssertFalse(
            overlayWindow.overlayView.fadeMode,
            "Fade must not toggle from a menu equivalent unless the overlay is key")
        XCTAssertEqual(
            overlayWindow.overlayView.paths.count, 1,
            "Clear All must not fire from a menu equivalent unless the overlay is key")

        // XCTest will not make this overlay key: ToolbarPanel answers
        // canBecomeKey = false, so makeKeyAndOrderFront leaves isKeyWindow false.
        // Drive the same product gate through the test seam instead.
        overlayWindow.orderFront(nil)
        appDelegate.overlayKeyWindowOverride = true
        XCTAssertTrue(appDelegate.validateMenuItem(fadeItem))
        XCTAssertTrue(appDelegate.validateMenuItem(clearItem))
        appDelegate.toggleFadeMode(NSMenuItem())
        appDelegate.clearAllAnnotations()
        XCTAssertTrue(overlayWindow.overlayView.fadeMode)
        XCTAssertTrue(overlayWindow.overlayView.paths.isEmpty)
    }

    func testOverlayWindowsRestorePersistedFadeMode() {
        testDefaults.settings[.fadeMode] = false

        let appDelegate = launchAppDelegate()

        // All overlay windows should be initialized with fade mode set to false.
        for window in appDelegate.overlayWindows.values {
            XCTAssertFalse(
                window.overlayView.fadeMode,
                "Overlay window should restore persisted fade mode as false.")
        }
    }

    func testToggleBoardVisibility() {
        let initialState = testDefaults.settings[.enableBoard]

        appDelegate.toggleBoardVisibility(nil)

        let newState = testDefaults.settings[.enableBoard]
        XCTAssertNotEqual(initialState, newState, "Board visibility should be toggled")
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.adaptColorsToBoardType, newState)
        }

        appDelegate.toggleBoardVisibility(nil)
        let finalState = testDefaults.settings[.enableBoard]
        XCTAssertEqual(
            initialState, finalState, "Board visibility should be toggled back to original state")
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.adaptColorsToBoardType, finalState)
        }
    }

    func testUpdateBoardMenuItems() {
        guard let menu = appDelegate.statusItem.menu else {
            XCTFail("Status bar menu not initialized")
            return
        }

        let toggleBoardItem = menu.items.first {
            $0.action == #selector(AppDelegate.toggleBoardVisibility(_:))
        }
        XCTAssertNotNil(toggleBoardItem, "Board toggle menu item should exist")

        let initialTitle = toggleBoardItem?.title

        let initialState = BoardManager.shared.isEnabled
        BoardManager.shared.isEnabled = !initialState

        appDelegate.updateBoardMenuItems()

        let newTitle = toggleBoardItem?.title
        XCTAssertNotEqual(
            initialTitle, newTitle, "Menu item title should change when board visibility changes")

        BoardManager.shared.isEnabled = initialState
    }

    /// Pressing `b` twice within the 0.3 s fade-out used to leave the board hidden while the
    /// menu said "Hide": the first press's fade-out completion hid the view after the second
    /// press had shown it again. Toggle through both the `b` key and the menu item, at gaps
    /// inside and outside the fade, and check every board agrees with the menu once it settles.
    func testRapidBoardTogglesKeepBoardAndMenuInSync() throws {
        let menu = try XCTUnwrap(appDelegate.statusItem.menu)
        let itemIndex = try XCTUnwrap(menu.items.firstIndex {
            $0.action == #selector(AppDelegate.toggleBoardVisibility(_:))
        })
        let delegate = try XCTUnwrap(appDelegate)
        let window = try XCTUnwrap(delegate.overlayWindows.values.first)
        let pressB = {
            window.keyDown(with: TestEvents.createKeyEvent(
                type: .keyDown, keyCode: 11, characters: "b", charactersIgnoringModifiers: "b")!)
        }
        // The status menu's items have no target and AppDelegate isn't NSApp's delegate under
        // test, so send the item's action to it the way a click would.
        let clickMenuItem = {
            let item = menu.items[itemIndex]
            XCTAssertTrue(NSApp.sendAction(item.action!, to: delegate, from: item))
        }

        func assertInSync(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
            let enabled = BoardManager.shared.isEnabled
            let title = menu.items[itemIndex].title
            XCTAssertEqual(title.hasPrefix("Hide"), enabled, "\(context): menu says \(title)", file: file, line: line)
            for overlay in delegate.overlayWindows.values {
                let board: BoardView = overlay.boardView
                XCTAssertEqual(board.isHidden, !enabled, "\(context): board isHidden", file: file, line: line)
                if enabled {
                    XCTAssertEqual(board.alphaValue, 1, "\(context): board alpha", file: file, line: line)
                }
            }
        }

        BoardManager.shared.isEnabled = true
        wait(for: 0.5)
        assertInSync("start")

        let toggles: [(String, () -> Void)] = [("b", pressB), ("menu", clickMenuItem)]
        for gap in [0.15, 0.6] {
            for (firstName, first) in toggles {
                for (secondName, second) in toggles {
                    let context = "\(firstName) then \(secondName) \(gap) s apart"
                    first()
                    wait(for: gap)
                    second()
                    wait(for: 0.4)
                    assertInSync(context)
                    XCTAssertTrue(BoardManager.shared.isEnabled, "\(context): two toggles end shown")
                }
            }
        }

        for _ in 0..<5 {
            pressB()
            wait(for: 0.07)
        }
        wait(for: 0.5)
        XCTAssertFalse(BoardManager.shared.isEnabled, "Five toggles from shown end hidden")
        assertInSync("five quick presses")
    }

    // MARK: - Toggle Click Effects Tests

    func testToggleClickEffectsTogglesBothSettings() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager

        // Start with both disabled
        cursorManager.clickEffectsEnabled = false
        cursorManager.cursorHighlightEnabled = false

        XCTAssertFalse(cursorManager.clickEffectsEnabled)
        XCTAssertFalse(cursorManager.cursorHighlightEnabled)

        // Toggle on - should enable both
        appDelegate.toggleClickEffects(nil)

        XCTAssertTrue(
            CursorHighlightManager.shared.clickEffectsEnabled,
            "clickEffectsEnabled should be true after toggle")
        XCTAssertTrue(
            CursorHighlightManager.shared.cursorHighlightEnabled,
            "cursorHighlightEnabled should be true after toggle")

        // Toggle off - should disable both
        appDelegate.toggleClickEffects(nil)

        XCTAssertFalse(
            CursorHighlightManager.shared.clickEffectsEnabled,
            "clickEffectsEnabled should be false after second toggle")
        XCTAssertFalse(
            CursorHighlightManager.shared.cursorHighlightEnabled,
            "cursorHighlightEnabled should be false after second toggle")

        CursorHighlightManager.shared = CursorHighlightManager()
    }

    func testToggleClickEffectsPostsNotification() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager

        cursorManager.clickEffectsEnabled = false
        cursorManager.cursorHighlightEnabled = false

        let expectation = expectation(forNotification: .cursorHighlightStateChanged, object: nil)
        expectation.expectedFulfillmentCount = 2  // One for each property set

        appDelegate.toggleClickEffects(nil)

        wait(for: [expectation], timeout: 1.0)

        CursorHighlightManager.shared = CursorHighlightManager()
    }

    // MARK: - Default Tool Tests

    func testSwitchToolPersistsLastUsedTool() {
        appDelegate.enableRectangleMode(NSMenuItem())
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .rectangle, "Explicitly switching tools should persist the choice as last used")

        appDelegate.enableHighlighterMode(NSMenuItem())
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .highlighter)
    }

    func testApplyConfiguredDefaultToolAppliesSpecificTool() throws {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        testDefaults.settings[.defaultTool] = .tool(.rectangle)
        appDelegate.enableArrowMode(NSMenuItem())  // start on a different tool than the configured default
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.applyConfiguredDefaultTool()

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .rectangle, "Activation should reset the tool to the configured default")
        }

        try assertToolMenuShows(.rectangle)
    }

    func testApplyConfiguredDefaultToolSkipsWhenToolAlreadyActive() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableRectangleMode(NSMenuItem())
        testDefaults.settings[.defaultTool] = .tool(.rectangle)
        testDefaults.settings[.lastUsedTool] = .highlighter

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .rectangle)
        XCTAssertEqual(
            testDefaults.settings[.lastUsedTool], .highlighter,
            "Applying a default tool that is already active should be a no-op (no switchTool, no tool feedback)")
    }

    func testApplyConfiguredDefaultToolDoesNotOverwriteLastUsedTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableHighlighterMode(NSMenuItem())
        testDefaults.settings[.defaultTool] = .tool(.rectangle)

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .rectangle)
        XCTAssertEqual(
            testDefaults.settings[.lastUsedTool], .highlighter,
            "Applying the configured default is not an explicit selection and must not overwrite the persisted last-used tool")
    }

    func testApplyConfiguredDefaultToolDoesNothingForLastUsed() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        XCTAssertEqual(testDefaults.settings[.defaultTool], .lastUsed, "Default should be Last Used until the setting is touched")

        appDelegate.enableArrowMode(NSMenuItem())
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow, "Last Used should preserve whatever tool was already active")
    }

    func testLaunchRestoresPersistedLastUsedTool() throws {
        testDefaults.settings[.lastUsedTool] = .highlighter

        let appDelegate = launchAppDelegate()

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .highlighter, "Overlay windows should restore the persisted last-used tool on launch")
        }

        // The menu reflects the restored tool, not a hardcoded default.
        try assertToolMenuShows(.highlighter, in: appDelegate)
    }

    func testLaunchDefaultsToPenWhenNoLastUsedToolSaved() {
        // testDefaults is a fresh suite with no LastUsedTool key set (see setUp).
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .pen, "Should fall back to .pen when no last-used tool was saved")
        }
    }

    func testInternalToolSwitchDoesNotOverwriteLastUsedTool() throws {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.settings[.selectAfterPlacingText] = true

        appDelegate.enablePenMode(NSMenuItem())
        appDelegate.enableTextMode(NSMenuItem())
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .text, "Explicitly switching to text should persist it as last used")

        let overlayView: OverlayView = try XCTUnwrap(overlayWindow.overlayView)
        let point = NSPoint(x: 100, y: 100)
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "", position: point, color: .red,
            fontSize: defaultTextAnnotationFontSize
        )
        overlayView.createTextField(at: point, withText: "")
        let textField = try XCTUnwrap(overlayView.activeTextField)
        textField.stringValue = "Hello"
        overlayView.commitTextField(textField)

        XCTAssertEqual(overlayView.currentTool, .select, "Committing a label should switch to Select")
        try assertToolMenuShows(.select)
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .text, "Internal tool switches should not overwrite the persisted last-used tool")
    }
}

@MainActor
final class MockAppDelegate: AppDelegate {}

/// An overlay that reports itself key when told to. XCTest can't make an overlay key.
final class KeyReportingOverlayWindow: OverlayWindow {
    var reportsKey = false
    override var isKeyWindow: Bool { reportsKey }
}

/// Records requests to become key, which AppKit may refuse while the test host isn't active.
/// `makeKeyAndOrderFront` can call `makeKey`, so this is a flag rather than a count.
final class KeyRequestRecordingOverlayWindow: OverlayWindow {
    var askedToBecomeKey = false

    override func makeKeyAndOrderFront(_ sender: Any?) {
        askedToBecomeKey = true
        super.makeKeyAndOrderFront(sender)
    }

    override func makeKey() {
        askedToBecomeKey = true
        super.makeKey()
    }
}
