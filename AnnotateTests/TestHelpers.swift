import XCTest

@testable import Annotate

// MARK: - Test Constants
enum TestConstants {
    static let defaultTimeout: TimeInterval = 2.0
    static let defaultDelay: TimeInterval = 0.1
    static let defaultFrameSize = NSSize(width: 800, height: 600)
    static let smallFrameSize = NSSize(width: 400, height: 300)
    static let testSuiteName = "com.annotate.tests"
}

// MARK: - Test UserDefaults
enum TestUserDefaults {
    /// One suite per test process. Xcode's parallel testing isolates classes by process, so
    /// parallel runs cannot clobber each other, and inside one process tests run serially
    /// and `create()` clears the suite before handing it out. A per-call UUID would isolate
    /// just as well, but the preferences daemon keeps an empty plist for every suite name
    /// it has ever seen, which added over a hundred files to the app container per run.
    private static let suiteName =
        "\(TestConstants.testSuiteName).\(ProcessInfo.processInfo.processIdentifier)"

    /// Creates a fresh isolated UserDefaults instance for testing
    /// - Returns: An empty UserDefaults suite completely isolated from production data
    static func create() -> UserDefaults {
        let suite = UserDefaults(suiteName: suiteName)!
        clear(suite)
        return suite
    }

    /// Clears all data from a test UserDefaults suite
    static func clear(_ userDefaults: UserDefaults) {
        userDefaults.dictionaryRepresentation().keys.forEach { key in
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.synchronize()
    }

    /// Completely removes this process's test suite so no test value is left behind in the
    /// app container.
    static func removeSuite() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.synchronize()
    }

    /// A suite separate from `create()`'s, for tests that must read back through a second
    /// `UserDefaults` rather than the writer's in-memory cache. The caller removes it with
    /// `removePersistentDomain(forName:)`.
    static func suite(named name: String) -> UserDefaults {
        UserDefaults(suiteName: name)!
    }
}

extension UserDefaults {
    /// Reads and writes this suite through the app's typed keys.
    var settings: SettingsStore { SettingsStore(defaults: self) }

    /// Stores a value bypassing the key's encoding: a legacy format, or one the key rejects.
    func setRawValue<Value>(_ value: Any, for key: SettingKey<Value>) {
        set(value, forKey: key.name)
    }

    /// The stored value as the key's encoding wrote it.
    func rawValue<Value>(for key: SettingKey<Value>) -> Any? {
        object(forKey: key.name)
    }
}

// MARK: - Test Factory Methods
enum TestFactory {
    static func createTimedPoint(x: CGFloat = 0, y: CGFloat = 0, timestamp: CFTimeInterval = 0)
        -> TimedPoint
    {
        TimedPoint(point: NSPoint(x: x, y: y), timestamp: timestamp)
    }

    static func createDrawingPath(points: [TimedPoint] = [], color: NSColor = .systemRed, lineWidth: CGFloat = 3.0)
        -> DrawingPath
    {
        DrawingPath(points: points, color: color, lineWidth: lineWidth)
    }

    static func createArrow(
        start: NSPoint = .zero,
        end: NSPoint = NSPoint(x: 100, y: 100),
        color: NSColor = .blue,
        lineWidth: CGFloat = 3.0,
        time: CFTimeInterval? = nil
    ) -> Arrow {
        Arrow(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)
    }

    static func createRectangle(
        start: NSPoint = .zero,
        end: NSPoint = NSPoint(x: 100, y: 100),
        color: NSColor = .green,
        lineWidth: CGFloat = 3.0,
        time: CFTimeInterval? = nil
    ) -> Rectangle {
        Rectangle(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)
    }

    static func createCircle(
        start: NSPoint = .zero,
        end: NSPoint = NSPoint(x: 100, y: 100),
        color: NSColor = .purple,
        lineWidth: CGFloat = 3.0,
        time: CFTimeInterval? = nil
    ) -> Circle {
        Circle(startPoint: start, endPoint: end, color: color, lineWidth: lineWidth, creationTime: time)
    }

    static func createTextAnnotation(
        text: String = "Test",
        position: NSPoint = .zero,
        color: NSColor = .black,
        fontSize: CGFloat = 18.0
    ) -> TextAnnotation {
        TextAnnotation(text: text, position: position, color: color, fontSize: fontSize)
    }
}

// MARK: - Test Event Helpers
enum TestEvents {
    static func createMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = [],
        windowNumber: Int = 0
    ) -> NSEvent? {
        return NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
    }

    static func createKeyEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        characters: String = "",
        charactersIgnoringModifiers: String? = nil,
        windowNumber: Int = 0,
        isARepeat: Bool = false
    ) -> NSEvent? {
        return NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        )
    }
    
    static func createScrollEvent(
        deltaY: CGFloat,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        // Create a CGEvent for scroll wheel
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(deltaY),
            wheel2: 0,
            wheel3: 0
        ) else {
            return nil
        }
        
        // Set modifier flags
        cgEvent.flags = CGEventFlags(rawValue: UInt64(modifierFlags.rawValue))
        
        // Convert to NSEvent
        return NSEvent(cgEvent: cgEvent)
    }
}

// MARK: - Mock Classes
class MockOverlayView: OverlayView {
    var drawCalled = false
    var clearAllCalled = false
    var undoCalled = false
    var redoCalled = false

    override func draw(_ dirtyRect: NSRect) {
        drawCalled = true
        super.draw(dirtyRect)
    }

    @discardableResult
    override func clearAll() -> Bool {
        clearAllCalled = true
        return super.clearAll()
    }

