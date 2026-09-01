import Cocoa

final class QuickPickerView: NSView {
    enum Mode: Equatable {
        case color
        case width
        case fontSize
        case counterSize
    }

    static let widthOptions: [CGFloat] = [1, 2, 3, 5, 8, 12, 16, 24]
    static let fontSizeOptions: [CGFloat] = [14, 18, 24, 32, 44, 60, 80, 110]
    static let counterSizeOptions: [CGFloat] = {
        let count = 8
        let span = counterFontSizeRange.upperBound - counterFontSizeRange.lowerBound
        return (0..<count).map {
            (counterFontSizeRange.lowerBound + span * CGFloat($0) / CGFloat(count - 1)).rounded()
        }
    }()

    static let cellSize: CGFloat = 46
    static let padding: CGFloat = 12
    static let commitAnimationDuration: TimeInterval = 0.16
    static let digitFontSize: CGFloat = 10
    static let digitFontWeight: NSFont.Weight = .medium

    static var digitFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: digitFontSize, weight: digitFontWeight)
    }

    let mode: Mode
    private(set) var selectedIndex: Int

    var selectedColor: NSColor? {
        guard mode == .color, colorPalette.indices.contains(selectedIndex) else { return nil }
        return colorPalette[selectedIndex]
    }

    var selectedWidth: CGFloat? {
        selectedValue(for: .width, in: Self.widthOptions)
    }

    var selectedFontSize: CGFloat? {
        selectedValue(for: .fontSize, in: Self.fontSizeOptions)
    }

    var selectedCounterSize: CGFloat? {
        selectedValue(for: .counterSize, in: Self.counterSizeOptions)
    }

    var optionCount: Int {
        mode == .color ? colorPalette.count : options.count
    }
    var previewLaydownAlpha: CGFloat {
        previewTool.laydownAlpha
    }


    private let previewColor: NSColor
    private let previewTool: ToolType
    private var cells: [QuickPickerCellView] = []
    private var glass: NSVisualEffectView!

    private var options: [CGFloat] {
        switch mode {
        case .color:
            return []
        case .width:
            return Self.widthOptions
        case .fontSize:
            return Self.fontSizeOptions
        case .counterSize:
            return Self.counterSizeOptions
        }
    }

    init(
        mode: Mode,
        anchor: NSPoint,
        within placementBounds: NSRect,
        currentColor: NSColor,
        currentWidth: CGFloat,
        currentFontSize: CGFloat = defaultTextAnnotationFontSize,
        currentCounterSize: CGFloat = defaultCounterFontSize,
        previewTool: ToolType
    ) {
        self.mode = mode
        previewColor = currentColor
        self.previewTool = previewTool

        switch mode {
        case .color:
            selectedIndex = colorPalette.firstIndex { $0.isClose(to: currentColor) } ?? 0
        case .width:
            selectedIndex = Self.nearestIndex(in: Self.widthOptions, to: currentWidth)
        case .fontSize:
            selectedIndex = Self.nearestIndex(in: Self.fontSizeOptions, to: currentFontSize)
        case .counterSize:
            selectedIndex = Self.nearestIndex(in: Self.counterSizeOptions, to: currentCounterSize)
        }

        let frame = Self.pickerFrame(
            itemCount: mode == .color ? colorPalette.count : Self.options(for: mode).count,
            anchor: anchor,
            within: placementBounds)
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.masksToBounds = true

        let glass = NSVisualEffectView(frame: bounds)
        glass.autoresizingMask = [.width, .height]
        glass.material = .hudWindow
        glass.blendingMode = .withinWindow
        glass.state = .active
        addSubview(glass)
        self.glass = glass

        buildCells()
        refreshSelection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func nearestIndex(in options: [CGFloat], to value: CGFloat) -> Int {
        options.indices.min { abs(options[$0] - value) < abs(options[$1] - value) } ?? 0
    }

    static func steppedValue(in options: [CGFloat], current: CGFloat, direction: Int) -> CGFloat {
        guard !options.isEmpty else { return current }
        if let first = options.first, current < first, direction < 0 {
            return current
        }
        if let last = options.last, current > last, direction > 0 {
            return current
        }
        let currentIndex = nearestIndex(in: options, to: current)
        let steppedIndex = max(0, min(options.count - 1, currentIndex + direction))
        return options[steppedIndex]
    }

    static func pickerFrame(itemCount: Int, anchor: NSPoint, within bounds: NSRect) -> NSRect {
        let size = NSSize(
            width: padding * 2 + cellSize * CGFloat(itemCount),
            height: padding * 2 + cellSize)
        let insetBounds = bounds.insetBy(dx: 8, dy: 8)

        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y + 28)
        if origin.y + size.height > insetBounds.maxY {
            origin.y = anchor.y - size.height - 28
        }

        if size.width <= insetBounds.width {
            origin.x = max(insetBounds.minX, min(origin.x, insetBounds.maxX - size.width))
        } else {
            origin.x = insetBounds.midX - size.width / 2
        }
        if size.height <= insetBounds.height {
            origin.y = max(insetBounds.minY, min(origin.y, insetBounds.maxY - size.height))
        } else {
            origin.y = insetBounds.midY - size.height / 2
        }

        return NSRect(origin: origin, size: size)
    }

    func index(at pointInSuperview: NSPoint) -> Int? {
        let local = convert(pointInSuperview, from: superview)
        let cellsRect = NSRect(
            x: Self.padding,
            y: Self.padding,
            width: CGFloat(optionCount) * Self.cellSize,
            height: Self.cellSize)
        guard cellsRect.contains(local) else { return nil }
        let index = Int((local.x - Self.padding) / Self.cellSize)
        return (0..<optionCount).contains(index) ? index : nil
    }

    @discardableResult
    func select(at pointInSuperview: NSPoint) -> Bool {
        guard let index = index(at: pointInSuperview) else { return false }
        select(index: index)
        return true
    }

    func select(index: Int) {
        guard (0..<optionCount).contains(index), index != selectedIndex else { return }
        selectedIndex = index
        refreshSelection()
    }

    func updateSelection(mouseInSuperview point: NSPoint) {
        guard let index = index(at: point) else { return }
        select(index: index)
    }

    func animateCommittedSelection(completion: @escaping () -> Void) {
        guard cells.indices.contains(selectedIndex), let layer = cells[selectedIndex].layer else {
            completion()
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1, 1.18, 1]
        animation.keyTimes = [0, 0.45, 1]
        animation.duration = Self.commitAnimationDuration
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        layer.add(animation, forKey: "quick-picker-commit")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.commitAnimationDuration) {
            completion()
        }
    }

    private static func options(for mode: Mode) -> [CGFloat] {
        switch mode {
        case .color:
            return []
        case .width:
            return widthOptions
        case .fontSize:
            return fontSizeOptions
        case .counterSize:
            return counterSizeOptions
        }
    }

    private func selectedValue(for expectedMode: Mode, in options: [CGFloat]) -> CGFloat? {
        guard mode == expectedMode, options.indices.contains(selectedIndex) else { return nil }
        return options[selectedIndex]
    }

    private func buildCells() {
        for index in 0..<optionCount {
            let cell = QuickPickerCellView(
                frame: NSRect(
                    x: Self.padding + CGFloat(index) * Self.cellSize,
                    y: Self.padding,
                    width: Self.cellSize,
                    height: Self.cellSize))
            cell.digit = index + 1
            cell.mode = mode
            cell.color = mode == .color ? colorPalette[index] : previewColor
            cell.value = mode == .color ? 0 : options[index]
            cell.valueRange = mode == .color ? 0...1 : (options.first ?? 0)...(options.last ?? 1)
            cell.laydownAlpha = previewTool.laydownAlpha
            glass.addSubview(cell)
            cells.append(cell)
        }
    }

    private func refreshSelection() {
        for (index, cell) in cells.enumerated() {
            cell.isSelected = index == selectedIndex
        }
    }
}

