import Cocoa
import SwiftUI

class ColorSwatchButton: NSButton {
    var swatchColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    var colorIndex: Int = 0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        swatchColor.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

class ColorPickerViewController: NSViewController {
    let colorPalette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .cyan, .systemIndigo,
        .magenta, .white, .black,
    ]

    private var keyMonitor: Any?
    private var buttons: [ColorSwatchButton] = []
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.userDefaults = .standard
        super.init(coder: coder)
    }

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fillEqually
        stackView.spacing = 0

        let columnsPerRow = 3
        var buttonIndex = 0

        for chunk in colorPalette.chunked(into: columnsPerRow) {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.distribution = .fillEqually
            rowStack.spacing = 5

            for color in chunk {
                let button = ColorSwatchButton(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
                button.swatchColor = color
                button.target = self
                button.action = #selector(colorSwatchClicked(_:))

                buttonIndex += 1
                button.colorIndex = buttonIndex

                buttons.append(button)

                rowStack.addArrangedSubview(button)
            }
            stackView.addArrangedSubview(rowStack)
        }

        containerView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
        ])

        self.view = containerView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupKeyboardMonitoring()
        updateButtonLabels()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeKeyboardMonitoring()
    }

    private func setupKeyboardMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let strongSelf = self, strongSelf.handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let characters = event.characters, characters.count == 1 else {
            return false
        }

        if let digit = Int(characters), digit >= 1 && digit <= min(9, colorPalette.count) {
            if digit <= buttons.count {
                let button = buttons[digit - 1]
                colorSwatchClicked(button)
                return true
            }
        }

        return false
    }

    private func updateButtonLabels() {
        for button in buttons {
            button.subviews.forEach { if $0 is NSTextField { $0.removeFromSuperview() } }

            let label = NSTextField()
            label.stringValue = "\(button.colorIndex)"
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.textColor = button.swatchColor.contrastingColor()

            label.font = NSFont.boldSystemFont(ofSize: 12)
            label.alignment = .center

            button.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }
    }

    @objc func colorSwatchClicked(_ sender: ColorSwatchButton) {
        guard let appDelegate = AppDelegate.shared else { return }
        let selectedColor = sender.swatchColor

        if let colorData = try? NSKeyedArchiver.archivedData(
            withRootObject: selectedColor, requiringSecureCoding: false)
        {
            userDefaults.set(colorData, forKey: "SelectedColor")
        }

        appDelegate.currentColor = selectedColor
        appDelegate.overlayWindows.values.forEach { $0.currentColor = selectedColor }
        appDelegate.updateStatusBarIcon(with: selectedColor)

        if let popover = AppDelegate.shared?.colorPopover {
            popover.performClose(nil)
        } else if let parentWindow = self.view.window {
            parentWindow.close()
        }
    }
}
