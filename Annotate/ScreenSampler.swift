import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ScreenCaptureKit
import os

/// Identifies what a redaction sample was made for: where the rectangle sits and how it
/// renders. The model has no stable id, so any move or restyle yields a new key and
/// therefore a fresh sample.
struct RedactionSampleKey: Hashable {
    let bounds: CGRect
    let style: RectangleStyle

    init(_ rectangle: Rectangle) {
        bounds = rectangle.bounds
        style = rectangle.style
    }
}

/// Filtered screen pixels for one pixelate or blur redaction.
struct RedactionSample {
    let image: CGImage
    /// The view rect the image depicts. Pixelate rounds out to whole blocks, so this can
    /// extend past the rectangle; drawing clips to the rectangle.
    let bounds: CGRect
    let key: RedactionSampleKey
}

/// One capture of a whole display, taken without Annotate's windows. Every pixelate and
/// blur sample is cropped from a snapshot like this.
struct DisplaySnapshot {
    /// The display's pixels, top row first.
    let image: CGImage
    /// The display's frame in Cocoa screen coordinates (points, bottom-left origin).
    let displayFrame: CGRect

    /// Pixels per point, read from the capture itself rather than assumed.
    var scale: CGFloat { CGFloat(image.width) / displayFrame.width }
}

/// A rect to crop out of a snapshot, in Cocoa screen coordinates, and how to filter it.
struct RedactionFilterRequest {
    let screenRect: CGRect
    let style: RectangleStyle
}

/// A filtered crop and the Cocoa screen rect it depicts.
struct RedactionFilterResult {
    let image: CGImage
    let screenRect: CGRect
}

/// Source of filtered screen pixels for pixelate and blur redactions. The overlay view only
/// talks to this protocol so tests can substitute a stub and never touch Screen Recording.
@MainActor
protocol RedactionSampling: AnyObject {
    /// Whether a capture can succeed right now. Checked from the draw loop, so it must be
    /// cheap and must never prompt; asking for Screen Recording access lives in Settings.
    var canSample: Bool { get }

    /// Captures the whole display under `view`, excluding Annotate's windows. `completion`
    /// runs on the main actor with nil on any failure, in which case the caller keeps its
    /// opaque placeholder so nothing behind the rectangle can leak.
    func captureDisplay(under view: NSView, completion: @escaping @MainActor (DisplaySnapshot?) -> Void)

    /// Crops each request out of `snapshot` and filters it, off the main actor. `completion`
    /// runs on the main actor with one entry per request, nil where nothing could be made.
    func filter(
        _ requests: [RedactionFilterRequest], from snapshot: DisplaySnapshot,
        completion: @escaping @MainActor ([RedactionFilterResult?]) -> Void)
}

private let log = Logger(subsystem: "com.epilande.Annotate", category: "ScreenSampler")

/// CIContext is thread-safe; one shared instance avoids rebuilding its GPU state per filter.
private let sharedCIContext = CIContext(options: [.cacheIntermediates: false])

/// Captures displays with ScreenCaptureKit, excluding Annotate's own windows so the overlay,
/// board and toolbar never end up in a sample, and filters crops of those captures.
@MainActor
final class ScreenSampler: RedactionSampling {
    static let shared = ScreenSampler()

    /// Smallest Gaussian blur radius in points; scaled by the backing factor when filtering.
    nonisolated static let minimumBlurRadiusPoints: CGFloat = 20
    /// Smallest pixelate block in points, so small type is unreadable on any display.
    nonisolated static let minimumPixelBlockPoints: CGFloat = 10

    /// Last known Screen Recording state. The draw loop asks per rectangle, so the answer is
    /// cached and refreshed whenever the app becomes active, which is when the user returns
    /// from granting (or revoking) access in System Settings.
    private(set) var hasScreenCaptureAccess = CGPreflightScreenCaptureAccess()

    var canSample: Bool { hasScreenCaptureAccess }

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func applicationDidBecomeActive() {
        refreshScreenCaptureAccess()
    }

    /// Re-reads the permission. Callers that react to activation themselves use the return
    /// value, since notification observers run in no particular order.
    @discardableResult
    func refreshScreenCaptureAccess() -> Bool {
        hasScreenCaptureAccess = CGPreflightScreenCaptureAccess()
        return hasScreenCaptureAccess
    }

    /// Shows the system Screen Recording prompt (macOS only does so the first time). Only
    /// Settings calls this: from the overlay the prompt would open behind the overlay window.
    @discardableResult
    func requestScreenCaptureAccess() -> Bool {
        hasScreenCaptureAccess = CGRequestScreenCaptureAccess()
        return hasScreenCaptureAccess
    }

