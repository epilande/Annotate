import AppKit
import Combine
import SwiftUI

enum ToolbarAction {
    case tool(ToolType)
    case colorPicker
    case widthPicker
    case toggleFade
    case deleteLast
    case clearAll
    case undo
}

@MainActor
final class ToolbarModel: ObservableObject {
    @Published var activeTool: ToolType = .pen
    @Published var currentColor: NSColor = .systemRed
    @Published var currentWidth: CGFloat = 3
    @Published var fadeMode = true
    @Published var shortcutsVersion = 0

    var widthDotDiameter: CGFloat {
        let index = QuickPickerView.nearestIndex(in: QuickPickerView.widthOptions, to: currentWidth)
        let progress = CGFloat(index) / CGFloat(max(QuickPickerView.widthOptions.count - 1, 1))
        return 4 + progress * 10
    }
}

@MainActor
struct ToolbarView: View {
    @ObservedObject var model: ToolbarModel
    let perform: (ToolbarAction) -> Void

    private static let tools: [(ToolType, ShortcutKey, String)] = [
        (.pen, .pen, "pencil"),
        (.highlighter, .highlighter, "highlighter"),
        (.arrow, .arrow, "arrow.up.right"),
        (.line, .line, "line.diagonal"),
        (.rectangle, .rectangle, "rectangle"),
        (.circle, .circle, "circle"),
        (.counter, .counter, "number"),
        (.text, .text, "textformat"),
        (.select, .select, "cursorarrow"),
        (.eraser, .eraser, "eraser"),
    ]

    private let spring = Animation.spring(response: 0.24, dampingFraction: 0.72)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                toolsSegment
                stateSegment
                actionsSegment
            }
            VStack(spacing: 8) {
                toolsSegment
                HStack(spacing: 10) {
                    stateSegment
                    actionsSegment
                }
            }
        }
        .id(model.shortcutsVersion)
        .animation(spring, value: model.activeTool)
        .animation(spring, value: model.currentColor)
        .animation(spring, value: model.currentWidth)
        .animation(spring, value: model.fadeMode)
    }

    private var toolsSegment: some View {
        segment {
            ForEach(Self.tools, id: \.0) { tool, key, symbol in
                toolbarButton(identifier: "toolbar.tool.\(tool.rawValue)", action: {
                    perform(.tool(tool))
                }) {
                    let active = model.activeTool == tool
                    chip(symbol: symbol, keycap: shortcut(for: key), active: active)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 11)
                                    .fill(Color(nsColor: model.currentColor))
                            }
                        }
                }
            }
        }
    }

    private var stateSegment: some View {
        segment {
            toolbarButton(identifier: "toolbar.color", action: { perform(.colorPicker) }) {
                HStack(spacing: 6) {
                    SwiftUI.Circle()
                        .fill(Color(nsColor: model.currentColor))
                        .frame(width: 14, height: 14)
                    keycap(shortcut(for: .colorPicker), lit: true)
                }
                .chipPadding()
            }

            toolbarButton(identifier: "toolbar.width", action: { perform(.widthPicker) }) {
                HStack(spacing: 6) {
                    SwiftUI.Circle()
                        .fill(Color(nsColor: model.currentColor))
                        .frame(width: model.widthDotDiameter, height: model.widthDotDiameter)
                        .frame(width: 14, height: 14)
                    keycap(shortcut(for: .lineWidthPicker), lit: true)
                }
                .chipPadding()
            }

            toolbarButton(identifier: "toolbar.fade", action: { perform(.toggleFade) }) {
                chip(symbol: "circle.lefthalf.filled", keycap: "␣", active: model.fadeMode)
                    .background {
                        if model.fadeMode {
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Color.primary.opacity(0.14))
                        }
                    }
            }
        }
    }

    private var actionsSegment: some View {
        segment {
            toolbarButton(identifier: "toolbar.deleteLast", action: { perform(.deleteLast) }) {
                chip(symbol: "delete.left", keycap: "⌫")
            }
            toolbarButton(identifier: "toolbar.clearAll", action: { perform(.clearAll) }) {
                chip(symbol: "trash", keycap: "⌥⌫")
            }
            toolbarButton(identifier: "toolbar.undo", action: { perform(.undo) }) {
                chip(symbol: "arrow.uturn.backward", keycap: "⌘Z")
            }
        }
    }

    private func segment<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .padding(5)
            .toolbarGlassSegment()
            .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
            .fixedSize()
    }

    private func toolbarButton<Label: View>(
        identifier: String,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        HoverScaleButton(action: action, label: label)
            .accessibilityIdentifier(identifier)
    }

    private func chip(symbol: String, keycap text: String, active: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
            keycap(text, lit: active, inverted: active)
        }
        .foregroundStyle(active ? Color.white : Color.primary.opacity(0.76))
        .chipPadding()
    }

    private func keycap(_ text: String, lit: Bool = false, inverted: Bool = false) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(
                inverted
                    ? Color.white.opacity(0.95)
                    : Color.primary.opacity(lit ? 0.95 : 0.58)
            )
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
            )
    }

    private func shortcut(for key: ShortcutKey) -> String {
        ShortcutManager.shared.getShortcut(for: key)
    }
}

private extension View {
    func chipPadding() -> some View {
        padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(SwiftUI.Rectangle())
    }
}

@MainActor
private struct HoverScaleButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) { label() }
            .buttonStyle(.plain)
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: hovering)
            .onHover { hovering = $0 }
    }
}
