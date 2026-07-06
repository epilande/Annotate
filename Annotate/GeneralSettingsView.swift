import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(UserDefaults.clearDrawingsOnStartKey)
    private var clearDrawingsOnStart = false
    @AppStorage(UserDefaults.hideDockIconKey)
    private var hideDockIcon = false
    @AppStorage(UserDefaults.hideToolFeedbackKey)
    private var hideToolFeedback = false
    @AppStorage(UserDefaults.persistTextModeKey)
    private var persistTextMode = false
    @AppStorage(UserDefaults.defaultToolKey)
    private var defaultToolOption: DefaultToolOption = .lastUsed

    /// Tools offered in the Default Tool picker, excluding Select and Eraser since neither
    /// is a sensible tool to land on when the overlay opens.
    private static let selectableDefaultTools = ToolType.allCases.filter {
        $0 != .select && $0 != .eraser
    }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .general)
            }

            Section {
                LabeledContent {
                    KeyboardShortcuts.Recorder("", name: .toggleOverlay)
                } label: {
                    Text("Activation Shortcut")
                    Text("Primary keyboard shortcut to activate Annotate")
                    Text("Requires modifier keys (⌘, ⌥, ⌃, or ⇧)")
                }

                LabeledContent {
                    KeyboardShortcuts.Recorder("", name: .toggleAlwaysOnMode)
                } label: {
                    Text("Always-On Mode")
                    Text("Keep Annotate active without auto-hide")
                    Text("Requires modifier keys (⌘, ⌥, ⌃, or ⇧)")
                }
            } header: {
                SettingsHeader(
                    icon: "keyboard",
                    color: .gray,
                    title: "Keyboard Shortcuts",
                    subtitle: "Set keyboard shortcuts to activate Annotate and jump to specific modes"
                )
            }

            Section {
                Toggle(isOn: $clearDrawingsOnStart) {
                    Text("Clear Drawings on Toggle")
                    Text("Clear all drawings when toggling overlay off")
                }

                Toggle(isOn: $hideToolFeedback) {
                    Text("Hide Tool Feedback")
                    Text("Disable visual feedback when switching tools")
                }

                Toggle(
                    isOn: Binding(
                        get: { !hideDockIcon },
                        set: { hideDockIcon = !$0 }
                    )
                ) {
                    Text("Show in Dock")
                    Text("Display Annotate icon in the Dock")
                }
                .onChange(of: hideDockIcon) { _, _ in
                    AppDelegate.shared?.updateDockIconVisibility()
                }

                Toggle(isOn: $persistTextMode) {
                    Text("Persist Text Mode")
                    Text("Stay in text mode after pressing Enter")
                }

                Picker(selection: $defaultToolOption) {
                    Text("Last Used").tag(DefaultToolOption.lastUsed)
                    ForEach(Self.selectableDefaultTools, id: \.self) { tool in
                        Text(tool.displayName).tag(DefaultToolOption.tool(tool))
                    }
                } label: {
                    Text("Default Tool")
                    Text("Tool selected each time the overlay is activated")
                }
            } header: {
                SettingsHeader(
                    icon: "macwindow",
                    color: .blue,
                    title: "Application",
                    subtitle: "Configure app launch and display options"
                )
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .settingsScrollEdgeEffect()
    }
}
