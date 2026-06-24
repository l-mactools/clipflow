import AppKit
import Carbon
import Foundation

@MainActor
final class ShortcutController: ObservableObject {
    @Published private(set) var openShortcut: HotKey
    @Published private(set) var quickCopyShortcuts: [HotKey]
    @Published private(set) var registrationError: String?

    private let store: ClipboardStore
    private let defaults: UserDefaults
    private var hotKeyReferences: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var openWindowAction: (() -> Void)?

    init(store: ClipboardStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        self.openShortcut = Self.loadHotKey(key: "openShortcut", defaults: defaults) ?? .openPanel
        self.quickCopyShortcuts = Self.loadHotKeys(key: "quickCopyShortcuts", defaults: defaults) ?? HotKey.quickCopyDefaults
        installEventHandler()
        registerAll()
    }

    deinit {
        hotKeyReferences.forEach { _ = UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func updateOpenShortcut(_ shortcut: HotKey) {
        guard !quickCopyShortcuts.contains(shortcut) else {
            registrationError = "该快捷键已用于快速复制"
            return
        }
        openShortcut = shortcut
        saveAndRegister()
    }

    func setOpenWindowAction(_ action: @escaping () -> Void) {
        openWindowAction = action
    }

    func updateQuickCopyShortcut(at index: Int, to shortcut: HotKey) {
        guard quickCopyShortcuts.indices.contains(index) else { return }
        guard shortcut != openShortcut,
              !quickCopyShortcuts.enumerated().contains(where: { $0.offset != index && $0.element == shortcut }) else {
            registrationError = "该快捷键已被其他操作使用"
            return
        }
        quickCopyShortcuts[index] = shortcut
        saveAndRegister()
    }

    private func installEventHandler() {
        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let controller = Unmanaged<ShortcutController>.fromOpaque(userData).takeUnretainedValue()
                controller.handle(id: hotKeyID.id)
                return noErr
            },
            1,
            [eventSpec],
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func registerAll() {
        hotKeyReferences.forEach { _ = UnregisterEventHotKey($0) }
        hotKeyReferences.removeAll()
        registrationError = nil

        register(openShortcut, id: 1)
        for (index, shortcut) in quickCopyShortcuts.enumerated() {
            register(shortcut, id: UInt32(100 + index))
        }
    }

    private func register(_ shortcut: HotKey, id: UInt32) {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeyReferences.append(reference)
        } else {
            registrationError = "快捷键 \(shortcut.displayName) 已被系统或其他应用占用"
        }
    }

    private func handle(id: UInt32) {
        if id == 1 {
            showMainWindow()
            return
        }
        let index = Int(id) - 100
        let recentItems = store.recentItems
        guard recentItems.indices.contains(index) else {
            NSSound.beep()
            return
        }
        store.copy(recentItems[index])
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindowAction?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            guard let window = NSApp.windows.first(where: { $0.title == "ClipFlow" && $0.canBecomeKey }) else {
                NSSound.beep()
                return
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func saveAndRegister() {
        if let data = try? JSONEncoder().encode(openShortcut) {
            defaults.set(data, forKey: "openShortcut")
        }
        if let data = try? JSONEncoder().encode(quickCopyShortcuts) {
            defaults.set(data, forKey: "quickCopyShortcuts")
        }
        registerAll()
    }

    private static func loadHotKey(key: String, defaults: UserDefaults) -> HotKey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }

    private static func loadHotKeys(key: String, defaults: UserDefaults) -> [HotKey]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([HotKey].self, from: data)
    }

    private static let signature: OSType = 0x434C5046 // CLPF
}
