import Cocoa
import os

private let log = Logger(subsystem: "com.epilande.Annotate", category: "Capture")

extension NSUserInterfaceItemIdentifier {
    /// The status menu's Recent Captures item.
    static let recentCaptures = Self("recentCaptures")
    /// One recent capture, whose submenu holds its actions.
    static let recentCapture = Self("recentCaptures.capture")
    static let copyRecentCapture = Self("recentCaptures.capture.copy")
    static let openRecentCapture = Self("recentCaptures.capture.open")
    static let showRecentCaptureInFinder = Self("recentCaptures.capture.showInFinder")
    static let noRecentCaptures = Self("recentCaptures.empty")
    static let unreachableCaptureFolder = Self("recentCaptures.unreachableFolder")
    static let openCaptureFolder = Self("recentCaptures.openFolder")
    static let clearRecentCaptures = Self("recentCaptures.clear")
}

/// The Recent Captures submenu, filled from `RecentCaptureStore` whenever it opens or the store
/// changes. It has a delegate of its own: the status menu's delegate drops every overlay back
/// above menus when its menu closes (#122), and this submenu closes while the status menu is
/// still open.
@MainActor
final class RecentCapturesMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Recent Captures")
    private unowned let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        update()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        update()
    }

    /// Brings the items up to date. With the same captures listed, each row keeps its item and
    /// only its title and thumbnail change, so a scan landing while a capture's actions are open
    /// leaves them open.
    func update() {
        let store = appDelegate.recentCaptures
        let rows = menu.items.filter { $0.identifier == .recentCapture }
        let listed = rows.compactMap { $0.representedObject as? URL }
        let hasNote = menu.items.contains { $0.identifier == .unreachableCaptureFolder }
        if !rows.isEmpty, listed == store.captures.map(\.file), hasNote == (store.missedFolder != nil) {
            for (row, capture) in zip(rows, store.captures) {
                row.title = Self.title(for: capture.createdAt)
                row.image = RecentCaptureThumbnail.menuImage(store.thumbnail(for: capture))
            }
            return
        }
        rebuild()
    }

    private func rebuild() {
        let store = appDelegate.recentCaptures
        menu.removeAllItems()
        if let missedFolder = store.missedFolder {
            menu.addItem(
                disabledItem("Can't reach \(missedFolder). Showing the default folder", .unreachableCaptureFolder))
        }
        if store.captures.isEmpty {
            menu.addItem(disabledItem("No Recent Captures", .noRecentCaptures))
        }
        for capture in store.captures {
            menu.addItem(row(for: capture, thumbnail: store.thumbnail(for: capture)))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Open Capture Folder", #selector(AppDelegate.openCaptureFolder(_:)), .openCaptureFolder))
        let clear = actionItem("Clear Menu", #selector(AppDelegate.clearRecentCaptures(_:)), .clearRecentCaptures)
        clear.isHidden = store.captures.isEmpty
        menu.addItem(clear)
    }

    private func row(for capture: RecentCapture, thumbnail: CGImage?) -> NSMenuItem {
        let item = NSMenuItem(title: Self.title(for: capture.createdAt), action: nil, keyEquivalent: "")
        item.identifier = .recentCapture
        item.representedObject = capture.file
        item.image = RecentCaptureThumbnail.menuImage(thumbnail)
        item.toolTip = Self.toolTip(for: capture.file)
        let actions = NSMenu(title: item.title)
        actions.autoenablesItems = false
        for (title, action, identifier) in [
            ("Copy", #selector(AppDelegate.copyRecentCapture(_:)), NSUserInterfaceItemIdentifier.copyRecentCapture),
            ("Open", #selector(AppDelegate.openRecentCapture(_:)), .openRecentCapture),
            ("Show in Finder", #selector(AppDelegate.showRecentCaptureInFinder(_:)), .showRecentCaptureInFinder),
        ] {
            let actionItem = actionItem(title, action, identifier)
            actionItem.representedObject = capture.file
            actions.addItem(actionItem)
        }
        item.submenu = actions
        return item
    }

    /// No key equivalents anywhere in here: one in the status menu works app-wide, overlay
    /// included.
    private func actionItem(_ title: String, _ action: Selector, _ identifier: NSUserInterfaceItemIdentifier)
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = appDelegate
        item.identifier = identifier
        return item
    }

    private func disabledItem(_ title: String, _ identifier: NSUserInterfaceItemIdentifier) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.identifier = identifier
        item.isEnabled = false
        return item
    }

    /// The day relative to today, and the time: "Today at 10:23 AM".
    static func title(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    /// The file's name, then its folder.
    static func toolTip(for file: URL) -> String {
        "\(file.lastPathComponent)\n\(CaptureSettingsView.displayPath(of: file.deletingLastPathComponent()))"
    }
}

/// The status menu's Recent Captures: the latest saved captures, each with Copy, Open, and Show
/// in Finder, then Open Capture Folder and Clear Menu.
extension AppDelegate {
    /// The Recent Captures item, which goes after Capture Area. Each status menu gets a fresh
    /// submenu, since a menu can have only one parent.
    func makeRecentCapturesItem() -> NSMenuItem {
        let recentMenu = RecentCapturesMenu(appDelegate: self)
        recentCapturesMenu = recentMenu
        recentCaptures.onChange = { [weak recentMenu] in recentMenu?.update() }
        let item = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        item.identifier = .recentCaptures
        item.submenu = recentMenu.menu
        return item
    }

    /// Copies the capture's PNG to the clipboard. One that is gone drops out of the menu. Any
    /// other failure says so in an alert, as a capture's would.
    @objc func copyRecentCapture(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? URL else { return }
        let actions = captureFileActions
        let folders = captureFolders
        recentCaptureCopyTask = Task { [weak self] in
            switch await actions.copy(file, from: folders) {
            case .copied:
                break
            case .missing:
                log.notice("Copy: the capture is no longer there")
                self?.recentCaptures.remove(file)
            case .failed(let error):
                log.error("Copy of a recent capture failed: \(error.localizedDescription)")
                self?.queueCaptureProblemAlert(.recentCopyFailed(file, error: error))
            }
        }
    }

    /// Opens the capture in its default app. The interactive overlay closes first, keeping its
    /// drawings, since it would cover the app; Always-On overlays stay.
    @objc func openRecentCapture(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? URL else { return }
        captureFolders.withAccess { _ in
            guard captureFileActions.fileExists(file) else {
                log.notice("Open: the capture is no longer there")
                recentCaptures.remove(file)
                return
            }
            closeInteractiveOverlayKeepingDrawings()
            _ = captureFileActions.open(file)
        }
    }

    /// Shows the capture in Finder, as its notification does.
    @objc func showRecentCaptureInFinder(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? URL else { return }
        if !showCaptureInFinder(file) {
            recentCaptures.remove(file)
        }
    }

    /// Opens the folder captures go to now: the chosen one, or the default folder when there is
    /// none or it can't be reached. Creates it first if it is missing, as Settings does.
    @objc func openCaptureFolder(_ sender: Any?) {
        captureFolders.withAccess { chosen in
            switch CaptureFileActions.prepareFolder(chosen ?? captureDefaultFolder ?? FileSink.defaultFolder) {
            case .success(let folder):
                closeInteractiveOverlayKeepingDrawings()
                _ = captureFileActions.open(folder)
            case .failure(let error):
                log.error("Couldn't open the capture folder: \(error.localizedDescription)")
                queueCaptureProblemAlert(.captureFolderUnavailable(error: error))
            }
        }
    }

    /// Empties the menu. The files stay in their folder.
    @objc func clearRecentCaptures(_ sender: Any?) {
        recentCaptures.clear()
    }
}

extension CaptureProblem {
    static func recentCopyFailed(_ file: URL, error: Error) -> CaptureProblem {
        CaptureProblem(
            title: "Couldn't Copy \(file.lastPathComponent)",
            icon: "⚠️",
            detail: "Annotate couldn't copy the capture to the clipboard. \(error.localizedDescription)")
    }

    static func captureFolderUnavailable(error: Error) -> CaptureProblem {
        CaptureProblem(
            title: "Couldn't Open the Capture Folder",
            icon: "📁",
            detail: CaptureFileActions.folderErrorMessage(error))
    }
}
