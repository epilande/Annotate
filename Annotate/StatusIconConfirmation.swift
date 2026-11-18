import AppKit

/// What the menu bar says about a capture that reached a destination: an icon in the status
/// item, and this announcement for VoiceOver.
enum CaptureConfirmation: String, Equatable {
    case saved = "Capture saved"
    case copied = "Capture copied"

    /// Saved when the image has a file, else copied when it is on the clipboard. Nil when it
    /// went nowhere, which the capture reports as a failure instead.
    init?(_ result: CaptureResult) {
        if result.savedFile != nil {
            self = .saved
        } else if result.copiedToClipboard {
            self = .copied
        } else {
            return nil
        }
    }

    var announcement: String { rawValue }

    /// The glyph the status item shows in a filled ring while this confirmation is up.
    var symbolName: String {
        switch self {
        case .saved: "square.and.arrow.down"
        case .copied: "doc.on.clipboard"
        }
    }

    /// The status item's icon while this confirmation is up: the glyph in a ring filled with
    /// `ringColor`. It draws at whatever scale it is shown at, so it stays sharp at 1x and 2x.
    @MainActor
    func statusIcon(ringColor: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
            let ink = ConfirmationIcon.inkBounds(of: symbol, named: symbolName)
        else { return nil }
        let glyphRect = ConfirmationIcon.glyphRect(symbolSize: symbol.size, inkBounds: ink)
        let image = NSImage(size: ConfirmationIcon.size, flipped: false) { _ in
            ConfirmationIcon.draw(symbol, in: glyphRect, ringColor: ringColor)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = announcement
        return image
    }
}

/// How a confirmation icon is drawn: the pencil icon's 18 pt size and 16 pt ring, filled, with
/// the glyph fit inside the same 11 pt box at its own aspect ratio and centered in the ring on
/// the pixels it inks.
enum ConfirmationIcon {
    static let size = NSSize(width: 18, height: 18)
    static let ring = NSRect(x: 1, y: 1, width: 16, height: 16)
    static let glyphBox = NSSize(width: 11, height: 11)
    /// The glyph's color on a light fill. White is used everywhere else.
    static let darkGlyph = NSColor.black

    /// `size` scaled to fit inside `box` at its own aspect ratio.
    static func fitted(_ size: NSSize, in box: NSSize) -> NSSize {
        let scale = min(box.width / size.width, box.height / size.height)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    /// Where a symbol of `symbolSize` is drawn: fit in `glyphBox`, and moved so the middle of
    /// `inkBounds` (its inked pixels, in the symbol's own points) sits on the ring's middle.
    /// A symbol's image includes padding, such as room below the baseline, so centering the
    /// image itself leaves the glyph off center.
    static func glyphRect(symbolSize: NSSize, inkBounds: CGRect) -> NSRect {
        let fit = fitted(symbolSize, in: glyphBox)
        let scale = fit.width / symbolSize.width
        return NSRect(
            x: ring.midX - inkBounds.midX * scale,
            y: ring.midY - inkBounds.midY * scale,
            width: fit.width,
            height: fit.height)
    }

    /// White when it reaches the 3:1 contrast that graphics need against `fill` (the WCAG
    /// minimum), else dark. Red, gray, magenta, indigo and black keep white; white, yellow,
    /// cyan, green and orange get the dark glyph. Opacity is ignored.
    static func glyphColor(onFill fill: NSColor) -> NSColor {
        guard let luminance = relativeLuminance(of: fill) else { return .white }
        return 1.05 / (luminance + 0.05) >= 3 ? .white : darkGlyph
    }

    /// WCAG relative luminance, 0 for black to 1 for white.
    static func relativeLuminance(of color: NSColor) -> CGFloat? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

    /// Draws the filled ring and `symbol` in the glyph color into the current context.
    static func draw(_ symbol: NSImage, in glyphRect: NSRect, ringColor: NSColor) {
        let circlePath = NSBezierPath(ovalIn: ring)
        ringColor.setFill()
        circlePath.fill()
        ringColor.setStroke()
        circlePath.lineWidth = 1.5
        circlePath.stroke()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // The symbol is black; recolor only its pixels, inside a layer of their own.
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        symbol.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
        glyphColor(onFill: ringColor).setFill()
        glyphRect.fill(using: .sourceIn)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The pixels `symbol` inks, in its own points with a bottom-left origin, measured once per
    /// symbol at 8x. Nil for a symbol that inks nothing.
    @MainActor
    static func inkBounds(of symbol: NSImage, named name: String) -> CGRect? {
        if let known = inkBoundsByName[name] { return known }
        let measured = measureInk(of: symbol, scale: 8)
        inkBoundsByName[name] = measured
        return measured
    }

    @MainActor private static var inkBoundsByName: [String: CGRect] = [:]

    static func measureInk(of symbol: NSImage, scale: Int) -> CGRect? {
        let size = symbol.size
        guard size.width > 0, size.height > 0,
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((size.width * CGFloat(scale)).rounded(.up)),
                pixelsHigh: Int((size.height * CGFloat(scale)).rounded(.up)),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: CGFloat(rep.pixelsWide) / CGFloat(scale), height: CGFloat(rep.pixelsHigh) / CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }
        var minX = Int.max, maxX = Int.min, minRow = Int.max, maxRow = Int.min
        for row in 0..<rep.pixelsHigh {
            for column in 0..<rep.pixelsWide where data[row * rep.bytesPerRow + column * 4 + 3] > 127 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard minX <= maxX else { return nil }
        let pixel = 1 / CGFloat(scale)
        // Rows run top down; points run bottom up.
        return CGRect(
            x: CGFloat(minX) * pixel,
            y: CGFloat(rep.pixelsHigh - 1 - maxRow) * pixel,
            width: CGFloat(maxX - minX + 1) * pixel,
            height: CGFloat(maxRow - minRow + 1) * pixel)
    }
}

/// How long the status item shows a capture's confirmation icon. Each capture starts the time
/// over, and the end always hands the icon back through `onChange`, so the regular icon comes
/// back drawn from the app's state at that moment, never from a copy taken before.
@MainActor
final class StatusIconConfirmation {
    /// Runs `action` after `delay`. Tests substitute one that holds the actions to run by hand.
    typealias Schedule = @MainActor (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Void

    /// A main run loop timer in the common modes, so it fires while the status menu is open,
    /// and in a run loop nested inside a main-queue job, where the main queue itself waits.
    static let runLoopTimer: Schedule = { delay, action in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    var duration: TimeInterval
    private(set) var isShowing = false
    /// How expiries run. Tests set one that holds them to run by hand.
    var schedule: Schedule
    private let onChange: @MainActor () -> Void
    /// Counts every show and end, so only the latest show's expiry ends the confirmation.
    private var generation = 0

    /// `onChange` runs when the confirmation goes up and again when it comes down.
    init(
        duration: TimeInterval = 1.5,
        schedule: @escaping Schedule = StatusIconConfirmation.runLoopTimer,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.duration = duration
        self.schedule = schedule
        self.onChange = onChange
    }

    /// Shows the confirmation for `duration` from now, however long it has been up already.
    func show() {
        generation += 1
        let shown = generation
        schedule(duration) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.end()
        }
        guard !isShowing else { return }
        isShowing = true
        onChange()
    }

    /// Takes the confirmation down now, and keeps any pending expiry from doing anything.
    func end() {
        generation += 1
        guard isShowing else { return }
        isShowing = false
        onChange()
    }
}
