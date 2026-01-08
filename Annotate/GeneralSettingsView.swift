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
    @State private var cursorHighlightEnabled: Bool = CursorHighlightManager.shared.cursorHighlightEnabled
    @State private var effectColor: Color = Color(CursorHighlightManager.shared.effectColor)
    @State private var effectSize: Double = Double(CursorHighlightManager.shared.effectSize)
    @State private var spotlightSize: Double = Double(CursorHighlightManager.shared.spotlightSize)
    @State private var activeCursorStyle: ActiveCursorStyle = CursorHighlightManager.shared.activeCursorStyle
    @State private var activeCursorSize: Double = Double(CursorHighlightManager.shared.activeCursorSize)

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
                    icon: "cursorarrow",
                    title: "Active Cursor",
                    subtitle: "Cursor appearance when overlay is active"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cursor Style")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Choose how the cursor appears while annotating")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ActiveCursorPreview(
                                style: activeCursorStyle,
                                color: CursorHighlightManager.shared.annotationColor,
                                size: CGFloat(activeCursorSize)
                            )
                        }
                        Picker("", selection: $activeCursorStyle) {
                            ForEach(ActiveCursorStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: activeCursorStyle) { _, newValue in
                            CursorHighlightManager.shared.activeCursorStyle = newValue
                        }
                    }

                    if activeCursorStyle == .circle || activeCursorStyle == .crosshair {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cursor Size")
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 8) {
                                Text("8")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                Slider(value: $activeCursorSize, in: 8...24)
                                    .onChange(of: activeCursorSize) { _, newValue in
                                        Task { @MainActor in
                                            CursorHighlightManager.shared.activeCursorSize = CGFloat(newValue)
                                        }
                                    }
                                Text("24")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .leading)
                            }
                        }
                    }
                }

                Divider()

                SettingsSection(
                    icon: "cursorarrow.motionlines",
                    title: "Cursor Highlight",
                    subtitle: "Spotlight and click effects for presentations"
                ) {
                    SettingsToggleRow(
                        title: "Enable Cursor Spotlight",
                        description: "Show spotlight following cursor",
                        isOn: $cursorHighlightEnabled
                    ) {
                        CursorHighlightManager.shared.cursorHighlightEnabled = cursorHighlightEnabled
                    }

                    if cursorHighlightEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Spotlight Size")
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 8) {
                                Text("30")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Slider(value: $spotlightSize, in: 30...100)
                                    .onChange(of: spotlightSize) { _, newValue in
                                        Task { @MainActor in
                                            CursorHighlightManager.shared.spotlightSize = CGFloat(newValue)
                                        }
                                    }
                                Text("100")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .leading)
                            }
                        }
                    }

                    SettingsToggleRow(
                        title: "Enable Click Effect",
                        description: "Ripple on click + highlight while holding",
                        isOn: $clickEffectsEnabled
                    ) {
                        CursorHighlightManager.shared.clickEffectsEnabled = clickEffectsEnabled
                    }

                    if clickEffectsEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Click Effect Size")
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 8) {
                                Text("30")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Slider(value: $effectSize, in: 30...100)
                                    .onChange(of: effectSize) { _, newValue in
                                        Task { @MainActor in
                                            CursorHighlightManager.shared.effectSize = CGFloat(newValue)
                                        }
                                    }
                                Text("100")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .leading)
                            }
                        }
                    }

                    if clickEffectsEnabled || cursorHighlightEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Effect Color")
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 6) {
                                ForEach(Array(colorPalette.enumerated()), id: \.offset) { _, color in
                                    PresetColorButton(
                                        color: color,
                                        isSelected: NSColor(effectColor).isClose(to: color)
                                    ) {
                                        effectColor = Color(color)
                                        CursorHighlightManager.shared.effectColor = color
                                    }
                                }
                            }
                        }
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
            cursorHighlightEnabled = CursorHighlightManager.shared.cursorHighlightEnabled
            effectColor = Color(CursorHighlightManager.shared.effectColor)
            effectSize = Double(CursorHighlightManager.shared.effectSize)
            spotlightSize = Double(CursorHighlightManager.shared.spotlightSize)
            activeCursorStyle = CursorHighlightManager.shared.activeCursorStyle
            activeCursorSize = Double(CursorHighlightManager.shared.activeCursorSize)
        }
    }
}

