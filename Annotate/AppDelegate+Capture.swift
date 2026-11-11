import Cocoa
import os

private let log = Logger(subsystem: "com.epilande.Annotate", category: "Capture")

/// Hears how a capture ended, once: with the result when it delivered the image anywhere,
/// or with the error that stopped it.
typealias CaptureCompletion = @MainActor (Result<CaptureResult, Error>) -> Void

/// What a Shortcuts action gets back from a capture.
struct CapturedImage: Equatable, Sendable {
    let png: Data
    /// The saved file, or nil when After Capture is Copy to clipboard or the save failed.
    let savedFile: URL?
    let capturedAt: Date

    init(png: Data, savedFile: URL?, capturedAt: Date) {
        self.png = png
        self.savedFile = savedFile
        self.capturedAt = capturedAt
    }

    init(_ result: CaptureResult) {
        self.init(png: result.png, savedFile: result.savedFile, capturedAt: result.capture.capturedAt)
    }
}

/// Capture Screen and Capture Area from the menu, the overlay shortcuts, Shortcuts actions, and
/// `AnnotateCommand.capture`: picks the display, reads what its overlay shows, and reports the
/// result on that overlay.
extension AppDelegate {
    /// The display a capture saves: the key interactive overlay's, else the one under the
    /// pointer, else the main display.
    static func captureTarget<Display>(keyOverlay: Display?, pointer: Display?, main: Display?) -> Display? {
        keyOverlay ?? pointer ?? main
    }

