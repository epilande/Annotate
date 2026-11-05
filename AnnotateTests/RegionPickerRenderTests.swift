import XCTest

@testable import Annotate

/// Renders the picker's layers over a solid background, as they composite on screen.
@MainActor
final class RegionPickerRenderTests: XCTestCase {
    private static let white = RGBA(r: 255, g: 255, b: 255, a: 255)
    private static let black = RGBA(r: 0, g: 0, b: 0, a: 255)
    /// White under the dim layer.
    private static let dimmedWhite: RGBA = {
        let value = Int((255 * (1 - Double(RegionPicker.dimOpacity))).rounded())
        return RGBA(r: value, g: value, b: value, a: 255)
    }()

    private let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

    /// The picker's layers over `background`, as an image whose rows run top-down.
    private func render(_ picker: RegionPicker, over background: RGBA) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: Int(bounds.width),
                height: Int(bounds.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CaptureTestImages.srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(background.cgColor)
        context.fill(bounds)
        try XCTUnwrap(picker.layer).render(in: context)
        return try XCTUnwrap(context.makeImage())
    }

    /// The pixel at a point in the picker's coordinates, whose origin is the bottom-left.
    private func pixel(_ image: CGImage, at point: NSPoint) -> RGBA {
        CaptureTestImages.pixel(image, x: Int(point.x), y: image.height - 1 - Int(point.y))
    }

    private func sublayer(_ name: String, of picker: RegionPicker) throws -> CALayer {
        try XCTUnwrap(picker.layer?.sublayers?.first { $0.name == name }, name)
    }

    func testBeforeADragTheWholeDisplayDims() throws {
        let image = try render(RegionPicker(frame: bounds), over: Self.white)

        for point in [NSPoint(x: 5, y: 5), NSPoint(x: 100, y: 50), NSPoint(x: 195, y: 95)] {
            let color = pixel(image, at: point)
            XCTAssertTrue(color.isClose(to: Self.dimmedWhite), "\(point): \(color)")
        }
    }

    func testTheDraggedRectStaysClearWithADimmedOutside() throws {
        let picker = RegionPicker(frame: bounds)
        picker.mouseDown(at: NSPoint(x: 20, y: 20))
        picker.mouseDragged(to: NSPoint(x: 120, y: 80))

        let image = try render(picker, over: Self.white)

        let inside = pixel(image, at: NSPoint(x: 60, y: 60))
        XCTAssertTrue(inside.isClose(to: Self.white), "Inside the rect is untouched: \(inside)")
        for point in [NSPoint(x: 5, y: 5), NSPoint(x: 160, y: 50), NSPoint(x: 60, y: 95)] {
            let color = pixel(image, at: point)
            XCTAssertTrue(color.isClose(to: Self.dimmedWhite), "\(point): \(color)")
        }
    }

    func testTheRectHasAWhiteBorder() throws {
        let picker = RegionPicker(frame: bounds)
        picker.mouseDown(at: NSPoint(x: 20, y: 20))
        picker.mouseDragged(to: NSPoint(x: 120, y: 80))

        let image = try render(picker, over: Self.black)

        // The border runs just outside the rect's left and top edges.
        for point in [NSPoint(x: 19, y: 50), NSPoint(x: 60, y: 80)] {
            let color = pixel(image, at: point)
            XCTAssertTrue(color.isClose(to: Self.white, tolerance: 40), "\(point): \(color)")
        }
        let inside = pixel(image, at: NSPoint(x: 60, y: 50))
        XCTAssertTrue(inside.isClose(to: Self.black), "\(inside)")
    }

    func testTheSizeLabelShowsOnItsDarkBackground() throws {
        let picker = RegionPicker(frame: bounds)
        picker.mouseDown(at: NSPoint(x: 20, y: 20))
        picker.mouseDragged(to: NSPoint(x: 120, y: 80))
        let label = try sublayer(RegionPicker.LayerName.sizeLabel, of: picker)
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual((label as? CATextLayer)?.string as? String, "100 × 60")

        let image = try render(picker, over: Self.white)

        // The label's corner, clear of its text, shows the dark background over white.
        let corner = pixel(image, at: NSPoint(x: label.frame.minX + 2, y: label.frame.midY))
        XCTAssertLessThan(corner.r, 120, "\(corner)")
    }

    func testAClickResetsTheDrawingToAFullDim() throws {
        let picker = RegionPicker(frame: bounds)
        picker.mouseDown(at: NSPoint(x: 20, y: 20))
        picker.mouseDragged(to: NSPoint(x: 120, y: 80))
        // Released as a click would, under the minimum size.
        picker.mouseUp(at: NSPoint(x: 21, y: 21))

        let image = try render(picker, over: Self.white)

        let formerlyInside = pixel(image, at: NSPoint(x: 60, y: 60))
        XCTAssertTrue(formerlyInside.isClose(to: Self.dimmedWhite), "\(formerlyInside)")
        XCTAssertTrue(try sublayer(RegionPicker.LayerName.sizeLabel, of: picker).isHidden)
        XCTAssertNil((try sublayer(RegionPicker.LayerName.border, of: picker) as? CAShapeLayer)?.path)
    }
}
