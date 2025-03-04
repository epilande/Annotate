import Cocoa

class BoardView: NSView {
    enum BoardType {
        case whiteboard
        case blackboard

        var backgroundColor: NSColor {
            switch self {
            case .whiteboard:
                return NSColor.white.withAlphaComponent(0.95)
            case .blackboard:
                return NSColor(calibratedWhite: 0.1, alpha: 0.95)
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
    private var currentAppearance: NSAppearance?

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
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        updateForAppearance()

        // Register for system appearance changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func appearanceDidChange() {
        updateForAppearance()
    }

    private func updateForAppearance() {
        let newAppearance = self.effectiveAppearance

        let isDarkMode = newAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        boardType = isDarkMode ? .blackboard : .whiteboard

        layer?.backgroundColor = boardType.backgroundColor.cgColor
        layer?.borderColor = boardType.borderColor.cgColor

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateForAppearance()
    }

    func getCurrentBoardType() -> BoardType {
        return boardType
    }

    override var isHidden: Bool {
        didSet {
            if !isHidden && oldValue {
                alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self.animator().alphaValue = 1
                }
            } else if isHidden && !oldValue {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    self.animator().alphaValue = 0
                }) {
                    super.isHidden = true
                }
                return
            }
            super.isHidden = isHidden
        }
    }
}
