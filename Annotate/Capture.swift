import AppKit
import ImageIO
import UniformTypeIdentifiers
import os

// Capture Screen: a ScreenCaptureKit snapshot of one display with Annotate's windows left out,
// with the board and annotations composited over it in process. Nothing here reads app
// singletons or views; `AppDelegate+Capture.swift` gathers the overlay's state and passes it in.

private let log = Logger(subsystem: "com.epilande.Annotate", category: "Capture")

/// What a capture covers. The raw value names it in command paths, so renaming a case breaks
/// saved links.
enum CaptureScope: String, CaseIterable, Sendable {
    case screen
}

/// The part of a display a capture keeps.
enum CaptureRegion: Equatable, Sendable {
    case display
}

/// One display, as a capture records it.
struct DisplayInfo: Equatable, Sendable {
    let id: CGDirectDisplayID
    /// The display's frame in Cocoa screen coordinates (points, bottom-left origin).
    let frame: CGRect
    /// Backing pixels per point.
    let scale: CGFloat

    init(id: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }

    @MainActor
    init?(screen: NSScreen) {
        guard let id = screen.displayID else { return nil }
        self.init(id: id, frame: screen.frame, scale: screen.backingScaleFactor)
    }
}

/// Where a capture's screen pixels come from. Implementations must never prompt for Screen
/// Recording; tests substitute a stub so nothing under test touches ScreenCaptureKit.
@MainActor
protocol DisplayCapturing: AnyObject {
    /// Whether a capture can succeed right now, from cached permission state.
    var canCapture: Bool { get }

    /// The whole display at its native pixel size, without Annotate's windows, or nil on any
    /// failure.
    func captureDisplay(_ display: DisplayInfo) async -> DisplaySnapshot?
}

/// What a display's overlay shows: the annotations, the board under them, and how faded
/// each annotation is. Taken when the capture starts.
struct CaptureScene {
    var document: OverlayDocument
    var board: BoardAppearance
    /// The board's opacity, 0.1 to 1. Only used while `board.isVisible`.
    var boardOpacity: CGFloat
    var fade: FadePolicy
    /// The fade clock reading annotations are drawn at.
    var now: CFTimeInterval

    /// A fully opaque board hides every screen pixel, so such a capture needs none.
    var coversScreen: Bool { board.isVisible && boardOpacity >= 1 }
}

/// A capture to make. `scene` is nil when the display's overlay is hidden, which saves the
/// plain screen: that is what is on it.
struct CaptureRequest {
    var display: DisplayInfo
    var region: CaptureRegion = .display
    var scene: CaptureScene?
    /// Mach host time the request was made at, the clock `creationTime` and ScreenCaptureKit
    /// frame times use.
    var hostTime: CFTimeInterval
    var date: Date

    var needsScreenPixels: Bool { !(scene?.coversScreen ?? false) }
}

/// A finished capture: the composited image and what went into it.
struct Capture {
    let image: CGImage
    let display: DisplayInfo
    /// The area the image covers, in display-local points with a top-left origin.
    let region: CGRect
    /// The board and annotations drawn over the screen, or nil for the plain screen.
    let scene: CaptureScene?
    /// Wall clock time of the capture.
    let capturedAt: Date
    /// Mach host time of the capture; see `CaptureRequest.hostTime`.
    let hostTime: CFTimeInterval

    /// Image pixels per point.
    var scale: CGFloat { CGFloat(image.width) / region.width }

    /// The image's size in points.
    var pointSize: NSSize { region.size }
}

/// Where a capture went.
enum CaptureDelivery: Equatable, Sendable {
    case file(URL)
    case clipboard

    var destination: CaptureDestination {
        switch self {
        case .file: return .file
        case .clipboard: return .clipboard
        }
    }
}

/// The kinds of place a capture can go.
enum CaptureDestination: Equatable, Sendable {
    case file
    case clipboard
}

/// A destination for finished captures.
@MainActor
protocol CaptureSink {
    /// What `deliver` returns on success, so a failure can say what didn't happen.
    var destination: CaptureDestination { get }

    func deliver(_ capture: Capture, png: Data) async throws -> CaptureDelivery
}

/// A sink that threw, and what it threw.
struct CaptureSinkFailure {
    let destination: CaptureDestination
    let error: Error
}

/// Why a capture produced nothing.
enum CaptureError: Error, Equatable {
    /// Screen Recording is not granted, and the capture needs screen pixels.
    case screenRecordingOff
    /// ScreenCaptureKit returned nothing.
    case snapshotFailed
    /// The image could not be composited or encoded.
    case renderFailed
}

/// The outcome of a capture that produced an image. `failures` holds the sinks that threw;
/// a capture with no delivery at all throws instead.
struct CaptureResult {
    let capture: Capture
    let deliveries: [CaptureDelivery]
    let failures: [CaptureSinkFailure]

    var savedFile: URL? {
        deliveries.lazy.compactMap { if case .file(let url) = $0 { return url } else { return nil } }.first
    }

    var copiedToClipboard: Bool { deliveries.contains(.clipboard) }

    /// The error a sink of `destination` threw, if one did.
    func failure(of destination: CaptureDestination) -> Error? {
        failures.first { $0.destination == destination }?.error
    }
}

/// Makes captures: takes the screen pixels, composites the scene over them, encodes a PNG,
/// and hands it to each sink.
@MainActor
final class CaptureService {
    let source: DisplayCapturing
    let sinks: [CaptureSink]

    init(source: DisplayCapturing, sinks: [CaptureSink]) {
        self.source = source
        self.sinks = sinks
    }