private struct PresetColorButton: View {
    let color: NSColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SwiftUI.Circle()
                .fill(Color(color))
                .frame(width: 24, height: 24)
                .overlay(
                    SwiftUI.Circle()
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    SwiftUI.Circle()
                        .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ActiveCursorPreview: View {
    let style: ActiveCursorStyle
    let color: NSColor
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            switch style {
            case .none:
                drawPointerCursor(context: context, center: center, outerColor: .white)

            case .outline:
                drawPointerCursor(context: context, center: center, outerColor: Color(color))

            case .circle:
                let innerSize = size * 0.4
                let strokeWidth = max(2.0, size / 10)
                let outerRect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                let innerRect = CGRect(x: center.x - innerSize / 2, y: center.y - innerSize / 2, width: innerSize, height: innerSize)

                context.stroke(Path(ellipseIn: outerRect), with: .color(Color(color)), lineWidth: strokeWidth)
                context.fill(Path(ellipseIn: innerRect), with: .color(Color(color)))

            case .crosshair:
                var path = Path()
                path.move(to: CGPoint(x: center.x - size / 2, y: center.y))
                path.addLine(to: CGPoint(x: center.x + size / 2, y: center.y))
                path.move(to: CGPoint(x: center.x, y: center.y - size / 2))
                path.addLine(to: CGPoint(x: center.x, y: center.y + size / 2))

                context.stroke(path, with: .color(Color(color)), lineWidth: max(2.5, size / 5))
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }

    private func drawPointerCursor(context: GraphicsContext, center: CGPoint, outerColor: Color) {
        let offsetX = center.x - 5.7
        let offsetY = center.y - 9.25

        var outerPath = Path()
        outerPath.move(to: CGPoint(x: offsetX, y: offsetY))
        outerPath.addLine(to: CGPoint(x: offsetX, y: offsetY + 16))
        outerPath.addLine(to: CGPoint(x: offsetX + 3.3, y: offsetY + 13.2))
        outerPath.addLine(to: CGPoint(x: offsetX + 6.1, y: offsetY + 18.5))
        outerPath.addLine(to: CGPoint(x: offsetX + 8, y: offsetY + 17.5))
        outerPath.addLine(to: CGPoint(x: offsetX + 9.6, y: offsetY + 16.6))
        outerPath.addLine(to: CGPoint(x: offsetX + 7, y: offsetY + 11.8))
        outerPath.addLine(to: CGPoint(x: offsetX + 11.4, y: offsetY + 11.8))
        outerPath.closeSubpath()

        var innerPath = Path()
        innerPath.move(to: CGPoint(x: offsetX + 1, y: offsetY + 2.8))
        innerPath.addLine(to: CGPoint(x: offsetX + 1, y: offsetY + 14))
        innerPath.addLine(to: CGPoint(x: offsetX + 3.5, y: offsetY + 11.6))
        innerPath.addLine(to: CGPoint(x: offsetX + 6.3, y: offsetY + 16.8))
        innerPath.addLine(to: CGPoint(x: offsetX + 8.2, y: offsetY + 15.9))
        innerPath.addLine(to: CGPoint(x: offsetX + 5.4, y: offsetY + 10.7))
        innerPath.addLine(to: CGPoint(x: offsetX + 9, y: offsetY + 10.7))
        innerPath.closeSubpath()

        context.fill(outerPath, with: .color(outerColor))
        context.fill(innerPath, with: .color(.black))
    }
}
