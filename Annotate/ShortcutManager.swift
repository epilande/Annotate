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
        self.key = key == "\u{8}" || key == "\u{f728}" ? "\u{7f}" : key.lowercased()
        self.modifiers = key.isEmpty ? [] : modifiers.intersection(Self.relevantModifiers)
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        let key: String
        switch event.keyCode {
        case 49: key = " "
        case 51, 117: key = "\u{7f}" // Backspace and forward Delete share the overlay action.
        case 53: key = "\u{1b}"
        case 36, 76: key = "\r"
        case 48: key = "\t"
        default: key = event.charactersIgnoringModifiers ?? ""
        }
        guard key.count == 1 else { return nil }
        self.init(key, modifiers: event.modifierFlags)
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

    var displayValue: String {
        guard !key.isEmpty else { return "" }
        let label: String
        switch key {
        case " ": label = "Space"
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

    /// Actions whose default binding arrived after users could already customize shortcuts.
    /// An existing custom binding on the same key wins over the new default (see `init`).
    static let newlyEditable: [ShortcutKey] = [.toggleFade, .toggleToolbar, .decreaseSize, .increaseSize, .clearAll, .redact]

    var defaultBinding: ShortcutBinding {
        switch self {
        case .toggleBackgroundDimming: return .unassigned
        case .toggleFade: return ShortcutBinding(" ")
        case .toggleToolbar: return ShortcutBinding("t", modifiers: [.option, .command])
        case .decreaseSize: return ShortcutBinding("[")
        case .increaseSize: return ShortcutBinding("]")
        case .clearAll: return ShortcutBinding("\u{7f}", modifiers: .option)
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
        }
    }
}

@MainActor
class ShortcutManager: @unchecked Sendable {
    static var shared = ShortcutManager()

    private let defaults: UserDefaults
    private let shortcutPrefix = "shortcut."
    private let globalShortcutProvider: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?
    private static let globalActions: [(name: KeyboardShortcuts.Name, label: String)] = [
        (.toggleOverlay, "Activation Shortcut"),
        (.toggleAlwaysOnMode, "Always-On Mode")
    ]

    init(userDefaults: UserDefaults = .standard,
         globalShortcutProvider: @escaping (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut) {
        self.defaults = userDefaults
        self.globalShortcutProvider = globalShortcutProvider
        // Existing assignments win over newly introduced defaults. Persist the unbound state
        // so clearing the old assignment later does not silently enable a second action.
        let existing = ShortcutKey.allCases.filter { !ShortcutKey.newlyEditable.contains($0) }
        for action in ShortcutKey.newlyEditable where defaults.object(forKey: shortcutPrefix + action.rawValue) == nil {
            if existing.contains(where: { binding(for: $0) == action.defaultBinding })
                || globalShortcutConflict(for: action.defaultBinding) != nil {
                defaults.set("", forKey: shortcutPrefix + action.rawValue)
            }
        }
    }

    func binding(for tool: ShortcutKey) -> ShortcutBinding {
        let storageKey = shortcutPrefix + tool.rawValue
        if let legacyKey = defaults.string(forKey: storageKey) {
            return ShortcutBinding(legacyKey)
        }
        if let value = defaults.dictionary(forKey: storageKey),
            let key = value["key"] as? String,
            let modifiers = (value["modifiers"] as? NSNumber)?.uintValue
        {
            return ShortcutBinding(key, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
        }
        return tool.defaultBinding
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
        defaults.set(["key": binding.key, "modifiers": binding.modifiers.rawValue],
                     forKey: shortcutPrefix + tool.rawValue)
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        return true
    }

    func clearShortcut(tool: ShortcutKey) {
        setShortcut(.unassigned, for: tool)
    }

    func matches(_ key: String, tool: ShortcutKey) -> Bool {
        !key.isEmpty && binding(for: tool) == ShortcutBinding(key)
    }

    func matches(_ event: NSEvent, tool: ShortcutKey) -> Bool {
        guard let candidate = ShortcutBinding(event: event) else { return false }
        return binding(for: tool) == candidate
    }

    func action(for event: NSEvent) -> ShortcutKey? {
        guard let candidate = ShortcutBinding(event: event) else { return nil }
        return ShortcutKey.allCases.first { binding(for: $0) == candidate }
    }

    @discardableResult
    func resetToDefault(tool: ShortcutKey) -> Bool {
        guard !isShortcutTaken(tool.defaultBinding, excluding: tool) else { return false }
        defaults.removeObject(forKey: shortcutPrefix + tool.rawValue)
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        return true
    }

    func resetAllToDefault() {
        ShortcutKey.allCases.forEach { tool in
            defaults.removeObject(forKey: shortcutPrefix + tool.rawValue)
            if globalShortcutConflict(for: tool.defaultBinding) != nil {
                defaults.set("", forKey: shortcutPrefix + tool.rawValue)
            }
        }
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
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
