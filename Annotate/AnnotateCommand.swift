import Cocoa

/// An action other apps can trigger: Shortcuts actions today, `annotate://` links next (#134).
/// Each command runs the same `AppDelegate` code the menu and shortcuts do, then shows the
/// on-screen HUD on any open overlay.
enum AnnotateCommand: Hashable, Sendable {
    case toggle
    case show
    case hide
    /// Selects the tool and opens the overlay.
    case tool(ToolType)
    /// Sets the annotation color without opening the overlay.
    case color(PaletteColor)
    case clear
    /// Shows or hides the overlay toolbar without opening the overlay.
    case toolbar(CommandSwitch)
    case fade(CommandSwitch)
    case board(CommandSwitch)

    /// Whether running a command changed anything.
    enum Outcome: Equatable, Sendable {
        case ran
        /// The app was already in the requested state, or there was nothing to act on.
        case noOp
    }

    // MARK: - Path form

    /// The command's stable string form, `/<command>[/<value>]`, such as `/show`, `/tool/arrow`,
    /// or `/toolbar/off`. Values are the raw values of `ToolType`, `PaletteColor`, and
    /// `CommandSwitch`.
    var path: String {
        switch self {
        case .toggle: return "/toggle"
        case .show: return "/show"
        case .hide: return "/hide"
        case .tool(let tool): return "/tool/\(tool.rawValue)"
        case .color(let color): return "/color/\(color.rawValue)"
        case .clear: return "/clear"
        case .toolbar(let target): return "/toolbar/\(target.rawValue)"
        case .fade(let target): return "/fade/\(target.rawValue)"
        case .board(let target): return "/board/\(target.rawValue)"
        }
    }

    /// Parses `path`'s form. The leading slash is optional, a trailing slash is ignored, and
    /// matching ignores case. Returns nil for an unknown command, a missing or unknown value,
    /// a value on a command that takes none, or extra components.
    init?(path: String) {
        var trimmed = Substring(path.lowercased())
        if trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
        if trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let name = components.first, components.count <= 2 else { return nil }
        let value = components.count == 2 ? components[1] : nil

        switch (name, value) {
        case ("toggle", nil): self = .toggle
        case ("show", nil): self = .show
        case ("hide", nil): self = .hide
        case ("clear", nil): self = .clear
        case ("tool", let value?):
            guard let tool = ToolType(rawValue: value) else { return nil }
            self = .tool(tool)
        case ("color", let value?):
            guard let color = PaletteColor(rawValue: value) else { return nil }
            self = .color(color)
        case ("toolbar", let value?):
            guard let target = CommandSwitch(rawValue: value) else { return nil }
            self = .toolbar(target)
        case ("fade", let value?):
            guard let target = CommandSwitch(rawValue: value) else { return nil }
            self = .fade(target)
        case ("board", let value?):
            guard let target = CommandSwitch(rawValue: value) else { return nil }
            self = .board(target)
        default:
            return nil
        }
    }

    // MARK: - Running

    @MainActor
    @discardableResult
    func run(on appDelegate: AppDelegate) -> Outcome {
        switch self {
        case .toggle, .show, .hide:
            let before = OverlayState(appDelegate)
            switch self {
            case .toggle: appDelegate.toggleOverlay()
            case .show: appDelegate.showInteractiveOverlay()
            default: appDelegate.hideAllOverlays()
            }
            return OverlayState(appDelegate) == before ? .noOp : .ran
        case .tool(let tool):
            let before = OverlayState(appDelegate)
            let toolAlreadySet = appDelegate.overlayWindows.values.allSatisfy {
                $0.overlayView.currentTool == tool
            }
            // Shows the tool HUD itself. Also opens the overlay under the pointer, which may be
            // hidden while another display's overlay is open.
            appDelegate.switchTool(to: tool)
            return toolAlreadySet && OverlayState(appDelegate) == before ? .noOp : .ran
        case .color(let color):
            let alreadySet = appDelegate.currentColor.isClose(to: color.nsColor)
            appDelegate.setColor(color.nsColor)
            for window in appDelegate.overlayWindows.values where window.isVisible {
                window.showColorFeedback(color)
            }
            return alreadySet ? .noOp : .ran
        case .clear:
            guard appDelegate.clearVisibleOverlays() else { return .noOp }
            appDelegate.showToggleFeedback("Cleared", icon: "🗑️")
            return .ran
        // A switch already in the requested state still shows its HUD, which reports the state.
        case .toolbar(let target):
            let current = appDelegate.toolbarVisible
            let visible = target.resolve(current: current)
            appDelegate.setToolbarVisible(visible)
            appDelegate.showToggleFeedback(visible ? "Toolbar On" : "Toolbar Off", icon: "🧰")
            return visible == current ? .noOp : .ran
        case .fade(let target):
            let current = appDelegate.fadeModeEnabled
            let enabled = target.resolve(current: current)
            // Shows the fade HUD itself.
            appDelegate.setFadeMode(enabled)
            return enabled == current ? .noOp : .ran
        case .board(let target):
            let board = BoardManager.shared
            let current = board.isEnabled
            let enabled = target.resolve(current: current)
            appDelegate.setBoardEnabled(enabled)
            appDelegate.showToggleFeedback(
                "\(board.displayName) \(enabled ? "On" : "Off")",
                icon: board.currentBoardType == .blackboard ? "⬛" : "⬜")
            return enabled == current ? .noOp : .ran
        }
    }

    /// What show, hide, toggle, and tool can change: the mode and which overlays are on screen.
    @MainActor
    private struct OverlayState: Equatable {
        let alwaysOn: Bool
        let visible: Set<ObjectIdentifier>

        init(_ appDelegate: AppDelegate) {
            alwaysOn = appDelegate.alwaysOnMode
            visible = Set(appDelegate.overlayWindows.values.filter(\.isVisible).map(ObjectIdentifier.init))
        }
    }
}

/// The target state for an on/off setting. The raw value names the state in Shortcuts
/// actions and command paths, so renaming a case breaks saved shortcuts and links.
///
/// Top level rather than nested in `AnnotateCommand`: Xcode 26's App Intents metadata
/// extraction can't read the static display representations of a nested `AppEnum`.
enum CommandSwitch: String, CaseIterable, Sendable {
    case on, off, toggle

    func resolve(current: Bool) -> Bool {
        switch self {
        case .on: return true
        case .off: return false
        case .toggle: return !current
        }
    }
}
