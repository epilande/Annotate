import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let toggleAlwaysOnMode = Self("toggleAlwaysOnMode")
}

/// The annotation colors offered by the color picker, in palette order. Shortcuts actions and
/// links name a color by its slot, so reordering cases breaks saved shortcuts and links.
enum PaletteColor: String, CaseIterable, Sendable {
    case red, orange, yellow
    case green, cyan, indigo
    case magenta, white, black

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .cyan: return .cyan
        case .indigo: return .systemIndigo
        case .magenta: return .magenta
        case .white: return .white
        case .black: return .black
        }
    }

    var displayName: String {
        rawValue.capitalized
    }

    /// The color's position in the palette, 1 for the first. It doesn't follow the color's
    /// keyboard shortcut, which the user can change.
    var slot: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    /// The color in palette slot `slot`, or nil when there is no such slot.
    init?(slot: Int) {
        guard let match = Self.allCases.first(where: { $0.slot == slot }) else { return nil }
        self = match
    }

    /// The entry `color` was picked from, matched as the color picker matches its selection.
    init?(matching color: NSColor) {
        guard let match = Self.allCases.first(where: { $0.nsColor.isClose(to: color) }) else { return nil }
        self = match
    }
}

let colorPalette: [NSColor] = PaletteColor.allCases.map(\.nsColor)

/// Seconds an annotation stays at full opacity in Fade Mode before it starts to fade out.
/// The default is the hold Fade Mode has always used.
let defaultFadeDelay: TimeInterval = 0.625
let fadeDelayRange: ClosedRange<TimeInterval> = 0.25...5

/// Formats a fade delay for the Settings slider, e.g. "0.625s" or "2s".
func fadeDelayLabel(_ seconds: TimeInterval) -> String {
    String(format: "%gs", seconds)
}

let defaultTextAnnotationFontSize: CGFloat = 18
let textAnnotationFontSizeRange: ClosedRange<CGFloat> = 12...120

/// Matches the quick-picker stroke ladder (`QuickPickerView.widthOptions` max 24).
let lineWidthRange: ClosedRange<CGFloat> = 0.5...24

/// 14 pt reproduces counters' original 15 pt radius / 2.5 pt stroke; the badge
/// scales from here (see `CounterAnnotation.radius`).
let soundEffectVolume: Float = 0.2

let defaultCounterFontSize: CGFloat = 14
let counterFontSizeRange: ClosedRange<CGFloat> = 12...60
