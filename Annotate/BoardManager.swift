import Cocoa

class BoardManager {
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

        if boardType == .blackboard && color.contrastingColor() == .white {
            if color.isEqual(NSColor.black) {
                return NSColor.white
            }
            return color.blended(withFraction: 0.3, of: NSColor.white) ?? color
        }

        if boardType == .whiteboard && color.contrastingColor() == .black {
            if color.isEqual(NSColor.white) {
                return NSColor.black
            }
            return color.blended(withFraction: 0.3, of: NSColor.black) ?? color
        }

        return color
    }
}

extension Notification.Name {
    static let boardStateChanged = Notification.Name("BoardStateChangedNotification")
    static let boardAppearanceChanged = Notification.Name("BoardAppearanceChangedNotification")
}
