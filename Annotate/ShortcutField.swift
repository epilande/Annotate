import SwiftUI
import AppKit

struct ShortcutField: View {
    let tool: ShortcutKey
    @Binding var shortcuts: [ShortcutKey: String]
    @Binding var editingShortcut: ShortcutKey?

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
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
                            AppDelegate.shared?.updateMenuKeyEquivalents()
                        }
                        editingShortcut = nil
                    }
                }

            Text("Recording...")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(minWidth: 100)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color(white: 0.35) : Color.white)
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
        .onKeyPress(.escape) {
            editingShortcut = nil
            return .handled
        }
        .onExitCommand {
            editingShortcut = nil
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            editingShortcut = nil
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
