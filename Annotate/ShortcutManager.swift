import AppKit
@preconcurrency import KeyboardShortcuts

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("shortcutsDidChange")
}

/// A logical key and its meaningful modifiers. Empty keys represent an explicitly cleared binding.
struct ShortcutBinding: Equatable, Hashable {
    let key: String
    let modifiers: NSEvent.ModifierFlags

    static let unassigned = ShortcutBinding("")
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(_ key: String, modifiers: NSEvent.ModifierFlags = []) {
        self.key = Self.normalizedKey(key)
        self.modifiers = key.isEmpty ? [] : modifiers.intersection(Self.relevantModifiers)
    }

    static func normalizedKey(_ key: String) -> String {
        key == "\u{8}" || key == "\u{f728}" ? "\u{7f}" : key.lowercased()
    }

    init?(event: NSEvent) {
        guard let chord = KeyChord(event: event) else { return nil }
        self.init(chord: chord)
    }

    init?(globalShortcut: KeyboardShortcuts.Shortcut) {
        guard let keyCode = CGKeyCode(exactly: globalShortcut.carbonKeyCode),
            let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        else { return nil }
        // Translate through the current layout, including Shift punctuation, without posting a key.
        cgEvent.flags = CGEventFlags(rawValue: UInt64(globalShortcut.modifiers.rawValue))
        guard let event = NSEvent(cgEvent: cgEvent) else { return nil }
        self.init(event: event)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    /// Stands in for the space bar in keycaps, where "Space" would be the widest label by far.
    /// `Text(keycap:)` draws it, and `spokenLabel(for:)` turns it back into a word.
    static let spaceGlyph = "␣"

    /// A `displayValue` as VoiceOver and prose should say it.
    static func spokenLabel(for displayValue: String) -> String {
        displayValue.replacingOccurrences(of: spaceGlyph, with: "Space")
    }

    var displayValue: String {
        guard !key.isEmpty else { return "" }
        let label: String
        switch key {
        case " ": label = Self.spaceGlyph
        case "\u{7f}": label = "⌫"
        case "\r": label = "↩"
        case "\t": label = "⇥"
        case "\u{1b}": label = "Esc"
        case "\u{f700}": label = "↑"
        case "\u{f701}": label = "↓"
        case "\u{f702}": label = "←"
        case "\u{f703}": label = "→"
        case "\u{f729}": label = "Home"
        case "\u{f72b}": label = "End"
        case "\u{f72c}": label = "Page Up"
        case "\u{f72d}": label = "Page Down"
        default:
            if let scalar = key.unicodeScalars.first, (0xf704...0xf726).contains(scalar.value) {
                label = "F\(scalar.value - 0xf704 + 1)"
            } else {
                label = modifiers.isEmpty ? key : key.uppercased()
            }
        }
        return (modifiers.contains(.control) ? "⌃" : "")
            + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "")
            + (modifiers.contains(.command) ? "⌘" : "") + label
    }

    var menuKeyEquivalent: String { key == "\u{7f}" ? "\u{8}" : key }

    var isReserved: Bool {
        if key == "\u{1b}" || key == "\t" || key == "\r" { return true }
        if key == "\u{7f}" && !modifiers.contains(.option) { return true }
        guard modifiers.contains(.command) else { return false }
        // Match the fixed handlers' modifier rules, including selection commands which
        // currently accept additional modifiers. Unrelated chords remain available.
        switch key {
        case "a", "c", "x", "v", "d", "w", "z": return true
        case "b", "=", "+", "-", "_": return modifiers.isDisjoint(with: [.option, .control])
        case "r": return modifiers.isDisjoint(with: [.option, .shift])
        case "q", ",": return modifiers == .command
        default: return false
        }
    }

}

enum ShortcutKey: String, CaseIterable {
    case pen = "p"
    case arrow = "a"
    case line = "l"
    case highlighter = "h"
    case rectangle = "r"
    case circle = "o"
    case redact = "x"
    case counter = "n"
    case text = "t"
    case select = "v"
    case eraser = "e"
    case colorPicker = "c"
    case lineWidthPicker = "w"
    case toggleBoard = "b"
    case toggleClickEffects = "k"
    case toggleBackgroundDimming = "toggleBackgroundDimming"
    case toggleFade
    case toggleToolbar
    case decreaseSize
    case increaseSize
    case clearAll
    case captureScreen
    case captureArea
    // One per palette color, in palette order. Unassigned by default (#147).
    case colorRed, colorOrange, colorYellow
    case colorGreen, colorCyan, colorIndigo
    case colorMagenta, colorWhite, colorBlack

    /// The per-color actions, in palette order.
    static let colorActions: [ShortcutKey] = PaletteColor.allCases.map(ShortcutKey.color)

