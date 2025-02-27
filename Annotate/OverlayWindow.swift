import Cocoa

class OverlayWindow: NSWindow {
    var overlayView: OverlayView!
    var anchorPoint: NSPoint = .zero
    private var isOptionCurrentlyPressed = false
    private var wasOptionPressedOnMouseDown = false
    private var isCenterModeActive = false

    var fadeTimer: Timer?
    let fadeInterval: TimeInterval = 1.0 / 60.0

    var currentColor: NSColor {
        get { overlayView.currentColor }
        set {
            overlayView.currentColor = newValue
            overlayView.needsDisplay = true
        }
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        let windowRect = NSRect(
            x: contentRect.origin.x,
            y: contentRect.origin.y,
            width: contentRect.width,
            height: contentRect.height
        )

        super.init(
            contentRect: windowRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag)

        self.level = .normal
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.setFrame(windowRect, display: true)

        let containerView = NSView(frame: NSRect(origin: .zero, size: windowRect.size))

        let visualEffect = NSVisualEffectView(frame: containerView.bounds)
        visualEffect.material = .fullScreenUI
        visualEffect.state = .active
        visualEffect.alphaValue = 0
        containerView.addSubview(visualEffect)

        overlayView = OverlayView(frame: containerView.bounds)
        overlayView.wantsLayer = true
        overlayView.layer?.opacity = 0.9
        containerView.addSubview(overlayView)

        self.contentView = containerView
    }

    func startFadeLoop() {
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(
            timeInterval: fadeInterval,
            target: self,
            selector: #selector(updateFade),
            userInfo: nil,
            repeats: true
        )
    }

    func stopFadeLoop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    @objc func updateFade() {
        overlayView.needsDisplay = true

        // Stop the loop if nothing is actively fading
        if !overlayView.isAnythingFading() {
            stopFadeLoop()
        }
    }

    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let startPoint = event.locationInWindow
        anchorPoint = startPoint
        wasOptionPressedOnMouseDown = event.modifierFlags.contains(.option)
        isCenterModeActive = wasOptionPressedOnMouseDown
        let clickCount = event.clickCount

        if let activeTextField = overlayView.activeTextField {
            overlayView.finalizeTextAnnotation(activeTextField)
        }

        if overlayView.currentTool == .counter {
            let counterAnnotation = CounterAnnotation(
                number: overlayView.nextCounterNumber,
                position: startPoint,
                color: currentColor,
                creationTime: CACurrentMediaTime()
            )

            overlayView.registerUndo(action: .addCounter(counterAnnotation))
            overlayView.counterAnnotations.append(counterAnnotation)
            overlayView.nextCounterNumber += 1
            overlayView.needsDisplay = true

            if overlayView.fadeMode {
                startFadeLoop()
            }
            return
        }

        if overlayView.currentTool == .text {
            for (index, annotation) in overlayView.textAnnotations.enumerated() {
                let textRect = getTextRect(for: annotation)
                if textRect.contains(startPoint) {
                    if clickCount == 1 {
                        // Single click - prepare for dragging
                        overlayView.draggedTextAnnotationIndex = index
                        overlayView.dragOffset = NSPoint(
                            x: startPoint.x - annotation.position.x,
                            y: startPoint.y - annotation.position.y
                        )
                        overlayView.originalTextPosition = annotation.position
                    } else if clickCount == 2 {
                        // Double click - edit text
                        overlayView.editingTextAnnotationIndex = index
                        let existingAnnotation = overlayView.textAnnotations[index]

                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: NSFont.systemFont(ofSize: 18)
                        ]
                        let size = existingAnnotation.text.size(withAttributes: attributes)

                        overlayView.createTextField(
                            at: existingAnnotation.position,
                            withText: existingAnnotation.text,
                            width: max(300, size.width + 20)
                        )
                    }
                    return
                }
            }

