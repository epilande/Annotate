import Cocoa

@MainActor
class BoardManager: @unchecked Sendable {
    static let shared = BoardManager()

    private init() {
        // Register for system appearance changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaults.enableBoardKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.enableBoardKey)
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
        get {
            let storedValue = UserDefaults.standard.double(forKey: UserDefaults.boardOpacityKey)
            return storedValue == 0 ? 0.9 : storedValue.clamped(to: 0.1...1.0)
        }
        set {
            UserDefaults.standard.set(
                newValue.clamped(to: 0.1...1.0), forKey: UserDefaults.boardOpacityKey)
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

    func adaptColor(_ color: NSColor, forBoardType boardType: BoardView.BoardType) -> NSColor {
        guard isEnabled else { return color }

        if boardType == .blackboard && color.isEqual(NSColor.black) {
            return NSColor.white
        } else if boardType == .whiteboard && color.isEqual(NSColor.white) {
            return NSColor.black
        }

        if boardType == .blackboard && color.contrastingColor() == .white {
            return color.blended(withFraction: 0.1, of: NSColor.white) ?? color
        }

        if boardType == .whiteboard && color.contrastingColor() == .black {
            return color.blended(withFraction: 0.1, of: NSColor.black) ?? color
        }

        return color
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
