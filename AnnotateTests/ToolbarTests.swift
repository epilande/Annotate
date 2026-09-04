import SwiftUI
import XCTest

@testable import Annotate

@MainActor
final class ToolbarTests: XCTestCase {
    private var defaults: UserDefaults!
    private var appDelegate: AppDelegate!
    private var window: OverlayWindow!
    private var installedStatusItem = false

    override func setUp() {
        super.setUp()
        defaults = TestUserDefaults.create()
        appDelegate = AppDelegate(userDefaults: defaults)
        AppDelegate.shared = appDelegate
        ShortcutManager.shared = ShortcutManager(userDefaults: defaults)
        window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView?.layoutSubtreeIfNeeded()
    }

    override func tearDown() {
        if installedStatusItem {
            NSStatusBar.system.removeStatusItem(appDelegate.statusItem)
        }
        window.close()
        window = nil
        AppDelegate.shared = nil
        appDelegate = nil
        ShortcutManager.shared = ShortcutManager()
        TestUserDefaults.removeSuite()
        defaults = nil
        super.tearDown()
    }

    func testToolbarUsesRequiredPersistenceKeyAndIsVisibleByDefault() {
        XCTAssertEqual(UserDefaults.toolbarVisibleKey, "ToolbarVisible")
        XCTAssertTrue(appDelegate.toolbarVisible)
        XCTAssertFalse(window.toolbarHost?.isHidden ?? true)
        XCTAssertFalse(window.toolbarFrame.isEmpty)
        XCTAssertEqual(window.toolbarFrame.minY, 20, accuracy: 0.5)
    }

    func testVisibilityPersistsAndUpdatesEveryOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        appDelegate.overlayWindows[screen] = window

        appDelegate.setToolbarVisible(false)

        XCTAssertEqual(defaults.object(forKey: UserDefaults.toolbarVisibleKey) as? Bool, false)
        XCTAssertTrue(window.toolbarHost?.isHidden ?? false)
        XCTAssertEqual(window.toolbarClearance, 0)
        XCTAssertEqual(window.feedbackBottomPadding, 20)

        appDelegate.setToolbarVisible(true)