    /// The action that picks `color`.
    static func color(_ color: PaletteColor) -> ShortcutKey {
        switch color {
        case .red: return .colorRed
        case .orange: return .colorOrange
        case .yellow: return .colorYellow
        case .green: return .colorGreen
        case .cyan: return .colorCyan
        case .indigo: return .colorIndigo
        case .magenta: return .colorMagenta
        case .white: return .colorWhite
        case .black: return .colorBlack
        }
    }

    /// The palette color this action picks, or nil for every other action.
    var paletteColor: PaletteColor? {
        PaletteColor.allCases.first { Self.color($0) == self }
    }

    /// Actions whose default binding arrived after users could already customize shortcuts.
    /// An existing custom binding on the same key wins over the new default (see `init`).
    static let newlyEditable: [ShortcutKey] = [
        .toggleFade, .toggleToolbar, .decreaseSize, .increaseSize, .clearAll, .redact, .captureScreen,
        .captureArea,
    ] + colorActions

    var defaultBinding: ShortcutBinding {
        switch self {
        case .toggleBackgroundDimming: return .unassigned
        case .colorRed, .colorOrange, .colorYellow, .colorGreen, .colorCyan, .colorIndigo,
            .colorMagenta, .colorWhite, .colorBlack:
            return .unassigned
        case .toggleFade: return ShortcutBinding(" ")
        case .toggleToolbar: return ShortcutBinding("t", modifiers: [.option, .command])
        case .decreaseSize: return ShortcutBinding("[")
        case .increaseSize: return ShortcutBinding("]")
        case .clearAll: return ShortcutBinding("\u{7f}", modifiers: .option)
        case .captureScreen: return ShortcutBinding("s", modifiers: .command)
        case .captureArea: return ShortcutBinding("s", modifiers: [.shift, .command])
        default: return ShortcutBinding(rawValue)
        }
    }

    var defaultKey: String { defaultBinding.key }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .highlighter: return "Highlighter"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .redact: return "Redact"
        case .counter: return "Counter"
        case .text: return "Text"
        case .select: return "Select"
        case .eraser: return "Eraser"
        case .colorPicker: return "Color Picker"
        case .lineWidthPicker: return "Line Width"
        case .toggleBoard: return "Toggle Board"
        case .toggleClickEffects: return "Toggle Cursor Highlight"
        case .toggleBackgroundDimming: return "Toggle Background Dimming"
        case .toggleFade: return "Toggle Fade Mode"
        case .toggleToolbar: return "Toggle Toolbar"
        case .decreaseSize: return "Decrease Size"
        case .increaseSize: return "Increase Size"
        case .clearAll: return "Clear All"
        case .captureScreen: return "Capture Screen"
        case .captureArea: return "Capture Area"
        case .colorRed, .colorOrange, .colorYellow, .colorGreen, .colorCyan, .colorIndigo,
            .colorMagenta, .colorWhite, .colorBlack:
            return "\(paletteColor?.displayName ?? "") Color"
        }
    }
}

@MainActor
class ShortcutManager: @unchecked Sendable {
    static var shared = ShortcutManager()

