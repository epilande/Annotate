// Fixture for scripts/ci/check_swiftlint_custom_rules.sh. Never compiled.
// Each line that must trigger a custom rule ends with `// expect: <rule>`;
// every other line must not trigger it. The AnnotateTests/ directory name is
// what puts this file in the rules' `included:` scope.

import AppKit
import Sparkle
import XCTest

final class PositionalLayerLookupFixture: XCTestCase {
    func testPositional(window: CursorHighlightWindow, layer: CALayer, view: NSView) throws {
        let spotlight = try XCTUnwrap(window.highlightView.layer?.sublayers?.first) // expect: positional_layer_lookup
        _ = layer.sublayers!.first // expect: positional_layer_lookup
        _ = layer.sublayers?.first?.opacity // expect: positional_layer_lookup
        _ = view.subviews[0] // expect: positional_layer_lookup
        _ = spotlight
    }

    func testByName(layer: CALayer) {
        _ = layer.sublayers?.first(where: { $0.name == "spotlight" })
        _ = layer.sublayers?.first(where: \.isHidden)
        _ = layer.sublayers?.first { $0.name == "spotlight" }
        _ = layer.sublayers?.first   { $0.name == "dimming" }
        _ = layer.sublayers?.firstIndex(of: layer)
        // A comment mentioning sublayers?.first or subviews[0] is fine.
        _ = "sublayers?.first"
    }
}

final class RealUpdaterFixture: XCTestCase {
    func testUpdater() throws {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.startUpdater() // expect: real_updater_in_tests
        XCTAssertNoThrow(try controller.startUpdater(), "Should be able to start updater") // expect: real_updater_in_tests
        // controller.startUpdater() or try updater.startUpdater() in a comment is fine.
        _ = "controller.startUpdater()"
        XCTAssertFalse(controller.updater.sessionInProgress)
    }
}

final class ObservableModelFixture: ObservableObject { // expect: observable_over_observable_object
    @Published var count = 0
}

class GenericObservableModelFixture<Value>: NSObject, ObservableObject where Value: Equatable { // expect: observable_over_observable_object
    @Published var value: Value?
}

@Observable
final class ObservationModelFixture {
    var count = 0
}

final class PublisherHolderFixture: NSObject {
    let publisher = ObservableObjectPublisher()
    class var shared: any ObservableObject { ObservableModelFixture() }
    // class CommentedModel: ObservableObject is fine.
    let text = "class StringModel: ObservableObject"
}

// The match stays on one line, so a conformance list that wraps is a known miss.
final class WrappedConformanceFixture: NSObject,
    ObservableObject {}