        XCTAssertFalse(window.toolbarHost?.isHidden ?? true)
        XCTAssertGreaterThan(window.toolbarClearance, 20)
        XCTAssertEqual(window.feedbackBottomPadding, window.toolbarClearance + 8)
    }

    func testStatusMenuToolbarToggleFlipsItsTitle() throws {
        appDelegate.setupStatusBarItem()
        installedStatusItem = true

        let item = try XCTUnwrap(
            appDelegate.statusItem.menu?.items.first {
                $0.action == #selector(AppDelegate.toggleToolbar)
            }
        )
        XCTAssertEqual(item.title, "Hide Toolbar")
        XCTAssertEqual(item.keyEquivalent, "/")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.shift])

        appDelegate.setToolbarVisible(false)
        XCTAssertEqual(item.title, "Show Toolbar")

        appDelegate.setToolbarVisible(true)
        XCTAssertEqual(item.title, "Hide Toolbar")
    }

    func testToolbarModelTracksLiveOverlayStateAndShortcutChanges() throws {
        window.overlayView.currentTool = .highlighter
        window.overlayView.currentColor = .systemBlue
        window.overlayView.currentLineWidth = 16
        window.overlayView.fadeMode = false

        XCTAssertEqual(window.toolbarModel.activeTool, .highlighter)
        XCTAssertTrue(window.toolbarModel.currentColor.isClose(to: .systemBlue))
        XCTAssertEqual(window.toolbarModel.currentWidth, 16)
        XCTAssertFalse(window.toolbarModel.fadeMode)

        XCTAssertEqual(window.toolbarModel.shortcuts[.pen], ShortcutKey.pen.defaultKey)

        ShortcutManager.shared.setShortcut("x", for: .pen)
        XCTAssertEqual(
            window.toolbarModel.shortcuts[.pen], "x",
            "The toolbar snapshot must refresh on .shortcutsDidChange")
    }

    func testWidthChipSizeFollowsCanonicalWidthLadder() {
        window.toolbarModel.currentWidth = QuickPickerView.widthOptions.first!
        let smallest = window.toolbarModel.widthDotDiameter
        window.toolbarModel.currentWidth = QuickPickerView.widthOptions.last!
        let largest = window.toolbarModel.widthDotDiameter

        XCTAssertEqual(smallest, 4)
        XCTAssertEqual(largest, 14)
        XCTAssertGreaterThan(largest, smallest)
    }

    func testToolbarActionsUseExistingToolFadePickerAndCanvasAuthorities() {
        let spy = ToolbarAppDelegateSpy(userDefaults: defaults)
        AppDelegate.shared = spy

        window.performToolbarAction(.tool(.rectangle))
        window.performToolbarAction(.toggleFade)
        XCTAssertEqual(spy.selectedTool, .rectangle)
        XCTAssertTrue(spy.didToggleFade)

        window.performToolbarAction(.colorPicker)
        XCTAssertTrue(window.isQuickPickerOpen)
        window.cancelQuickPicker()
        window.performToolbarAction(.widthPicker)
        XCTAssertTrue(window.isQuickPickerOpen)
        window.cancelQuickPicker()

        let path = TestFactory.createDrawingPath(
            points: [TestFactory.createTimedPoint(x: 20, y: 20)]
        )
        window.overlayView.currentTool = .pen
        window.overlayView.paths.append(path)
        window.performToolbarAction(.deleteLast)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        window.overlayView.paths.append(path)
        window.performToolbarAction(.clearAll)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        window.undoManager?.removeAllActions()

        window.overlayView.registerUndo(action: .addPath(path))
        window.overlayView.paths.append(path)
        window.performToolbarAction(.undo)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        AppDelegate.shared = appDelegate
    }

    func testToolbarMouseGestureNeverStartsOrCompletesCanvasGesture() {
        let toolbarPoint = NSPoint(x: window.toolbarFrame.midX, y: window.toolbarFrame.midY)
        XCTAssertTrue(window.isPointInToolbar(toolbarPoint))
        let draggedPoint = NSPoint(x: toolbarPoint.x + 30, y: toolbarPoint.y + 30)

        sendMouse(.leftMouseDown, at: toolbarPoint)
        sendMouse(.leftMouseDragged, at: draggedPoint)
        sendMouse(.leftMouseUp, at: draggedPoint)

        XCTAssertEqual(window.anchorPoint, .zero)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        let canvasPoint = NSPoint(x: 100, y: 300)
        sendMouse(.leftMouseDown, at: canvasPoint)
        XCTAssertEqual(window.anchorPoint, canvasPoint)
    }

    func testQuickPickerPlacementAndFeedbackClearVisibleToolbar() throws {
        let clearance = window.toolbarClearance
        XCTAssertGreaterThan(clearance, 0)

        window.beginQuickPicker(.color, anchor: NSPoint(x: 600, y: 0))
        let picker = try XCTUnwrap(
            window.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first
        )

        XCTAssertGreaterThanOrEqual(picker.frame.minY, clearance)
        XCTAssertEqual(window.feedbackBottomPadding, clearance + 8)
    }

    func testQuestionMarkTogglesPersistedVisibility() throws {
        window.sendEvent(try XCTUnwrap(questionMarkEvent()))

        XCTAssertFalse(appDelegate.toolbarVisible)
    }

    func testQuestionMarkTypesWhileEditingAnnotationText() throws {
        let field = try XCTUnwrap(startEditingAnnotationText())

        XCTAssertTrue(appDelegate.toolbarVisible)

        window.sendEvent(try XCTUnwrap(questionMarkEvent()))
        XCTAssertTrue(
            appDelegate.toolbarVisible,
            "? must not toggle the toolbar from sendEvent while editing")

        try XCTSkipUnless(
            field.currentEditor() != nil,
            "Typing needs a live field editor, which headless runs do not provide")
        let typed =
            field.stringValue.contains("?")
            || field.currentEditor()?.string.contains("?") == true
        XCTAssertTrue(typed, "? should insert into the annotation field while editing")
    }

    func testToolbarHostAcceptsFirstMouse() {
        XCTAssertTrue(
            window.toolbarHost?.acceptsFirstMouse(for: nil) ?? false,
            "Chips live in a nonactivating panel; the host must take the first click")
    }

    func testAlwaysOnModePassesClicksThroughAndHidesToolbar() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        appDelegate.overlayWindows[screen] = window
        appDelegate.alwaysOnMode = false
        window.overlayView.currentTool = .pen
        appDelegate.toggleAlwaysOnMode()
        defer {
            if appDelegate.alwaysOnMode {
                appDelegate.toggleAlwaysOnMode()
            }
        }
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(
            window.ignoresMouseEvents,
            "Always-On is a read-only overlay; every click belongs to the app underneath")
        XCTAssertTrue(window.overlayView.isReadOnlyMode)
        XCTAssertTrue(
            window.toolbarHost?.isHidden ?? false,
            "Always-On carries no toolbar, so nothing on the overlay is clickable")

        let canvasStart = NSPoint(x: 100, y: 300)
        let canvasEnd = NSPoint(x: 180, y: 360)
        sendMouse(.leftMouseDown, at: canvasStart)
        sendMouse(.leftMouseDragged, at: canvasEnd)
        sendMouse(.leftMouseUp, at: canvasEnd)

        XCTAssertTrue(window.overlayView.paths.isEmpty, "Always-On must never draw")
        XCTAssertEqual(window.anchorPoint, .zero)

        appDelegate.toggleAlwaysOnMode()

        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertFalse(window.overlayView.isReadOnlyMode)
        XCTAssertFalse(
            window.toolbarHost?.isHidden ?? true,
            "Leaving Always-On restores the toolbar")
    }

    func testToolbarActionFinalizesActiveTextAnnotation() throws {
        let field = try XCTUnwrap(startEditingAnnotationText())
        field.stringValue = "Keep me"
        field.currentEditor()?.string = "Keep me"

        window.performToolbarAction(.tool(.pen))

        XCTAssertNil(window.overlayView.activeTextField)
        XCTAssertEqual(window.overlayView.textAnnotations.last?.text, "Keep me")
    }

    func testCanvasStrokeCrossingToolbarIsNotCaptured() throws {
        window.overlayView.currentTool = .pen
        let canvasStart = NSPoint(x: 100, y: 300)
        let overBar = NSPoint(x: window.toolbarFrame.midX, y: window.toolbarFrame.midY)
        XCTAssertTrue(window.isPointInToolbar(overBar))
        XCTAssertFalse(window.isPointInToolbar(canvasStart))

        sendMouse(.leftMouseDown, at: canvasStart)
        XCTAssertEqual(window.anchorPoint, canvasStart)

        sendMouse(.leftMouseDragged, at: overBar)
        sendMouse(.leftMouseUp, at: overBar)

        XCTAssertFalse(
            window.overlayView.paths.isEmpty,
            "A canvas-origin stroke must finish even if drag/up cross the toolbar")
        XCTAssertEqual(window.anchorPoint, canvasStart)
    }

    func testToolbarViewWrapsToASecondRowWhenWidthIsTight() {
        let wide = NSHostingController(rootView: ToolbarView(model: window.toolbarModel) { _ in })
            .sizeThatFits(in: CGSize(width: 1_200, height: 200))
        let narrow = NSHostingController(rootView: ToolbarView(model: window.toolbarModel) { _ in })
            .sizeThatFits(in: CGSize(width: 700, height: 200))

        XCTAssertGreaterThan(
            narrow.height, wide.height,
            "A narrow proposal must take the stacked ViewThatFits layout")
    }

    private func questionMarkEvent() -> NSEvent? {
        TestEvents.createKeyEvent(
            type: .keyDown,
            keyCode: 44,
            modifierFlags: [.shift],
            characters: "?",
            windowNumber: window.windowNumber
        )
    }

    private func sendMouse(_ type: NSEvent.EventType, at location: NSPoint) {
        window.sendEvent(
            TestEvents.createMouseEvent(
                type: type, location: location, windowNumber: window.windowNumber)!)
    }

    private func startEditingAnnotationText() throws -> NSTextField? {
        window.overlayView.currentTool = .text
        window.overlayView.currentTextAnnotation = TextAnnotation(
            text: "",
            position: NSPoint(x: 120, y: 120),
            color: .black,
            fontSize: defaultTextAnnotationFontSize
        )
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.overlayView.createTextField(
            at: NSPoint(x: 120, y: 120), withText: "", width: 200)
        let field = try XCTUnwrap(
            window.overlayView.activeTextField, "Expected an annotation text field")
        if window.firstResponder !== field && window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
        if field.currentEditor() == nil {
            field.becomeFirstResponder()
        }
        return field
    }
}

@MainActor
private final class ToolbarAppDelegateSpy: AppDelegate {
    var selectedTool: ToolType?
    var didToggleFade = false

    override func switchTool(to tool: ToolType, persist: Bool = true) {
        selectedTool = tool
    }

    override func toggleFadeMode(_ sender: Any?) {
        didToggleFade = true
    }
}
