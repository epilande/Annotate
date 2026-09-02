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

    func testStatusMenuExposesCheckedQuestionMarkToolbarToggle() throws {
        appDelegate.setupStatusBarItem()
        installedStatusItem = true

        let item = try XCTUnwrap(
            appDelegate.statusItem.menu?.items.first {
                $0.action == #selector(AppDelegate.toggleToolbar)
            }
        )
        XCTAssertEqual(item.title, "Toolbar")
        XCTAssertEqual(item.keyEquivalent, "/")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.shift])
        XCTAssertEqual(item.state, .on)

        appDelegate.setToolbarVisible(false)
        XCTAssertEqual(item.state, .off)
    }

    func testToolbarModelTracksLiveOverlayStateAndShortcutChanges() {
        window.overlayView.currentTool = .highlighter
        window.overlayView.currentColor = .systemBlue
        window.overlayView.currentLineWidth = 16
        window.overlayView.fadeMode = false

        XCTAssertEqual(window.toolbarModel.activeTool, .highlighter)
        XCTAssertTrue(window.toolbarModel.currentColor.isClose(to: .systemBlue))
        XCTAssertEqual(window.toolbarModel.currentWidth, 16)
        XCTAssertFalse(window.toolbarModel.fadeMode)

        let version = window.toolbarModel.shortcutsVersion
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        XCTAssertEqual(window.toolbarModel.shortcutsVersion, version + 1)
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
    func testToolbarMouseGestureNeverStartsOrCompletesCanvasGesture() throws {
        let toolbarPoint = NSPoint(x: window.toolbarFrame.midX, y: window.toolbarFrame.midY)
        XCTAssertTrue(window.isPointInToolbar(toolbarPoint))

        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: toolbarPoint
        )))
        window.mouseDragged(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: toolbarPoint.x + 30, y: toolbarPoint.y + 30)
        )))
        window.mouseUp(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseUp,
            location: NSPoint(x: toolbarPoint.x + 30, y: toolbarPoint.y + 30)
        )))

        XCTAssertEqual(window.anchorPoint, .zero)
        XCTAssertTrue(window.overlayView.paths.isEmpty)

        let canvasPoint = NSPoint(x: 100, y: 300)
        window.mouseDown(with: try XCTUnwrap(TestEvents.createMouseEvent(
            type: .leftMouseDown,
            location: canvasPoint
        )))
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
        let event = try XCTUnwrap(questionMarkEvent())

        window.keyDown(with: event)

        XCTAssertFalse(appDelegate.toolbarVisible)
    }

    func testQuestionMarkTypesWhileEditingAnnotationText() throws {
        guard startEditingAnnotationText() != nil else { return }

        XCTAssertTrue(appDelegate.toolbarVisible)

        window.keyDown(with: try XCTUnwrap(questionMarkEvent()))
        XCTAssertTrue(
            appDelegate.toolbarVisible,
            "? must not toggle the toolbar from keyDown while editing")

        window.sendEvent(try XCTUnwrap(questionMarkEvent()))
        XCTAssertTrue(
            appDelegate.toolbarVisible,
            "? must not toggle the toolbar from sendEvent while editing")

        let field = try XCTUnwrap(window.overlayView.activeTextField)
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

    func testAlwaysOnClickThroughStillHitsToolbar() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        appDelegate.overlayWindows[screen] = window
        appDelegate.alwaysOnMode = false
        appDelegate.toggleAlwaysOnMode()
        defer {
            if appDelegate.alwaysOnMode {
                appDelegate.toggleAlwaysOnMode()
            }
        }
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(
            window.ignoresMouseEvents,
            "Always-On must not ignore all mouse events or toolbar chips never fire")
        XCTAssertTrue(window.overlayView.isReadOnlyMode)

        let canvasPoint = NSPoint(x: 100, y: 300)
        XCTAssertFalse(window.isPointInToolbar(canvasPoint))
        XCTAssertNil(
            window.contentView?.hitTest(canvasPoint),
            "Canvas clicks in Always-On must pass through")

        let toolbarPoint = NSPoint(x: window.toolbarFrame.midX, y: window.toolbarFrame.midY)
        XCTAssertTrue(window.isPointInToolbar(toolbarPoint))
        let toolbarHit = window.contentView?.hitTest(toolbarPoint)
        XCTAssertNotNil(toolbarHit, "Toolbar chips must receive clicks in Always-On")
        let host = try XCTUnwrap(window.toolbarHost)
        XCTAssertTrue(toolbarHit === host || toolbarHit?.isDescendant(of: host) == true)
    }

    func testAlwaysOnClickThroughStillHitsQuickPicker() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        appDelegate.overlayWindows[screen] = window
        appDelegate.alwaysOnMode = false
        appDelegate.toggleAlwaysOnMode()
        defer {
            window.cancelQuickPicker()
            if appDelegate.alwaysOnMode {
                appDelegate.toggleAlwaysOnMode()
            }
        }
        window.contentView?.layoutSubtreeIfNeeded()

        window.beginQuickPicker(.color, anchor: NSPoint(x: 600, y: 400))
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(window.isQuickPickerOpen)
        let picker = try XCTUnwrap(
            window.overlayView.subviews.compactMap { $0 as? QuickPickerView }.first
        )

        let canvasPoint = NSPoint(x: 100, y: 300)
        XCTAssertFalse(
            picker.frame.contains(window.overlayView.convert(canvasPoint, from: window.contentView)))
        XCTAssertNil(
            window.contentView?.hitTest(canvasPoint),
            "Canvas clicks in Always-On must still pass through while the picker is open")

        let pickerPoint = window.overlayView.convert(
            NSPoint(x: picker.frame.midX, y: picker.frame.midY),
            to: window.contentView
        )
        let pickerHit = window.contentView?.hitTest(pickerPoint)
        XCTAssertNotNil(pickerHit, "Quick picker must receive clicks in Always-On")
        XCTAssertTrue(pickerHit === picker || pickerHit?.isDescendant(of: picker) == true)
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

    func testToolbarViewBuildsForWideAndNarrowProposals() {
        let view = ToolbarView(model: window.toolbarModel) { _ in }
        let host = NSHostingView(rootView: view)

        host.frame = NSRect(x: 0, y: 0, width: 1_200, height: 200)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)

        host.frame = NSRect(x: 0, y: 0, width: 700, height: 200)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
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

    private func startEditingAnnotationText() -> NSTextField? {
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
        guard let field = window.overlayView.activeTextField else {
            XCTFail("Expected an annotation text field")
            return nil
        }
        if window.firstResponder !== field && window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
        if field.currentEditor() == nil {
            field.becomeFirstResponder()
        }
        XCTAssertNotNil(window.overlayView.activeTextField)
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
