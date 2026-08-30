import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let toggleAlwaysOnMode = Self("toggleAlwaysOnMode")
}

extension UserDefaults {
    static let clearDrawingsOnStartKey = "ClearDrawingsOnStart"
    static let hideDockIconKey = "HideDockIcon"
    static let fadeModeKey = "FadeMode"
    static let enableBoardKey = "EnableBoard"
    static let boardOpacityKey = "BoardOpacity"
    static let alwaysOnModeKey = "AlwaysOnMode"
    static let lineWidthKey = "LineWidth"
    static let hideToolFeedbackKey = "HideToolFeedback"
    static let soundsEnabledKey = "SoundsEnabled"
    static let soundsEnabledDefault = true
    static let clickRippleEnabledKey = "ClickRippleEnabled"
    static let clickRippleColorKey = "ClickRippleColor"
    static let clickRippleSizeKey = "ClickRippleSize"
    static let cursorHighlightEnabledKey = "CursorHighlightEnabled"
    static let spotlightSizeKey = "SpotlightSize"
    static let spotlightRequiresOverlayKey = "SpotlightRequiresOverlay"
    static let activeCursorStyleKey = "ActiveCursorStyle"
    static let activeCursorSizeKey = "ActiveCursorSize"
    static let persistTextModeKey = "PersistTextMode"
    static let defaultTextFontSizeKey = "TextFontSize"
    static let textBackgroundKey = "TextBackgroundOn"
    static let defaultCounterFontSizeKey = "CounterFontSize"
    static let defaultToolKey = "DefaultTool"
    static let lastUsedToolKey = "LastUsedTool"
}

let colorPalette: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow,
    .systemGreen, .cyan, .systemIndigo,
    .magenta, .white, .black,
]

let defaultTextAnnotationFontSize: CGFloat = 18
let textAnnotationFontSizeRange: ClosedRange<CGFloat> = 12...120

/// Matches the quick-picker stroke ladder (`QuickPickerView.widthOptions` max 24).
let lineWidthRange: ClosedRange<CGFloat> = 0.5...24

/// 14 pt reproduces counters' original 15 pt radius / 2.5 pt stroke; the badge
/// scales from here (see `CounterAnnotation.radius`).
let soundEffectVolume: Float = 0.2

let defaultCounterFontSize: CGFloat = 14
let counterFontSizeRange: ClosedRange<CGFloat> = 12...60

extension UserDefaults {
    var soundsEnabled: Bool {
        get {
            guard object(forKey: Self.soundsEnabledKey) != nil else {
                return Self.soundsEnabledDefault
            }
            return bool(forKey: Self.soundsEnabledKey)
        }
        set {
            set(newValue, forKey: Self.soundsEnabledKey)
        }
    }

    var textToolFontSize: CGFloat {
        get {
            let stored = double(forKey: Self.defaultTextFontSizeKey)
            return stored > 0 ? CGFloat(stored) : defaultTextAnnotationFontSize
        }
        set {
            set(Double(newValue), forKey: Self.defaultTextFontSizeKey)
        }
    }

    var textBackgroundEnabled: Bool {
        get { bool(forKey: Self.textBackgroundKey) }
        set { set(newValue, forKey: Self.textBackgroundKey) }
    }

    var counterToolFontSize: CGFloat {
        get {
            let stored = double(forKey: Self.defaultCounterFontSizeKey)
            return stored > 0 ? CGFloat(stored) : defaultCounterFontSize
        }
        set {
            set(Double(newValue), forKey: Self.defaultCounterFontSizeKey)
        }
    }

    /// The tool to apply on overlay activation. Defaults to `.lastUsed`, which leaves the
    /// current in-memory tool untouched.
    var defaultToolOption: DefaultToolOption {
        get {
            let stored = string(forKey: Self.defaultToolKey) ?? ""
            return DefaultToolOption(rawValue: stored) ?? .lastUsed
        }
        set {
            set(newValue.rawValue, forKey: Self.defaultToolKey)
        }
    }

    /// The most recently explicitly selected tool, persisted so it survives app relaunches.
    var lastUsedTool: ToolType {
        get {
            let stored = string(forKey: Self.lastUsedToolKey) ?? ""
            return ToolType(rawValue: stored) ?? .pen
        }
        set {
            set(newValue.rawValue, forKey: Self.lastUsedToolKey)
        }
    }
}
