import Cocoa

@MainActor
class BoardManager: @unchecked Sendable {
    static var shared = BoardManager()

    private let settings: SettingsStore

    init(userDefaults: UserDefaults = SettingsStore.standard.defaults) {
        self.settings = SettingsStore(defaults: userDefaults)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    var isEnabled: Bool {
        get { settings[.enableBoard] }
        set {
            settings[.enableBoard] = newValue
            notifyBoardStateChanged()
        }
    }

    var currentBoardType: BoardView.BoardType {
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDarkMode ? .blackboard : .whiteboard
    }

    var displayName: String {
        return currentBoardType == .blackboard ? "Blackboard" : "Whiteboard"
    }

    var opacity: Double {
        get { settings[.boardOpacity] }
        set {
            settings[.boardOpacity] = newValue.clamped(to: 0.1...1.0)
            NotificationCenter.default.post(name: .boardAppearanceChanged, object: nil)
        }
    }

    func toggle() {
        isEnabled = !isEnabled
    }

    @objc func systemAppearanceChanged() {
        NotificationCenter.default.post(name: .boardAppearanceChanged, object: nil)
    }

    private func notifyBoardStateChanged() {
        NotificationCenter.default.post(name: .boardStateChanged, object: nil)
    }

    /// The board as the renderer sees it right now.
    var appearance: BoardAppearance {
        BoardAppearance(isVisible: isEnabled, type: currentBoardType)
    }

    func adaptColor(_ color: NSColor, forBoardType boardType: BoardView.BoardType) -> NSColor {
        BoardAppearance(isVisible: isEnabled, type: boardType).adapt(color)
    }
}

extension Notification.Name {
    static let boardStateChanged = Notification.Name("BoardStateChangedNotification")
    static let boardAppearanceChanged = Notification.Name("BoardAppearanceChangedNotification")
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