            // If we didn't click on existing text, create new one
            overlayView.currentTextAnnotation = TextAnnotation(
                text: "",
                position: startPoint,
                color: currentColor,
                fontSize: 18
            )
            overlayView.createTextField(at: startPoint)
        }

        switch overlayView.currentTool {
        case .pen:
            let t = CACurrentMediaTime()
            overlayView.currentPath = DrawingPath(
                points: [TimedPoint(point: startPoint, timestamp: t)],
                color: currentColor)
        case .arrow:
            overlayView.currentArrow = Arrow(
                startPoint: startPoint, endPoint: startPoint, color: currentColor)
        case .highlighter:
            let t = CACurrentMediaTime()
            overlayView.currentHighlight = DrawingPath(
                points: [TimedPoint(point: startPoint, timestamp: t)],
                color: currentColor.withAlphaComponent(0.3))
        case .rectangle:
            overlayView.currentRectangle = Rectangle(
                startPoint: startPoint, endPoint: startPoint, color: overlayView.currentColor)
        case .circle:
            overlayView.currentCircle = Circle(
                startPoint: startPoint, endPoint: startPoint, color: overlayView.currentColor)
        case .text:
            break
        case .counter:
            break
        }
        overlayView.needsDisplay = true
    }

    private func getTextRect(for annotation: TextAnnotation) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize)
        ]
        let size = annotation.text.size(withAttributes: attributes)
        return NSRect(
            x: annotation.position.x,
            y: annotation.position.y,
            width: size.width + 20,
            height: size.height + 10
        )
    }

    override func mouseDragged(with event: NSEvent) {
        overlayView.needsDisplay = true
        let currentPoint = event.locationInWindow

        if let draggedIndex = overlayView.draggedTextAnnotationIndex,
            let dragOffset = overlayView.dragOffset
        {
            // Update the position of the dragged text annotation
            let newPosition = NSPoint(
                x: currentPoint.x - dragOffset.x,
                y: currentPoint.y - dragOffset.y
            )
            overlayView.textAnnotations[draggedIndex].position = newPosition
            overlayView.needsDisplay = true
            return
        }

        switch overlayView.currentTool {
        case .pen:
            let t = CACurrentMediaTime()
            overlayView.currentPath?.points.append(TimedPoint(point: currentPoint, timestamp: t))
        case .arrow:
            overlayView.currentArrow?.endPoint = currentPoint
        case .highlighter:
            let t = CACurrentMediaTime()
            overlayView.currentHighlight?.points.append(
                TimedPoint(point: currentPoint, timestamp: t))
        case .rectangle:
            if isCenterModeActive {
                let dx = currentPoint.x - anchorPoint.x
                let dy = currentPoint.y - anchorPoint.y
                let newStart = NSPoint(x: anchorPoint.x - dx, y: anchorPoint.y - dy)
                let newEnd = NSPoint(x: anchorPoint.x + dx, y: anchorPoint.y + dy)
                overlayView.currentRectangle?.startPoint = newStart
                overlayView.currentRectangle?.endPoint = newEnd
            } else {
                overlayView.currentRectangle?.endPoint = currentPoint
            }
        case .circle:
            if isCenterModeActive {
                let dx = currentPoint.x - anchorPoint.x
                let dy = currentPoint.y - anchorPoint.y
                let newStart = NSPoint(x: anchorPoint.x - dx, y: anchorPoint.y - dy)
                let newEnd = NSPoint(x: anchorPoint.x + dx, y: anchorPoint.y + dy)
                overlayView.currentCircle?.startPoint = newStart
                overlayView.currentCircle?.endPoint = newEnd
            } else {
                overlayView.currentCircle?.endPoint = currentPoint
            }
        case .text:
            break
        case .counter:
            break
        }
        overlayView.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        overlayView.needsDisplay = true

        if let draggedIndex = overlayView.draggedTextAnnotationIndex {
            let oldPosition =
                overlayView.originalTextPosition
                ?? overlayView.textAnnotations[draggedIndex].position
            let newPosition = overlayView.textAnnotations[draggedIndex].position
            if newPosition != oldPosition {
                overlayView.registerUndo(action: .moveText(draggedIndex, oldPosition, newPosition))
            }
            overlayView.draggedTextAnnotationIndex = nil
            overlayView.originalTextPosition = nil
            overlayView.dragOffset = nil
        }

        switch overlayView.currentTool {
        case .pen:
            if var currentPath = overlayView.currentPath {
                let finalTime = CACurrentMediaTime()
                // Find the oldest point’s timestamp
                guard let minTimestamp = currentPath.points.map({ $0.timestamp }).min() else {
                    return
                }
                var updatedPoints = currentPath.points
                // Shift each point so that the oldest is effectively 0 at mouseUp
                let offset = finalTime - minTimestamp
                for i in 0..<updatedPoints.count {
                    updatedPoints[i].timestamp += offset
                }
                currentPath.points = updatedPoints
                overlayView.registerUndo(action: .addPath(currentPath))
                overlayView.paths.append(currentPath)
                overlayView.currentPath = nil
            }
        case .arrow:
            if var currentArrow = overlayView.currentArrow {
                currentArrow.creationTime = CACurrentMediaTime()
                overlayView.registerUndo(action: .addArrow(currentArrow))
                overlayView.arrows.append(currentArrow)
                overlayView.currentArrow = nil
            }
        case .highlighter:
            if var currentHighlight = overlayView.currentHighlight {
                let finalTime = CACurrentMediaTime()
                // Find the oldest point’s timestamp
                guard let minTimestamp = currentHighlight.points.map({ $0.timestamp }).min() else {
                    return
                }
                var updatedPoints = currentHighlight.points
                // Shift each point so that the oldest is effectively 0 at mouseUp
                let offset = finalTime - minTimestamp
                for i in 0..<updatedPoints.count {
                    updatedPoints[i].timestamp += offset
                }
                currentHighlight.points = updatedPoints
                overlayView.registerUndo(action: .addHighlight(currentHighlight))
                overlayView.highlightPaths.append(currentHighlight)
                overlayView.currentHighlight = nil
            }
        case .rectangle:
            if var currentRectangle = overlayView.currentRectangle {
                currentRectangle.creationTime = CACurrentMediaTime()
                overlayView.registerUndo(action: .addRectangle(currentRectangle))
                overlayView.rectangles.append(currentRectangle)
                overlayView.currentRectangle = nil
            }
        case .circle:
            if var currentCircle = overlayView.currentCircle {
                currentCircle.creationTime = CACurrentMediaTime()
                overlayView.registerUndo(action: .addCircle(currentCircle))
                overlayView.circles.append(currentCircle)
                overlayView.currentCircle = nil
            }
        case .text:
            break
        case .counter:
            break
        }
        overlayView.needsDisplay = true
        wasOptionPressedOnMouseDown = false
        isCenterModeActive = false

        if overlayView.fadeMode {
            startFadeLoop()
        }
    }

    override func keyDown(with event: NSEvent) {
        let cmdPressed = event.modifierFlags.contains(.command)
        let key = event.characters?.lowercased() ?? ""

        // Handle single-key shortcuts if no modifiers are pressed
        if !cmdPressed
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        {
            switch key {
            case ShortcutManager.shared.getShortcut(for: .pen):
                AppDelegate.shared?.enablePenMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .arrow):
                AppDelegate.shared?.enableArrowMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .highlighter):
                AppDelegate.shared?.enableHighlighterMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .rectangle):
                AppDelegate.shared?.enableRectangleMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .circle):
                AppDelegate.shared?.enableCircleMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .counter):
                AppDelegate.shared?.enableCounterMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .text):
                AppDelegate.shared?.enableTextMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .colorPicker):
                AppDelegate.shared?.showColorPicker(nil)
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 53:  // ESC key
            AppDelegate.shared?.toggleOverlay()
        case 51:  // Delete/Backspace key
            if event.modifierFlags.contains(.option) {
                overlayView.clearAll()
            } else {
                overlayView.deleteLastItem()
            }
        case 49:  // Spacebar - toggle drawing mode
            AppDelegate.shared?.toggleFadeMode(NSMenuItem())
        case 13:  // 'w' key
            if cmdPressed { AppDelegate.shared?.closeOverlay() }
        case 6:  // 'z' key
            if cmdPressed {
                if event.modifierFlags.contains(.shift) {
                    overlayView.redo()
                } else {
                    overlayView.undo()
                }
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let optionPressed = event.modifierFlags.contains(.option)

        if !wasOptionPressedOnMouseDown {
            if !isOptionCurrentlyPressed && optionPressed {
                recenterAnchorForCurrentShape()
                isCenterModeActive = true
            } else if isOptionCurrentlyPressed && !optionPressed {
                isCenterModeActive = false
            }
        }

        isOptionCurrentlyPressed = optionPressed
    }

    private func recenterAnchorForCurrentShape() {
        if let rect = overlayView.currentRectangle {
            let boundingRect = NSRect(
                x: min(rect.startPoint.x, rect.endPoint.x),
                y: min(rect.startPoint.y, rect.endPoint.y),
                width: abs(rect.endPoint.x - rect.startPoint.x),
                height: abs(rect.endPoint.y - rect.startPoint.y)
            )
            anchorPoint = NSPoint(x: boundingRect.midX, y: boundingRect.midY)
        } else if let circle = overlayView.currentCircle {
            let boundingRect = NSRect(
                x: min(circle.startPoint.x, circle.endPoint.x),
                y: min(circle.startPoint.y, circle.endPoint.y),
                width: abs(circle.endPoint.x - circle.startPoint.x),
                height: abs(circle.endPoint.y - circle.startPoint.y)
            )
            anchorPoint = NSPoint(x: boundingRect.midX, y: boundingRect.midY)
        }
    }
}
