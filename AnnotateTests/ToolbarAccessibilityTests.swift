import AppKit
import XCTest

@testable import Annotate

/// VoiceOver must hear what each chip does, not its keycap (#131), the same way in every
/// layout and with the keycaps hidden.
@MainActor
final class ToolbarAccessibilityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var appDelegate: AppDelegate!
    private var windows: [OverlayWindow] = []
    private var assistiveAppWasAttached = false

    /// Every chip on the bar, by identifier, with the name VoiceOver reads and the default
    /// shortcut its hint speaks.
    private static let expected: [(identifier: String, label: String, hint: String)] = [
        ("toolbar.tool.pen", "Pen", "Shortcut: p"),
        ("toolbar.tool.arrow", "Arrow", "Shortcut: a"),
        ("toolbar.tool.line", "Line", "Shortcut: l"),
        ("toolbar.tool.highlighter", "Highlighter", "Shortcut: h"),
        ("toolbar.tool.rectangle", "Rectangle", "Shortcut: r"),
        ("toolbar.tool.circle", "Circle", "Shortcut: o"),
        ("toolbar.tool.redact", "Redact", "Shortcut: x"),
        ("toolbar.tool.text", "Text", "Shortcut: t"),
        ("toolbar.tool.counter", "Counter", "Shortcut: n"),
        ("toolbar.tool.select", "Select", "Shortcut: v"),
        ("toolbar.tool.eraser", "Eraser", "Shortcut: e"),
        ("toolbar.color", "Color", "Shortcut: c"),
        ("toolbar.width", "Size", "Shortcut: w"),
        ("toolbar.fade", "Fade Mode", "Shortcut: Space"),
        ("toolbar.deleteLast", "Delete Last", "Shortcut: ⌫"),
        ("toolbar.clearAll", "Clear All", "Shortcut: ⌥⌫"),
        ("toolbar.undo", "Undo", "Shortcut: ⌘Z")
    ]

    override func setUp() {
        super.setUp()
        TestWindows.recordOpenWindows()
        assistiveAppWasAttached = TestAccessibility.setAssistiveAppAttached(true)
        defaults = TestUserDefaults.create()
        appDelegate = AppDelegate(userDefaults: defaults)
        AppDelegate.shared = appDelegate
        ShortcutManager.shared = ShortcutManager(userDefaults: defaults)
    }

    override func tearDown() {
        windows.forEach { $0.close() }
        windows = []
        AppDelegate.shared = nil
        appDelegate = nil
        ShortcutManager.shared = ShortcutManager()
        TestUserDefaults.removeSuite()
        defaults = nil
        TestAccessibility.setAssistiveAppAttached(assistiveAppWasAttached)
        assertNoLeakedWindows()
        super.tearDown()
    }

    private func makeOverlay(width: CGFloat = 1_200) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView?.layoutSubtreeIfNeeded()
        windows.append(window)
        return window
    }

    private func chips(on window: OverlayWindow) throws -> [String: TestAccessibility.Element] {
        let host = try XCTUnwrap(window.toolbarPanel?.hostingView)
        host.layoutSubtreeIfNeeded()
        return TestAccessibility.elements(in: host)
    }

    /// Applies the toolbar settings the way Settings does, through every open overlay.
    private func apply(showsShortcuts: Bool, layout: ToolbarLayout) {
        defaults.settings[.toolbarShowsShortcuts] = showsShortcuts
        defaults.settings[.toolbarLayout] = layout
        for (index, window) in windows.enumerated() {
            window.refreshToolbarAppearance()
            XCTAssertEqual(window.toolbarModel.showsShortcuts, showsShortcuts, "overlay \(index)")
            XCTAssertEqual(window.toolbarModel.layout, layout, "overlay \(index)")
        }
    }

    private func assertNamesAndHints(
        _ chips: [String: TestAccessibility.Element],
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Set(chips.keys),
            Set(Self.expected.map(\.identifier)),
            "\(context): every chip is an element, and nothing else is",
            file: file,
            line: line)
        for chip in Self.expected {
            let message = "\(context): \(chip.identifier)"
            XCTAssertEqual(chips[chip.identifier]?.label, chip.label, message, file: file, line: line)
            XCTAssertEqual(chips[chip.identifier]?.hint, chip.hint, message, file: file, line: line)
        }
    }

    func testEveryChipIsNamedForItsActionInEveryLayoutWithOrWithoutKeycaps() throws {
        let wide = makeOverlay()
        // Too narrow for one row, so the horizontal bar wraps the tools onto their own row.
        let narrow = makeOverlay(width: 600)
        let rowHeight = try XCTUnwrap(wide.toolbarPanel).frame.height
        let narrowHeight = try XCTUnwrap(narrow.toolbarPanel).frame.height
        XCTAssertGreaterThan(narrowHeight, rowHeight * 1.5, "The narrow overlay's bar should be the two-row layout")

        for layout in ToolbarLayout.allCases {
            for showsShortcuts in [true, false] {
                apply(showsShortcuts: showsShortcuts, layout: layout)
                let context = "\(layout), shortcuts \(showsShortcuts ? "shown" : "hidden")"
                assertNamesAndHints(try chips(on: wide), context)
                assertNamesAndHints(try chips(on: narrow), "\(context), narrow overlay")
            }
        }
    }

    func testNoChipIsNamedAfterItsKeycap() throws {
        let window = makeOverlay()
        let keycaps = Set(
            ShortcutKey.allCases.map(\.defaultBinding.displayValue).map(ShortcutBinding.spokenLabel(for:))
                + ["⌫", "⌘Z"])

        for (identifier, chip) in try chips(on: window) {
            let label = try XCTUnwrap(chip.label, identifier)
            XCTAssertFalse(label.isEmpty, identifier)
            XCTAssertFalse(
                keycaps.contains { $0.caseInsensitiveCompare(label) == .orderedSame },
                "\(identifier) is named \(label), which is a keycap")
        }
    }

    func testTheHintFollowsACustomShortcutAndDisappearsWhenItIsCleared() throws {
        let window = makeOverlay()
        ShortcutManager.shared.setShortcut("g", for: .pen)
        ShortcutManager.shared.setShortcut("", for: .toggleFade)
        apply(showsShortcuts: false, layout: .horizontal)

        let chips = try chips(on: window)
        XCTAssertEqual(chips["toolbar.tool.pen"]?.label, "Pen")
        XCTAssertEqual(chips["toolbar.tool.pen"]?.hint, "Shortcut: g", "Hidden keycaps still announce the shortcut")
        XCTAssertEqual(chips["toolbar.fade"]?.label, "Fade Mode")
        XCTAssertEqual(chips["toolbar.fade"]?.hint ?? "", "", "A cleared binding has no shortcut to announce")
    }

    func testOnlyTheActiveToolChipIsSelected() throws {
        let window = makeOverlay()
        for tool in [ToolType.pen, .highlighter, .eraser] {
            window.overlayView.currentTool = tool
            let selected = try chips(on: window).filter(\.value.isSelected).map(\.key)
            XCTAssertEqual(selected, ["toolbar.tool.\(tool.rawValue)"])
        }
    }

    func testFadeChipReportsWhetherFadeModeIsOn() throws {
        let window = makeOverlay()
        window.overlayView.fadeMode = true
        XCTAssertEqual(try chips(on: window)["toolbar.fade"]?.value, "On")
        XCTAssertEqual(try chips(on: window)["toolbar.fade"]?.isSelected, false, "Fade is a toggle, not a selection")

        window.overlayView.fadeMode = false
        XCTAssertEqual(try chips(on: window)["toolbar.fade"]?.value, "Off")
    }

    func testColorChipReadsEveryPaletteColorByItsPaletteName() throws {
        let window = makeOverlay()
        let names = ["Red", "Orange", "Yellow", "Green", "Cyan", "Indigo", "Magenta", "White", "Black"]
        XCTAssertEqual(PaletteColor.allCases.map(\.displayName), names, "The names the color picker uses")

        for color in PaletteColor.allCases {
            window.overlayView.currentColor = color.nsColor
            XCTAssertEqual(try chips(on: window)["toolbar.color"]?.value, color.displayName)
        }
    }
}
