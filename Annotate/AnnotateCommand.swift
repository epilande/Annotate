import Cocoa

/// An action other apps can trigger: Shortcuts actions today, `annotate://` links next (#134).
/// Each command runs the same `AppDelegate` code the menu and shortcuts do, then shows the
/// on-screen HUD on any open overlay.
enum AnnotateCommand: Equatable {
    case toggle
    case show
    case hide
    /// Selects the tool and opens the overlay.
    case tool(ToolType)
    /// Sets the annotation color without opening the overlay.
    case color(PaletteColor)
    case clear
    /// Shows or hides the overlay toolbar without opening the overlay.
    case toolbar(Switch)
    case fade(Switch)
    case board(Switch)

    /// The target state for an on/off setting.
    enum Switch: String, CaseIterable, Sendable {
        case on, off, toggle

        func resolve(current: Bool) -> Bool {
            switch self {
            case .on: return true
            case .off: return false
            case .toggle: return !current
            }
        }
    }

    @MainActor
    func run(on appDelegate: AppDelegate) {
        switch self {
        case .toggle:
            appDelegate.toggleOverlay()
        case .show:
            appDelegate.showInteractiveOverlay()
        case .hide:
            appDelegate.hideAllOverlays()
        case .tool(let tool):
            // Shows the tool HUD itself.
            appDelegate.switchTool(to: tool)
        case .color(let color):
            appDelegate.setColor(color.nsColor)
            for window in appDelegate.overlayWindows.values where window.isVisible {
                window.showColorFeedback(color)
            }
        case .clear:
            appDelegate.clearVisibleOverlays()
            appDelegate.showToggleFeedback("Cleared", icon: "🗑️")
        case .toolbar(let target):
            let visible = target.resolve(current: appDelegate.toolbarVisible)
            appDelegate.setToolbarVisible(visible)
            appDelegate.showToggleFeedback(visible ? "Toolbar On" : "Toolbar Off", icon: "🧰")
        case .fade(let target):
            // Shows the fade HUD itself.
            appDelegate.setFadeMode(target.resolve(current: appDelegate.fadeModeEnabled))
        case .board(let target):
            let board = BoardManager.shared
            let enabled = target.resolve(current: board.isEnabled)
            appDelegate.setBoardEnabled(enabled)
            appDelegate.showToggleFeedback(
                "\(board.displayName) \(enabled ? "On" : "Off")",
                icon: board.currentBoardType == .blackboard ? "⬛" : "⬜")
        }
    }
}
