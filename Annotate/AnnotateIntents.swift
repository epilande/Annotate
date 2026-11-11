import AppIntents
import UniformTypeIdentifiers

// Shortcuts actions. Each one is a thin wrapper that runs an `AnnotateCommand`.
//
// Xcode extracts action metadata at build time and only accepts literals in titles, display
// representations, and parameter summaries, so these can't reuse `displayName`.
// `AnnotateIntentsTests` checks every enum case has a display representation.

/// An action that runs one `AnnotateCommand` in the running app.
protocol AnnotateCommandIntent: AppIntent {
    var command: AnnotateCommand { get }
}

extension AnnotateCommandIntent {
    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appDelegate = AppDelegate.shared else {
            throw AnnotateIntentError.appNotReady
        }
        command.run(on: appDelegate)
        return .result()
    }
}

enum AnnotateIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case screenRecordingOff
    /// Capture Area's picker closed before an area was picked.
    case captureCancelled
    /// Capture Area couldn't open its picker, most likely because one is already open.
    case captureAreaUnavailable
    /// The capture produced no image, or the image went nowhere. `detail` says which.
    case captureFailed(detail: String)

    /// The error a Shortcuts action shows for a capture that threw `error`.
    init(capturing error: Error) {
        switch error {
        case CaptureError.screenRecordingOff: self = .screenRecordingOff
        case CaptureError.cancelled: self = .captureCancelled
        case CaptureError.pickerUnavailable: self = .captureAreaUnavailable
        case is CaptureError: self = .captureFailed(detail: CaptureProblem.failed.detail)
        default: self = .captureFailed(detail: CaptureProblem.undelivered(error: error).detail)
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "Annotate is still starting up. Try again in a moment."
        case .screenRecordingOff:
            return "Annotate needs Screen Recording permission to capture. Turn it on in Annotate's Settings, in the Capture pane."
        case .captureCancelled:
            return "Capture Area was cancelled before an area was picked."
        case .captureAreaUnavailable:
            return "Annotate couldn't start Capture Area. If an area is already being picked, finish or cancel it first."
        case .captureFailed(let detail):
            return "\(detail)"
        }
    }
}

struct ToggleOverlayIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Toggle Overlay"
    static let description = IntentDescription(
        "Opens the annotation overlay on the display under the pointer, or closes it if it's open.")

    var command: AnnotateCommand { .toggle }
}

struct ShowOverlayIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Show Overlay"
    static let description = IntentDescription(
        "Opens the annotation overlay on the display under the pointer, leaving Always-On mode.")

    var command: AnnotateCommand { .show }
}

struct HideOverlayIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Hide Overlay"
    static let description = IntentDescription(
        "Closes the annotation overlay on every display, leaving Always-On mode.")

    var command: AnnotateCommand { .hide }
}

struct SelectToolIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Select Tool"
    static let description = IntentDescription(
        "Selects an annotation tool and opens the overlay.")

    @Parameter(title: "Tool")
    var tool: ToolType

    static var parameterSummary: some ParameterSummary {
        Summary("Select \(\.$tool)")
    }

    var command: AnnotateCommand { .tool(tool) }

    init() {}

    init(tool: ToolType) {
        self.tool = tool
    }
}

struct SetColorIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Set Color"
    static let description = IntentDescription(
        "Sets the annotation color. Doesn't open the overlay.")

    @Parameter(title: "Color")
    var color: PaletteColor

    static var parameterSummary: some ParameterSummary {
        Summary("Set color to \(\.$color)")
    }

    var command: AnnotateCommand { .color(color) }

    init() {}

    init(color: PaletteColor) {
        self.color = color
    }
}

struct ClearAnnotationsIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Clear Annotations"
    static let description = IntentDescription(
        "Clears the annotations on every open overlay. Clear can be undone in the overlay.")

    var command: AnnotateCommand { .clear }
}

struct SetToolbarIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Set Toolbar"
    static let description = IntentDescription(
        "Shows or hides the overlay toolbar. Doesn't open the overlay.")

    @Parameter(title: "State", default: .toggle)
    var state: CommandSwitch

    static var parameterSummary: some ParameterSummary {
        Summary("Set toolbar to \(\.$state)")
    }

    var command: AnnotateCommand { .toolbar(state) }

    init() {}

    init(state: CommandSwitch) {
        self.state = state
    }
}

struct SetFadeModeIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Set Fade Mode"
    static let description = IntentDescription(
        "Turns Fade mode on or off. With it off, annotations persist until cleared.")

    @Parameter(title: "State", default: .toggle)
    var state: CommandSwitch

    static var parameterSummary: some ParameterSummary {
        Summary("Set fade mode to \(\.$state)")
    }

    var command: AnnotateCommand { .fade(state) }

    init() {}

    init(state: CommandSwitch) {
        self.state = state
    }
}

