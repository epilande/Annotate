import SwiftUI
import XCTest

@testable import Annotate

@MainActor
final class EqualWidthColumnTests: XCTestCase {
    /// Frames the children were placed at, in the column's own coordinates.
    private final class PlacedFrames {
        var byIndex: [Int: CGRect] = [:]
    }

    override func setUp() {
        super.setUp()
        TestWindows.recordOpenWindows()
    }

    override func tearDown() {
        assertNoLeakedWindows()
        super.tearDown()
    }

    func testEverySegmentTakesTheWidestNaturalWidth() throws {
        // Flexible children, like the toolbar's segments: each has its own natural width and
        // takes whatever width it is offered.
        let frames = try layOut([
            .flexible(idealWidth: 40, height: 100),
            .flexible(idealWidth: 70, height: 30),
            .flexible(idealWidth: 55, height: 20),
        ])

        XCTAssertEqual(frames.size, CGSize(width: 70, height: 100 + 30 + 20 + 2 * 8))
        XCTAssertEqual(frames.placed[0], CGRect(x: 0, y: 0, width: 70, height: 100))
        XCTAssertEqual(frames.placed[1], CGRect(x: 0, y: 108, width: 70, height: 30))
        XCTAssertEqual(frames.placed[2], CGRect(x: 0, y: 146, width: 70, height: 20))
    }

    func testTheColumnFollowsTheContentRatherThanTheProposal() throws {
        let roomy = try layOut([.flexible(idealWidth: 40, height: 10), .flexible(idealWidth: 64, height: 10)],
                               proposal: CGSize(width: 900, height: 900))
        let tight = try layOut([.flexible(idealWidth: 40, height: 10), .flexible(idealWidth: 64, height: 10)],
                               proposal: CGSize(width: 20, height: 20))

        XCTAssertEqual(roomy.size.width, 64, "Extra room must not widen the column")
        XCTAssertEqual(tight.size.width, 64, "A tight proposal must not squeeze a segment below its content")
    }

    func testARigidSegmentNarrowerThanTheColumnSitsAtTheLeadingEdge() throws {
        let frames = try layOut([.rigid(width: 30, height: 10), .flexible(idealWidth: 50, height: 10)])

        XCTAssertEqual(frames.size.width, 50)
        XCTAssertEqual(frames.placed[0], CGRect(x: 0, y: 0, width: 30, height: 10))
        XCTAssertEqual(frames.placed[1], CGRect(x: 0, y: 18, width: 50, height: 10))
    }

    // MARK: - Helpers

    private enum Child {
        case flexible(idealWidth: CGFloat, height: CGFloat)
        case rigid(width: CGFloat, height: CGFloat)
    }

    private func layOut(
        _ children: [Child], proposal: CGSize = CGSize(width: 500, height: 500)
    ) throws -> (size: CGSize, placed: [Int: CGRect]) {
        let placed = PlacedFrames()
        let column = EqualWidthColumn(spacing: 8) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                Group {
                    switch child {
                    case let .flexible(idealWidth, height):
                        Color.clear.frame(idealWidth: idealWidth, maxWidth: .infinity, minHeight: height, maxHeight: height)
                    case let .rigid(width, height):
                        Color.clear.frame(width: width, height: height)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("column")) } action: {
                    placed.byIndex[index] = $0
                }
            }
        }
        .coordinateSpace(.named("column"))

        let size = NSHostingController(rootView: column).sizeThatFits(in: proposal)
        let host = NSHostingView(rootView: column)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(5)
        while placed.byIndex.count < children.count && Date() < deadline {
            wait(for: 0.01)
        }
        XCTAssertEqual(placed.byIndex.count, children.count, "Every child must report where it was placed")
        return (size, placed.byIndex)
    }
}
