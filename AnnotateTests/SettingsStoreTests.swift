import SwiftUI
import XCTest

@testable import Annotate

/// The literal key strings and raw values below are what earlier releases wrote to disk. They
/// are spelled out instead of read from `SettingKey` on purpose: if a key's name or encoding
/// changes, these tests fail instead of every user's setting silently resetting.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: SettingsStore!

    override func setUp() {
        super.setUp()
        defaults = TestUserDefaults.create()
        settings = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        settings = nil
        defaults = nil
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    // MARK: - Defaults

    func testUnsetKeysReadTheirDefaults() {
        XCTAssertFalse(settings[.clearDrawingsOnStart])
        XCTAssertFalse(settings[.hideDockIcon])
        XCTAssertFalse(settings[.hideToolFeedback])
        XCTAssertTrue(settings[.fadeMode])
        XCTAssertFalse(settings[.alwaysOnMode])
        XCTAssertTrue(settings[.toolbarVisible])
        XCTAssertFalse(settings[.soundsEnabled])
        XCTAssertFalse(settings[.enableBoard])
        XCTAssertFalse(settings[.textBackground])
        XCTAssertFalse(settings[.selectAfterPlacingText])
        XCTAssertFalse(settings[.clickRippleEnabled])
        XCTAssertFalse(settings[.cursorHighlightEnabled])
        XCTAssertFalse(settings[.spotlightRequiresOverlay])
        XCTAssertFalse(settings[.spotlightDimmingEnabled])
        XCTAssertFalse(settings[.spotlightAutoDim])

        XCTAssertEqual(settings[.boardOpacity], 0.9)
        XCTAssertEqual(settings[.fadeDelay], 0.625)
        XCTAssertEqual(settings[.lineWidth], 3)
        XCTAssertEqual(settings[.textFontSize], defaultTextAnnotationFontSize)
        XCTAssertEqual(settings[.counterFontSize], defaultCounterFontSize)
        XCTAssertEqual(settings[.clickRippleSize], 70)
        XCTAssertEqual(settings[.spotlightSize], 50)
        XCTAssertEqual(settings[.spotlightDimmingOpacity], 0.5)
        XCTAssertEqual(settings[.activeCursorSize], 14)
        XCTAssertEqual(settings[.systemCursorScale], 1)

        XCTAssertEqual(settings[.soundTheme], .chalk)
        XCTAssertEqual(settings[.lastUsedTool], .pen)
        XCTAssertEqual(settings[.defaultTool], .lastUsed)
        XCTAssertEqual(settings[.redactionStyle], .solid)
        XCTAssertEqual(settings[.counterStyle], .bordered)
        XCTAssertEqual(settings[.activeCursorStyle], ActiveCursorStyle.none)

        assertColor(settings[.selectedColor], isCloseTo: .systemRed)
        assertColor(settings[.clickRippleColor], isCloseTo: .systemYellow)
        XCTAssertEqual(settings[.hideCursorEffectsInApps], [])
        XCTAssertEqual(settings[.toolbarPositions], [:])

        for action in ShortcutKey.allCases {
            XCTAssertEqual(settings[.shortcut(action)], action.defaultBinding, "\(action)")
        }
    }

    func testRemovingAValueRestoresTheDefault() {
        settings[.fadeMode] = false
        XCTAssertTrue(settings.hasValue(for: .fadeMode))

        settings.removeValue(for: .fadeMode)

        XCTAssertFalse(settings.hasValue(for: .fadeMode))
        XCTAssertTrue(settings[.fadeMode])
    }

    // MARK: - Round trips

    func testValuesRoundTrip() {
        settings[.toolbarVisible] = false
        settings[.boardOpacity] = 0.35
        settings[.fadeDelay] = 2.5
        settings[.lineWidth] = 0.5
        settings[.textFontSize] = 44
        settings[.soundTheme] = .typewriter
        settings[.lastUsedTool] = .counter
        settings[.defaultTool] = .tool(.arrow)
        settings[.redactionStyle] = .pixelate
        settings[.counterStyle] = .filled
        settings[.activeCursorStyle] = .crosshair
        settings[.clickRippleColor] = .systemPurple
        settings[.hideCursorEffectsInApps] = ["com.apple.Keynote", "com.microsoft.Powerpoint"]
        settings[.toolbarPositions] = ["1": [12, 34], "2": [-5, 6.5]]
        settings[.shortcut(.pen)] = ShortcutBinding("q", modifiers: [.command, .shift])
        settings[.shortcut(.arrow)] = .unassigned

        XCTAssertFalse(settings[.toolbarVisible])
        XCTAssertEqual(settings[.boardOpacity], 0.35)
        XCTAssertEqual(settings[.fadeDelay], 2.5)
        XCTAssertEqual(settings[.lineWidth], 0.5)
        XCTAssertEqual(settings[.textFontSize], 44)
        XCTAssertEqual(settings[.soundTheme], .typewriter)
        XCTAssertEqual(settings[.lastUsedTool], .counter)
        XCTAssertEqual(settings[.defaultTool], .tool(.arrow))
        XCTAssertEqual(settings[.redactionStyle], .pixelate)
        XCTAssertEqual(settings[.counterStyle], .filled)
        XCTAssertEqual(settings[.activeCursorStyle], .crosshair)
        assertColor(settings[.clickRippleColor], isCloseTo: .systemPurple)
        XCTAssertEqual(settings[.hideCursorEffectsInApps], ["com.apple.Keynote", "com.microsoft.Powerpoint"])
        XCTAssertEqual(settings[.toolbarPositions], ["1": [12, 34], "2": [-5, 6.5]])
        XCTAssertEqual(settings[.shortcut(.pen)], ShortcutBinding("q", modifiers: [.command, .shift]))
        XCTAssertEqual(settings[.shortcut(.arrow)], .unassigned)
    }

    func testEveryPaletteColorRoundTrips() {
        for color in colorPalette {
            settings[.selectedColor] = color
            assertColor(settings[.selectedColor], isCloseTo: color)
        }
    }

    // MARK: - Fallbacks

    func testSizesTreatZeroOrNegativeAsUnset() {
        defaults.set(0.0, forKey: "TextFontSize")
        defaults.set(-4.0, forKey: "CounterFontSize")
        defaults.set(0.0, forKey: "SpotlightDimmingOpacity")

        XCTAssertEqual(settings[.textFontSize], defaultTextAnnotationFontSize)
        XCTAssertEqual(settings[.counterFontSize], defaultCounterFontSize)
        XCTAssertEqual(settings[.spotlightDimmingOpacity], 0.5)
    }

    func testWrongTypeReadsTheDefault() {
        defaults.set(Data([0x01]), forKey: "FadeMode")
        defaults.set(["on"], forKey: "ToolbarVisible")
        defaults.set("thick", forKey: "LineWidth")
        defaults.set("maybe", forKey: "SoundsEnabled")
        defaults.set(Data([0x01]), forKey: "BoardOpacity")
        defaults.set(["big"], forKey: "TextFontSize")
        defaults.set("large", forKey: "mouseDriverCursorSize")

        XCTAssertTrue(settings[.fadeMode])
        XCTAssertTrue(settings[.toolbarVisible])
        XCTAssertEqual(settings[.lineWidth], 3)
        XCTAssertFalse(settings[.soundsEnabled])
        XCTAssertEqual(settings[.boardOpacity], 0.9)
        XCTAssertEqual(settings[.textFontSize], defaultTextAnnotationFontSize)
        XCTAssertEqual(settings[.systemCursorScale], 1)
    }

    /// `defaults write` without a type flag stores a string, which `bool(forKey:)` and
    /// `double(forKey:)` coerce, so those keep reading.
    func testNumericAndBooleanStringsStillRead() {
        defaults.set("YES", forKey: "SoundsEnabled")
        defaults.set("1", forKey: "HideDockIcon")
        defaults.set("true", forKey: "EnableBoard")
        defaults.set("90.5", forKey: "ClickRippleSize")
        defaults.set(2, forKey: "SpotlightSize")

        XCTAssertTrue(settings[.soundsEnabled])
        XCTAssertTrue(settings[.hideDockIcon])
        XCTAssertTrue(settings[.enableBoard])
        XCTAssertEqual(settings[.clickRippleSize], 90.5)
        XCTAssertEqual(settings[.spotlightSize], 2)
    }

    /// These keys read with an `as?` cast before the store, so any string, even one that
    /// `bool(forKey:)` or `double(forKey:)` would coerce, reads as the default.
    func testStringsReadTheDefaultForKeysThatNeverAcceptedThem() {
        defaults.set("NO", forKey: "FadeMode")
        defaults.set("NO", forKey: "ToolbarVisible")
        defaults.set("NO", forKey: "LineWidth")
        XCTAssertTrue(settings[.fadeMode])
        XCTAssertTrue(settings[.toolbarVisible])
        XCTAssertEqual(settings[.lineWidth], 3)

        defaults.set("0", forKey: "FadeMode")
        defaults.set("false", forKey: "ToolbarVisible")
        defaults.set("5.5", forKey: "LineWidth")
        XCTAssertTrue(settings[.fadeMode])
        XCTAssertTrue(settings[.toolbarVisible])
        XCTAssertEqual(settings[.lineWidth], 3)
    }

    func testLineWidthKeepsAStoredZero() {
        defaults.set(0.0, forKey: "LineWidth")
        XCTAssertEqual(settings[.lineWidth], 0)
    }

    func testBoardOpacityTreatsZeroAsUnsetAndClampsTheRest() {
        defaults.set(0.0, forKey: "BoardOpacity")
        XCTAssertEqual(settings[.boardOpacity], 0.9)

        defaults.set(0.01, forKey: "BoardOpacity")
        XCTAssertEqual(settings[.boardOpacity], 0.1)

        defaults.set(5.0, forKey: "BoardOpacity")
        XCTAssertEqual(settings[.boardOpacity], 1.0)
    }

    func testFadeDelayTreatsZeroOrNegativeAsUnsetAndClampsTheRest() {
        defaults.set(0.0, forKey: "FadeDelay")
        XCTAssertEqual(settings[.fadeDelay], 0.625)

        defaults.set(-1.0, forKey: "FadeDelay")
        XCTAssertEqual(settings[.fadeDelay], 0.625)

        defaults.set(0.1, forKey: "FadeDelay")
        XCTAssertEqual(settings[.fadeDelay], 0.25)

        defaults.set(10.0, forKey: "FadeDelay")
        XCTAssertEqual(settings[.fadeDelay], 5)

        defaults.set("1.5", forKey: "FadeDelay")
        XCTAssertEqual(settings[.fadeDelay], 1.5, "`defaults write` without -float stores a string")
    }

    func testFadeDelayPersistsAsSecondsUnderFadeDelay() {
        settings[.fadeDelay] = 3

        XCTAssertEqual(defaults.object(forKey: "FadeDelay") as? Double, 3)
        XCTAssertEqual(SettingsStore(defaults: defaults)[.fadeDelay], 3, "a fresh store reads it back")
    }

    func testUnknownRawValuesReadTheDefault() {
        defaults.set("granite", forKey: "SoundTheme")
        defaults.set("lasso", forKey: "LastUsedTool")
        defaults.set("lasso", forKey: "DefaultTool")
        defaults.set("spiral", forKey: "ActiveCursorStyle")
        defaults.set("mosaic", forKey: "RedactionStyle")

        XCTAssertEqual(settings[.soundTheme], .chalk)
        XCTAssertEqual(settings[.lastUsedTool], .pen)
        XCTAssertEqual(settings[.defaultTool], .lastUsed)
        XCTAssertEqual(settings[.activeCursorStyle], ActiveCursorStyle.none)
        XCTAssertEqual(settings[.redactionStyle], .solid)
    }

    func testAStoredOutlineRedactionReadsSolid() {
        defaults.set("outline", forKey: "RedactionStyle")
        XCTAssertEqual(settings[.redactionStyle], .solid, "A redaction must always hide")
    }

    func testUnreadableColorDataReadsTheDefault() {
        defaults.set(Data([0xde, 0xad]), forKey: "SelectedColor")
        assertColor(settings[.selectedColor], isCloseTo: .systemRed)
    }

    func testMalformedToolbarPositionsAreDropped() {
        defaults.set(["1": [10.0, 20.0], "2": ["nonsense"]], forKey: "ToolbarPositions")
        XCTAssertEqual(settings[.toolbarPositions], ["1": [10, 20]])
    }

    // MARK: - Compatibility with values written before the store

    func testReadsValuesWrittenByEarlierReleases() throws {
        defaults.set(true, forKey: "ClearDrawingsOnStart")
        defaults.set(true, forKey: "HideDockIcon")
        defaults.set(true, forKey: "HideToolFeedback")
        defaults.set(false, forKey: "FadeMode")
        defaults.set(true, forKey: "AlwaysOnMode")
        defaults.set(false, forKey: "ToolbarVisible")
        defaults.set(true, forKey: "SoundsEnabled")
        defaults.set(true, forKey: "EnableBoard")
        defaults.set(true, forKey: "TextBackgroundOn")
        defaults.set(true, forKey: "SelectAfterPlacingText")
        defaults.set(true, forKey: "ClickRippleEnabled")
        defaults.set(true, forKey: "CursorHighlightEnabled")
        defaults.set(true, forKey: "SpotlightRequiresOverlay")
        defaults.set(true, forKey: "SpotlightDimmingEnabled")
        defaults.set(true, forKey: "SpotlightAutoDim")

        defaults.set(0.4, forKey: "BoardOpacity")
        defaults.set(7.5, forKey: "LineWidth")
        defaults.set(32.0, forKey: "TextFontSize")
        defaults.set(24.0, forKey: "CounterFontSize")
        defaults.set(90.0, forKey: "ClickRippleSize")
        defaults.set(80.0, forKey: "SpotlightSize")
        defaults.set(0.7, forKey: "SpotlightDimmingOpacity")
        defaults.set(20.0, forKey: "ActiveCursorSize")
        defaults.set(Float(2.5), forKey: "mouseDriverCursorSize")

        defaults.set("paper", forKey: "SoundTheme")
        defaults.set("highlighter", forKey: "LastUsedTool")
        defaults.set("rectangle", forKey: "DefaultTool")
        defaults.set("blur", forKey: "RedactionStyle")
        defaults.set("outline", forKey: "ActiveCursorStyle")

        defaults.set(
            try NSKeyedArchiver.archivedData(withRootObject: NSColor.systemIndigo, requiringSecureCoding: false),
            forKey: "SelectedColor")
        defaults.set(
            try NSKeyedArchiver.archivedData(withRootObject: NSColor.systemGreen, requiringSecureCoding: true),
            forKey: "ClickRippleColor")
        defaults.set(["com.apple.Keynote"], forKey: "HideCursorEffectsInApps")
        defaults.set(["69734208": [140.0, 500.0]], forKey: "ToolbarPositions")

        defaults.set("j", forKey: "shortcut.p")
        defaults.set("", forKey: "shortcut.a")
        defaults.set(
            ["key": "f", "modifiers": NSEvent.ModifierFlags([.command, .option]).rawValue],
            forKey: "shortcut.toggleFade")

        XCTAssertTrue(settings[.clearDrawingsOnStart])
        XCTAssertTrue(settings[.hideDockIcon])
        XCTAssertTrue(settings[.hideToolFeedback])
        XCTAssertFalse(settings[.fadeMode])
        XCTAssertTrue(settings[.alwaysOnMode])
        XCTAssertFalse(settings[.toolbarVisible])
        XCTAssertTrue(settings[.soundsEnabled])
        XCTAssertTrue(settings[.enableBoard])
        XCTAssertTrue(settings[.textBackground])
        XCTAssertTrue(settings[.selectAfterPlacingText])
        XCTAssertTrue(settings[.clickRippleEnabled])
        XCTAssertTrue(settings[.cursorHighlightEnabled])
        XCTAssertTrue(settings[.spotlightRequiresOverlay])
        XCTAssertTrue(settings[.spotlightDimmingEnabled])
        XCTAssertTrue(settings[.spotlightAutoDim])

        XCTAssertEqual(settings[.boardOpacity], 0.4)
        XCTAssertEqual(settings[.lineWidth], 7.5)
        XCTAssertEqual(settings[.textFontSize], 32)
        XCTAssertEqual(settings[.counterFontSize], 24)
        XCTAssertEqual(settings[.clickRippleSize], 90)
        XCTAssertEqual(settings[.spotlightSize], 80)
        XCTAssertEqual(settings[.spotlightDimmingOpacity], 0.7)
        XCTAssertEqual(settings[.activeCursorSize], 20)
        XCTAssertEqual(settings[.systemCursorScale], 2.5)

        XCTAssertEqual(settings[.soundTheme], .paper)
        XCTAssertEqual(settings[.lastUsedTool], .highlighter)
        XCTAssertEqual(settings[.defaultTool], .tool(.rectangle))
        XCTAssertEqual(settings[.redactionStyle], .blur)
        XCTAssertEqual(settings[.activeCursorStyle], .outline)

        assertColor(settings[.selectedColor], isCloseTo: .systemIndigo)
        assertColor(settings[.clickRippleColor], isCloseTo: .systemGreen)
        XCTAssertEqual(settings[.hideCursorEffectsInApps], ["com.apple.Keynote"])
        XCTAssertEqual(settings[.toolbarPositions], ["69734208": [140, 500]])

        XCTAssertEqual(settings[.shortcut(.pen)], ShortcutBinding("j"))
        XCTAssertEqual(settings[.shortcut(.arrow)], .unassigned)
        XCTAssertEqual(settings[.shortcut(.toggleFade)], ShortcutBinding("f", modifiers: [.command, .option]))
    }

    func testWritesTheEncodingsEarlierReleasesRead() throws {
        settings[.fadeMode] = false
        settings[.boardOpacity] = 0.4
        settings[.textFontSize] = 32
        settings[.soundTheme] = .paper
        settings[.defaultTool] = .tool(.rectangle)
        settings[.selectedColor] = .systemIndigo
        settings[.hideCursorEffectsInApps] = ["com.apple.Keynote"]
        settings[.toolbarPositions] = ["69734208": [140, 500]]
        settings[.shortcut(.toggleFade)] = ShortcutBinding("f", modifiers: [.command, .option])
        settings[.shortcut(.arrow)] = .unassigned

        XCTAssertEqual(defaults.object(forKey: "FadeMode") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "BoardOpacity") as? Double, 0.4)
        XCTAssertEqual(defaults.object(forKey: "TextFontSize") as? Double, 32)
        XCTAssertEqual(defaults.string(forKey: "SoundTheme"), "paper")
        XCTAssertEqual(defaults.string(forKey: "DefaultTool"), "rectangle")
        let colorData = try XCTUnwrap(defaults.data(forKey: "SelectedColor"))
        let color = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData))
        assertColor(color, isCloseTo: .systemIndigo)
        XCTAssertEqual(defaults.stringArray(forKey: "HideCursorEffectsInApps"), ["com.apple.Keynote"])
        XCTAssertEqual(
            defaults.dictionary(forKey: "ToolbarPositions")?["69734208"] as? [Double], [140, 500])

        let chord = try XCTUnwrap(defaults.dictionary(forKey: "shortcut.toggleFade"))
        XCTAssertEqual(chord["key"] as? String, "f")
        XCTAssertEqual(
            (chord["modifiers"] as? NSNumber)?.uintValue, NSEvent.ModifierFlags([.command, .option]).rawValue)
        XCTAssertEqual(defaults.string(forKey: "shortcut.a"), "")
    }

    // MARK: - SwiftUI

    func testAppStorageUsesTheKeysNameAndDefault() {
        XCTAssertTrue(AppStorage(.toolbarVisible, store: defaults).wrappedValue)
        XCTAssertEqual(AppStorage(.textFontSize, store: defaults).wrappedValue, Double(defaultTextAnnotationFontSize))
        XCTAssertEqual(AppStorage(.soundTheme, store: defaults).wrappedValue, .chalk)
        XCTAssertEqual(AppStorage(.fadeDelay, store: defaults).wrappedValue, 0.625)
        XCTAssertEqual(AppStorage(.counterStyle, store: defaults).wrappedValue, .bordered)

        settings[.toolbarVisible] = false
        settings[.textFontSize] = 40
        settings[.soundTheme] = .marker
        settings[.fadeDelay] = 2

        XCTAssertFalse(AppStorage(.toolbarVisible, store: defaults).wrappedValue)
        XCTAssertEqual(AppStorage(.textFontSize, store: defaults).wrappedValue, 40)
        XCTAssertEqual(AppStorage(.soundTheme, store: defaults).wrappedValue, .marker)
        XCTAssertEqual(AppStorage(.fadeDelay, store: defaults).wrappedValue, 2)
    }
}