struct SetBoardIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Set Board"
    static let description = IntentDescription(
        "Shows or hides the whiteboard (the blackboard in Dark Mode) behind annotations.")

    @Parameter(title: "State", default: .toggle)
    var state: CommandSwitch

    static var parameterSummary: some ParameterSummary {
        Summary("Set board to \(\.$state)")
    }

    var command: AnnotateCommand { .board(state) }

    init() {}

    init(state: CommandSwitch) {
        self.state = state
    }
}

// MARK: - Pickers

extension ToolType: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tool"

    static let caseDisplayRepresentations: [ToolType: DisplayRepresentation] = [
        .pen: "Pen",
        .arrow: "Arrow",
        .line: "Line",
        .highlighter: "Highlighter",
        .rectangle: "Rectangle",
        .circle: "Circle",
        .redact: "Redact",
        .text: "Text",
        .counter: "Counter",
        .select: "Select",
        .eraser: "Eraser",
    ]
}

extension PaletteColor: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Color"

    static let caseDisplayRepresentations: [PaletteColor: DisplayRepresentation] = [
        .red: "Red",
        .orange: "Orange",
        .yellow: "Yellow",
        .green: "Green",
        .cyan: "Cyan",
        .indigo: "Indigo",
        .magenta: "Magenta",
        .white: "White",
        .black: "Black",
    ]
}

extension CommandSwitch: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "State"

    static let caseDisplayRepresentations: [CommandSwitch: DisplayRepresentation] = [
        .on: "On",
        .off: "Off",
        .toggle: "Toggle",
    ]
}

// MARK: - Capture

/// A Shortcuts action that captures and passes the PNG to the next action. It runs the same
/// capture the menu does, so the image also goes where After Capture says, and the overlay and
/// the notification report it. There is no `annotate://` link for capture
/// (`AnnotateCommand.runsFromLinks`).
protocol AnnotateCaptureIntent: AppIntent {
    var scope: CaptureScope { get }
}

extension AnnotateCaptureIntent {
    /// The command the menu and the overlay shortcut run for the same capture.
    var command: AnnotateCommand { .capture(scope) }

    /// Captures in the running app and returns the PNG as a file.
    @MainActor
    func captureFile(temporaryDirectory: URL = FileManager.default.temporaryDirectory) async throws -> IntentFile {
        guard let appDelegate = AppDelegate.shared else {
            throw AnnotateIntentError.appNotReady
        }
        let image: CapturedImage
        do {
            image = try await appDelegate.captureForShortcuts(scope)
        } catch {
            throw AnnotateIntentError(capturing: error)
        }
        return try CaptureIntentFile.make(for: image, temporaryDirectory: temporaryDirectory)
    }
}

/// The file a capture action returns.
enum CaptureIntentFile {
    /// The saved file when there is one this process can read. Otherwise, as with After Capture
    /// set to Copy to clipboard, the PNG goes to a temporary file, never into the capture folder,
    /// which the system removes once the shortcut is done with it. Both carry the name a saved
    /// capture would have.
    static func make(for image: CapturedImage, temporaryDirectory: URL) throws -> IntentFile {
        if let saved = image.savedFile, FileManager.default.isReadableFile(atPath: saved.path) {
            return IntentFile(fileURL: saved, filename: saved.lastPathComponent, type: .png)
        }
        let name = FileSink.fileName(FileSink.baseName(for: image.capturedAt), attempt: 1)
        let temporary = temporaryDirectory.appendingPathComponent("Annotate-\(UUID().uuidString).png", isDirectory: false)
        do {
            try image.png.write(to: temporary, options: .withoutOverwriting)
        } catch {
            throw AnnotateIntentError.captureFailed(
                detail: "Annotate couldn't hand the image to Shortcuts. \(error.localizedDescription)")
        }
        var file = IntentFile(fileURL: temporary, filename: name, type: .png)
        file.removedOnCompletion = true
        return file
    }
}

struct CaptureScreenIntent: AnnotateCaptureIntent {
    static let title: LocalizedStringResource = "Capture Screen"
    static let description = IntentDescription(
        "Captures the display with its annotations as a PNG and passes it on. Also saves it, copies it, or both, as After Capture says in Annotate's Settings.")

    var scope: CaptureScope { .screen }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try await captureFile())
    }
}

struct CaptureAreaIntent: AnnotateCaptureIntent {
    static let title: LocalizedStringResource = "Capture Area"
    static let description = IntentDescription(
        "Opens the overlay so you can drag out part of the display, then captures it with its annotations as a PNG and passes it on. Also saves it, copies it, or both, as After Capture says in Annotate's Settings. Fails if the pick is cancelled.")

    var scope: CaptureScope { .area }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try await captureFile())
    }
}
