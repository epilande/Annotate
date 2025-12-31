import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var shortcuts: [ShortcutKey: String] = ShortcutManager.shared.allShortcuts
    @State private var editingShortcut: ShortcutKey?
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SettingsSection(
                    icon: "pencil.tip",
                    title: "Drawing Tools",
                    subtitle: "Basic drawing and annotation shortcuts"
                ) {
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
                }

                Divider()

                SettingsSection(
                    icon: "square.on.circle",
                    title: "Shapes",
                    subtitle: "Geometric shape shortcuts"
                ) {
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
                }

                Divider()

                SettingsSection(
                    icon: "wand.and.stars",
                    title: "Advanced Tools",
                    subtitle: "Additional annotation features"
                ) {
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
                }

                Divider()

                SettingsSection(
                    icon: "slider.horizontal.3",
                    title: "Utilities",
                    subtitle: "Color, width, and board controls"
                ) {
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
                        label: "Toggle Click Effects",
                        description: "Enable or disable click visual feedback",
                        shortcuts: $shortcuts,
                        editingShortcut: $editingShortcut
                    )
                }

                Divider()

                HStack {
                    Spacer()
                    Button {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset All to Default", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 60)
        }
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 32)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(colorScheme == .dark ? Color(white: 0.35) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                colorScheme == .dark
                                                    ? Color(white: 0.45) : Color(white: 0.8),
                                                lineWidth: 1.0)
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
                            .font(.system(size: 14))
                            .foregroundStyle(isHoveringReset ? .secondary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                    .onHover { isHoveringReset = $0 }
                }
            }
        }
    }
}
