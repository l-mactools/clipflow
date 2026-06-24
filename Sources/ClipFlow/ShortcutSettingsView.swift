import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var shortcuts: ShortcutController

    var body: some View {
        Form {
            Section("打开面板") {
                LabeledContent("全局快捷键") {
                    ShortcutRecorder(shortcut: shortcuts.openShortcut) {
                        shortcuts.updateOpenShortcut($0)
                    }
                }
                Text("按下快捷键打开历史面板，使用 ↑↓ 选择，按回车确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = shortcuts.registrationError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 500, height: 260)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: HotKey
    let onChange: (HotKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: shortcut, onChange: onChange)
    }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.title = shortcut.displayName
        button.coordinator = context.coordinator
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        context.coordinator.shortcut = shortcut
        context.coordinator.onChange = onChange
        if !button.isRecording { button.title = shortcut.displayName }
    }

    final class Coordinator {
        var shortcut: HotKey
        var onChange: (HotKey) -> Void

        init(shortcut: HotKey, onChange: @escaping (HotKey) -> Void) {
            self.shortcut = shortcut
            self.onChange = onChange
        }
    }

    final class RecorderButton: NSButton {
        weak var coordinator: Coordinator?
        var isRecording = false
        private var keyMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        deinit {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }

        @objc func beginRecording() {
            isRecording = true
            title = "请按组合键…"
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            guard let window else {
                NSSound.beep()
                return
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                if window.makeFirstResponder(self) {
                    installKeyMonitor()
                } else {
                    isRecording = false
                    title = coordinator?.shortcut.displayName ?? "设置快捷键"
                    NSSound.beep()
                }
            }
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            capture(event)
        }

        private func installKeyMonitor() {
            removeKeyMonitor()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, isRecording else { return event }
                capture(event)
                return nil
            }
        }

        private func capture(_ event: NSEvent) {
            if event.keyCode == 53 {
                finishRecording()
                return
            }
            guard let shortcut = HotKey(event: event) else {
                NSSound.beep()
                return
            }
            coordinator?.shortcut = shortcut
            coordinator?.onChange(shortcut)
            finishRecording()
        }

        private func finishRecording() {
            isRecording = false
            removeKeyMonitor()
            if let shortcut = coordinator?.shortcut { title = shortcut.displayName }
            window?.makeFirstResponder(nil)
        }

        private func removeKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }
}
