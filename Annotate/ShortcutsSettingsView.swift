import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var shortcuts: [ShortcutKey: String] = ShortcutManager.shared.allShortcuts
    @State private var editingShortcut: ShortcutKey?
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .shortcuts)
            }

            Section {
                ShortcutSettingRow(
                    tool: .pen,
                    label: "Pen",
                    description: "Draw freeform pen strokes",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .arrow,
                    label: "Arrow",
                    description: "Draw directional arrows",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .line,
                    label: "Line",
                    description: "Draw straight lines",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .highlighter,
                    label: "Highlighter",
                    description: "Highlight with transparency",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
            } header: {
                SettingsHeader(
                    icon: "pencil.tip",
                    color: .blue,
                    title: "Drawing Tools",
                    subtitle: "Basic drawing and annotation shortcuts"
                )
            }

            Section {
                ShortcutSettingRow(
                    tool: .rectangle,
                    label: "Rectangle",
                    description: "Draw rectangular shapes",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .circle,
                    label: "Circle",
                    description: "Draw circular shapes",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
            } header: {
                SettingsHeader(
                    icon: "square.on.circle",
                    color: .green,
                    title: "Shapes",
                    subtitle: "Geometric shape shortcuts"
                )
            }

            Section {
                ShortcutSettingRow(
                    tool: .counter,
                    label: "Counter",
                    description: "Add numbered counters",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .text,
                    label: "Text",
                    description: "Add text annotations",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .select,
                    label: "Select",
                    description: "Select and edit annotations",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .eraser,
                    label: "Eraser",
                    description: "Remove annotations by dragging",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
            } header: {
                SettingsHeader(
                    icon: "wand.and.stars",
                    color: .purple,
                    title: "Advanced Tools",
                    subtitle: "Additional annotation features"
                )
            }

            Section {
                ShortcutSettingRow(
                    tool: .colorPicker,
                    label: "Color Picker",
                    description: "Choose annotation color",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .lineWidthPicker,
                    label: "Line Width",
                    description: "Adjust stroke width",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .toggleBoard,
                    label: "Toggle Board",
                    description: "Show or hide board background",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
                ShortcutSettingRow(
                    tool: .toggleClickEffects,
                    label: "Toggle Cursor Highlight",
                    description: "Enable or disable cursor visual feedback",
                    shortcuts: $shortcuts,
                    editingShortcut: $editingShortcut
                )
            } header: {
                SettingsHeader(
                    icon: "slider.horizontal.3",
                    color: .orange,
                    title: "Utilities",
                    subtitle: "Color, width, and board controls"
                )
            }

            Section {
                HStack {
                    Spacer()
                    Button {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset All to Default", systemImage: "arrow.counterclockwise")
                    }
                    .glassButtonStyle()
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeEffect()
        .onAppear {
            shortcuts = ShortcutManager.shared.allShortcuts
        }
        .alert("Reset All Shortcuts?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                ShortcutManager.shared.resetAllToDefault()
                shortcuts = ShortcutManager.shared.allShortcuts
                editingShortcut = nil
            }
        } message: {
            Text("This will reset all keyboard shortcuts to their default values. This action cannot be undone.")
        }
    }
}

struct ShortcutSettingRow: View {
    let tool: ShortcutKey
    let label: String
    let description: String
    @Binding var shortcuts: [ShortcutKey: String]
    @Binding var editingShortcut: ShortcutKey?

    @State private var isHoveringKey = false
    @State private var isHoveringReset = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if editingShortcut == tool {
                    ShortcutField(
                        tool: tool,
                        shortcuts: $shortcuts,
                        editingShortcut: $editingShortcut
                    )
                    .frame(minWidth: 60)
                } else {
                    Button(action: { editingShortcut = tool }) {
                        Text(shortcuts[tool] ?? tool.defaultKey)
                            .font(.body.weight(.medium).monospaced())
                            .foregroundStyle(.primary)
                            .frame(minWidth: 32)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.quaternary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(.separator, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .opacity(isHoveringKey ? 0.8 : 1.0)
                    .onHover { isHoveringKey = $0 }

                    Button {
                        ShortcutManager.shared.resetToDefault(tool: tool)
                        shortcuts = ShortcutManager.shared.allShortcuts
                        editingShortcut = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(isHoveringReset ? .secondary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                    .onHover { isHoveringReset = $0 }
                }
            }
        } label: {
            Text(label)
            Text(description)
        }
    }
}
