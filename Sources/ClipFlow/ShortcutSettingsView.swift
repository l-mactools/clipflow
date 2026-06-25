import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var shortcuts: ShortcutController
    @EnvironmentObject private var store: ClipboardStore

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

            Section("历史有效期") {
                Picker("统一保存时长", selection: unifiedRetentionBinding) {
                    ForEach(Self.retentionOptions, id: \.hours) { option in
                        Text(option.title).tag(option.hours)
                    }
                }

                Toggle("按内容类型分别设置", isOn: perKindRetentionBinding)

                if !store.retentionPolicy.perKindHours.isEmpty {
                    ForEach(ClipKind.allCases) { kind in
                        Picker(kind.rawValue, selection: retentionBinding(for: kind)) {
                            ForEach(Self.retentionOptions, id: \.hours) { option in
                                Text(option.title).tag(option.hours)
                            }
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
        .frame(width: 520, height: 500)
    }

    private var unifiedRetentionBinding: Binding<Int> {
        Binding {
            store.retentionPolicy.unifiedHours
        } set: {
            store.updateUnifiedRetention(hours: $0)
        }
    }

    private var perKindRetentionBinding: Binding<Bool> {
        Binding {
            !store.retentionPolicy.perKindHours.isEmpty
        } set: { enabled in
            if enabled {
                for kind in ClipKind.allCases where store.retentionPolicy.perKindHours[kind] == nil {
                    store.updateKindRetention(kind, hours: store.retentionPolicy.unifiedHours)
                }
            } else {
                store.useUnifiedRetentionForAllKinds()
            }
        }
    }

    private func retentionBinding(for kind: ClipKind) -> Binding<Int> {
        Binding {
            store.retentionPolicy.perKindHours[kind] ?? store.retentionPolicy.unifiedHours
        } set: {
            store.updateKindRetention(kind, hours: $0)
        }
    }

    private static let retentionOptions = [
        (title: "1 小时", hours: 1),
        (title: "6 小时", hours: 6),
        (title: "12 小时", hours: 12),
        (title: "24 小时", hours: 24),
        (title: "3 天", hours: 72),
        (title: "7 天", hours: 168),
        (title: "30 天", hours: 720)
    ]
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