    func captureDisplay(under view: NSView, completion: @escaping @MainActor (DisplaySnapshot?) -> Void) {
        guard let screen = view.window?.screen, let displayID = screen.displayID else {
            completion(nil)
            return
        }
        let displayFrame = screen.frame
        Task { @MainActor in
            let image = await Self.capture(displayID: displayID)
            completion(image.map { DisplaySnapshot(image: $0, displayFrame: displayFrame) })
        }
    }

    func filter(
        _ requests: [RedactionFilterRequest], from snapshot: DisplaySnapshot,
        completion: @escaping @MainActor ([RedactionFilterResult?]) -> Void
    ) {
        Task { @MainActor in
            completion(await Self.filterOffMain(requests, from: snapshot))
        }
    }

    /// Nonisolated and async, so it runs on the global executor: a large blur never stalls
    /// drawing or mouse tracking; only the completion hops back.
    nonisolated private static func filterOffMain(
        _ requests: [RedactionFilterRequest], from snapshot: DisplaySnapshot
    ) async -> [RedactionFilterResult?] {
        requests.map { makeSample(from: snapshot, screenRect: $0.screenRect, style: $0.style) }
    }

    // MARK: - Geometry

    /// Converts a Cocoa screen rect (bottom-left origin, global coordinates) into the
    /// display-local, top-left-origin rect in points. Returns nil when the rect lies off the
    /// display or is too small to sample.
    nonisolated static func displayLocalRect(screenRect: CGRect, displayFrame: CGRect) -> CGRect? {
        let clipped = screenRect.intersection(displayFrame)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return CGRect(
            x: clipped.minX - displayFrame.minX,
            y: displayFrame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
    }

    /// The pixels of a display snapshot that a Cocoa screen rect covers, top-left origin,
    /// with each edge rounded to the nearest whole pixel.
    nonisolated static func pixelRect(screenRect: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGRect? {
        guard let local = displayLocalRect(screenRect: screenRect, displayFrame: displayFrame) else {
            return nil
        }
        let minX = (local.minX * scale).rounded()
        let minY = (local.minY * scale).rounded()
        let maxX = (local.maxX * scale).rounded()
        let maxY = (local.maxY * scale).rounded()
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The Cocoa screen rect a snapshot pixel rect depicts; the inverse of `pixelRect`.
    nonisolated static func screenRect(pixelRect: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: displayFrame.minX + pixelRect.minX / scale,
            y: displayFrame.maxY - pixelRect.maxY / scale,
            width: pixelRect.width / scale,
            height: pixelRect.height / scale
        )
    }

    /// Pixel block edge for a crop of the given pixel size: at least ten points, and for
    /// larger rectangles about a twelfth of the short side, rounded down to a power-of-two
    /// multiple of the minimum. Dragging a rectangle out therefore changes the block size
    /// only at a few thresholds, and each larger grid lines up with the smaller one.
    nonisolated static func pixelBlockSize(forPixelWidth width: Int, height: Int, scale: CGFloat) -> CGFloat {
        let minimum = max(1, (minimumPixelBlockPoints * scale).rounded())
        let proportional = CGFloat(min(width, height)) / 12
        guard proportional >= minimum * 2 else { return minimum }
        return minimum * exp2(log2(proportional / minimum).rounded(.down))
    }

    /// Blur sigma in pixels for a crop of the given pixel size: at least twenty points,
    /// growing with the rectangle so large type under a large blur does not stay legible.
    nonisolated static func blurSigma(forPixelWidth width: Int, height: Int, scale: CGFloat) -> CGFloat {
        let minimum = minimumBlurRadiusPoints * scale
        let proportional = CGFloat(min(width, height)) / 8
        return max(minimum, proportional).rounded()
    }

    // MARK: - Capture

    /// Captures the whole display at its native pixel size. No `sourceRect`: cropping
    /// happens in `makeSample`, in pixel coordinates we control.
    nonisolated private static func capture(displayID: CGDirectDisplayID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                log.error("No shareable display matches id \(displayID)")
                return nil
            }
            // Excluding our own process is what keeps the placeholder, board and toolbar out
            // of the snapshot. Without a match there is no safe capture, so bail.
            let bundleID = Bundle.main.bundleIdentifier
            let ownApps = content.applications.filter { $0.bundleIdentifier == bundleID }
            guard !ownApps.isEmpty else {
                log.error("Own app not in shareable content; refusing to sample")
                return nil
            }

            let filter = SCContentFilter(
                display: display, excludingApplications: ownApps, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            let pixelScale = CGFloat(filter.pointPixelScale)
            configuration.width = max(1, Int((filter.contentRect.width * pixelScale).rounded()))
            configuration.height = max(1, Int((filter.contentRect.height * pixelScale).rounded()))
            configuration.showsCursor = false
            configuration.captureResolution = .best
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
        } catch {
            log.error("Capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Filters

    /// Crops `screenRect` out of the snapshot and filters it in `style`. Returns nil for
    /// styles that need no pixels and for rects off the display.
    nonisolated static func makeSample(
        from snapshot: DisplaySnapshot, screenRect: CGRect, style: RectangleStyle
    ) -> RedactionFilterResult? {
        let scale = snapshot.scale
        guard
            let rect = pixelRect(
                screenRect: screenRect, displayFrame: snapshot.displayFrame, scale: scale)
        else { return nil }
        let filtered: (image: CGImage, pixelRect: CGRect)?
        switch style {
        case .pixelate: filtered = pixelate(snapshot.image, pixelRect: rect, scale: scale)
        case .blur: filtered = blur(snapshot.image, pixelRect: rect, scale: scale)
        case .outline, .solid: filtered = nil
        }
        guard let filtered else { return nil }
        return RedactionFilterResult(
            image: filtered.image,
            screenRect: Self.screenRect(
                pixelRect: filtered.pixelRect, displayFrame: snapshot.displayFrame, scale: scale))
    }

    /// Averages the blocks of a grid anchored at the display's top-left corner, so a block
    /// always covers the same pixels however the rectangle is dragged. Returns one pixel
    /// per block (drawing it with interpolation off restores the blocks) and the
    /// block-aligned pixel rect it covers, which can run past `rect` by less than a block.
    nonisolated static func pixelate(
        _ image: CGImage, pixelRect rect: CGRect, scale: CGFloat
    ) -> (image: CGImage, pixelRect: CGRect)? {
        let block = pixelBlockSize(forPixelWidth: Int(rect.width), height: Int(rect.height), scale: scale)
        let minX = (rect.minX / block).rounded(.down) * block
        let minY = (rect.minY / block).rounded(.down) * block
        let aligned = CGRect(
            x: minX, y: minY,
            width: (rect.maxX / block).rounded(.up) * block - minX,
            height: (rect.maxY / block).rounded(.up) * block - minY)
        guard let input = croppedInput(image, covering: aligned, padding: 0) else { return nil }
        // A box as wide as a block, read at each block's center, is that block's average.
        // Clamping repeats the display's edge pixels into blocks that hang off the display.
        let blocks = input.clampedToExtent()
            .applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: block / 2])
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 1 / block, y: 1 / block))
        let grid = CGRect(x: 0, y: 0, width: aligned.width / block, height: aligned.height / block)
        guard let output = sharedCIContext.createCGImage(blocks, from: grid) else { return nil }
        return (output, aligned)
    }

