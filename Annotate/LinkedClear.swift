import Cocoa

/// One Clear All that emptied several displays at once, as the Shortcuts action and the
/// `annotate://` clear link do (`AppDelegate.clearVisibleOverlays`).
///
/// Each overlay keeps its own undo stack, so the clear leaves an ordinary Clear All step on
/// every display it emptied. This links those steps: undoing or redoing the clear on any display
/// does the same on every other display whose next step is still that clear. Nothing is added
/// to or removed from another display's stack, so each display's own history stays intact.
///
/// A display leaves the link when it records a new step of its own. Drawing after the clear
/// puts the new step above it, and drawing after undoing it empties the redo stack. Either way
/// the clear is no longer that display's next step, so its Undo and Redo go back to acting on
/// that display alone.
@MainActor
final class LinkedClear {
    private let views = NSHashTable<OverlayView>.weakObjects()

    private init() {}

    /// Links the Clear All steps `views` just registered. Does nothing for fewer than two
    /// views, so a clear that emptied one display behaves like any other clear.
    static func link(_ views: [OverlayView]) {
        guard views.count > 1 else { return }
        let linkedClear = LinkedClear()
        for view in views {
            linkedClear.views.add(view)
            view.clearLink = ClearLink(clear: linkedClear)
        }
    }

    /// Undoes the clear on the other displays still waiting to undo it.
    func undo(besides source: OverlayView) {
        for view in members(besides: source) where view.clearLink?.undoesClearNext == true {
            view.undoOnThisDisplay()
        }
    }

    /// Redoes the clear on the other displays still waiting to redo it.
    func redo(besides source: OverlayView) {
        for view in members(besides: source) where view.clearLink?.redoesClearNext == true {
            view.redoOnThisDisplay()
        }
    }

    private func members(besides source: OverlayView) -> [OverlayView] {
        views.allObjects.filter { $0 !== source && $0.clearLink?.clear === self }
    }
}

/// Where one display's undo stack stands relative to its step in a `LinkedClear`.
///
/// `UndoManager` can't say which step is next, so this follows along: every Undo and Redo on
/// the display is recorded here (`OverlayView.undoOnThisDisplay()`), and any new step ends the
/// link (`OverlayView.registerUndo(action:)`). That keeps two facts true while linked. Until the
/// clear is undone, it is the newest step and the redo stack is empty. Once it is undone, it
/// sits on the redo stack under one step for each Undo since.
struct ClearLink {
    let clear: LinkedClear
    private var isUndone = false
    /// Steps undone after the clear was, so that many Redos come before the clear's.
    private var stepsAboveOnRedoStack = 0

    init(clear: LinkedClear) {
        self.clear = clear
    }

    var undoesClearNext: Bool { !isUndone }
    var redoesClearNext: Bool { isUndone && stepsAboveOnRedoStack == 0 }

    /// Records an Undo of a step the display has. Returns the linked clear when that step is
    /// the clear.
    mutating func recordUndo() -> LinkedClear? {
        guard !isUndone else {
            stepsAboveOnRedoStack += 1
            return nil
        }
        isUndone = true
        return clear
    }

    /// Records a Redo of a step the display has. Returns the linked clear when that step is
    /// the clear.
    mutating func recordRedo() -> LinkedClear? {
        guard isUndone else { return nil }
        guard stepsAboveOnRedoStack == 0 else {
            stepsAboveOnRedoStack -= 1
            return nil
        }
        isUndone = false
        return clear
    }
}
