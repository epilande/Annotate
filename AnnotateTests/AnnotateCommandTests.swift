import AppIntents
import XCTest

@testable import Annotate

@MainActor
final class AnnotateCommandTests: XCTestCase {
    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!
    var screen: NSScreen!
    var overlay: OverlayWindow!
    /// Stands in for the macOS privacy prompt in capture tests.
    var privacyPromptUp = false
    /// Messages a capture reported in an alert, which tests record instead of showing.
    var captureProblemAlerts: [String] = []
    /// The detail text of each alert in `captureProblemAlerts`.
    var captureProblemDetails: [String] = []

    override func setUp() {
        super.setUp()
        TestWindows.recordOpenWindows()
        testDefaults = TestUserDefaults.create()
        BoardManager.shared = BoardManager(userDefaults: testDefaults)
        ShortcutManager.shared = ShortcutManager(userDefaults: testDefaults)

        appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        // Commands that open the overlay use the display under the pointer.
        screen = NSScreen.screens.first
        overlay = appDelegate.overlayWindows[screen]
        appDelegate.pointerLocationOverride = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    override func tearDown() {
        appDelegate.overlayWindows.values.forEach { $0.stopFadeLoop() }
        appDelegate.tearDownAfterLaunch()
        appDelegate = nil
        overlay = nil
        screen = nil
        assertNoLeakedWindows()
        TestUserDefaults.removeSuite()
        testDefaults = nil
        super.tearDown()
    }

    @discardableResult
    private func run(_ command: AnnotateCommand) -> AnnotateCommand.Outcome {
        command.run(on: appDelegate)
    }

    /// Ends the run-loop pass, which closes the undo group AppKit opens per event. A Shortcuts
    /// action runs in a pass of its own, after the passes that typed into the label.
    private func endEvent() {
        wait(for: 0.01)
    }

    /// Types through the field editor, as a user does, so the field's own value is stale until
    /// editing ends.
    private func typeIntoActiveLabel(_ text: String, on view: OverlayView) throws {
        let field = try XCTUnwrap(view.activeTextField)
        try XCTUnwrap(field.currentEditor(), "The label must be in an editing session").string = text
    }

    private var visibleOverlays: [OverlayWindow] {
        appDelegate.overlayWindows.values.filter(\.isVisible)
    }

    private func feedbackText(on window: OverlayWindow) -> String? {
        window.currentFeedbackView?.subviews.lazy.compactMap { $0 as? NSTextField }.first?.stringValue
    }

    // MARK: - Palette

    func testPaletteColorNamesThePickerColorsInOrder() {
        XCTAssertEqual(colorPalette, PaletteColor.allCases.map(\.nsColor))
        XCTAssertEqual(
            PaletteColor.allCases.map(\.rawValue),
            ["red", "orange", "yellow", "green", "cyan", "indigo", "magenta", "white", "black"])
        XCTAssertEqual(PaletteColor.indigo.displayName, "Indigo")
    }

    func testSwitchResolvesAgainstTheCurrentState() {
        XCTAssertTrue(CommandSwitch.on.resolve(current: true))
        XCTAssertTrue(CommandSwitch.on.resolve(current: false))
        XCTAssertFalse(CommandSwitch.off.resolve(current: true))
        XCTAssertFalse(CommandSwitch.off.resolve(current: false))
        XCTAssertFalse(CommandSwitch.toggle.resolve(current: true))
        XCTAssertTrue(CommandSwitch.toggle.resolve(current: false))
    }

    // MARK: - Show, hide, toggle

    func testShowOpensTheInteractiveOverlayUnderThePointer() {
        run(.show)
        XCTAssertTrue(overlay.isVisible)
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.overlayView.isReadOnlyMode)

        run(.show)
        XCTAssertTrue(overlay.isVisible, "Show must not close an open overlay")
    }

