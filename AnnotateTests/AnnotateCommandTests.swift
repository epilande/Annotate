import AppIntents
import XCTest

@testable import Annotate

@MainActor
final class AnnotateCommandTests: XCTestCase {
    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!
    var screen: NSScreen!
    var overlay: OverlayWindow!

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

    func testCaptureMenuItemTakesTheShortcut() throws {
        let item = try XCTUnwrap(
            appDelegate.statusItem.menu?.items.first { $0.action == #selector(AppDelegate.captureScreen) })
        XCTAssertEqual(item.title, "Capture Screen")
        XCTAssertEqual(item.keyEquivalent, "s")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
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
