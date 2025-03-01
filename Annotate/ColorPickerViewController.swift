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

        // Add visual indicators of keyboard shortcuts
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

        // Check if the character is a digit between 1-9
        if let digit = Int(characters), digit >= 1 && digit <= min(9, colorPalette.count) {
            // Find the button with this index and simulate a click
            if digit <= buttons.count {
                let button = buttons[digit - 1]
                colorSwatchClicked(button)
                return true
            }
        }

        return false
    }

    private func updateButtonLabels() {
        // Add number indicators to buttons
        for button in buttons {
            // Remove any existing label
            button.subviews.forEach { if $0 is NSTextField { $0.removeFromSuperview() } }

            // Create a text label to show the shortcut number
            let label = NSTextField()
            label.stringValue = "\(button.colorIndex)"
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.textColor = button.swatchColor.contrastingColor()

            label.font = NSFont.boldSystemFont(ofSize: 12)
            label.alignment = .center

            // Add the label to the button and center it
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

        // Save color to UserDefaults
        if let colorData = try? NSKeyedArchiver.archivedData(
            withRootObject: selectedColor, requiringSecureCoding: false)
        {
            UserDefaults.standard.set(colorData, forKey: "SelectedColor")
        }

        // Apply color app-wide
        appDelegate.currentColor = selectedColor
        appDelegate.overlayWindows.values.forEach { $0.currentColor = selectedColor }
        appDelegate.updateStatusBarIcon(with: selectedColor)

        // Close the popover
        if let presentingPopover = self.view.window?.parent?.contentViewController as? NSPopover {
            presentingPopover.close()
        } else if let parentWindow = self.view.window {
            parentWindow.close()
        }
    }
}
