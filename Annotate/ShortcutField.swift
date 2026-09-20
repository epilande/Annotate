import SwiftUI
import AppKit
@preconcurrency import KeyboardShortcuts

struct ShortcutRecordingEventResult {
    let editingShortcut: ShortcutKey?
    let consumesEvent: Bool
    var error: String? = nil
}

enum ShortcutRecordingEventHandler {
    @MainActor
    static func handle(
        _ event: NSEvent,
        editingShortcut: ShortcutKey?,
        manager: ShortcutManager? = nil
    ) -> ShortcutRecordingEventResult {
        guard let tool = editingShortcut else {
            return ShortcutRecordingEventResult(editingShortcut: nil, consumesEvent: false)
        }
        if event.type == .keyDown && event.keyCode == 53 {
            return ShortcutRecordingEventResult(editingShortcut: nil, consumesEvent: true)
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            return ShortcutRecordingEventResult(editingShortcut: nil, consumesEvent: false)
        }
        guard event.type == .keyDown else {
            return ShortcutRecordingEventResult(editingShortcut: tool, consumesEvent: false)
        }
        guard !event.isARepeat, let binding = ShortcutBinding(event: event) else {
            return ShortcutRecordingEventResult(editingShortcut: tool, consumesEvent: true)
        }
        if binding.isReserved {
            return ShortcutRecordingEventResult(editingShortcut: tool, consumesEvent: true,
                error: "This shortcut is reserved for a built-in action.")
        }
        let manager = manager ?? .shared
        if let conflict = manager.globalShortcutConflict(for: binding) {
            return ShortcutRecordingEventResult(editingShortcut: tool, consumesEvent: true,
                error: "This shortcut is assigned to \(conflict) in General Settings. Change it there first.")
        }
        guard manager.setShortcut(binding, for: tool) else {
            return ShortcutRecordingEventResult(editingShortcut: tool, consumesEvent: true,
                error: "This shortcut is already assigned. Clear it from the other action first.")
        }
        return ShortcutRecordingEventResult(editingShortcut: nil, consumesEvent: true)
    }
}

struct ShortcutField: View {
    let tool: ShortcutKey
    @Binding var shortcuts: [ShortcutKey: String]
    @Binding var editingShortcut: ShortcutKey?

    @State private var eventMonitor: Any?
    @State private var error: String?
    @State private var shortcutsWereEnabled = false
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Recording...")
                .font(.body)
                .foregroundStyle(.primary)
                .frame(minWidth: 100)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 2)
                        )
                )
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            shortcutsWereEnabled = KeyboardShortcuts.isEnabled
            KeyboardShortcuts.isEnabled = false
            setupEventMonitor()
        }
        .onDisappear {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            KeyboardShortcuts.isEnabled = shortcutsWereEnabled
        }
        .onChange(of: controlActiveState) { _, state in
            if state == .inactive { editingShortcut = nil }
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            let result = ShortcutRecordingEventHandler.handle(event, editingShortcut: editingShortcut)
            shortcuts = ShortcutManager.shared.allShortcuts
            editingShortcut = result.editingShortcut
            error = result.error
            return result.consumesEvent ? nil : event
        }
    }
}