final class QuickPickerCellView: NSView {
    var digit = 0 {
        didSet { digitView.digit = digit }
    }
    var mode: QuickPickerView.Mode = .color
    var color: NSColor = .white
    var value: CGFloat = 0
    var valueRange: ClosedRange<CGFloat> = 0...1
    var laydownAlpha: CGFloat = 1
    var isSelected = false {
        didSet {
            digitView.isSelected = isSelected
            needsDisplay = true
        }
    }

    private let digitView = QuickPickerDigitView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        digitView.frame = bounds
        digitView.autoresizingMask = [.width, .height]
        addSubview(digitView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isSelected {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10).fill()
        }

        let diameter: CGFloat
        if mode == .color {
            diameter = isSelected ? 29 : 27
        } else {
            let span = valueRange.upperBound - valueRange.lowerBound
            let fraction = span > 0 ? (value - valueRange.lowerBound) / span : 0
            diameter = 8 + fraction * 20
        }

        let dotRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2 + 2,
            width: diameter,
            height: diameter)
        let dot = NSBezierPath(ovalIn: dotRect)
        let fillColor = mode == .color ? color : color.withAlphaComponent(laydownAlpha)
        fillColor.setFill()
        dot.fill()

        if isSelected {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

final class QuickPickerDigitView: NSView {
    var digit = 0 {
        didSet { needsDisplay = true }
    }
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override var allowsVibrancy: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let label = NSAttributedString(
            string: String(digit),
            attributes: [
                .font: QuickPickerView.digitFont,
                .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor
            ])
        let labelSize = label.size()
        label.draw(
            at: NSPoint(
                x: bounds.width - 5 - labelSize.width,
                y: 3))
    }
}
