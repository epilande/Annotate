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

/// Which way the floating toolbar runs.
enum ToolbarLayout: String, CaseIterable {
    /// One row along the bottom, wrapping onto two rows on a narrow display.
    case horizontal
    /// One column, resting along the left edge.
    case vertical

    var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

@MainActor
final class ToolbarModel: ObservableObject {
    @Published var activeTool: ToolType = .pen
    @Published var currentColor: NSColor = .systemRed
    @Published var currentWidth: CGFloat = 3
    @Published var fadeMode = true
    /// Snapshot of the user's tool shortcuts, refreshed by the window on `.shortcutsDidChange`.
    @Published var shortcuts: [ShortcutKey: String] = [:]
    /// Whether the chips carry their shortcut keycaps.
    @Published var showsShortcuts = true
    @Published var layout: ToolbarLayout = .horizontal
    /// Bumped after the live host is given a new measured size so `ViewThatFits` remounts
    /// against that width instead of keeping a stacked choice from a previous overlay.
    @Published var layoutGeneration = 0

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spring = Animation.spring(response: 0.24, dampingFraction: 0.72)

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            // Resolve the segments' backdrop together on first presentation. Separate
            // effects in this non-key panel keep an inactive fill until the first click.
            // Zero spacing preserves the gaps between the three glass surfaces.
            GlassEffectContainer(spacing: 0) { toolbarContent }
        } else {
            toolbarContent
        }
    }

    private var isVertical: Bool { model.layout == .vertical }

    /// The direction chips run inside a segment.
    private var segmentLayout: AnyLayout {
        isVertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
    }

    @ViewBuilder
    private var segments: some View {
        if isVertical {
            VStack(spacing: 8) {
                toolsSegment
                stateSegment
                actionsSegment
            }
        } else {
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
        }
    }

    private var toolbarContent: some View {
        segments
        .id(model.layoutGeneration)
        .animation(reduceMotion ? nil : spring, value: model.activeTool)
        .animation(spring, value: model.currentColor)
        .animation(spring, value: model.currentWidth)
        .animation(spring, value: model.fadeMode)
    }

    private var toolsSegment: some View {
        segmentLayout {
            ForEach(ToolType.allCases, id: \.self) { tool in
                toolbarButton(identifier: "toolbar.tool.\(tool.rawValue)", action: {
                    perform(.tool(tool))
                }) {
                    let active = model.activeTool == tool
                    chip(symbol: tool.symbolName, keycap: shortcut(for: tool.shortcutKey), active: active)
                        .anchorPreference(key: SelectedToolBounds.self, value: .bounds) {
                            active ? $0 : nil
                        }
                }
            }
        }
        .backgroundPreferenceValue(SelectedToolBounds.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let bounds = proxy[anchor]
                    ToolbarSelectionLens()
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                        .animation(reduceMotion ? nil : spring, value: bounds)
                }
            }
        }
        .toolbarSegment()
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
                .chipWidth(filling: isVertical)
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
                .chipWidth(filling: isVertical)
                .chipPadding()
            }

            toolbarButton(identifier: "toolbar.fade", action: { perform(.toggleFade) }) {
                chip(symbol: "circle.lefthalf.filled", keycap: shortcut(for: .toggleFade), active: model.fadeMode)
                    .background {
                        if model.fadeMode {
                            ToolbarSelectionLens()
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
                chip(symbol: "trash", keycap: shortcut(for: .clearAll))
            }
            toolbarButton(identifier: "toolbar.undo", action: { perform(.undo) }) {
                chip(symbol: "arrow.uturn.backward", keycap: "⌘Z")
            }
        }
    }

    private func segment<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        segmentLayout { content() }
            .toolbarSegment()
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
                // Symbols differ in width; in a column that would leave the keycaps ragged.
                .frame(minWidth: isVertical ? 14 : nil)
            keycap(text, lit: active)
        }
        .chipWidth(filling: isVertical)
        .foregroundStyle(Color.primary.opacity(active ? 1 : 0.76))
        .chipPadding()
    }

    @ViewBuilder
    private func keycap(_ text: String, lit: Bool = false) -> some View {
        if model.showsShortcuts {
            keycapLabel(text, lit: lit)
        }
    }

    private func keycapLabel(_ text: String, lit: Bool) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(lit ? 0.95 : 0.58))
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
            )
    }

    private func shortcut(for key: ShortcutKey) -> String {
        model.shortcuts[key] ?? key.defaultBinding.displayValue
    }
}

private struct SelectedToolBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private extension View {
    func toolbarSegment() -> some View {
        padding(5)
            .toolbarGlassSegment()
            .fixedSize()
    }

    /// In a column, stretches every chip to the widest one so the selection lens and hover
    /// targets line up. The segment is `fixedSize`, so "widest" is the column's own width.
    func chipWidth(filling: Bool) -> some View {
        frame(maxWidth: filling ? .infinity : nil, alignment: .leading)
    }

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