    /// Where captures can go: a file and the clipboard. The file goes in the folder
    /// `chosenFolder` holds, or in `folder` when there is none or it can't be reached. Each
    /// request's `afterCapture` picks from these. In a debug build launched with
    /// `FileSink.failSavesArgument`, every save fails.
    static func captureSinks(
        folder: URL = FileSink.defaultFolder,
        chosenFolder: CaptureFolderStore? = nil,
        pasteboard: NSPasteboard = .general,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> [CaptureSink] {
        var file = FileSink(folder: folder, chosenFolder: chosenFolder)
        #if DEBUG
        if arguments.contains(FileSink.failSavesArgument) {
            log.notice("Capture saves fail on purpose: launched with \(FileSink.failSavesArgument, privacy: .public)")
            file.writeBytes = { _, _ in throw FileSink.ForcedSaveFailure() }
        }
        #endif
        return [file, ClipboardSink(pasteboard: pasteboard)]
    }

    var captureTargetScreen: NSScreen? {
        let keyOverlay = alwaysOnMode
            ? nil : overlayWindows.first { $0.value.isVisible && $0.value.isKeyWindow }?.key
        return Self.captureTarget(keyOverlay: keyOverlay, pointer: getCurrentScreen(), main: NSScreen.main)
    }

    /// The display Capture Area picks on: the key interactive overlay's, else the open overlay
    /// under the pointer, else any open overlay.
    private var areaTargetScreen: NSScreen? {
        let open = overlayWindows.filter { $0.value.isVisible }
        if let key = open.first(where: { $0.value.isKeyWindow })?.key { return key }
        if let pointer = getCurrentScreen(), open[pointer] != nil { return pointer }
        return NSScreen.screens.first { open[$0] != nil }
    }

    func capture(_ scope: CaptureScope) {
        switch scope {
        case .screen: captureScreen()
        case .area: captureArea()
        }
    }

    /// Runs a capture for a Shortcuts action and returns the image once it has gone where After
    /// Capture says. It reports on the overlay and sends the notification as the menu does, but
    /// a capture that delivered nothing throws instead of showing an alert, since Shortcuts
    /// shows the error. Capture Area waits for the drag, and throws `CaptureError.cancelled`
    /// when the picker closes without one.
    func captureForShortcuts(_ scope: CaptureScope) async throws -> CapturedImage {
        try await withCheckedThrowingContinuation { continuation in
            let completion: CaptureCompletion = { continuation.resume(with: $0.map(CapturedImage.init)) }
            switch scope {
            case .screen: startScreenCapture(alertsOnFailure: false, completion: completion)
            case .area: startAreaCapture(alertsOnFailure: false, completion: completion)
            }
        }
    }

    /// Saves the display with its board and annotations, as its overlay shows them, and copies
    /// the image, as After Capture says. With the overlay hidden it takes the plain screen.
    @objc func captureScreen() {
        startScreenCapture()
    }

    private func startScreenCapture(alertsOnFailure: Bool = true, completion: CaptureCompletion? = nil) {
        guard let screen = captureTargetScreen, let display = DisplayInfo(screen: screen) else {
            log.error("No display to capture")
            completion?(.failure(CaptureError.snapshotFailed))
            return
        }
        let overlay = overlayWindows[screen]
        startCapture(
            CaptureRequest(
                display: display,
                scene: overlay.flatMap { $0.isVisible ? captureScene(of: $0) : nil },
                hostTime: CACurrentMediaTime(),
                date: Date(),
                afterCapture: settings[.afterCapture]),
            on: overlay,
            alertsOnFailure: alertsOnFailure,
            completion: completion)
    }

    /// Lets the user drag out part of a display, then handles it with its board and annotations
    /// as Capture Screen does. The picker needs the interactive overlay, so with
    /// none open, including in Always-On, this opens it first. The fade holds while picking,
    /// and the capture shows each annotation at the fade the picker showed.
    @objc func captureArea() {
        startAreaCapture()
    }

    /// `completion` hears the capture's outcome, or why there was none: Screen Recording is
    /// off, the picker couldn't open, or it closed without a pick.
    private func startAreaCapture(alertsOnFailure: Bool = true, completion: CaptureCompletion? = nil) {
        // Without Screen Recording the drag would come to nothing, so ask before anything opens.
        // From Always-On, the Screen Recording flow brings Always-On back afterwards, drawings
        // and all.
        let board = BoardManager.shared
        if !captureService.source.canCapture,
            !CaptureScene.boardCoversScreen(board.appearance, opacity: CGFloat(board.opacity))
        {
            showScreenRecordingOff(on: areaTargetScreen.flatMap { overlayWindows[$0] })
            completion?(.failure(CaptureError.screenRecordingOff))
            return
        }
        var heldAlwaysOnFade: OverlayWindow?
        if !isInteractiveOverlayOpen {
            // Always-On annotations are on screen, so the overlay opening over them keeps them,
            // even with Clear Drawings on Start, and keeps Always-On's Persist fade until the
            // picker closes, or leaving Always-On would expire the older ones at once.
            if alwaysOnMode, let screen = getCurrentScreen(), let overlay = overlayWindows[screen] {
                overlaysKeepingDrawings.insert(ObjectIdentifier(overlay))
                overlaysHoldingAlwaysOnFade.insert(ObjectIdentifier(overlay))
                heldAlwaysOnFade = overlay
            }
            showInteractiveOverlay()
        }
        let opened = beginAreaPicker(
            releasingHeldFadeOf: heldAlwaysOnFade, alertsOnFailure: alertsOnFailure, completion: completion)
        if !opened {
            if let heldAlwaysOnFade {
                releaseHeldAlwaysOnFade(of: heldAlwaysOnFade)
            }
            completion?(.failure(CaptureError.pickerUnavailable))
        }
    }

    /// Opens the picker on the target display, and returns whether it opened. When it does,
    /// closing it in any way releases `held`'s Always-On fade, and `completion` hears either
    /// the capture's outcome or, when the picker closed without a pick, `CaptureError.cancelled`.
    private func beginAreaPicker(
        releasingHeldFadeOf held: OverlayWindow?, alertsOnFailure: Bool, completion: CaptureCompletion?
    ) -> Bool {
        guard let screen = areaTargetScreen, let overlay = overlayWindows[screen],
            let display = DisplayInfo(screen: screen)
        else {
            log.error("No overlay to pick an area on")
            return false
        }
        guard !overlay.isRegionPickerOpen else { return false }
        // The picker reads Escape from its own overlay, and another display's may be key.
        overlay.makeKeyAndOrderFront(nil)
        // The picker calls `onDismiss` after `onPick` too, so this tells a pick from a cancel.
        var picked = false
        let onDismiss: () -> Void = { [weak self] in
            if let self, let held {
                self.releaseHeldAlwaysOnFade(of: held)
            }
            if !picked {
                completion?(.failure(CaptureError.cancelled))
            }
        }
        return overlay.beginRegionPicker(onDismiss: onDismiss) { [weak self, weak overlay] rect in
            guard let self, let overlay else { return }
            picked = true
            // Runs before the picker closes, so the scene's fade clock is still frozen.
            self.startCapture(
                CaptureRequest(
                    display: display,
                    region: .rect(fromViewRect: rect, displayHeight: display.frame.height),
                    scene: self.captureScene(of: overlay),
                    hostTime: CACurrentMediaTime(),
                    date: Date(),
                    afterCapture: self.settings[.afterCapture]),
                on: overlay,
                alertsOnFailure: alertsOnFailure,
                completion: completion)
        }
    }

    /// Gives an overlay Capture Area opened from Always-On its Fade Mode setting back. Back in
    /// Always-On, as when its shortcut ended the pick, Persist stays as Always-On wants.
    func releaseHeldAlwaysOnFade(of overlay: OverlayWindow) {
        guard overlaysHoldingAlwaysOnFade.remove(ObjectIdentifier(overlay)) != nil, !alwaysOnMode else { return }
        overlay.overlayView.fadeMode = settings[.fadeMode]
    }

    /// `alertsOnFailure` false leaves a capture that delivered nothing to the caller, which
    /// reports it itself; the overlay's HUD still says so.
    private func startCapture(
        _ request: CaptureRequest, on overlay: OverlayWindow?, alertsOnFailure: Bool = true,
        completion: CaptureCompletion? = nil
    ) {
        // Each capture waits for the one before it, so captures finish in the order they were
        // asked for: an older image never replaces a newer one on the clipboard or in the HUD,
        // and every capture still gets its own file. The scene above is already taken, so the
        // annotations are the ones on screen when this capture was asked for.
        let service = captureService
        let previous = captureTask
        captureTask = Task { @MainActor [weak self] in
            await previous?.value
            // The caller hears first: a problem alert is modal, and a Shortcuts action
            // shouldn't wait on it.
            do {
                let result = try await service.capture(request)
                completion?(.success(result))
                self?.reportCapture(result, on: overlay)
            } catch {
                completion?(.failure(error))
                self?.reportCaptureFailure(error, on: overlay, alerts: alertsOnFailure)
            }
        }
    }

    private func reportCaptureFailure(_ error: Error, on overlay: OverlayWindow?, alerts: Bool) {
        switch error {
        case CaptureError.screenRecordingOff:
            showScreenRecordingOff(on: overlay)
        case is CaptureError:
            log.error("Capture failed")
            reportCaptureProblem(.failed, on: overlay, alerts: alerts)
        default:
            log.error("Capture failed: \(error.localizedDescription)")
            reportCaptureProblem(.undelivered(error: error), on: overlay, alerts: alerts)
        }
    }

    /// The overlay's picture as it stands. Commits a label being typed first, as closing the
    /// overlay does, so the capture holds what the user sees.
    private func captureScene(of overlay: OverlayWindow) -> CaptureScene {
        let view: OverlayView = overlay.overlayView
        if let activeField = view.activeTextField {
            view.finalizeTextAnnotation(activeField)
        }
        let board = BoardManager.shared
        return CaptureScene(
            document: view.document,
            board: board.appearance,
            boardOpacity: CGFloat(board.opacity),
            fade: view.fade,
            now: view.fadeClock())
    }

    /// A system notification, when allowed, and the overlay's HUD, when it is open. A problem
    /// takes the HUD's place, and shows even with the overlay closed.
    private func reportCapture(_ result: CaptureResult, on overlay: OverlayWindow?) {
        if let notice = CaptureNotice(result) {
            captureNotifier.post(notice)
        }
        if let problem = CaptureProblem(result) {
            reportCaptureProblem(problem, on: overlay)
            return
        }
        guard let overlay, overlay.isVisible else { return }
        if let file = result.savedFile {
            overlay.showToggleFeedback("Saved \(file.lastPathComponent)", icon: "📸")
        } else if result.copiedToClipboard {
            overlay.showToggleFeedback("Copied to Clipboard", icon: "📋")
        }
    }

    /// On the overlay's HUD when it is open and showing feedback. Otherwise an alert: from the
    /// status menu with the overlay closed, or with Hide Tool Feedback on, a failed capture is
    /// never silent. `alerts` false skips the alert, for a caller that reports the problem itself.
    private func reportCaptureProblem(_ problem: CaptureProblem, on overlay: OverlayWindow?, alerts: Bool = true) {
        if let overlay, overlay.isVisible, !settings[.hideToolFeedback] {
            overlay.showToggleFeedback(problem.title, icon: problem.icon)
        } else if alerts {
            showCaptureProblemAlert(problem.title, problem.detail)
        }
    }

    /// Never asks from here: the system prompt would open under the overlay. Says so on the
    /// overlay, then gets every overlay out of the way and opens Settings to Capture, which
    /// asks. When the prompt from an earlier capture is still up, Settings stays closed so
    /// it can't cover the prompt. Annotations stay for when the overlay opens again.
    private func showScreenRecordingOff(on overlay: OverlayWindow?) {
        let showsNotice = overlay?.isVisible == true && !settings[.hideToolFeedback]
        overlay?.showToggleFeedback(
            isPrivacyPromptOnScreen()
                ? "Screen Recording is off. Answer the macOS prompt"
                : "Screen Recording is off. Opening Settings…",
            icon: "🔒")
        DispatchQueue.main.asyncAfter(deadline: .now() + (showsNotice ? screenRecordingNoticeDelay : 0)) {
            [weak self] in
            guard let self else { return }
            self.moveOverlaysAsideForPermission()
            if self.isPrivacyPromptOnScreen() {
                self.restoreOverlaysWhenPermissionUIIsGone()
                return
            }
            self.isSettingsOpenForPermission = true
            self.openSettingsPane(.capture, true) { [weak self] in
                self?.isSettingsOpenForPermission = false
                self?.restoreOverlaysWhenPermissionUIIsGone()
            }
        }
    }

    /// Closes the interactive overlay, keeping its drawings for the next time it opens.
    /// Always-On overlays sit above every normal window, so their annotations would cover
    /// Settings and the system prompt; they are ordered out instead, to come back later.
    private func moveOverlaysAsideForPermission() {
        let visible = overlayWindows.values.filter(\.isVisible)
        guard alwaysOnMode else {
            guard isInteractiveOverlayOpen else { return }
            overlaysKeepingDrawings.formUnion(visible.map(ObjectIdentifier.init))
            hideAllOverlays()
            return
        }
        guard !visible.isEmpty else { return }
        visible.forEach { $0.orderOut(nil) }
        overlaysAwaitingPermission.append(contentsOf: visible)
        CursorHighlightManager.shared.overlayVisibilityChanged()
    }

    /// Brings back the Always-On overlays `moveOverlaysAsideForPermission` ordered out, once
    /// Settings has closed and no privacy prompt is on screen. The prompt belongs to another
    /// process and says nothing when it closes, so this checks again until it is gone.
    /// Nothing comes back if Always-On has ended or the display is gone.
    private func restoreOverlaysWhenPermissionUIIsGone() {
        guard !overlaysAwaitingPermission.isEmpty, !isSettingsOpenForPermission else { return }
        if isPrivacyPromptOnScreen() {
            guard !isPollingForPrivacyPrompt else { return }
            isPollingForPrivacyPrompt = true
            DispatchQueue.main.asyncAfter(deadline: .now() + privacyPromptPollInterval) { [weak self] in
                self?.isPollingForPrivacyPrompt = false
                self?.restoreOverlaysWhenPermissionUIIsGone()
            }
            return
        }
        let waiting = overlaysAwaitingPermission
        overlaysAwaitingPermission = []
        guard alwaysOnMode else { return }
        let current = Set(overlayWindows.values.map(ObjectIdentifier.init))
        let restored = waiting.filter { current.contains(ObjectIdentifier($0)) && !$0.isVisible }
        guard !restored.isEmpty else { return }
        restored.forEach { $0.orderFront(nil) }
        CursorHighlightManager.shared.overlayVisibilityChanged()
    }

    /// Whether `overlay` was closed by the app and keeps its drawings this time it opens.
    /// Any opening uses the exemption up, so a later close by the user clears as usual.
    @discardableResult
    func consumeKeptDrawings(of overlay: OverlayWindow) -> Bool {
        overlaysKeepingDrawings.remove(ObjectIdentifier(overlay)) != nil
    }
}

/// A capture that went wrong, in whole or in part: a short title for the HUD and the alert,
/// and the alert's detail.
struct CaptureProblem: Equatable {
    let title: String
    let icon: String
    let detail: String

