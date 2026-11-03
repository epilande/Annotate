import Cocoa
import os

private let log = Logger(subsystem: "com.epilande.Annotate", category: "Capture")

/// Capture Screen and Capture Area from the menu, the overlay shortcuts, and
/// `AnnotateCommand.capture`: picks the display, reads what its overlay shows, and reports the
/// result on that overlay.
extension AppDelegate {
    /// The display a capture saves: the key interactive overlay's, else the one under the
    /// pointer, else the main display.
    static func captureTarget<Display>(keyOverlay: Display?, pointer: Display?, main: Display?) -> Display? {
        keyOverlay ?? pointer ?? main
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

    /// Saves the display with its board and annotations, as its overlay shows them, and copies
    /// the image. With the overlay hidden it saves the plain screen.
    @objc func captureScreen() {
        guard let screen = captureTargetScreen, let display = DisplayInfo(screen: screen) else {
            log.error("No display to capture")
            return
        }
        let overlay = overlayWindows[screen]
        startCapture(
            CaptureRequest(
                display: display,
                scene: overlay.flatMap { $0.isVisible ? captureScene(of: $0) : nil },
                hostTime: CACurrentMediaTime(),
                date: Date()),
            on: overlay)
    }

    /// Lets the user drag out part of a display, then saves it with its board and annotations
    /// and copies it, as Capture Screen does. The picker needs the interactive overlay, so with
    /// none open, including in Always-On, this opens it first. The fade holds while picking,
    /// and the capture shows each annotation at the fade the picker showed.
    @objc func captureArea() {
        if !isInteractiveOverlayOpen {
            // Always-On annotations are on screen, so the overlay opening over them keeps them,
            // even with Clear Drawings on Start.
            if alwaysOnMode, let screen = getCurrentScreen(), let overlay = overlayWindows[screen] {
                overlaysKeepingDrawings.insert(ObjectIdentifier(overlay))
            }
            showInteractiveOverlay()
        }
        guard let screen = areaTargetScreen, let overlay = overlayWindows[screen],
            let display = DisplayInfo(screen: screen)
        else {
            log.error("No overlay to pick an area on")
            return
        }
        guard !overlay.isRegionPickerOpen else { return }
        // Without Screen Recording the drag would come to nothing, so ask before it starts.
        let board = BoardManager.shared
        if !captureService.source.canCapture,
            !CaptureScene.boardCoversScreen(board.appearance, opacity: CGFloat(board.opacity))
        {
            showScreenRecordingOff(on: overlay)
            return
        }
        // The picker reads Escape from its own overlay, and another display's may be key.
        overlay.makeKeyAndOrderFront(nil)
        overlay.beginRegionPicker { [weak self, weak overlay] rect in
            guard let self, let overlay else { return }
            // Runs before the picker closes, so the scene's fade clock is still frozen.
            self.startCapture(
                CaptureRequest(
                    display: display,
                    region: .rect(fromViewRect: rect, displayHeight: display.frame.height),
                    scene: self.captureScene(of: overlay),
                    hostTime: CACurrentMediaTime(),
                    date: Date()),
                on: overlay)
        }
    }

    private func startCapture(_ request: CaptureRequest, on overlay: OverlayWindow?) {
        // Each capture waits for the one before it, so captures finish in the order they were
        // asked for: an older image never replaces a newer one on the clipboard or in the HUD,
        // and every capture still gets its own file. The scene above is already taken, so the
        // annotations are the ones on screen when this capture was asked for.
        let service = captureService
        let previous = captureTask
        captureTask = Task { @MainActor [weak self] in
            await previous?.value
            do {
                let result = try await service.capture(request)
                self?.reportCapture(result, on: overlay)
            } catch CaptureError.screenRecordingOff {
                self?.showScreenRecordingOff(on: overlay)
            } catch {
                log.error("Capture failed: \(error.localizedDescription)")
                self?.reportCaptureProblem(.failed, on: overlay)
            }
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

    /// Success shows on the overlay, if it is open. When one destination failed, says which,
    /// even with the overlay closed.
    private func reportCapture(_ result: CaptureResult, on overlay: OverlayWindow?) {
        if let file = result.savedFile {
            if let copyError = result.failure(of: .clipboard) {
                reportCaptureProblem(.copyFailed(savedAs: file, error: copyError), on: overlay)
                return
            }
            guard let overlay, overlay.isVisible else { return }
            overlay.showToggleFeedback("Saved \(file.lastPathComponent)", icon: "📸")
        } else if result.copiedToClipboard {
            reportCaptureProblem(.saveFailed(error: result.failure(of: .file)), on: overlay)
        }
    }

    /// On the overlay's HUD when it is open and showing feedback. Otherwise an alert: from the
    /// status menu with the overlay closed, or with Hide Tool Feedback on, a failed capture is
    /// never silent.
    private func reportCaptureProblem(_ problem: CaptureProblem, on overlay: OverlayWindow?) {
        if let overlay, overlay.isVisible, !settings[.hideToolFeedback] {
            overlay.showToggleFeedback(problem.title, icon: problem.icon)
        } else {
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
