import Cocoa

@MainActor
class BoardView: NSView {
    enum BoardType {
        case whiteboard
        case blackboard

        @MainActor
        var backgroundColor: NSColor {
            switch self {
            case .whiteboard:
                return NSColor.white.withAlphaComponent(CGFloat(BoardManager.shared.opacity))
            case .blackboard:
                return NSColor(calibratedWhite: 0.1, alpha: CGFloat(BoardManager.shared.opacity))
            }
        }

        var borderColor: NSColor {
            switch self {
            case .whiteboard:
                return NSColor.lightGray
            case .blackboard:
                return NSColor.darkGray
            }
        }
    }

    private var boardType: BoardType = .whiteboard

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.borderWidth = 1

        updateForAppearance()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: .boardAppearanceChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibilityChanged),
            name: .boardStateChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appearanceDidChange() {
        updateForAppearance()
    }

    /// Applied in the same pass that posts the notification, so the board never lags the
    /// menu item, which `AppDelegate` updates synchronously from the same state.
    @objc private func visibilityChanged() {
        isHidden = !BoardManager.shared.isEnabled
    }

    func updateForAppearance() {
        boardType = BoardManager.shared.currentBoardType

        layer?.backgroundColor = boardType.backgroundColor.cgColor
        layer?.borderColor = boardType.borderColor.cgColor

        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateForAppearance()
    }

    /// Showing fades the board in; hiding is instant. The inherited setter has already applied
    /// the new value by the time `didSet` runs, so nothing here may set visibility later. A
    /// fade-out whose completion hid the view used to land after a newer show when the board
    /// was toggled twice within 0.3 s, leaving it hidden while the menu said "Hide".
    override var isHidden: Bool {
        didSet {
            guard oldValue, !isHidden else { return }
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.animator().alphaValue = 1
            }
        }
    }
}
