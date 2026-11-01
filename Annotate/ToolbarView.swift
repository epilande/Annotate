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

extension ToolbarAction {
    /// What VoiceOver calls the chip. It names the action rather than reading the keycap, and
    /// stays the same in either layout and with the keycaps hidden.
    var accessibilityLabel: String {
        switch self {
        case .tool(let tool): return tool.displayName
        case .colorPicker: return "Color"
        case .widthPicker: return "Line Width"
        case .toggleFade: return "Fade Mode"
        // Matches the Delete row in Settings › Shortcuts: the selection, else the newest item.
        case .deleteLast: return "Delete"
        case .clearAll: return "Clear All"
        case .undo: return "Undo"
        }
    }
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

    private static let symbolFont = Font.system(size: 13, weight: .medium)
    private static let fadeSymbol = "circle.lefthalf.filled"
    private static let deleteLastSymbol = "delete.left"
    private static let clearAllSymbol = "trash"
    private static let undoSymbol = "arrow.uturn.backward"
    /// Every symbol a chip can show. The color and width dots are narrower than all of them.
    private static let chipSymbols =
        ToolType.allCases.map(\.symbolName) + [fadeSymbol, deleteLastSymbol, clearAllSymbol, undoSymbol]

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
            EqualWidthColumn(spacing: 8) {
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
                let active = model.activeTool == tool
                toolbarButton(.tool(tool), identifier: "toolbar.tool.\(tool.rawValue)") {
                    chip(symbol: tool.symbolName, keycap: keycapText(for: .tool(tool)), active: active)
                        .anchorPreference(key: SelectedToolBounds.self, value: .bounds) {
                            active ? $0 : nil
                        }
                }
                .accessibilityAddTraits(active ? .isSelected : [])
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
        .toolbarSegment(vertical: isVertical)
    }

    private var stateSegment: some View {
        segment {
            toolbarButton(.colorPicker, identifier: "toolbar.color") {
                HStack(spacing: 6) {
                    iconSlot {
                        SwiftUI.Circle()
                            .fill(Color(nsColor: model.currentColor))
                            .frame(width: 14, height: 14)
                    }
                    keycap(keycapText(for: .colorPicker), lit: true)
                }
                .chipWidth(filling: isVertical)
                .chipPadding()
            }
            .accessibilityValue(model.currentColor.accessibilityName)

            // No value: the picker this chip opens (line width, font size, or counter size)
            // depends on the tool, so a width alone would be wrong for some of them.
            toolbarButton(.widthPicker, identifier: "toolbar.width") {
                HStack(spacing: 6) {
                    iconSlot {
                        SwiftUI.Circle()
                            .fill(Color(nsColor: model.currentColor))
                            .frame(width: model.widthDotDiameter, height: model.widthDotDiameter)
                            .frame(width: 14, height: 14)
                    }
                    keycap(keycapText(for: .widthPicker), lit: true)
                }
                .chipWidth(filling: isVertical)
                .chipPadding()
            }

            toolbarButton(.toggleFade, identifier: "toolbar.fade") {
                chip(symbol: Self.fadeSymbol, keycap: keycapText(for: .toggleFade), active: model.fadeMode)
                    .background {
                        if model.fadeMode {
                            ToolbarSelectionLens()
                        }
                    }
            }
            .accessibilityValue(model.fadeMode ? "On" : "Off")
        }
    }

    private var actionsSegment: some View {
        segment {
            toolbarButton(.deleteLast, identifier: "toolbar.deleteLast") {
                chip(symbol: Self.deleteLastSymbol, keycap: keycapText(for: .deleteLast))
            }
            toolbarButton(.clearAll, identifier: "toolbar.clearAll") {
                chip(symbol: Self.clearAllSymbol, keycap: keycapText(for: .clearAll))
            }
            toolbarButton(.undo, identifier: "toolbar.undo") {
                chip(symbol: Self.undoSymbol, keycap: keycapText(for: .undo))
            }
        }
    }

