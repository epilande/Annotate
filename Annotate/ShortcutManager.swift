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
    case filledRectangle
    case filledCircle
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
    // One per palette color, in palette order. Unassigned by default (#147). The raw value,
    // which names the stored preference, is the color's palette slot (`PaletteColor.slot`).
    case colorRed = "color1"
    case colorOrange = "color2"
    case colorYellow = "color3"
    case colorGreen = "color4"
    case colorCyan = "color5"
    case colorIndigo = "color6"
    case colorMagenta = "color7"
    case colorWhite = "color8"
    case colorBlack = "color9"

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
        .captureArea, .filledRectangle, .filledCircle,
    ] + colorActions

    var defaultBinding: ShortcutBinding {
        switch self {
        case .toggleBackgroundDimming: return .unassigned
        case .colorRed, .colorOrange, .colorYellow, .colorGreen, .colorCyan, .colorIndigo,
            .colorMagenta, .colorWhite, .colorBlack:
            return .unassigned
        case .filledRectangle: return ShortcutBinding("r", modifiers: .shift)
        case .filledCircle: return ShortcutBinding("o", modifiers: .shift)
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
        case .circle: return "Oval"
        case .filledRectangle: return "Filled Rectangle"
        case .filledCircle: return "Filled Oval"
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

    /// Binds each palette color to its palette position (1 for the first color, and so on).
    /// It first clears every color's number key, so it always restores palette order, even
    /// after colors swapped numbers. A digit bound to any other action stays where it is, and
    /// that color keeps a binding that isn't a number key, or is left unassigned. Returns the
    /// digits that were left alone.
    @discardableResult
    func assignDigitsToColors() -> [SkippedColorDigit] {
        for action in ShortcutKey.colorActions where Self.pickerDigit(of: binding(for: action)) != nil {
            settings[.shortcut(action)] = .unassigned
        }
        var skipped: [SkippedColorDigit] = []
        for (index, color) in PaletteColor.allCases.prefix(9).enumerated() {
            let digit = ShortcutBinding(String(index + 1))
            guard !setShortcut(digit, for: .color(color)) else { continue }
            let owner = ShortcutKey.allCases.first { $0 != .color(color) && binding(for: $0) == digit }
            skipped.append(
                SkippedColorDigit(
                    color: color,
                    digit: digit.key,
                    owner: owner?.displayName ?? globalShortcutConflict(for: digit) ?? ""))
        }
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        return skipped
    }

    /// Records `newBinding` for a color action. When another color already has it, the two
    /// colors trade bindings, so a number moves between colors in one step. Any other conflict
    /// is rejected, as `setShortcut` rejects it.
    @discardableResult
    func setColorShortcut(_ newBinding: ShortcutBinding, for action: ShortcutKey) -> Bool {
        guard action.paletteColor != nil, !newBinding.key.isEmpty, !newBinding.isReserved,
            globalShortcutConflict(for: newBinding) == nil,
            let other = ShortcutKey.colorActions.first(where: { $0 != action && binding(for: $0) == newBinding })
        else { return setShortcut(newBinding, for: action) }
        settings[.shortcut(other)] = binding(for: action)
        settings[.shortcut(action)] = newBinding
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        return true
    }

    /// The number the color picker shows under each palette color, in palette order.
    /// Worked out from the color shortcuts each time the picker opens, and never stored.
    func colorPickerNumbers() -> [Int] {
        Self.colorPickerNumbers(for: PaletteColor.allCases.map { binding(for: .color($0)) })
    }

    /// The color picker's numbers for these color bindings, in palette order. A color bound
    /// to a bare digit uses that digit. Every other color keeps its palette position when no
    /// color took it, and the colors left over take the free numbers in palette order. Only
    /// color bindings are passed in, so a digit bound to another action doesn't move anything.
    static func colorPickerNumbers(for bindings: [ShortcutBinding]) -> [Int] {
        let count = bindings.count
        var used = Set<Int>()
        var numbers: [Int?] = bindings.map { binding in
            guard let digit = pickerDigit(of: binding), digit <= count, used.insert(digit).inserted
            else { return nil }
            return digit
        }
        // Positions are distinct, so claiming them in any order can't collide.
        for index in numbers.indices where numbers[index] == nil && !used.contains(index + 1) {
            numbers[index] = index + 1
            used.insert(index + 1)
        }
        var free = (1...max(count, 1)).filter { !used.contains($0) }
        for index in numbers.indices where numbers[index] == nil && !free.isEmpty {
            numbers[index] = free.removeFirst()
        }
        return numbers.map { $0 ?? 0 }
    }

    /// The digit 1–9 a binding puts on a bare number key, or nil.
    static func pickerDigit(of binding: ShortcutBinding) -> Int? {
        guard binding.modifiers.isEmpty, binding.key.count == 1, let digit = Int(binding.key),
            (1...9).contains(digit)
        else { return nil }
        return digit
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
