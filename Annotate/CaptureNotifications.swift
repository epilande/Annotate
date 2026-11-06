import AppKit
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import UserNotifications
import os

private let log = Logger(subsystem: "com.epilande.Annotate", category: "Capture")

/// What macOS lets Annotate do with notifications.
enum CaptureNotificationAccess: Equatable, Sendable {
    case undetermined
    case allowed
    case denied
}

/// What a finished capture's notification says. Sent to users who may never see the HUD, so it
/// covers captures made with the overlay closed or Hide Tool Feedback on.
struct CaptureNotice {
    let title: String
    let body: String
    /// The saved file, which gets Show in Finder. Nil when the image is only on the clipboard.
    let file: URL?
    let image: CGImage

    /// The notice for a capture that reached a destination, or nil if it reached none.
    init?(_ result: CaptureResult) {
        image = result.capture.image
        file = result.savedFile
        if let file {
            title = result.missedFolder == nil ? "Capture Saved" : "Capture Saved to the Default Folder"
            body = file.lastPathComponent
        } else if result.copiedToClipboard {
            title = "Capture Copied"
            body = "The image is on the clipboard."
        } else {
            return nil
        }
    }

    /// The file a notification response should show in Finder: clicking the notification does
    /// the same as its Show in Finder button.
    static func fileToShow(action: String, userInfo: [AnyHashable: Any]) -> URL? {
        guard action == showInFinderAction || action == UNNotificationDefaultActionIdentifier,
            let path = userInfo[filePathKey] as? String
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// `userInfo` for a notification about `file`.
    static func userInfo(for file: URL?) -> [String: String] {
        file.map { [filePathKey: $0.path] } ?? [:]
    }

    /// Writes a thumbnail of `image` to its own temporary file and returns it. The notification
    /// system moves whatever file it is given into its own store, so the saved capture must
    /// never be the attachment.
    nonisolated static func writeThumbnail(
        of image: CGImage, maxPixels: Int = thumbnailMaxPixels, in folder: URL = FileManager.default.temporaryDirectory
    ) -> URL? {
        let longestSide = max(image.width, image.height)
        guard longestSide > 0 else { return nil }
        let ratio = min(1, CGFloat(maxPixels) / CGFloat(longestSide))
        let width = max(1, Int((CGFloat(image.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(image.height) * ratio).rounded()))
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, space.model == .rgb,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let url = folder.appendingPathComponent("AnnotateCapture-\(UUID().uuidString).png", isDirectory: false)
        guard let thumbnail = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    static let showInFinderAction = "com.epilande.Annotate.capture.showInFinder"
    static let savedCategory = "com.epilande.Annotate.capture.saved"
    static let filePathKey = "filePath"
    static let thumbnailMaxPixels = 640
}

/// Sends the notification a finished capture gets. Only the Capture pane may ask for
/// permission, since a prompt anywhere else would land under the overlay; tests substitute a
/// stub, because the real notification center can't run outside an app bundle.
@MainActor
protocol CaptureNotifying: AnyObject {
    /// The current permission, without asking.
    func access() async -> CaptureNotificationAccess

    /// Shows the system prompt if the user hasn't answered it yet, and returns the permission.
    func requestAccess() async -> CaptureNotificationAccess

    /// Sends `notice` if permission allows, and does nothing otherwise.
    func post(_ notice: CaptureNotice)
}

/// Stands in where `UNUserNotificationCenter` can't: it raises an exception in any process that
/// isn't an app bundle, such as `swift test` and `swift run`.
final class SilentCaptureNotifier: CaptureNotifying {
    func access() async -> CaptureNotificationAccess { .denied }
    func requestAccess() async -> CaptureNotificationAccess { .denied }
    func post(_ notice: CaptureNotice) {}
}

/// Capture notifications through `UNUserNotificationCenter`, with a thumbnail, and a Show in
/// Finder button for a saved file.
final class SystemCaptureNotifier: NSObject, CaptureNotifying, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let folders: CaptureFolderStore

    /// The real notifier inside an app bundle, and a silent one anywhere else.
    static func forThisProcess(folders: CaptureFolderStore) -> CaptureNotifying {
        Bundle.main.bundleURL.pathExtension == "app" ? SystemCaptureNotifier(folders: folders) : SilentCaptureNotifier()
    }

    private init(folders: CaptureFolderStore) {
        center = .current()
        self.folders = folders
        super.init()
        center.delegate = self
        let showInFinder = UNNotificationAction(
            identifier: CaptureNotice.showInFinderAction, title: "Show in Finder", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: CaptureNotice.savedCategory, actions: [showInFinder], intentIdentifiers: [])
        ])
    }

    func access() async -> CaptureNotificationAccess {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .undetermined
        case .denied: .denied
        default: .allowed
        }
    }

    func requestAccess() async -> CaptureNotificationAccess {
        do {
            _ = try await center.requestAuthorization(options: [.alert])
        } catch {
            log.error("Notification permission request failed: \(error.localizedDescription)")
        }
        return await access()
    }

    func post(_ notice: CaptureNotice) {
        Task {
            guard await access() == .allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.threadIdentifier = "captures"
            content.userInfo = CaptureNotice.userInfo(for: notice.file)
            if notice.file != nil {
                content.categoryIdentifier = CaptureNotice.savedCategory
            }
            let thumbnail = await Self.makeThumbnail(of: notice.image)
            // Whatever the system didn't move into its store.
            defer { if let thumbnail { try? FileManager.default.removeItem(at: thumbnail) } }
            if let thumbnail,
                let attachment = try? UNNotificationAttachment(identifier: "capture", url: thumbnail)
            {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                log.error("Capture notification failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func makeThumbnail(of image: CGImage) async -> URL? {
        CaptureNotice.writeThumbnail(of: image)
    }

    /// A menu bar app is often the active app, and macOS hides notifications from the active
    /// app unless told otherwise.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let file = CaptureNotice.fileToShow(
            action: response.actionIdentifier, userInfo: response.notification.request.content.userInfo)
        if let file {
            await showInFinder(file)
        }
    }

    /// Holds the chosen folder's scope, so Finder can be handed a file saved there.
    private func showInFinder(_ file: URL) {
        folders.withAccess { _ in
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }
}
