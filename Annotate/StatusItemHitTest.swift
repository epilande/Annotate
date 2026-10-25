import Cocoa

/// Finds the status item under a press that landed on an overlay (#122). The overlay sits above
/// the menu bar so it can draw over full screen apps, which means the window server hands it every
/// press in the menu bar, including presses on the status item. A window can't let presses through
/// one region, so the overlay asks here and opens the menu itself.
@MainActor
enum StatusItemHitTest {
    struct Hit: Equatable {
        /// The item's column, from the bottom of its menu bar to the top, in screen coordinates.
        let frame: NSRect
        /// Whether the press is on the menu bar that hosts the status item's window, as opposed to
        /// the copy of the item another display's menu bar shows.
        let isOnHostMenuBar: Bool
    }

    /// Taller than any menu bar, including the ones beside a notch. Presses below this strip are
    /// rejected before the window list is read, so drawing never pays for the lookup.
    static let menuBarStripHeight: CGFloat = 64

    /// The status item under `point`, if a menu bar is showing there.
    ///
    /// - Parameters:
    ///   - buttonFrame: The frame of the status item's window, on the display that hosts it.
    ///   - hostScreenFrame: The frame of that display.
    ///   - screenFrames: Every display's frame.
    ///   - menuBarFrames: The menu bars on screen right now, read only when `point` is near the
    ///     top of a display.
    ///
    /// Other displays' menu bars show the same items, laid out from the right edge. The item
    /// therefore keeps its distance from the right edge on every display. That layout is how macOS
    /// arranges status items, not something AppKit reports, so the column on a display other than
    /// the host is inferred. An item macOS hides on a narrow menu bar is not detected as hidden.
    static func hit(
        at point: NSPoint,
        buttonFrame: NSRect,
        hostScreenFrame: NSRect,
        screenFrames: [NSRect],
        menuBarFrames: () -> [NSRect]
    ) -> Hit? {
        guard !buttonFrame.isEmpty,
              let screen = screenFrames.first(where: { $0.contains(point) }),
              point.y >= screen.maxY - menuBarStripHeight
        else { return nil }

        let distanceFromRightEdge = hostScreenFrame.maxX - buttonFrame.maxX
        let minX = screen.maxX - distanceFromRightEdge - buttonFrame.width
        guard point.x >= minX, point.x < minX + buttonFrame.width else { return nil }

        // A hidden menu bar (a full screen app, or auto-hide) is moved off screen or ordered out,
        // so the press belongs to the drawing.
        guard let menuBar = menuBarFrames().first(where: { $0.contains(point) }) else { return nil }
        return Hit(
            frame: NSRect(x: minX, y: menuBar.minY, width: buttonFrame.width, height: menuBar.height),
            isOnHostMenuBar: menuBar.intersects(buttonFrame)
        )
    }

    /// Where to pop the status menu up under the item in `hit`, for
    /// `NSMenu.popUp(positioning: nil, at:in: nil)`, so it lands where clicking the button puts it.
    /// Clicking the button puts the menu window's top left 5 pt left of the item and 1 pt below
    /// the menu bar. `popUp` puts the window's left edge at the point but its top 5 pt above it.
    /// Measured on macOS 27.0.1 by opening the same menu both ways and reading the menu window's
    /// frame from the window list.
    static func popUpMenuLocation(for hit: Hit) -> NSPoint {
        NSPoint(x: hit.frame.minX + popUpMenuOffset.width, y: hit.frame.minY + popUpMenuOffset.height)
    }

    static let popUpMenuOffset = NSSize(width: -5, height: -6)

    /// The menu bars on screen right now, in screen coordinates.
    static func visibleMenuBarFrames() -> [NSRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]],
              let primaryScreen = NSScreen.screens.first
        else { return [] }
        return menuBarFrames(
            in: windows,
            menuBarLevel: Int(CGWindowLevelForKey(.mainMenuWindow)),
            primaryScreenHeight: primaryScreen.frame.height,
            excludingPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    /// The frames of the menu bar windows in a `CGWindowListCopyWindowInfo` list, converted from
    /// window server coordinates (origin at the primary display's top left, y down) to screen
    /// coordinates (origin at its bottom left, y up). Windows are matched by level, because their
    /// owner names are hidden without Screen Recording permission.
    static func menuBarFrames(
        in windows: [[String: Any]],
        menuBarLevel: Int,
        primaryScreenHeight: CGFloat,
        excludingPID: pid_t
    ) -> [NSRect] {
        windows.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == menuBarLevel,
                  window[kCGWindowOwnerPID as String] as? pid_t != excludingPID,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return nil }
            return NSRect(
                x: bounds.minX,
                y: primaryScreenHeight - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
        }
    }
}
