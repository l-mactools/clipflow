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
            }

            Section("直接复制最近记录") {
                Text("无需打开面板，按下快捷键后，对应记录会直接进入系统剪贴板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(shortcuts.quickCopyShortcuts.indices, id: \.self) { index in
                    LabeledContent("第 \(index + 1) 条记录") {
                        ShortcutRecorder(shortcut: shortcuts.quickCopyShortcuts[index]) {
                            shortcuts.updateQuickCopyShortcut(at: index, to: $0)
                        }
                    }
                }
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
        .frame(width: 500, height: 520)
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

        override var acceptsFirstResponder: Bool { true }

        @objc func beginRecording() {
            isRecording = true
            title = "请按组合键…"
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 {
                finishRecording()
                return
            }
            guard let shortcut = HotKey(event: event) else {
                NSSound.beep()
                return
            }
            coordinator?.onChange(shortcut)
            title = shortcut.displayName
            finishRecording()
        }

        private func finishRecording() {
            isRecording = false
            if let shortcut = coordinator?.shortcut { title = shortcut.displayName }
            window?.makeFirstResponder(nil)
        }
    }
}