    func testShowLeavesAlwaysOnForTheInteractiveOverlay() {
        appDelegate.toggleAlwaysOnMode()
        XCTAssertTrue(overlay.isVisible)
        XCTAssertTrue(overlay.overlayView.isReadOnlyMode)

        run(.show)

        XCTAssertFalse(appDelegate.alwaysOnMode)
        XCTAssertFalse(testDefaults.settings[.alwaysOnMode])
        XCTAssertTrue(overlay.isVisible)
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.overlayView.isReadOnlyMode)
        XCTAssertEqual(visibleOverlays.map(ObjectIdentifier.init), [ObjectIdentifier(overlay)])
    }

    func testHideClosesTheOverlayWhenThePointerIsOnAnotherDisplay() {
        run(.show)
        XCTAssertTrue(overlay.isVisible)
        // Off every display, so a pointer-based close finds nothing.
        appDelegate.pointerLocationOverride = NSPoint(x: -1_000_000, y: -1_000_000)

        run(.hide)

        XCTAssertTrue(visibleOverlays.isEmpty)
    }

    func testHideLeavesAlwaysOn() {
        appDelegate.toggleAlwaysOnMode()
        XCTAssertFalse(visibleOverlays.isEmpty)

        run(.hide)

        XCTAssertFalse(appDelegate.alwaysOnMode)
        XCTAssertFalse(testDefaults.settings[.alwaysOnMode])
        XCTAssertTrue(visibleOverlays.isEmpty)
    }

    func testToggleOpensThenClosesTheOverlay() {
        run(.toggle)
        XCTAssertTrue(overlay.isVisible)
        run(.toggle)
        XCTAssertFalse(overlay.isVisible)
    }

    // MARK: - Tool and color

    func testToolOpensTheOverlayWithTheToolAndItsHUD() {
        run(.tool(.arrow))

        XCTAssertTrue(overlay.isVisible)
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .arrow)
        }
        XCTAssertEqual(testDefaults.settings[.lastUsedTool], .arrow)
        XCTAssertEqual(feedbackText(on: overlay)?.contains("Arrow"), true)
    }

    func testToolLeavesAlwaysOn() {
        appDelegate.toggleAlwaysOnMode()

        run(.tool(.rectangle))

        XCTAssertFalse(appDelegate.alwaysOnMode)
        XCTAssertTrue(overlay.isVisible)
        XCTAssertFalse(overlay.overlayView.isReadOnlyMode)
        XCTAssertEqual(overlay.overlayView.currentTool, .rectangle)
    }

    func testColorSetsTheColorWithoutOpeningTheOverlay() {
        run(.color(.green))

        XCTAssertTrue(visibleOverlays.isEmpty)
        XCTAssertEqual(appDelegate.currentColor, .systemGreen)
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.currentColor, .systemGreen)
        }
        XCTAssertTrue(testDefaults.settings[.selectedColor].isClose(to: .systemGreen))
        XCTAssertEqual(CursorHighlightManager.shared.annotationColor, .systemGreen)
    }

    func testColorShowsItsHUDOnTheOpenOverlay() {
        run(.show)
        run(.color(.indigo))
        XCTAssertEqual(feedbackText(on: overlay), "🎨 Indigo")
    }

    // MARK: - Clear

    func testClearClearsTheOpenOverlayEvenWhenItIsNotKey() {
        run(.show)
        appDelegate.overlayKeyWindowOverride = false
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())

        // The menu's Clear All only acts on the key overlay.
        appDelegate.clearAllAnnotations()
        XCTAssertEqual(overlay.overlayView.paths.count, 1)

        run(.clear)
        XCTAssertTrue(overlay.overlayView.paths.isEmpty)
        XCTAssertEqual(feedbackText(on: overlay), "🗑️ Cleared")
    }

    func testClearClearsEveryDisplayInAlwaysOn() {
        appDelegate.toggleAlwaysOnMode()
        appDelegate.overlayWindows.values.forEach {
            $0.overlayView.arrows.append(TestFactory.createArrow())
        }

        run(.clear)

        for window in appDelegate.overlayWindows.values {
            XCTAssertTrue(window.overlayView.arrows.isEmpty)
        }
    }

    func testOneUndoAfterClearOnTwoDisplaysRestoresBoth() throws {
        // The status menu sits in every display's menu bar, so its Undo follows the pointer
        // (#122). ⌘Z and the toolbar act on their own overlay. Each overlay keeps its own undo
        // stack, and the clear links its step on each, so one Undo anywhere restores both.
        // `LinkedClearTests` covers the same without a second display.
        let screens = NSScreen.screens
        try XCTSkipUnless(screens.count > 1, "Needs a second display")
        appDelegate.toggleAlwaysOnMode()
        let first = try XCTUnwrap(appDelegate.overlayWindows[screens[0]])
        let second = try XCTUnwrap(appDelegate.overlayWindows[screens[1]])
        for window in [first, second] {
            window.overlayView.arrows.append(TestFactory.createArrow())
        }
        endEvent()

        run(.clear)
        endEvent()
        appDelegate.pointerLocationOverride = NSPoint(x: screens[1].frame.midX, y: screens[1].frame.midY)
        appDelegate.undo()
        endEvent()

        XCTAssertEqual(second.overlayView.arrows.count, 1, "The display under the pointer is restored")
        XCTAssertEqual(first.overlayView.arrows.count, 1, "So is the other display")

        first.overlayView.redo()
        XCTAssertTrue(first.overlayView.arrows.isEmpty)
        XCTAssertTrue(second.overlayView.arrows.isEmpty, "One Redo clears both again")
    }

    func testClearCommitsANewLabelBeingTypedSoUndoRestoresIt() throws {
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        // Committing stamps the label with the current time, and Undo drops annotations past
        // their fade. A CI stall longer than the 1.25 s fade would leave nothing to restore.
        view.fadeMode = false
        let point = NSPoint(x: 100, y: 100)
        view.currentTextAnnotation = TextAnnotation(
            text: "", position: point, color: .red, fontSize: defaultTextAnnotationFontSize)
        view.createTextField(at: point, withText: "")
        try typeIntoActiveLabel("Draft", on: view)
        endEvent()

        XCTAssertEqual(run(.clear), .ran)
        endEvent()
        XCTAssertNil(view.activeTextField)
        XCTAssertTrue(view.textAnnotations.isEmpty)

        view.undo()
        XCTAssertEqual(view.textAnnotations.map(\.text), ["Draft"])
    }

    func testClearCommitsAnEditInProgressSoUndoRestoresTheNewText() throws {
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        // Committing stamps the label with the current time, and Undo drops annotations past
        // their fade. A CI stall longer than the 1.25 s fade would leave nothing to restore.
        view.fadeMode = false
        let label = TextAnnotation(
            text: "Before",
            position: NSPoint(x: 100, y: 100),
            color: .red,
            fontSize: defaultTextAnnotationFontSize)
        view.textAnnotations = [label]
        // As a double-click on the label starts an edit.
        view.editingTextAnnotationIndex = 0
        view.currentTextAnnotation = label
        view.createTextField(at: label.position, withText: label.text)
        try typeIntoActiveLabel("After", on: view)
        endEvent()

        run(.clear)
        endEvent()
        XCTAssertTrue(view.textAnnotations.isEmpty)

        view.undo()
        XCTAssertEqual(view.textAnnotations.map(\.text), ["After"])
    }

    func testClearAfterEmptyingALabelInAnEditLetsUndoRestoreIt() throws {
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        let label = TextAnnotation(
            text: "Before",
            position: NSPoint(x: 100, y: 100),
            color: .red,
            fontSize: defaultTextAnnotationFontSize)
        view.textAnnotations = [label]
        view.paths.append(TestFactory.createDrawingPath())
        view.editingTextAnnotationIndex = 0
        view.currentTextAnnotation = label
        view.createTextField(at: label.position, withText: label.text)
        try typeIntoActiveLabel("", on: view)
        endEvent()

        run(.clear)
        endEvent()
        XCTAssertTrue(view.textAnnotations.isEmpty)
        XCTAssertTrue(view.paths.isEmpty)

        view.undo()
        XCTAssertEqual(view.textAnnotations.map(\.text), ["Before"])
        XCTAssertEqual(view.paths.count, 1)
    }

    func testClearShowsItsHUDOnlyWhenItClearedSomething() {
        run(.show)
        XCTAssertEqual(run(.clear), .noOp)
        XCTAssertNil(overlay.currentFeedbackView)

        overlay.overlayView.paths.append(TestFactory.createDrawingPath())
        XCTAssertEqual(run(.clear), .ran)
        XCTAssertEqual(feedbackText(on: overlay), "🗑️ Cleared")
    }

    func testClearLeavesAHiddenOverlayAlone() {
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())
        XCTAssertFalse(appDelegate.clearVisibleOverlays())
        XCTAssertEqual(overlay.overlayView.paths.count, 1)
    }

    // MARK: - Toolbar, fade, board

    func testToolbarSwitchesWithoutOpeningTheOverlay() {
        XCTAssertTrue(appDelegate.toolbarVisible)

        run(.toolbar(.off))
        XCTAssertFalse(testDefaults.settings[.toolbarVisible])
        run(.toolbar(.off))
        XCTAssertFalse(testDefaults.settings[.toolbarVisible], "Off must not toggle")
        run(.toolbar(.toggle))
        XCTAssertTrue(testDefaults.settings[.toolbarVisible])
        run(.toolbar(.on))
        XCTAssertTrue(testDefaults.settings[.toolbarVisible], "On must not toggle")

        XCTAssertTrue(visibleOverlays.isEmpty)
    }

    func testToolbarShowsItsHUDOnTheOpenOverlay() {
        run(.show)
        run(.toolbar(.off))
        XCTAssertEqual(feedbackText(on: overlay), "🧰 Toolbar Off")
    }

    func testCommandHUDHonorsHideToolFeedback() {
        testDefaults.settings[.hideToolFeedback] = true
        run(.show)
        run(.toolbar(.off))
        XCTAssertNil(overlay.currentFeedbackView)
    }

    func testFadeOnAndOffSetEveryOverlay() {
        run(.fade(.on))
        XCTAssertTrue(testDefaults.settings[.fadeMode])
        run(.fade(.on))
        XCTAssertTrue(testDefaults.settings[.fadeMode], "On must not toggle")
        for window in appDelegate.overlayWindows.values {
            XCTAssertTrue(window.overlayView.fadeMode)
        }

        run(.fade(.off))
        XCTAssertFalse(testDefaults.settings[.fadeMode])
        for window in appDelegate.overlayWindows.values {
            XCTAssertFalse(window.overlayView.fadeMode)
        }

        run(.fade(.toggle))
        XCTAssertTrue(testDefaults.settings[.fadeMode])
    }

    func testFadeInAlwaysOnIsStoredForWhenItEnds() {
        run(.fade(.off))
        appDelegate.toggleAlwaysOnMode()

        run(.fade(.on))
        XCTAssertTrue(testDefaults.settings[.fadeMode])
        XCTAssertFalse(overlay.overlayView.fadeMode, "Always-On annotations must not fade")

        appDelegate.toggleAlwaysOnMode()
        XCTAssertTrue(overlay.overlayView.fadeMode)
    }

    func testBoardSwitches() {
        XCTAssertFalse(BoardManager.shared.isEnabled)

        run(.board(.on))
        XCTAssertTrue(BoardManager.shared.isEnabled)
        XCTAssertTrue(testDefaults.settings[.enableBoard])
        run(.board(.on))
        XCTAssertTrue(BoardManager.shared.isEnabled, "On must not toggle")
        run(.board(.toggle))
        XCTAssertFalse(BoardManager.shared.isEnabled)
        run(.board(.off))
        XCTAssertFalse(BoardManager.shared.isEnabled, "Off must not toggle")

        XCTAssertTrue(visibleOverlays.isEmpty)
    }

    // MARK: - Outcome

    func testCommandsReportWhetherTheyChangedAnything() {
        XCTAssertEqual(run(.hide), .noOp, "Nothing is open")
        XCTAssertEqual(run(.show), .ran)
        XCTAssertEqual(run(.show), .noOp, "Already open")
        XCTAssertEqual(run(.tool(.arrow)), .ran)
        XCTAssertEqual(run(.tool(.arrow)), .noOp)
        XCTAssertEqual(run(.color(.cyan)), .ran)
        XCTAssertEqual(run(.color(.cyan)), .noOp)
        XCTAssertEqual(run(.toolbar(.off)), .ran)
        XCTAssertEqual(run(.toolbar(.off)), .noOp)
        XCTAssertEqual(run(.fade(.toggle)), .ran)
        XCTAssertEqual(run(.board(.off)), .noOp, "The board starts off")
        XCTAssertEqual(run(.board(.on)), .ran)
        XCTAssertEqual(run(.hide), .ran)
        XCTAssertEqual(run(.toggle), .ran)
    }

    // MARK: - Path form

    static let everyCommand: [AnnotateCommand] =
        [.toggle, .show, .hide, .clear]
        + ToolType.allCases.map(AnnotateCommand.tool)
        + PaletteColor.allCases.map(AnnotateCommand.color)
        + CommandSwitch.allCases.flatMap { [.toolbar($0), .fade($0), .board($0)] }
        + CaptureScope.allCases.map(AnnotateCommand.capture)

    func testEveryCommandRoundTripsThroughItsPath() {
        for command in Self.everyCommand {
            XCTAssertEqual(AnnotateCommand(path: command.path), command, command.path)
        }
        XCTAssertEqual(Set(Self.everyCommand.map(\.path)).count, Self.everyCommand.count)
    }

    func testPathsAreStable() {
        XCTAssertEqual(AnnotateCommand.toggle.path, "/toggle")
        XCTAssertEqual(AnnotateCommand.tool(.highlighter).path, "/tool/highlighter")
        XCTAssertEqual(AnnotateCommand.color(.indigo).path, "/color/indigo")
        XCTAssertEqual(AnnotateCommand.toolbar(.off).path, "/toolbar/off")
        XCTAssertEqual(AnnotateCommand.fade(.toggle).path, "/fade/toggle")
        XCTAssertEqual(AnnotateCommand.board(.on).path, "/board/on")
        XCTAssertEqual(AnnotateCommand.capture(.screen).path, "/capture/screen")
        XCTAssertEqual(AnnotateCommand.capture(.area).path, "/capture/area")
    }

    func testPathParsingIsLenientAboutSlashesAndCase() {
        XCTAssertEqual(AnnotateCommand(path: "show"), .show)
        XCTAssertEqual(AnnotateCommand(path: "/show/"), .show)
        XCTAssertEqual(AnnotateCommand(path: "/Tool/Arrow"), .tool(.arrow))
        XCTAssertEqual(AnnotateCommand(path: "color/RED/"), .color(.red))
    }

    func testPathParsingRejectsMalformedPaths() {
        let invalid = [
            "", "/", "//", "/nope", "/tool", "/tool/", "/tool/brush", "/color/purple",
            "/toolbar", "/toolbar/maybe", "/show/now", "/clear/all", "/tool/arrow/extra",
            "//show", "/fade//on", "/capture", "/capture/window",
        ]
        for path in invalid {
            XCTAssertNil(AnnotateCommand(path: path), path)
        }
    }

    // MARK: - Capture

    /// Points the app's captures at a stub source, a temporary folder, and a private pasteboard.
    /// Without a `source`, every capture is a solid blue screen.
    @discardableResult
    private func useStubCapture(
        canCapture: Bool = true, source: DisplayCapturing? = nil
    ) throws -> (folder: URL, pasteboard: NSPasteboard) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotateCommandTests-\(UUID().uuidString)", isDirectory: true)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnnotateCommandTests-\(UUID().uuidString)"))
        addTeardownBlock { @MainActor in
            try? FileManager.default.removeItem(at: folder)
            pasteboard.releaseGlobally()
        }
        let pixelSize = screen.frame.size.applying(
            CGAffineTransform(scaleX: screen.backingScaleFactor, y: screen.backingScaleFactor))
        let snapshot = CaptureTestImages.solid(
            width: Int(pixelSize.width), height: Int(pixelSize.height), RGBA(r: 0, g: 0, b: 255, a: 255))
        privacyPromptUp = false
        appDelegate.isPrivacyPromptOnScreen = { [unowned self] in self.privacyPromptUp }
        captureProblemAlerts = []
        captureProblemDetails = []
        appDelegate.showCaptureProblemAlert = { [unowned self] message, detail in
            self.captureProblemAlerts.append(message)
            self.captureProblemDetails.append(detail)
        }
        appDelegate.privacyPromptPollInterval = 0.02
        appDelegate.captureService = CaptureService(
            source: source ?? StubDisplayCapturing(canCapture: canCapture, snapshotImage: snapshot),
            sinks: [FileSink(folder: folder), ClipboardSink(pasteboard: pasteboard)])
        return (folder, pasteboard)
    }

    /// A 40 point solid redaction at the display's bottom-left corner.
    private var solidRedactionInTheCorner: Rectangle {
        Rectangle(
            startPoint: .zero,
            endPoint: NSPoint(x: 40, y: 40),
            color: .black,
            lineWidth: 1,
            style: .solid)
    }

    func testCaptureSavesAndCopiesTheDisplayWithItsAnnotations() async throws {
        let (folder, pasteboard) = try useStubCapture()
        run(.show)
        overlay.overlayView.rectangles = [solidRedactionInTheCorner]

        XCTAssertEqual(run(.capture(.screen)), .ran)
        await appDelegate.captureTask?.value

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(feedbackText(on: overlay), "📸 Saved \(file)")
        let png = try XCTUnwrap(pasteboard.data(forType: .png))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png)?.cgImage)
        // The solid redaction at the display's bottom-left corner.
        let corner = CaptureTestImages.pixel(image, x: 4, y: image.height - 4)
        XCTAssertTrue(corner.isClose(to: RGBA(r: 0, g: 0, b: 0, a: 255)), "\(corner)")
        let middle = CaptureTestImages.pixel(image, x: image.width / 2, y: image.height / 2)
        XCTAssertTrue(middle.isClose(to: RGBA(r: 0, g: 0, b: 255, a: 255)), "\(middle)")
    }

    func testCaptureCommitsALabelBeingTyped() async throws {
        try useStubCapture()
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        // Committing stamps the label with the current time; keep it from fading mid-test.
        view.fadeMode = false
        let point = NSPoint(x: 100, y: 100)
        view.currentTextAnnotation = TextAnnotation(
            text: "", position: point, color: .red, fontSize: defaultTextAnnotationFontSize)
        view.createTextField(at: point, withText: "")
        try typeIntoActiveLabel("Hello", on: view)
        endEvent()

        run(.capture(.screen))
        await appDelegate.captureTask?.value

        XCTAssertNil(view.activeTextField)
        XCTAssertEqual(view.textAnnotations.map(\.text), ["Hello"])
    }

    /// Opens the overlay with a label being typed, as `testCaptureCommitsALabelBeingTyped` does.
    private func startTypingALabel(_ text: String) throws -> OverlayView {
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        view.fadeMode = false
        let point = NSPoint(x: 100, y: 100)
        view.currentTextAnnotation = TextAnnotation(
            text: "", position: point, color: .red, fontSize: defaultTextAnnotationFontSize)
        view.createTextField(at: point, withText: "")
        try typeIntoActiveLabel(text, on: view)
        endEvent()
        return view
    }

    private func keyDown(_ key: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(
            TestEvents.createKeyEvent(
                type: .keyDown,
                keyCode: 1,
                modifierFlags: modifiers,
                characters: key,
                windowNumber: overlay.windowNumber))
    }

    func testCommandSWhileTypingALabelCommitsItAndCaptures() async throws {
        let (folder, _) = try useStubCapture()
        let view = try startTypingALabel("Hello")

        // AppKit offers a Command chord to the window as a key equivalent before the field editor.
        XCTAssertTrue(overlay.performKeyEquivalent(with: try keyDown("s", modifiers: .command)))
        await appDelegate.captureTask?.value

        XCTAssertNil(view.activeTextField)
        XCTAssertEqual(view.textAnnotations.map(\.text), ["Hello"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }

    func testCaptureBoundToABareLetterStillTypesIntoALabel() throws {
        try useStubCapture()
        XCTAssertTrue(ShortcutManager.shared.setShortcut(ShortcutBinding("q"), for: .captureScreen))
        let view = try startTypingALabel("Hi")

        overlay.sendEvent(try keyDown("q"))

        XCTAssertNil(appDelegate.captureTask, "Only a Command binding fires while typing")
        XCTAssertNotNil(view.activeTextField)
    }

    func testCaptureWithTheOverlayHiddenSavesThePlainScreen() async throws {
        let (folder, _) = try useStubCapture()
        overlay.overlayView.rectangles = [solidRedactionInTheCorner]

        XCTAssertEqual(run(.capture(.screen)), .ran)
        await appDelegate.captureTask?.value

        XCTAssertTrue(visibleOverlays.isEmpty)
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let image = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: file))?.cgImage)
        let corner = CaptureTestImages.pixel(image, x: 4, y: image.height - 4)
        XCTAssertTrue(corner.isClose(to: RGBA(r: 0, g: 0, b: 255, a: 255)), "\(corner)")
    }

    func testOverlappingCapturesFinishInTheOrderTheyWereAskedFor() async throws {
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
        // Small snapshots keep the newer capture quick, so without ordering it would land first.
        let source = GatedDisplayCapturing(images: [
            CaptureTestImages.solid(width: 32, height: 20, red),
            CaptureTestImages.solid(width: 32, height: 20, blue),
        ])
        let (folder, pasteboard) = try useStubCapture(source: source)
        run(.show)

        run(.capture(.screen))
        run(.capture(.screen))
        // Give the second capture time to overtake the held first one if nothing orders them.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(source.captureCount, 1, "The second capture must wait for the first to finish")
        source.open()
        await appDelegate.captureTask?.value
        // Unordered, the held capture would still be running here; let it finish too, so the
        // assertions below see where it lands.
        var files: [URL] = []
        for _ in 0..<300 {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            if files.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(source.captureCount, 2)
        XCTAssertEqual(files.count, 2, "Each capture keeps its own file")
        let png = try XCTUnwrap(pasteboard.data(forType: .png))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png)?.cgImage)
        let pixel = CaptureTestImages.pixel(image, x: 16, y: 10)
        XCTAssertTrue(pixel.isClose(to: blue), "The newer capture must end up on the clipboard: \(pixel)")
        let newest = try XCTUnwrap(files.first { (try? Data(contentsOf: $0)) == png })
        XCTAssertEqual(feedbackText(on: overlay), "📸 Saved \(newest.lastPathComponent)")
    }

    /// Runs the run loop until `condition` holds or `timeout` passes. Synchronous on purpose:
    /// an async test holds the main queue, so delayed main-queue work would never run.
    private func runLoop(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = CACurrentMediaTime() + timeout
        while !condition(), CACurrentMediaTime() < deadline {
            wait(for: 0.01)
        }
    }

    func testCaptureWithoutScreenRecordingClosesTheOverlayAndOpensCaptureSettings() throws {
        let (folder, _) = try useStubCapture(canCapture: false)
        appDelegate.screenRecordingNoticeDelay = 0.3
        var opened: [(SettingsPane, Bool)] = []
        appDelegate.openSettingsPane = { pane, request, _ in opened.append((pane, request)) }
        run(.show)
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())

        XCTAssertEqual(run(.capture(.screen)), .ran)
        runLoop { self.feedbackText(on: self.overlay) != nil }

        XCTAssertEqual(feedbackText(on: overlay), "🔒 Screen Recording is off. Opening Settings…")
        XCTAssertTrue(opened.isEmpty, "Settings waits for the notice")
        XCTAssertTrue(appDelegate.isInteractiveOverlayOpen)
        runLoop { !opened.isEmpty }
        XCTAssertFalse(appDelegate.isInteractiveOverlayOpen)
        XCTAssertEqual(opened.map(\.0), [.capture])
        XCTAssertEqual(opened.map(\.1), [true])
        XCTAssertEqual(overlay.overlayView.paths.count, 1, "Annotations survive the close")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    /// How many times a capture opened Settings in the current test.
    private var settingsOpenCount = 0

    /// Opens Always-On, asks for a capture without Screen Recording, and returns the overlays
    /// that were up, the ones still up when Settings opened, and the Settings close handler.
    private func denyCaptureInAlwaysOn() throws -> (
        alwaysOn: Set<ObjectIdentifier>, visibleAtOpen: Set<ObjectIdentifier>, closeSettings: @MainActor () -> Void
    ) {
        try useStubCapture(canCapture: false)
        appDelegate.screenRecordingNoticeDelay = 0
        var visibleAtOpen: Set<ObjectIdentifier>?
        var closeSettings: (@MainActor () -> Void)?
        appDelegate.openSettingsPane = { _, _, onClose in
            self.settingsOpenCount += 1
            visibleAtOpen = Set(self.visibleOverlays.map(ObjectIdentifier.init))
            closeSettings = onClose
        }
        appDelegate.toggleAlwaysOnMode()
        let alwaysOn = Set(visibleOverlays.map(ObjectIdentifier.init))
        XCTAssertFalse(alwaysOn.isEmpty)
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())

        XCTAssertEqual(run(.capture(.screen)), .ran)
        runLoop { closeSettings != nil }
        return (alwaysOn, try XCTUnwrap(visibleAtOpen), try XCTUnwrap(closeSettings))
    }

    func testCaptureWithoutScreenRecordingInAlwaysOnClearsOverlaysUntilSettingsCloses() throws {
        let (alwaysOn, visibleAtOpen, closeSettings) = try denyCaptureInAlwaysOn()

        XCTAssertTrue(visibleAtOpen.isEmpty, "Always-On annotations must not cover Settings or the prompt")
        XCTAssertTrue(appDelegate.alwaysOnMode, "Always-On stays on")

        closeSettings()
        XCTAssertEqual(Set(visibleOverlays.map(ObjectIdentifier.init)), alwaysOn)
        XCTAssertEqual(overlay.overlayView.paths.count, 1, "Annotations survive")
    }

    func testOverlaysStayHiddenWhenAlwaysOnEndsBeforeSettingsCloses() throws {
        let (_, _, closeSettings) = try denyCaptureInAlwaysOn()

        appDelegate.toggleAlwaysOnMode()
        closeSettings()

        XCTAssertTrue(visibleOverlays.isEmpty)
    }

    func testAlwaysOnOverlaysWaitForThePrivacyPromptToClose() throws {
        let (alwaysOn, _, closeSettings) = try denyCaptureInAlwaysOn()
        // Settings asked, and macOS put its prompt up.
        privacyPromptUp = true

        // A second capture while the prompt is up must leave Settings closed and the prompt on top.
        XCTAssertEqual(run(.capture(.screen)), .ran)
        wait(for: 0.1)
        XCTAssertEqual(settingsOpenCount, 1, "Settings must not open over the prompt")

        closeSettings()
        wait(for: 0.1)
        XCTAssertTrue(visibleOverlays.isEmpty, "Overlays must not come back over the prompt")

        privacyPromptUp = false
        runLoop { !self.visibleOverlays.isEmpty }
        XCTAssertEqual(Set(visibleOverlays.map(ObjectIdentifier.init)), alwaysOn)
    }

    func testDeniedCaptureWhileThePromptIsUpLeavesSettingsClosed() throws {
        try useStubCapture(canCapture: false)
        appDelegate.screenRecordingNoticeDelay = 0.3
        appDelegate.openSettingsPane = { _, _, _ in self.settingsOpenCount += 1 }
        privacyPromptUp = true
        run(.show)

        XCTAssertEqual(run(.capture(.screen)), .ran)
        runLoop { self.feedbackText(on: self.overlay) != nil }
        XCTAssertEqual(feedbackText(on: overlay), "🔒 Screen Recording is off. Answer the macOS prompt")
        // The overlay still closes, or it would cover the prompt.
        runLoop { !self.appDelegate.isInteractiveOverlayOpen }
        wait(for: 0.1)

        XCTAssertFalse(appDelegate.isInteractiveOverlayOpen)
        XCTAssertEqual(settingsOpenCount, 0)
    }

    func testPrivacyPromptIsFoundByItsHelpersWindows() {
        let windows: [[String: Any]] = [
            [kCGWindowOwnerPID as String: NSNumber(value: 10)],
            [kCGWindowOwnerPID as String: NSNumber(value: 42)],
        ]
        XCTAssertTrue(SystemPrivacyPrompt.hasWindow(ownedBy: [42], in: windows))
        XCTAssertFalse(SystemPrivacyPrompt.hasWindow(ownedBy: [7], in: windows))
        XCTAssertFalse(SystemPrivacyPrompt.hasWindow(ownedBy: [42], in: []))
    }

    func testDeniedCaptureKeepsDrawingsWithClearDrawingsOnStart() throws {
        try useStubCapture(canCapture: false)
        appDelegate.screenRecordingNoticeDelay = 0
        appDelegate.openSettingsPane = { _, _, _ in }
        testDefaults.settings[.clearDrawingsOnStart] = true
        run(.show)
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())

        run(.capture(.screen))
        runLoop { !self.appDelegate.isInteractiveOverlayOpen }
        run(.show)
        XCTAssertEqual(overlay.overlayView.paths.count, 1, "The app closed the overlay, not the user")

        // The exemption is used up: a close by the user clears on the next open as usual.
        run(.hide)
        run(.show)
        XCTAssertTrue(overlay.overlayView.paths.isEmpty)
    }

    func testCaptureFailureWithTheOverlayClosedIsReported() async throws {
        try useStubCapture(source: StubDisplayCapturing(snapshotImage: nil))
        XCTAssertTrue(visibleOverlays.isEmpty)

        // The status menu item, as in the live check.
        appDelegate.captureScreen()
        await appDelegate.captureTask?.value

        XCTAssertEqual(captureProblemAlerts, ["Capture Failed"])
        XCTAssertEqual(captureProblemDetails, ["Annotate couldn't finish the capture. Try again in a moment."])
    }

    func testCaptureFailureWithToolFeedbackHiddenStillShowsAnAlert() async throws {
        try useStubCapture(source: StubDisplayCapturing(snapshotImage: nil))
        testDefaults.settings[.hideToolFeedback] = true
        run(.show)

        appDelegate.captureScreen()
        await appDelegate.captureTask?.value

        XCTAssertNil(feedbackText(on: overlay))
        XCTAssertEqual(captureProblemAlerts, ["Capture Failed"], "A failure is never silent")
    }

    func testCaptureFailureWithTheOverlayOpenStaysOnTheOverlay() async throws {
        try useStubCapture(source: StubDisplayCapturing(snapshotImage: nil))
        run(.show)

        appDelegate.captureScreen()
        await appDelegate.captureTask?.value

        XCTAssertEqual(feedbackText(on: overlay), "⚠️ Capture Failed")
        XCTAssertTrue(captureProblemAlerts.isEmpty)
    }

    func testFailedSaveWithTheOverlayClosedIsReported() async throws {
        try useStubCapture()
        // A regular file where the folder should be makes the save fail; the copy still works.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotateCommandTests-\(UUID().uuidString)")
        try Data().write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnnotateCommandTests-\(UUID().uuidString)"))
        addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
        appDelegate.captureService = CaptureService(
            source: StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 32, height: 20, RGBA(r: 0, g: 0, b: 255, a: 255))),
            sinks: [FileSink(folder: blocker), ClipboardSink(pasteboard: pasteboard)])

        appDelegate.captureScreen()
        await appDelegate.captureTask?.value

        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertEqual(captureProblemAlerts, ["Couldn't Save. Copied to Clipboard"])
        let detail = try XCTUnwrap(captureProblemDetails.first)
        XCTAssertTrue(detail.hasPrefix("The image is on the clipboard, but Annotate couldn't save it."), detail)
        XCTAssertFalse(detail.contains("couldn't finish the capture"), "Only the save failed")
    }

    /// Saves to a temporary folder while every copy to the clipboard fails.
    private func useCaptureWhoseCopyFails() throws -> URL {
        try useStubCapture()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotateCommandTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        appDelegate.captureService = CaptureService(
            source: StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 32, height: 20, RGBA(r: 0, g: 0, b: 255, a: 255))),
            sinks: [FileSink(folder: folder), FailingSink(destination: .clipboard)])
        return folder
    }

    func testFailedCopyWithTheOverlayClosedIsReported() async throws {
        let folder = try useCaptureWhoseCopyFails()

        appDelegate.captureScreen()
        await appDelegate.captureTask?.value

        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: folder.path).first)
        XCTAssertEqual(captureProblemAlerts, ["Couldn't Copy. Saved \(file)"])
        XCTAssertTrue(try XCTUnwrap(captureProblemDetails.first).hasPrefix("The image was saved, but Annotate couldn't copy it"))
    }

    func testFailedCopyWithTheOverlayOpenSaysSoOnTheOverlay() async throws {
        let folder = try useCaptureWhoseCopyFails()
        run(.show)

        appDelegate.captureScreen()
        await appDelegate.captureTask?.value

        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: folder.path).first)
        XCTAssertEqual(feedbackText(on: overlay), "⚠️ Couldn't Copy. Saved \(file)")
        XCTAssertTrue(captureProblemAlerts.isEmpty)
    }

    func testShareableContentListsAppsWhoseWindowsAreOffScreen() {
        // With the overlay closed Annotate has no window on screen. Listing only on-screen
        // windows left it out, so the filter had nothing to exclude and refused to capture.
        XCTAssertFalse(ScreenSampler.listsOnScreenWindowsOnly)
    }

    func testCaptureMenuItemTakesTheShortcut() throws {
        let item = try XCTUnwrap(
            appDelegate.statusItem.menu?.items.first { $0.action == #selector(AppDelegate.captureScreen) })
        XCTAssertEqual(item.title, "Capture Screen")
        XCTAssertEqual(item.keyEquivalent, "s")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    }

    // MARK: - Capture Area

    /// Presses at `start`, drags to `end`, and releases there, through the overlay's own event
    /// routing. Points are in the overlay view's coordinates, which the window shares.
    private func drag(from start: NSPoint, to end: NSPoint) throws {
        let steps: [(NSEvent.EventType, NSPoint)] = [(.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)]
        for (type, point) in steps {
            overlay.sendEvent(
                try XCTUnwrap(TestEvents.createMouseEvent(type: type, location: point, windowNumber: overlay.windowNumber)))
        }
    }

    private func pressEscape() throws {
        overlay.sendEvent(
            try XCTUnwrap(
                TestEvents.createKeyEvent(
                    type: .keyDown, keyCode: 53, characters: "\u{1b}", windowNumber: overlay.windowNumber)))
    }

    func testCaptureAreaOpensTheOverlayAndSavesTheDraggedArea() async throws {
        let (folder, pasteboard) = try useStubCapture()
        XCTAssertTrue(visibleOverlays.isEmpty)

        XCTAssertEqual(run(.capture(.area)), .ran)

        XCTAssertTrue(appDelegate.isInteractiveOverlayOpen)
        XCTAssertTrue(overlay.isRegionPickerOpen)
        XCTAssertNil(appDelegate.captureTask, "Nothing is captured before the drag")
        overlay.overlayView.rectangles = [solidRedactionInTheCorner]

        // Up and to the left, from (80, 60) to the display's bottom-left corner.
        try drag(from: NSPoint(x: 80, y: 60), to: .zero)
        XCTAssertFalse(overlay.isRegionPickerOpen)
        await appDelegate.captureTask?.value

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(feedbackText(on: overlay), "📸 Saved \(try XCTUnwrap(files.first))")
        let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(pasteboard.data(forType: .png)))?.cgImage)
        let scale = screen.backingScaleFactor
        XCTAssertEqual(image.width, Int(80 * scale))
        XCTAssertEqual(image.height, Int(60 * scale))
        // The 40 point solid redaction in the bottom-left corner, and the screen beside it.
        let corner = CaptureTestImages.pixel(image, x: 4, y: image.height - 4)
        XCTAssertTrue(corner.isClose(to: RGBA(r: 0, g: 0, b: 0, a: 255)), "\(corner)")
        let topRight = CaptureTestImages.pixel(image, x: image.width - 4, y: 4)
        XCTAssertTrue(topRight.isClose(to: RGBA(r: 0, g: 0, b: 255, a: 255)), "\(topRight)")
    }

    func testEscapeCancelsCaptureAreaAndKeepsTheOverlayOpen() throws {
        try useStubCapture()
        run(.show)
        let toolbarWasAttached = overlay.toolbarPanel?.isAttached
        run(.capture(.area))
        XCTAssertTrue(overlay.isRegionPickerOpen)
        XCTAssertEqual(overlay.toolbarPanel?.isAttached ?? false, false, "The whole display can be picked")

        try pressEscape()

        XCTAssertFalse(overlay.isRegionPickerOpen)
        XCTAssertTrue(appDelegate.isInteractiveOverlayOpen, "Escape closes only the picker")
        XCTAssertFalse(overlay.overlayView.isFadeFrozen)
        XCTAssertEqual(overlay.toolbarPanel?.isAttached, toolbarWasAttached)
        XCTAssertNil(appDelegate.captureTask)
    }

    func testCaptureAreaHoldsTheFadeAndCapturesAtTheHeldTime() async throws {
        let (_, pasteboard) = try useStubCapture()
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        var clock: CFTimeInterval = 1000
        view.fadeClock = { clock }
        view.fadeMode = true
        // A thick red outline around the bottom-left corner, made just now.
        var outline = Rectangle(
            startPoint: .zero, endPoint: NSPoint(x: 40, y: 40), color: .red, lineWidth: 20, style: .outline)
        outline.creationTime = clock
        view.rectangles = [outline]

        run(.capture(.area))
        XCTAssertTrue(view.isFadeFrozen)
        XCTAssertNil(overlay.fadeTimer, "A held fade has nothing to animate")
        // The drag takes far longer than the outline lasts.
        clock += view.fadeDuration * 10
        XCTAssertEqual(view.fadeClock(), 1000)

        try drag(from: .zero, to: NSPoint(x: 80, y: 60))

        XCTAssertFalse(view.isFadeFrozen)
        XCTAssertEqual(view.fadeClock(), clock, "The fade runs on the real clock again")
        XCTAssertTrue(view.rectangles.isEmpty, "Once the picker closes the outline is past its fade")
        await appDelegate.captureTask?.value
        let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(pasteboard.data(forType: .png)))?.cgImage)
        let corner = CaptureTestImages.pixel(image, x: 2, y: image.height - 2)
        XCTAssertTrue(corner.isClose(to: RGBA(r: 255, g: 0, b: 0, a: 255), tolerance: 40), "Captured as the picker showed it: \(corner)")
    }

    func testCaptureAreaFromAlwaysOnOpensTheInteractiveOverlayWithItsDrawings() throws {
        try useStubCapture()
        testDefaults.settings[.clearDrawingsOnStart] = true
        appDelegate.toggleAlwaysOnMode()
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())

        run(.capture(.area))

        XCTAssertFalse(appDelegate.alwaysOnMode)
        XCTAssertTrue(appDelegate.isInteractiveOverlayOpen)
        XCTAssertTrue(overlay.isRegionPickerOpen)
        XCTAssertEqual(overlay.overlayView.paths.count, 1, "The Always-On drawings were on screen, so they stay")
    }

    /// Enters Always-On in Fade Mode with a thick red outline around the bottom-left corner
    /// made long ago: Always-On holds it in Persist, while Fade Mode would have expired it.
    @discardableResult
    private func showAnOldDrawingInAlwaysOn() throws -> OverlayView {
        testDefaults.settings[.fadeMode] = true
        let view = try XCTUnwrap(overlay.overlayView)
        let clock: CFTimeInterval = 1000
        view.fadeClock = { clock }
        appDelegate.toggleAlwaysOnMode()
        var outline = Rectangle(
            startPoint: .zero, endPoint: NSPoint(x: 40, y: 40), color: .red, lineWidth: 20, style: .outline)
        outline.creationTime = clock - view.fadeDuration * 10
        view.rectangles = [outline]
        return view
    }

    func testCaptureAreaFromAlwaysOnKeepsDrawingsPastTheirFade() async throws {
        let (_, pasteboard) = try useStubCapture()
        let view = try showAnOldDrawingInAlwaysOn()

        run(.capture(.area))

        XCTAssertFalse(appDelegate.alwaysOnMode)
        XCTAssertTrue(overlay.isRegionPickerOpen)
        XCTAssertFalse(view.fadeMode, "Always-On's Persist holds through the pick")
        XCTAssertEqual(view.rectangles.count, 1, "Leaving Always-On must not expire what it showed")

        try drag(from: .zero, to: NSPoint(x: 80, y: 60))
        await appDelegate.captureTask?.value

        let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(pasteboard.data(forType: .png)))?.cgImage)
        let corner = CaptureTestImages.pixel(image, x: 2, y: image.height - 2)
        XCTAssertTrue(corner.isClose(to: RGBA(r: 255, g: 0, b: 0, a: 255), tolerance: 40), "\(corner)")
        XCTAssertTrue(view.fadeMode, "The Fade Mode setting is back once the picker closes")
        XCTAssertTrue(appDelegate.overlaysHoldingAlwaysOnFade.isEmpty)
    }

    func testCaptureAreaFromAlwaysOnGivesFadeModeBackOnEscape() throws {
        try useStubCapture()
        let view = try showAnOldDrawingInAlwaysOn()
        run(.capture(.area))

        try pressEscape()

        XCTAssertTrue(view.fadeMode)
        XCTAssertTrue(appDelegate.overlaysHoldingAlwaysOnFade.isEmpty)
    }

    func testAlwaysOnShortcutWhilePickingClosesThePicker() throws {
        try useStubCapture()
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        run(.capture(.area))
        XCTAssertTrue(overlay.isRegionPickerOpen)

        // The global Always-On shortcut calls this directly, outside the picker's key handling.
        appDelegate.toggleAlwaysOnMode()

        XCTAssertTrue(appDelegate.alwaysOnMode)
        XCTAssertFalse(overlay.isRegionPickerOpen)
        XCTAssertFalse(view.isFadeFrozen)
        XCTAssertFalse(view.subviews.contains { $0 is RegionPicker }, "No dimming left on a click-through overlay")
    }

    func testAlwaysOnShortcutWhilePickingFromAlwaysOnKeepsTheDrawings() throws {
        try useStubCapture()
        let view = try showAnOldDrawingInAlwaysOn()
        run(.capture(.area))

        appDelegate.toggleAlwaysOnMode()

        XCTAssertTrue(appDelegate.alwaysOnMode)
        XCTAssertFalse(view.fadeMode, "Back in Always-On's Persist")
        XCTAssertEqual(view.rectangles.count, 1)
        XCTAssertTrue(appDelegate.overlaysHoldingAlwaysOnFade.isEmpty)
    }

    func testCaptureAreaWithoutScreenRecordingInAlwaysOnKeepsTheDrawings() throws {
        try useStubCapture(canCapture: false)
        appDelegate.screenRecordingNoticeDelay = 0
        var closeSettings: (@MainActor () -> Void)?
        appDelegate.openSettingsPane = { _, _, onClose in closeSettings = onClose }
        let view = try showAnOldDrawingInAlwaysOn()

        run(.capture(.area))
        runLoop { closeSettings != nil }

        XCTAssertFalse(overlay.isRegionPickerOpen)
        XCTAssertTrue(appDelegate.alwaysOnMode, "Asking for access never leaves Always-On")
        try XCTUnwrap(closeSettings)()
        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(view.rectangles.count, 1)
    }

    func testActiveCursorStyleStandsDownWhilePicking() async throws {
        try useStubCapture()
        let original = CursorHighlightManager.shared
        let manager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = manager
        addTeardownBlock { @MainActor in
            manager.showSystemCursor()
            CursorHighlightManager.shared = original
        }
        manager.activeCursorStyle = .circle
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)
        view.updateCursor()
        XCTAssertTrue(manager.shouldShowActiveCursorOnScreen(screen))
        XCTAssertTrue(manager.isCursorHidden)

        // Opening: the crosshair shows, and the canvas asking again doesn't hide it.
        run(.capture(.area))
        XCTAssertFalse(manager.shouldShowActiveCursorOnScreen(screen))
        XCTAssertFalse(manager.isCursorHidden)
        view.updateCursor()
        XCTAssertFalse(manager.isCursorHidden)

        // Cancelling brings the style back. The canvas is asked directly: a state change also
        // refreshes hidden overlays on other displays, which show the system cursor, so with
        // two displays the shared result depends on which overlay goes last.
        try pressEscape()
        XCTAssertTrue(manager.shouldShowActiveCursorOnScreen(screen))
        view.updateCursor()
        XCTAssertTrue(manager.isCursorHidden)

        // So does picking.
        run(.capture(.area))
        XCTAssertFalse(manager.isCursorHidden)
        try drag(from: .zero, to: NSPoint(x: 80, y: 60))
        XCTAssertTrue(manager.shouldShowActiveCursorOnScreen(screen))
        view.updateCursor()
        XCTAssertTrue(manager.isCursorHidden)
        await appDelegate.captureTask?.value
    }

    /// Sends a cursor update the way AppKit does: to the owner of each cursor-update tracking
    /// area in the overlay, which is the canvas, not the picker on top of it.
    private func deliverCursorUpdate() throws {
        let event = try XCTUnwrap(
            NSEvent.enterExitEvent(
                with: .cursorUpdate,
                location: NSPoint(x: 300, y: 300),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: overlay.windowNumber,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil))
        let views = [overlay.overlayView as NSView] + overlay.overlayView.subviews
        let owners = views.flatMap(\.trackingAreas)
            .filter { $0.options.contains(.cursorUpdate) }
            .compactMap { $0.owner as? NSResponder }
        XCTAssertFalse(owners.isEmpty, "Something must answer cursor updates")
        owners.forEach { $0.cursorUpdate(with: event) }
    }

    func testThePickerShowsTheCrosshairWithEveryCursorStyle() throws {
        try useStubCapture()
        let original = CursorHighlightManager.shared
        let manager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = manager
        addTeardownBlock { @MainActor in
            manager.showSystemCursor()
            CursorHighlightManager.shared = original
        }
        run(.show)
        let view = try XCTUnwrap(overlay.overlayView)

        for style in ActiveCursorStyle.allCases {
            manager.activeCursorStyle = style
            run(.capture(.area))
            NSCursor.arrow.set()

            // AppKit asks again on every move across the overlay; each answer must be the crosshair.
            try deliverCursorUpdate()
            XCTAssertTrue(NSCursor.current === NSCursor.crosshair, "\(style) while picking")
            view.updateCursor()
            XCTAssertTrue(NSCursor.current === NSCursor.crosshair, "\(style) after the canvas refreshes its cursor")
            XCTAssertFalse(manager.isCursorHidden, "\(style)")

            try pressEscape()
            try deliverCursorUpdate()
            XCTAssertFalse(NSCursor.current === NSCursor.crosshair, "\(style): the tool's cursor is back")
            XCTAssertEqual(manager.isCursorHidden, style != .none, "\(style)")
        }
    }

    func testCaptureAreaFromAClosedOverlayStillClearsWithClearDrawingsOnStart() throws {
        try useStubCapture()
        testDefaults.settings[.clearDrawingsOnStart] = true
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())

        run(.capture(.area))

        XCTAssertTrue(overlay.isRegionPickerOpen)
        XCTAssertTrue(overlay.overlayView.paths.isEmpty, "Opens the way the overlay shortcut does")
    }

    func testShiftCommandSWhileTypingALabelCommitsItAndPicks() throws {
        try useStubCapture()
        let view = try startTypingALabel("Hello")

        XCTAssertTrue(overlay.performKeyEquivalent(with: try keyDown("S", modifiers: [.shift, .command])))

        XCTAssertNil(view.activeTextField)
        XCTAssertEqual(view.textAnnotations.map(\.text), ["Hello"])
        XCTAssertTrue(overlay.isRegionPickerOpen)
    }

    func testShortcutsStandDownWhilePicking() throws {
        try useStubCapture()
        run(.show)
        overlay.overlayView.currentTool = .arrow
        run(.capture(.area))

        overlay.sendEvent(try keyDown("p"))
        XCTAssertTrue(overlay.performKeyEquivalent(with: try keyDown("s", modifiers: .command)))

        XCTAssertEqual(overlay.overlayView.currentTool, .arrow)
        XCTAssertTrue(overlay.isRegionPickerOpen)
        XCTAssertNil(appDelegate.captureTask)
    }

    func testClosingTheOverlayCancelsThePicker() throws {
        try useStubCapture()
        run(.capture(.area))
        XCTAssertTrue(overlay.overlayView.isFadeFrozen)

        run(.hide)

        XCTAssertFalse(overlay.isRegionPickerOpen)
        XCTAssertFalse(overlay.overlayView.isFadeFrozen)
    }

    func testCaptureAreaWithoutScreenRecordingAsksBeforePicking() throws {
        try useStubCapture(canCapture: false)
        appDelegate.screenRecordingNoticeDelay = 0
        var opened: [SettingsPane] = []
        appDelegate.openSettingsPane = { pane, _, _ in opened.append(pane) }
        run(.show)

        run(.capture(.area))

        XCTAssertFalse(overlay.isRegionPickerOpen)
        runLoop { !opened.isEmpty }
        XCTAssertEqual(opened, [.capture])
    }

    func testCaptureAreaOverAnOpaqueBoardNeedsNoScreenRecording() throws {
        try useStubCapture(canCapture: false)
        BoardManager.shared.isEnabled = true
        BoardManager.shared.opacity = 1
        run(.show)

        run(.capture(.area))

        XCTAssertTrue(overlay.isRegionPickerOpen)
    }

    func testCaptureAreaMenuItemTakesTheShortcut() throws {
        let item = try XCTUnwrap(
            appDelegate.statusItem.menu?.items.first { $0.action == #selector(AppDelegate.captureArea) })
        XCTAssertEqual(item.title, "Capture Area")
        XCTAssertEqual(item.keyEquivalent, "s")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.shift, .command])
    }

    // MARK: - App Intents

    func testEveryPickerCaseHasADisplayRepresentation() {
        for tool in ToolType.allCases {
            let title = ToolType.caseDisplayRepresentations[tool].map { String(localized: $0.title) }
            XCTAssertEqual(title, tool.displayName)
        }
        for color in PaletteColor.allCases {
            let title = PaletteColor.caseDisplayRepresentations[color].map { String(localized: $0.title) }
            XCTAssertEqual(title, color.displayName)
        }
        for state in CommandSwitch.allCases {
            XCTAssertNotNil(CommandSwitch.caseDisplayRepresentations[state])
        }
    }

    func testIntentsMapToTheirCommands() {
        XCTAssertEqual(ToggleOverlayIntent().command, .toggle)
        XCTAssertEqual(ShowOverlayIntent().command, .show)
        XCTAssertEqual(HideOverlayIntent().command, .hide)
        XCTAssertEqual(SelectToolIntent(tool: .counter).command, .tool(.counter))
        XCTAssertEqual(SetColorIntent(color: .yellow).command, .color(.yellow))
        XCTAssertEqual(ClearAnnotationsIntent().command, .clear)
        XCTAssertEqual(SetToolbarIntent(state: .off).command, .toolbar(.off))
        XCTAssertEqual(SetFadeModeIntent(state: .on).command, .fade(.on))
        XCTAssertEqual(SetBoardIntent(state: .toggle).command, .board(.toggle))
    }

    func testIntentRunsItsCommandInTheApp() async throws {
        _ = try await SelectToolIntent(tool: .highlighter).perform()

        XCTAssertTrue(overlay.isVisible)
        XCTAssertEqual(overlay.overlayView.currentTool, .highlighter)
    }

    func testIntentFailsBeforeTheAppHasLaunched() async {
        AppDelegate.shared = nil
        defer { AppDelegate.shared = appDelegate }

        do {
            _ = try await ClearAnnotationsIntent().perform()
            XCTFail("perform() must throw without an AppDelegate")
        } catch {
            XCTAssertEqual(error as? AnnotateIntentError, .appNotReady)
        }
    }
}