    private let settings: SettingsStore
    private let globalShortcutProvider: @MainActor (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?
    private static let globalActions: [(name: KeyboardShortcuts.Name, label: String)] = [
        (.toggleOverlay, "Activation Shortcut"),
        (.toggleAlwaysOnMode, "Always-On Mode")
    ]

    init(userDefaults: UserDefaults = SettingsStore.standard.defaults,
         globalShortcutProvider: @escaping @MainActor (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut) {
        self.settings = SettingsStore(defaults: userDefaults)
        self.globalShortcutProvider = globalShortcutProvider
        // Existing assignments win over newly introduced defaults. Persist the unbound state
        // so clearing the old assignment later does not silently enable a second action.
        // Every other action counts, including other newly editable ones a user already customized.
        // An unassigned default can't conflict, so there is nothing to persist for it.
        for action in ShortcutKey.newlyEditable
        where !action.defaultBinding.key.isEmpty && !settings.hasValue(for: .shortcut(action)) {
            if ShortcutKey.allCases.contains(where: { $0 != action && binding(for: $0) == action.defaultBinding })
                || globalShortcutConflict(for: action.defaultBinding) != nil {
                settings[.shortcut(action)] = .unassigned
            }
        }
    }

    func binding(for tool: ShortcutKey) -> ShortcutBinding {
        settings[.shortcut(tool)]
    }

    /// The logical key, for callers that do not need modifiers (such as picker release tracking).
    func getShortcut(for tool: ShortcutKey) -> String { binding(for: tool).key }

    @discardableResult
    func setShortcut(_ key: String, for tool: ShortcutKey) -> Bool {
        setShortcut(ShortcutBinding(key), for: tool)
    }

    @discardableResult
    func setShortcut(_ binding: ShortcutBinding, for tool: ShortcutKey) -> Bool {
        guard !binding.isReserved, !isShortcutTaken(binding, excluding: tool) else { return false }
        settings[.shortcut(tool)] = binding
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        return true
    }

    func clearShortcut(tool: ShortcutKey) {
        setShortcut(.unassigned, for: tool)
    }

    func matches(_ key: String, tool: ShortcutKey) -> Bool {
        !key.isEmpty && binding(for: tool) == ShortcutBinding(key)
    }

    func matches(_ chord: KeyChord, tool: ShortcutKey) -> Bool {
        binding(for: tool).matches(chord)
    }

    func action(for chord: KeyChord) -> ShortcutKey? {
        ShortcutKey.allCases.first { binding(for: $0).matches(chord) }
    }

    @discardableResult
    func resetToDefault(tool: ShortcutKey) -> Bool {
        guard !isShortcutTaken(tool.defaultBinding, excluding: tool) else { return false }
        settings.removeValue(for: .shortcut(tool))
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        return true
    }

    func resetAllToDefault() {
        ShortcutKey.allCases.forEach { tool in
            settings.removeValue(for: .shortcut(tool))
            if globalShortcutConflict(for: tool.defaultBinding) != nil {
                settings[.shortcut(tool)] = .unassigned
            }
        }
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// A digit that **Use 1–9 for colors** left alone because another action already had it.
    struct SkippedColorDigit: Equatable {
        let color: PaletteColor
        let digit: String
        /// The display name of the action or global shortcut that has the digit.
        let owner: String
    }

    /// Binds each palette color to the digit the color picker shows under its swatch (1 for
    /// the first color, and so on). A digit already bound to any other action stays where it
    /// is, and that color keeps its current binding. A digit held by another color moves once
    /// that color takes its own digit. Returns the digits that were left alone.
    @discardableResult
    func assignDigitsToColors() -> [SkippedColorDigit] {
        let digits = Dictionary(
            uniqueKeysWithValues: PaletteColor.allCases.prefix(9).enumerated().map { index, color in
                (color, ShortcutBinding(String(index + 1)))
            })
        var pending = PaletteColor.allCases.filter { digits[$0] != nil }
        // Repeat while progress is made, so a color can take a digit another color frees.
        var madeProgress = true
        while madeProgress && !pending.isEmpty {
            let before = pending.count
            pending = pending.filter { color in
                guard let digit = digits[color] else { return false }
                let action = ShortcutKey.color(color)
                return binding(for: action) != digit && !setShortcut(digit, for: action)
            }
            madeProgress = pending.count < before
        }
        return pending.compactMap { color in
            guard let digit = digits[color] else { return nil }
            let owner = ShortcutKey.allCases.first { $0 != .color(color) && binding(for: $0) == digit }
            return SkippedColorDigit(
                color: color,
                digit: digit.key,
                owner: owner?.displayName ?? globalShortcutConflict(for: digit) ?? "")
        }
    }

    func isShortcutTaken(_ key: String, excluding tool: ShortcutKey) -> Bool {
        isShortcutTaken(ShortcutBinding(key), excluding: tool)
    }

    func isShortcutTaken(_ binding: ShortcutBinding, excluding tool: ShortcutKey) -> Bool {
        guard !binding.key.isEmpty else { return false }
        return globalShortcutConflict(for: binding) != nil
            || ShortcutKey.allCases.contains { $0 != tool && self.binding(for: $0) == binding }
    }

    func globalShortcutConflict(for binding: ShortcutBinding, excluding name: KeyboardShortcuts.Name? = nil) -> String? {
        guard !binding.key.isEmpty else { return nil }
        return Self.globalActions.first { action in
            guard action.name != name, let shortcut = globalShortcutProvider(action.name) else { return false }
            return ShortcutBinding(globalShortcut: shortcut) == binding
        }?.label
    }

    func conflictForGlobalShortcut(_ shortcut: KeyboardShortcuts.Shortcut, excluding name: KeyboardShortcuts.Name) -> String? {
        guard let candidate = ShortcutBinding(globalShortcut: shortcut) else { return nil }
        if let tool = ShortcutKey.allCases.first(where: { binding(for: $0) == candidate }) {
            return tool.displayName
        }
        return globalShortcutConflict(for: candidate, excluding: name)
    }

    /// Formatted keycaps shared by settings and the floating toolbar.
    var allShortcuts: [ShortcutKey: String] {
        Dictionary(uniqueKeysWithValues: ShortcutKey.allCases.map { ($0, binding(for: $0).displayValue) })
    }
}