    private func segment<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        segmentLayout { content() }
            .toolbarSegment(vertical: isVertical)
    }

    /// Every chip is built here, so none can miss its VoiceOver name. The label names the
    /// action, never the keycap, and the shortcut is the hint whether or not keycaps are shown.
    private func toolbarButton<Label: View>(
        _ action: ToolbarAction,
        identifier: String,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        HoverScaleButton(action: { perform(action) }, label: label)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(action.accessibilityLabel)
            .accessibilityHint(shortcutHint(for: action))
    }

    private func chip(symbol: String, keycap text: String, active: Bool = false) -> some View {
        HStack(spacing: 6) {
            iconSlot {
                Image(systemName: symbol)
                    .font(Self.symbolFont)
            }
            keycap(text, lit: active)
        }
        .chipWidth(filling: isVertical)
        .foregroundStyle(Color.primary.opacity(active ? 1 : 0.76))
        .chipPadding()
    }

    /// In a column, seats an icon at the leading edge of a slot as wide as the widest icon on
    /// the bar, so the keycaps after the icons start at the same x in every segment. The slot
    /// is sized by laying out every symbol, hidden and zero-height, rather than by a measured
    /// constant, so a new or wider symbol keeps the keycaps in line.
    @ViewBuilder
    private func iconSlot<Icon: View>(@ViewBuilder _ icon: () -> Icon) -> some View {
        if isVertical {
            ZStack(alignment: .leading) {
                ZStack {
                    ForEach(Self.chipSymbols, id: \.self) { Image(systemName: $0) }
                }
                .font(Self.symbolFont)
                .frame(height: 0)
                .hidden()
                .accessibilityHidden(true)
                icon()
            }
        } else {
            icon()
        }
    }

    @ViewBuilder
    private func keycap(_ text: String, lit: Bool = false) -> some View {
        if model.showsShortcuts {
            keycapLabel(text, lit: lit)
        }
    }

    private func keycapLabel(_ text: String, lit: Bool) -> some View {
        Text(keycap: text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            // The chip's hint speaks the shortcut, so the keycap stays out of its label.
            .accessibilityHidden(true)
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

    /// The keycap a chip shows. Its VoiceOver hint is built from the same text.
    private func keycapText(for action: ToolbarAction) -> String {
        switch action {
        case .tool(let tool): return shortcut(for: tool.shortcutKey)
        case .colorPicker: return shortcut(for: .colorPicker)
        case .widthPicker: return shortcut(for: .lineWidthPicker)
        case .toggleFade: return shortcut(for: .toggleFade)
        case .deleteLast: return "⌫"
        case .clearAll: return shortcut(for: .clearAll)
        case .undo: return "⌘Z"
        }
    }

    /// Empty for a cleared binding, so VoiceOver has no shortcut to announce.
    private func shortcutHint(for action: ToolbarAction) -> String {
        let keys = keycapText(for: action)
        return keys.isEmpty ? "" : "Shortcut: \(ShortcutBinding.spokenLabel(for: keys))"
    }
}

/// The vertical toolbar's segments, top to bottom, each as wide as the widest one's natural
/// width. A `VStack` would leave each segment at its own width, so one long keycap (or icon)
/// would make its segment jut out past the others.
struct EqualWidthColumn: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = columnWidth(of: subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: heights.reduce(0, +) + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let segmentProposal = ProposedViewSize(width: columnWidth(of: subviews), height: nil)
        var y = bounds.minY
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: segmentProposal)
            y += subview.sizeThatFits(segmentProposal).height + spacing
        }
    }

    /// The widest segment's natural width: what each one asks for with no width proposed.
    private func columnWidth(of subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}

private struct SelectedToolBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private extension View {
    /// A row's segments keep their own size. A column's take the width `EqualWidthColumn`
    /// proposes, which is never narrower than their own.
    func toolbarSegment(vertical: Bool) -> some View {
        padding(5)
            .toolbarGlassSegment()
            .fixedSize(horizontal: !vertical, vertical: true)
    }

    /// In a column, stretches every chip to the segment's width so the selection lens and hover
    /// targets line up. `EqualWidthColumn` gives every segment the widest one's width.
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
