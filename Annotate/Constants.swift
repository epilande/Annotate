import Foundation
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
}