    /// Blurs `rect` using the pixels around it, so the edges look like the screen they sit
    /// on instead of smearing the border outward. Returns the blur at a fraction of the
    /// crop's resolution: the blur has already removed the detail the extra pixels would
    /// hold, so it scales back up smoothly.
    nonisolated static func blur(
        _ image: CGImage, pixelRect rect: CGRect, scale: CGFloat
    ) -> (image: CGImage, pixelRect: CGRect)? {
        let sigma = blurSigma(forPixelWidth: Int(rect.width), height: Int(rect.height), scale: scale)
        let downscale = max(1, (sigma / 8).rounded(.down))
        guard let input = croppedInput(image, covering: rect, padding: sigma * 3) else { return nil }
        // Clamping only matters at the display's edges, where there is nothing further out.
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .transformed(by: CGAffineTransform(scaleX: 1 / downscale, y: 1 / downscale))
        let extent = CGRect(
            x: 0, y: 0,
            width: (rect.width / downscale).rounded(.up),
            height: (rect.height / downscale).rounded(.up))
        guard let blurred = sharedCIContext.createCGImage(output, from: extent) else { return nil }
        return (blurred, rect)
    }

    /// Crops `rect` plus `padding` (snapshot pixels, top-left origin) out of `image`, clipped
    /// to the image, as a Core Image image placed so that `rect` spans from the origin.
    /// Cropping the CGImage first keeps Core Image from uploading the whole display.
    nonisolated private static func croppedInput(
        _ image: CGImage, covering rect: CGRect, padding: CGFloat
    ) -> CIImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let region = rect.insetBy(dx: -padding, dy: -padding).intersection(imageBounds).integral
        guard !region.isEmpty, let piece = image.cropping(to: region) else { return nil }
        // Core Image puts the piece's bottom-left corner at the origin; shift it to where
        // that corner sits relative to the bottom-left of `rect`.
        return CIImage(cgImage: piece).transformed(
            by: CGAffineTransform(
                translationX: region.minX - rect.minX, y: rect.maxY - region.maxY))
    }
}

extension NSScreen {
    /// The CoreGraphics display id backing this screen, matching `SCDisplay.displayID`.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
