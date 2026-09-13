import SwiftUI
import AppKit

struct ShortcutRecordingEventResult {
    let editingShortcut: ShortcutKey?
    let consumesEvent: Bool
}

enum ShortcutRecordingEventHandler {
    static func handle(
        _ event: NSEvent,
        editingShortcut: ShortcutKey?
    ) -> ShortcutRecordingEventResult {
        if event.type == .keyDown && event.keyCode == 53 {
            return ShortcutRecordingEventResult(editingShortcut: nil, consumesEvent: true)
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            return ShortcutRecordingEventResult(editingShortcut: nil, consumesEvent: false)
        }
        return ShortcutRecordingEventResult(
            editingShortcut: editingShortcut,
            consumesEvent: false
        )
    }
}

struct ShortcutField: View {
    let tool: ShortcutKey
    @Binding var shortcuts: [ShortcutKey: String]
    @Binding var editingShortcut: ShortcutKey?

    @FocusState private var isFocused: Bool
    @State private var eventMonitor: Any?

    var body: some View {
        ZStack {
            TextField("", text: .constant(""))
                .opacity(0)
                .frame(width: 0, height: 0)
                .focused($isFocused)
                .onAppear {
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSControl.textDidChangeNotification)
                ) { _ in
                    if let event = NSApp.currentEvent, event.type == .keyDown {
                        let key = event.characters?.lowercased() ?? ""
                        if !key.isEmpty {
                            ShortcutManager.shared.setShortcut(key, for: tool)
                            shortcuts = ShortcutManager.shared.allShortcuts
                        }
                        editingShortcut = nil
                    }
                }

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
        }
        .onAppear {
            setupEventMonitor()
        }
        .onDisappear {
            removeEventMonitor()
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            let result = ShortcutRecordingEventHandler.handle(
                event,
                editingShortcut: editingShortcut
            )
            editingShortcut = result.editingShortcut
            return result.consumesEvent ? nil : event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