    static let failed = CaptureProblem(
        title: "Capture Failed", icon: "⚠️", detail: "Annotate couldn't finish the capture. Try again in a moment.")

    /// Every destination the capture had failed, so the image went nowhere.
    static func undelivered(error: Error) -> CaptureProblem {
        CaptureProblem(
            title: "Capture Failed",
            icon: "⚠️",
            detail: "Annotate couldn't deliver the image. \(error.localizedDescription)")
    }

    static func folderUnavailable(_ folder: String, savedAs file: URL) -> CaptureProblem {
        CaptureProblem(
            title: "Can't Reach \(folder). Saved to Default Folder",
            icon: "📁",
            detail: "Annotate can't reach \(folder), so it saved \(file.lastPathComponent) in "
                + "\(CaptureSettingsView.displayPath(of: file.deletingLastPathComponent())). "
                + "Choose another folder in Settings.")
    }

    static func copyFailed(savedAs file: URL, error: Error) -> CaptureProblem {
        CaptureProblem(
            title: "Couldn't Copy. Saved \(file.lastPathComponent)",
            icon: "⚠️",
            detail: "The image was saved, but Annotate couldn't copy it to the clipboard. \(error.localizedDescription)")
    }

    static func saveFailed(error: Error?) -> CaptureProblem {
        CaptureProblem(
            title: "Couldn't Save. Copied to Clipboard",
            icon: "📋",
            detail: ["The image is on the clipboard, but Annotate couldn't save it.", error?.localizedDescription]
                .compactMap { $0 }
                .joined(separator: " "))
    }
}

extension CaptureProblem {
    /// What a capture that produced an image, and got it somewhere, still has to report.
    init?(_ result: CaptureResult) {
        if let file = result.savedFile {
            if let copyError = result.failure(of: .clipboard) {
                self = .copyFailed(savedAs: file, error: copyError)
            } else if let missedFolder = result.missedFolder {
                self = .folderUnavailable(missedFolder, savedAs: file)
            } else {
                return nil
            }
        } else if let saveError = result.failure(of: .file), result.copiedToClipboard {
            self = .saveFailed(error: saveError)
        } else {
            return nil
        }
    }
}

/// The macOS privacy prompt, which asks for Screen Recording among other permissions. Another
/// process shows it, `universalAccessAuthWarn`, and its windows can be found by owner without
/// any permission.
enum SystemPrivacyPrompt {
    static let helperBundleIdentifier = "com.apple.accessibility.universalAccessAuthWarn"

    @MainActor
    static var isOnScreen: Bool {
        let helpers = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleIdentifier)
                .map(\.processIdentifier))
        guard !helpers.isEmpty,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        return hasWindow(ownedBy: helpers, in: windows)
    }

    /// Whether any window in a `CGWindowListCopyWindowInfo` list belongs to one of `owners`.
    static func hasWindow(ownedBy owners: Set<pid_t>, in windows: [[String: Any]]) -> Bool {
        windows.contains { window in
            (window[kCGWindowOwnerPID as String] as? NSNumber).map { owners.contains($0.int32Value) } ?? false
        }
    }
}
