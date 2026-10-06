import Cocoa

/// Detects the macOS screenshot selection (Cmd+Shift+4, Cmd+Shift+5) by the full-screen window it
/// puts up. There is no public API for this. The same window also stays up during a Cmd+Shift+5
/// recording, so callers must only ask while the selection is holding back mouse events.
@MainActor
enum ScreenshotSelection {
    static let screenshotUIBundleIdentifier = "com.apple.screencaptureui"
    /// `screencapture -i` draws its own selection instead of going through screencaptureui.
    static let commandLineOwnerName = "screencapture"

    static func isVisible() -> Bool {
        let ownerPIDs = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: screenshotUIBundleIdentifier)
                .map(\.processIdentifier)
        )
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        return containsSelectionWindow(
            windows,
            ownerPIDs: ownerPIDs,
            screenSizes: NSScreen.screens.map(\.frame.size)
        )
    }

    /// Whether any window in a `CGWindowListCopyWindowInfo` list belongs to the screenshot UI and
    /// covers a whole display. The size check skips the toolbar and the floating thumbnail.
    static func containsSelectionWindow(
        _ windows: [[String: Any]],
        ownerPIDs: Set<pid_t>,
        screenSizes: [CGSize]
    ) -> Bool {
        windows.contains { window in
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
            let ownerName = window[kCGWindowOwnerName as String] as? String
            guard ownerPID.map(ownerPIDs.contains) == true || ownerName == commandLineOwnerName,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return false }
            return screenSizes.contains { bounds.width >= $0.width && bounds.height >= $0.height }
        }
    }
}
