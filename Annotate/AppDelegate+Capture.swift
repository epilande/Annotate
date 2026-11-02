import Cocoa
import os

private let log = Logger(subsystem: "com.epilande.Annotate", category: "Capture")

/// Capture Screen from the menu, the overlay shortcut, and `AnnotateCommand.capture`: picks the
/// display, reads what its overlay shows, and reports the result on that overlay.
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

    func capture(_ scope: CaptureScope) {
        switch scope {
        case .screen: captureScreen()
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
        let request = CaptureRequest(
            display: display,
            scene: overlay.flatMap { $0.isVisible ? captureScene(of: $0) : nil },
            hostTime: CACurrentMediaTime(),
            date: Date())

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
                overlay?.showToggleFeedback("Capture Failed", icon: "⚠️")
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

    private func reportCapture(_ result: CaptureResult, on overlay: OverlayWindow?) {
        guard let overlay, overlay.isVisible else { return }
        if let file = result.savedFile {
            overlay.showToggleFeedback("Saved \(file.lastPathComponent)", icon: "📸")
        } else if result.copiedToClipboard {
            overlay.showToggleFeedback("Couldn't Save. Copied to Clipboard", icon: "📋")
        }
    }

    /// Never asks from here: the system prompt would open under the overlay. Says so on the
    /// overlay, then gets every overlay out of the way and opens Settings to Capture, which
    /// asks. Annotations stay for when the overlay opens again.
    private func showScreenRecordingOff(on overlay: OverlayWindow?) {
        let showsNotice = overlay?.isVisible == true && !settings[.hideToolFeedback]
        overlay?.showToggleFeedback("Screen Recording is off. Opening Settings…", icon: "🔒")
        DispatchQueue.main.asyncAfter(deadline: .now() + (showsNotice ? screenRecordingNoticeDelay : 0)) {
            [weak self] in
            guard let self else { return }
            let suspended = self.clearOverlaysForSettings()
            self.openSettingsPane(.capture, true) { [weak self] in
                self?.restoreAlwaysOnOverlays(suspended)
            }
        }
    }

    /// Closes the interactive overlay. Always-On overlays sit above every normal window, so
    /// their annotations would cover Settings and the system prompt; they are ordered out
    /// instead, and returned so they can come back once Settings closes.
    private func clearOverlaysForSettings() -> [OverlayWindow] {
        guard alwaysOnMode else {
            if isInteractiveOverlayOpen {
                hideAllOverlays()
            }
            return []
        }
        let visible = overlayWindows.values.filter(\.isVisible)
        visible.forEach { $0.orderOut(nil) }
        CursorHighlightManager.shared.overlayVisibilityChanged()
        return visible
    }

    /// Brings back the Always-On overlays `clearOverlaysForSettings` ordered out, unless
    /// Always-On has ended or the display is gone since.
    private func restoreAlwaysOnOverlays(_ windows: [OverlayWindow]) {
        guard alwaysOnMode else { return }
        let current = Set(overlayWindows.values.map(ObjectIdentifier.init))
        let restored = windows.filter { current.contains(ObjectIdentifier($0)) && !$0.isVisible }
        guard !restored.isEmpty else { return }
        restored.forEach { $0.orderFront(nil) }
        CursorHighlightManager.shared.overlayVisibilityChanged()
    }
}
