import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(UserDefaults.clearDrawingsOnStartKey)
    private var clearDrawingsOnStart = false
    @AppStorage(UserDefaults.hideDockIconKey)
    private var hideDockIcon = false
    @State private var shortcuts: [ShortcutKey: String] = ShortcutManager.shared.allShortcuts
    @State private var editingShortcut: ShortcutKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("General") {
                VStack(alignment: .center, spacing: 12) {
                    KeyboardShortcuts.Recorder("Annotate Hotkey:", name: .toggleOverlay)

                    Divider()

                    Toggle("Clear Drawings on Toggle", isOn: $clearDrawingsOnStart)
                        .toggleStyle(.checkbox)
                        .help(
                            "When enabled, all drawings will be cleared each time you toggle the overlay"
                        )

                    Toggle("Hide Dock Icon", isOn: $hideDockIcon)
                        .toggleStyle(.checkbox)
                        .help("When enabled, Annotate will not show in the Dock")
                        .onChange(of: hideDockIcon) { _ in
                            AppDelegate.shared?.updateDockIconVisibility()
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)

            GroupBox("Shortcuts") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ShortcutKey.allCases, id: \.self) { tool in
                        HStack {
                            Text(tool.displayName)
                                .frame(width: 100, alignment: .trailing)

                            if editingShortcut == tool {
                                ShortcutField(
                                    tool: tool, shortcuts: $shortcuts,
                                    editingShortcut: $editingShortcut)
                            } else {
                                Text(shortcuts[tool] ?? tool.defaultKey)
                                    .frame(width: 80)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                    .onTapGesture {
                                        editingShortcut = tool
                                    }
                            }

                            Button("Reset") {
                                ShortcutManager.shared.resetToDefault(tool: tool)
                                shortcuts = ShortcutManager.shared.allShortcuts
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    Button("Reset All to Defaults") {
                        ShortcutManager.shared.resetAllToDefault()
                        shortcuts = ShortcutManager.shared.allShortcuts
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            shortcuts = ShortcutManager.shared.allShortcuts
        }
    }
}
