import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ScreenCaptureKit
import os

/// Identifies one redaction rectangle's capture request. The model has no stable id, so a
/// request is keyed by where the rectangle sits and how it renders; any move or restyle
/// yields a new key and therefore a fresh capture.
struct RedactionSampleKey: Hashable {
    let bounds: CGRect
    let style: RectangleStyle

    init(_ rectangle: Rectangle) {
        bounds = rectangle.bounds
        style = rectangle.style
    }
}

/// Source of filtered screen pixels for pixelate and blur redactions. The overlay view only
/// talks to this protocol so tests can substitute a stub and never touch Screen Recording.
@MainActor
protocol RedactionSampling: AnyObject {
    /// Whether a capture can succeed right now. Checked from the draw loop, so it must be
    /// cheap and must never prompt; asking for Screen Recording access lives in Settings.
    var canSample: Bool { get }

    /// Captures and filters the screen content under `rectangle` (in `view` coordinates).
    /// `completion` runs on the main actor with nil on any failure, in which case the caller
    /// keeps its opaque placeholder so nothing behind the rectangle can leak.
    func requestSample(
        for rectangle: Rectangle, in view: NSView,
        completion: @escaping @MainActor (CGImage?) -> Void)
}

private let log = Logger(subsystem: "com.epilande.Annotate", category: "ScreenSampler")

/// CIContext is thread-safe; one shared instance avoids rebuilding its GPU state per capture.
private let sharedCIContext = CIContext(options: [.cacheIntermediates: false])

/// Captures the region under a redaction rectangle with ScreenCaptureKit, excluding
/// Annotate's own windows so the overlay, board and toolbar never end up in the sample.
@MainActor
final class ScreenSampler: RedactionSampling {
    static let shared = ScreenSampler()

    /// Smallest Gaussian blur radius in points; scaled by the backing factor at capture time.
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

    func requestSample(
        for rectangle: Rectangle, in view: NSView,
        completion: @escaping @MainActor (CGImage?) -> Void
    ) {
        guard let window = view.window,
            let screen = window.screen,
            let displayID = screen.displayID
        else {
            completion(nil)
            return
        }
        let screenRect = window.convertToScreen(view.convert(rectangle.bounds, to: nil))
        guard
            let region = Self.displayLocalRect(screenRect: screenRect, displayFrame: screen.frame)
        else {
            completion(nil)
            return
        }
        let scale = window.backingScaleFactor
        let style = rectangle.style
        Task { @MainActor in
            let filtered = await Self.captureAndFilter(
                displayID: displayID, region: region, scale: scale, style: style)
            completion(filtered)
        }
    }

    // MARK: - Geometry

    /// Converts a Cocoa screen rect (bottom-left origin, global coordinates) into the
    /// display-local, top-left-origin rect in points that ScreenCaptureKit expects. Returns
    /// nil when the rect lies off the display or is too small to sample.
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

    /// Pixel block edge for a capture of the given pixel size: at least ten points, growing
    /// with the rectangle so large redactions do not look like fine mosaics.
    nonisolated static func pixelBlockSize(forPixelWidth width: Int, height: Int, scale: CGFloat) -> CGFloat {
        let minimum = minimumPixelBlockPoints * scale
        let proportional = CGFloat(min(width, height)) / 12
        return max(minimum, proportional).rounded()
    }

    /// Blur sigma in pixels for a capture of the given pixel size: at least twenty points,
    /// growing with the rectangle so large type under a large blur does not stay legible.
    nonisolated static func blurSigma(forPixelWidth width: Int, height: Int, scale: CGFloat) -> CGFloat {
        let minimum = minimumBlurRadiusPoints * scale
        let proportional = CGFloat(min(width, height)) / 8
        return max(minimum, proportional).rounded()
    }

    // MARK: - Capture

    /// Runs capture and filtering together off the main actor so a large blur never
    /// stalls drawing; only the completion hops back.
    nonisolated private static func captureAndFilter(
        displayID: CGDirectDisplayID, region: CGRect, scale: CGFloat, style: RectangleStyle
    ) async -> CGImage? {
        guard let captured = await capture(displayID: displayID, region: region, scale: scale) else {
            return nil
        }
        return filter(captured, style: style, scale: scale)
    }

    nonisolated private static func capture(
        displayID: CGDirectDisplayID, region: CGRect, scale: CGFloat
    ) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                log.error("No shareable display matches id \(displayID)")
                return nil
            }
            // Excluding our own process is what keeps the placeholder, board and toolbar out
            // of the sample. Without a match there is no safe capture, so bail.
            let bundleID = Bundle.main.bundleIdentifier
            let ownApps = content.applications.filter { $0.bundleIdentifier == bundleID }
            guard !ownApps.isEmpty else {
                log.error("Own app not in shareable content; refusing to sample")
                return nil
            }

            let filter = SCContentFilter(
                display: display, excludingApplications: ownApps, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region
            configuration.width = max(1, Int((region.width * scale).rounded()))
            configuration.height = max(1, Int((region.height * scale).rounded()))
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

    /// Applies the redaction style's filter. The result covers the input's extent at a
    /// reduced resolution (see `pixelate` and `blur`) and is scaled up when drawn.
    nonisolated static func filter(_ image: CGImage, style: RectangleStyle, scale: CGFloat) -> CGImage? {
        switch style {
        case .pixelate: return pixelate(image, scale: scale)
        case .blur: return blur(image, scale: scale)
        case .outline, .solid: return nil
        }
    }

    /// Returns one pixel per block (a full-screen sample stays a few kilobytes instead of
    /// tens of megabytes); drawing it with interpolation off restores the blocks.
    nonisolated static func pixelate(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let block = pixelBlockSize(forPixelWidth: image.width, height: image.height, scale: scale)
        let filter = CIFilter.pixellate()
        // Each cell takes the color at its center. Clamping first means the partial cells
        // along the far edges still land on real pixels instead of transparent nothing.
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(block)
        // Anchoring the grid at the origin puts every block on a multiple of the block size,
        // so shrinking by the block size maps each block onto exactly one output pixel.
        filter.center = .zero
        guard let output = filter.outputImage else { return nil }
        let grid = CGRect(
            x: 0, y: 0,
            width: (CGFloat(image.width) / block).rounded(.up),
            height: (CGFloat(image.height) / block).rounded(.up))
        let blocks = output.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 1 / block, y: 1 / block))
        return sharedCIContext.createCGImage(blocks, from: grid)
    }

    /// Returns the blur at a fraction of the capture resolution. The blur has already
    /// removed the detail the extra pixels would hold, so it scales back up smoothly.
    nonisolated static func blur(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let sigma = blurSigma(forPixelWidth: image.width, height: image.height, scale: scale)
        let downscale = max(1, (sigma / 8).rounded(.down))
        // Clamping first stops the blur from pulling transparent black in from outside
        // the extent, which would otherwise darken the border of the sample.
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .transformed(by: CGAffineTransform(scaleX: 1 / downscale, y: 1 / downscale))
        let extent = CGRect(
            x: 0, y: 0,
            width: (CGFloat(image.width) / downscale).rounded(.up),
            height: (CGFloat(image.height) / downscale).rounded(.up))
        return sharedCIContext.createCGImage(output, from: extent)
    }
}

extension NSScreen {
    /// The CoreGraphics display id backing this screen, matching `SCDisplay.displayID`.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
