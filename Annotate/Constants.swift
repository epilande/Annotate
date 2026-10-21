import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let toggleAlwaysOnMode = Self("toggleAlwaysOnMode")
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
