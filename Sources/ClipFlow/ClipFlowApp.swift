import AppKit
import SwiftUI

@main
struct ClipFlowApp: App {
    @StateObject private var store: ClipboardStore
    @StateObject private var shortcuts: ShortcutController
    @StateObject private var quickPanel: QuickPanelController
    @State private var didHideInitialWindow = false

    init() {
        Brand.applyApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
        let store = ClipboardStore()
        let quickPanel = QuickPanelController(store: store)
        let shortcuts = ShortcutController()
        shortcuts.setOpenAction { [weak quickPanel] in
            quickPanel?.toggle()
        }
        _store = StateObject(wrappedValue: store)
        _shortcuts = StateObject(wrappedValue: shortcuts)
        _quickPanel = StateObject(wrappedValue: quickPanel)
    }

    var body: some Scene {
        WindowGroup("拾笺", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 560)
                .background(.ultraThinMaterial)
                .onAppear {
                    Brand.applyApplicationIcon()
                    guard !didHideInitialWindow else { return }
                    didHideInitialWindow = true
                    DispatchQueue.main.async {
                        NSApp.windows.first(where: { $0.title == "拾笺" })?.orderOut(nil)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 680)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
        } label: {
            Image(systemName: "clipboard")
                .symbolRenderingMode(.monochrome)
        }

        Settings {
            ShortcutSettingsView()
                .environmentObject(shortcuts)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        Button("打开拾笺") {
            openWindow(id: "main")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                guard let window = NSApp.windows.first(where: {
                    $0.title == "拾笺" && $0.canBecomeKey
                }) else { return }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }

        Button("快捷键设置…") {
            openSettings()
            bringSettingsToFront()
        }

        Divider()

        Button(store.isMonitoring ? "暂停监听" : "继续监听") {
            store.isMonitoring.toggle()
        }

        Button("退出") { NSApp.terminate(nil) }
    }

    private func bringSettingsToFront() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            let settingsWindow = NSApp.windows.first(where: {
                ($0.title.localizedCaseInsensitiveContains("settings") ||
                 $0.title.localizedCaseInsensitiveContains("设置")) &&
                $0.canBecomeKey
            })
            settingsWindow?.makeKeyAndOrderFront(nil)
            settingsWindow?.orderFrontRegardless()
        }
    }
}
