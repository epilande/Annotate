import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(UserDefaults.clearDrawingsOnStartKey)
    private var clearDrawingsOnStart = false
    @AppStorage(UserDefaults.hideDockIconKey)
    private var hideDockIcon = false
    @AppStorage(UserDefaults.hideToolFeedbackKey)
    private var hideToolFeedback = false
    @AppStorage(UserDefaults.enableBoardKey)
    private var enableBoard = false
    @State private var boardOpacity: Double = BoardManager.shared.opacity
    @State private var clickEffectsEnabled: Bool = CursorHighlightManager.shared.clickEffectsEnabled
    @State private var effectColor: Color = Color(CursorHighlightManager.shared.effectColor)
    @State private var effectSize: Double = Double(CursorHighlightManager.shared.effectSize)
    @State private var highlightMode: CursorHighlightMode = CursorHighlightManager.shared.highlightMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(
                    icon: "keyboard",
                    title: "Keyboard Shortcuts",
                    subtitle: "Set keyboard shortcuts to activate Annotate and jump to specific modes"
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Activation Shortcut")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Primary keyboard shortcut to activate Annotate")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("Requires modifier keys (⌘, ⌥, ⌃, or ⇧)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: .toggleOverlay)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Always-On Mode")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Keep Annotate active without auto-hide")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("Requires modifier keys (⌘, ⌥, ⌃, or ⇧)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: .toggleAlwaysOnMode)
                    }
                }

                Divider()

                SettingsSection(
                    icon: "macwindow",
                    title: "Application",
                    subtitle: "Configure app launch and display options"
                ) {
                    SettingsToggleRow(
                        title: "Clear Drawings on Toggle",
                        description: "Clear all drawings when toggling overlay off",
                        isOn: $clearDrawingsOnStart
                    )

                    SettingsToggleRow(
                        title: "Hide Tool Feedback",
                        description: "Disable visual feedback when switching tools",
                        isOn: $hideToolFeedback
                    )

                    SettingsToggleRow(
                        title: "Show in Dock",
                        description: "Display Annotate icon in the Dock",
                        isOn: Binding(
                            get: { !hideDockIcon },
                            set: { hideDockIcon = !$0 }
                        )
                    ) {
                        AppDelegate.shared?.updateDockIconVisibility()
                    }
                }

                Divider()

                SettingsSection(
                    icon: "rectangle.inset.filled",
                    title: "Board Settings",
                    subtitle: "Customize board appearance and visibility"
                ) {
                    SettingsToggleRow(
                        title: "Enable Board",
                        description: "Show whiteboard or blackboard background",
                        isOn: $enableBoard
                    ) {
                        BoardManager.shared.isEnabled = enableBoard
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Board Opacity")
                            .font(.system(size: 13, weight: .semibold))

                        HStack(spacing: 8) {
                            Text("10%")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)

                            Slider(value: $boardOpacity, in: 0.1...1.0)
                                .onChange(of: boardOpacity) { _, newValue in
                                    BoardManager.shared.opacity = newValue
                                }

                            Text("100%")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 35, alignment: .leading)
                        }
                    }
                }

                Divider()

                SettingsSection(
                    icon: "cursorarrow.motionlines",
                    title: "Click Effects",
                    subtitle: "Visual feedback for mouse clicks"
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Visibility Mode")
                                .font(.system(size: 13, weight: .semibold))
                            Text("When click effects are visible")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $highlightMode) {
                            Text("Always On").tag(CursorHighlightMode.always)
                            Text("Overlay Only").tag(CursorHighlightMode.overlayOnly)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .onChange(of: highlightMode) { _, newValue in
                            CursorHighlightManager.shared.highlightMode = newValue
                        }
                    }

                    SettingsToggleRow(
                        title: "Enable Click Effects",
                        description: "Ripple on click + highlight while holding",
                        isOn: $clickEffectsEnabled
                    ) {
                        CursorHighlightManager.shared.clickEffectsEnabled = clickEffectsEnabled
                    }

                    if clickEffectsEnabled {
                        HStack(spacing: 16) {
                            ColorPicker("Color", selection: $effectColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: effectColor) { _, newValue in
                                    CursorHighlightManager.shared.effectColor = NSColor(newValue)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Effect Size")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text("30")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Slider(value: $effectSize, in: 30...150)
                                        .onChange(of: effectSize) { _, newValue in
                                            CursorHighlightManager.shared.effectSize = CGFloat(newValue)
                                        }
                                    Text("150")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.leading, 16)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 60)
        }
        .onAppear {
            enableBoard = BoardManager.shared.isEnabled
            boardOpacity = BoardManager.shared.opacity
            clickEffectsEnabled = CursorHighlightManager.shared.clickEffectsEnabled
            effectColor = Color(CursorHighlightManager.shared.effectColor)
            effectSize = Double(CursorHighlightManager.shared.effectSize)
            highlightMode = CursorHighlightManager.shared.highlightMode
        }
    }
}
