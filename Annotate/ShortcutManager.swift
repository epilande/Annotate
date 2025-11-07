import Foundation

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("shortcutsDidChange")
}

enum ShortcutKey: String, CaseIterable {
    case pen = "p"
    case arrow = "a"
    case line = "l"
    case highlighter = "h"
    case rectangle = "r"
    case circle = "o"
    case counter = "n"
    case text = "t"
    case select = "v"
    case colorPicker = "c"
    case lineWidthPicker = "w"
    case toggleBoard = "b"

    var defaultKey: String { rawValue }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .highlighter: return "Highlighter"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .counter: return "Counter"
        case .text: return "Text"
        case .select: return "Select"
        case .colorPicker: return "Color Picker"
        case .lineWidthPicker: return "Line Width"
        case .toggleBoard: return "Toggle Board"
        }
    }
}

@MainActor
class ShortcutManager: @unchecked Sendable {
    static var shared = ShortcutManager()

    private let defaults: UserDefaults
    private let shortcutPrefix = "shortcut."

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    func getShortcut(for tool: ShortcutKey) -> String {
        defaults.string(forKey: shortcutPrefix + tool.rawValue) ?? tool.defaultKey
    }

    func setShortcut(_ key: String, for tool: ShortcutKey) {
        if isShortcutTaken(key, excluding: tool) {
            print("Shortcut '\(key)' is already in use.")
            return
        }
        defaults.set(key, forKey: shortcutPrefix + tool.rawValue)
        defaults.synchronize()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func resetToDefault(tool: ShortcutKey) {
        defaults.removeObject(forKey: shortcutPrefix + tool.rawValue)
        defaults.synchronize()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func resetAllToDefault() {
        ShortcutKey.allCases.forEach { tool in
            defaults.removeObject(forKey: shortcutPrefix + tool.rawValue)
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func isShortcutTaken(_ key: String, excluding tool: ShortcutKey) -> Bool {
        for otherTool in ShortcutKey.allCases where otherTool != tool {
            if getShortcut(for: otherTool) == key {
                return true
            }
        }
        return false
    }
}

extension ShortcutManager {
    var allShortcuts: [ShortcutKey: String] {
        Dictionary(uniqueKeysWithValues: ShortcutKey.allCases.map { ($0, getShortcut(for: $0)) })
    }
}
