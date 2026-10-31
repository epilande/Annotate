import AppIntents

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

enum AnnotateIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: return "Annotate is still starting up. Try again in a moment."
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
    var state: AnnotateCommand.Switch

    static var parameterSummary: some ParameterSummary {
        Summary("Set toolbar to \(\.$state)")
    }

    var command: AnnotateCommand { .toolbar(state) }

    init() {}

    init(state: AnnotateCommand.Switch) {
        self.state = state
    }
}

struct SetFadeModeIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Set Fade Mode"
    static let description = IntentDescription(
        "Turns Fade mode on or off. With it off, annotations persist until cleared.")

    @Parameter(title: "State", default: .toggle)
    var state: AnnotateCommand.Switch

    static var parameterSummary: some ParameterSummary {
        Summary("Set fade mode to \(\.$state)")
    }

    var command: AnnotateCommand { .fade(state) }

    init() {}

    init(state: AnnotateCommand.Switch) {
        self.state = state
    }
}

struct SetBoardIntent: AnnotateCommandIntent {
    static let title: LocalizedStringResource = "Set Board"
    static let description = IntentDescription(
        "Shows or hides the whiteboard (the blackboard in Dark Mode) behind annotations.")

    @Parameter(title: "State", default: .toggle)
    var state: AnnotateCommand.Switch

    static var parameterSummary: some ParameterSummary {
        Summary("Set board to \(\.$state)")
    }

    var command: AnnotateCommand { .board(state) }

    init() {}

    init(state: AnnotateCommand.Switch) {
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

extension AnnotateCommand.Switch: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "State"

    static let caseDisplayRepresentations: [AnnotateCommand.Switch: DisplayRepresentation] = [
        .on: "On",
        .off: "Off",
        .toggle: "Toggle",
    ]
}