    override func undo() {
        undoCalled = true
        super.undo()
    }

    override func redo() {
        redoCalled = true
        super.redo()
    }
}

// MARK: - XCTestCase Extensions
extension XCTestCase {
    func wait(for duration: TimeInterval) {
        // Nested default-mode run loop so GCD asyncAfter (hold/dismiss) can run.
        // Do not wait on XCTestExpectation: that stalls @MainActor tests on CI.
        // Do not run in .common — that is a mode set, not a runnable mode, so
        // the wait elapsed wall-clock without ever draining the main queue.
        guard duration > 0 else { return }
        _ = CFRunLoopRunInMode(.defaultMode, duration, false)
    }

    nonisolated func assertEventually(
        timeout: TimeInterval = TestConstants.defaultTimeout,
        interval: TimeInterval = TestConstants.defaultDelay,
        description: String? = nil,
        condition: @escaping @Sendable () -> Bool
    ) {
        let expectation = self.expectation(description: description ?? "Async condition")

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if condition() {
                timer.invalidate()
                expectation.fulfill()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            timer.invalidate()
        }

        wait(for: [expectation], timeout: timeout + 1)
        XCTAssertTrue(condition(), description ?? "Condition not met within timeout")
    }

    func assertColor(_ color1: NSColor, isCloseTo color2: NSColor, tolerance: CGFloat = 0.01) {
        guard let rgb1 = color1.usingColorSpace(.genericRGB),
            let rgb2 = color2.usingColorSpace(.genericRGB)
        else {
            XCTFail("Colors could not be converted to RGB space")
            return
        }

        XCTAssertEqual(rgb1.redComponent, rgb2.redComponent, accuracy: tolerance)
        XCTAssertEqual(rgb1.greenComponent, rgb2.greenComponent, accuracy: tolerance)
        XCTAssertEqual(rgb1.blueComponent, rgb2.blueComponent, accuracy: tolerance)
        XCTAssertEqual(rgb1.alphaComponent, rgb2.alphaComponent, accuracy: tolerance)
    }

    func assertPoint(_ point1: NSPoint, isCloseTo point2: NSPoint, tolerance: CGFloat = 0.01) {
        XCTAssertEqual(point1.x, point2.x, accuracy: tolerance)
        XCTAssertEqual(point1.y, point2.y, accuracy: tolerance)
    }
}

// MARK: - Window Lifecycle
@MainActor
enum TestWindows {
    /// Windows that existed when the current test started. Under `xcodebuild test` the tests run
    /// inside Annotate.app, whose own overlays and cursor windows stay open the whole time and
    /// react to the notifications tests post. Held weakly so a closed window can still go away.
    private static var presentAtSetUp = NSHashTable<NSWindow>.weakObjects()

    /// Annotate windows that were never closed. A test that drops its last reference to an
    /// overlay without calling `close()` leaves it alive for the rest of the run, where every
    /// `.shortcutsDidChange` post makes it re-measure its toolbar. Two dozen of those once made
    /// the shortcut suites spend most of CI's test time on windows nobody could see.
    ///
    /// AppKit keeps a closed window in `NSApp.windows` until it is deallocated, which can be
    /// after tearDown, so membership alone is not a leak. What `close()` leaves behind is: an
    /// overlay without its toolbar or fade timer, and a cursor window without its display link.
    static var unclosed: [NSWindow] {
        NSApp.windows.filter { window in
            switch window {
            case let overlay as OverlayWindow:
                return overlay.toolbarPanel != nil || overlay.fadeTimer != nil
            case let cursor as CursorHighlightWindow:
                return cursor.animationDisplayLink != nil
            default:
                return false
            }
        }
    }

    /// Call at the start of `setUp` in any suite that calls `assertNoLeakedWindows()`.
    static func recordOpenWindows() {
        presentAtSetUp.removeAllObjects()
        NSApp.windows.forEach { presentAtSetUp.add($0) }
    }

    /// Windows the current test created and did not close.
    static var leaked: [NSWindow] {
        unclosed.filter { !presentAtSetUp.contains($0) }
    }
}

extension XCTestCase {
    /// Call at the end of `tearDown` in any suite that creates an overlay or cursor highlight
    /// window, after the suite has closed its own, with `TestWindows.recordOpenWindows()` at the
    /// start of `setUp`.
    @MainActor
    func assertNoLeakedWindows(file: StaticString = #filePath, line: UInt = #line) {
        let leaked = TestWindows.leaked
        guard !leaked.isEmpty else { return }
        let names = leaked.map { String(describing: type(of: $0)) }.joined(separator: ", ")
        XCTFail("\(name) left \(leaked.count) window(s) open: \(names). Close them in tearDown.",
                file: file, line: line)
        // Close them anyway so one leaky test does not slow down or fail every test after it.
        leaked.forEach { window in
            (window as? CursorHighlightWindow)?.stopAnimationLoop()
            window.close()
        }
    }
}

extension AppDelegate {
    /// Undoes `applicationDidFinishLaunching` for a delegate a test launched: closes its overlay
    /// and cursor highlight windows, removes its status item and event monitors, and stops
    /// observing, so nothing it created outlives the test.
    func tearDownAfterLaunch() {
        overlayWindows.values.forEach { $0.close() }
        overlayWindows.removeAll()
        cursorHighlightWindows.values.forEach {
            $0.stopAnimationLoop()
            $0.close()
        }
        cursorHighlightWindows.removeAll()
        aboutWindow?.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        NotificationCenter.default.removeObserver(self)
        if AppDelegate.shared === self {
            AppDelegate.shared = nil
        }
    }
}
