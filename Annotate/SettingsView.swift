import SwiftUI

/// The five settings panes shown in the sidebar.
///
/// Drives the sidebar list, the colored icon tiles, and each pane's header.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case tools = "Tools"
    case board = "Board"
    case cursor = "Cursor"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }

    /// Pane name shown in the sidebar, window title, and pane header.
    var title: String { rawValue }

    /// SF Symbol shown in the sidebar icon tile.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tools: "pencil.and.outline"
        case .board: "rectangle.on.rectangle"
        case .cursor: "cursorarrow.rays"
        case .shortcuts: "keyboard"
        }
    }

    /// System color for the sidebar icon tile.
    var color: Color {
        switch self {
        case .general: .gray
        case .tools: .orange
        case .board: .indigo
        case .cursor: .purple
        case .shortcuts: .blue
        }
    }

    /// Secondary line under the pane title in `PaneHeader`.
    var subtitle: String {
        switch self {
        case .general: "Activation shortcuts and application behavior"
        case .tools: "Default sizes for text and counter annotations"
        case .board: "Board background appearance and visibility"
        case .cursor: "Cursor style, spotlight, and click effects"
        case .shortcuts: "Single-key shortcuts for tools and utilities"
        }
    }
}

/// Bold title and secondary subtitle shown at the top of each settings pane.
struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pane.title)
                .font(.system(size: 21, weight: .bold))
            Text(pane.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

/// Main settings window: a `NavigationSplitView` sidebar of the five panes
/// with a grouped `Form` detail, mirroring the System Settings layout.
struct SettingsView: View {
    @State private var selection: SettingsPane? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        IconTile(symbol: pane.symbol, color: pane.color)
                    }
                    .tag(pane)
                }
            }
            .settingsScrollEdgeEffect()
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Annotate")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralSettingsView()
                case .tools: ToolsSettingsView()
                case .board: BoardSettingsView()
                case .cursor: CursorSettingsView()
                case .shortcuts: ShortcutsSettingsView()
                }
            }
            .frame(minWidth: 480)
            // The window's transparent unified toolbar reserves a tall top
            // safe area that the detail column leaves empty. Collapse it so
            // each pane's header starts near the top of the window, except
            // when the sidebar is hidden and the detail column would slide
            // under the traffic lights and sidebar toggle.
            .ignoresSafeArea(.container, edges: columnVisibility == .detailOnly ? [] : .top)
        }
        .frame(minWidth: 780, minHeight: 580)
    }
}

