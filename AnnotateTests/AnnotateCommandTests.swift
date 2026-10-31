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

    private func run(_ command: AnnotateCommand) {
        command.run(on: appDelegate)
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
        XCTAssertTrue(AnnotateCommand.Switch.on.resolve(current: true))
        XCTAssertTrue(AnnotateCommand.Switch.on.resolve(current: false))
        XCTAssertFalse(AnnotateCommand.Switch.off.resolve(current: true))
        XCTAssertFalse(AnnotateCommand.Switch.off.resolve(current: false))
        XCTAssertFalse(AnnotateCommand.Switch.toggle.resolve(current: true))
        XCTAssertTrue(AnnotateCommand.Switch.toggle.resolve(current: false))
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
        for state in AnnotateCommand.Switch.allCases {
            XCTAssertNotNil(AnnotateCommand.Switch.caseDisplayRepresentations[state])
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