    func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        var snapshot: DisplaySnapshot?
        if request.needsScreenPixels {
            guard source.canCapture else { throw CaptureError.screenRecordingOff }
            guard let taken = await source.captureDisplay(request.display) else {
                throw CaptureError.snapshotFailed
            }
            snapshot = taken
        }

        var scene = request.scene
        if let current = scene {
            scene?.document = await CaptureCompositor.resampleRedactions(
                in: current.document, from: snapshot, display: request.display)
        }

        guard let image = CaptureCompositor.composite(snapshot: snapshot, display: request.display, scene: scene)
        else { throw CaptureError.renderFailed }
        let capture = Capture(
            image: image,
            display: request.display,
            region: CGRect(origin: .zero, size: request.display.frame.size),
            scene: scene,
            capturedAt: request.date,
            hostTime: request.hostTime)

        guard let png = await CaptureCompositor.encodePNG(image, scale: capture.scale) else {
            throw CaptureError.renderFailed
        }

        var deliveries: [CaptureDelivery] = []
        var failures: [CaptureSinkFailure] = []
        for sink in sinks {
            do {
                deliveries.append(try await sink.deliver(capture, png: png))
            } catch {
                log.error("Capture sink failed: \(error.localizedDescription)")
                failures.append(CaptureSinkFailure(destination: sink.destination, error: error))
            }
        }
        if deliveries.isEmpty, let first = failures.first { throw first.error }
        return CaptureResult(capture: capture, deliveries: deliveries, failures: failures)
    }
}

/// Builds a capture's image: screen pixels, then the board, then the annotations.
@MainActor
enum CaptureCompositor {
    /// Draws `scene` over `snapshot` at the snapshot's pixel size, or at the display's backing
    /// scale when there is no snapshot. Selection chrome and live previews never draw: the
    /// renderer leaves them out. Returns nil if no bitmap context can be made.
    static func composite(snapshot: DisplaySnapshot?, display: DisplayInfo, scene: CaptureScene?) -> CGImage? {
        let pointSize = display.frame.size
        let pixelWidth: Int
        let pixelHeight: Int
        if let snapshot {
            pixelWidth = snapshot.image.width
            pixelHeight = snapshot.image.height
        } else {
            pixelWidth = Int((pointSize.width * display.scale).rounded())
            pixelHeight = Int((pointSize.height * display.scale).rounded())
        }
        guard pixelWidth > 0, pixelHeight > 0, pointSize.width > 0, pointSize.height > 0,
            let context = makeContext(width: pixelWidth, height: pixelHeight, like: snapshot?.image)
        else { return nil }

        let pixelBounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        if let snapshot {
            context.draw(snapshot.image, in: pixelBounds)
        }

        context.scaleBy(x: CGFloat(pixelWidth) / pointSize.width, y: CGFloat(pixelHeight) / pointSize.height)
        if let scene {
            let canvas = CGRect(origin: .zero, size: pointSize)
            if scene.board.isVisible {
                context.setFillColor(scene.board.type.backgroundColor(opacity: scene.boardOpacity).cgColor)
                context.fill(canvas)
            }
            AnnotationRenderer(
                document: scene.document,
                live: nil,
                board: scene.board,
                fade: scene.fade,
                now: scene.now,
                canvas: canvas
            ).draw(in: context)
        }
        return context.makeImage()
    }

    /// A copy of `document` whose pixelate and blur redactions hold samples from `snapshot`,
    /// the pixels this capture saves. Samples the overlay made earlier can show what was
    /// under the rectangle before the screen changed, so every one is replaced; without a
    /// snapshot each redaction draws its opaque placeholder.
    static func resampleRedactions(
        in document: OverlayDocument, from snapshot: DisplaySnapshot?, display: DisplayInfo
    ) async -> OverlayDocument {
        var document = document
        let indices = document.rectangles.indices.filter { document.rectangles[$0].needsSample }
        for index in indices {
            document.rectangles[index].sample = nil
        }
        guard let snapshot, !indices.isEmpty else { return document }

        let origin = display.frame.origin
        let requests = indices.map { index in
            let rectangle = document.rectangles[index]
            return RedactionFilterRequest(
                screenRect: rectangle.bounds.offsetBy(dx: origin.x, dy: origin.y), style: rectangle.style)
        }
        let results = await filterOffMain(requests, from: snapshot)
        for (index, result) in zip(indices, results) {
            guard let result else { continue }
            let rectangle = document.rectangles[index]
            document.rectangles[index].sample = RedactionSample(
                image: result.image,
                bounds: result.screenRect.offsetBy(dx: -origin.x, dy: -origin.y),
                key: RedactionSampleKey(rectangle))
        }
        return document
    }

    nonisolated private static func filterOffMain(
        _ requests: [RedactionFilterRequest], from snapshot: DisplaySnapshot
    ) async -> [RedactionFilterResult?] {
        requests.map { ScreenSampler.makeSample(from: snapshot, screenRect: $0.screenRect, style: $0.style) }
    }

    /// PNG data with DPI metadata of 72 times `scale`, as `screencapture` writes, so apps
    /// that honor it show the image at its point size. Runs off the main actor: a 5K
    /// composite takes a while to compress.
    nonisolated static func encodePNG(_ image: CGImage, scale: CGFloat) async -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let dpi = 72 * scale
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A premultiplied 8-bit RGBA context in the snapshot's color space, which is the
    /// display's, so annotation colors land as the overlay shows them. sRGB when there is no
    /// snapshot or its space can't back a bitmap.
    private static func makeContext(width: Int, height: Int, like image: CGImage?) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        let candidates = [image?.colorSpace, srgb].compactMap { $0 }.filter { $0.model == .rgb }
        for space in candidates {
            if let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: bitmapInfo)
            {
                return context
            }
        }
        return nil
    }
}
