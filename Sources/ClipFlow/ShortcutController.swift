import Carbon
import Foundation

@MainActor
final class ShortcutController: ObservableObject {
    @Published private(set) var openShortcut: HotKey
    @Published private(set) var registrationError: String?

    private let defaults: UserDefaults
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var openAction: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.openShortcut = Self.loadHotKey(defaults: defaults) ?? .openPanel
        installEventHandler()
        registerShortcut()
    }

    deinit {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func setOpenAction(_ action: @escaping () -> Void) {
        openAction = action
    }

    func updateOpenShortcut(_ shortcut: HotKey) {
        openShortcut = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: "openShortcut")
        }
        registerShortcut()
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
                guard status == noErr, hotKeyID.id == 1 else { return status }
                Unmanaged<ShortcutController>.fromOpaque(userData).takeUnretainedValue().openAction?()
                return noErr
            },
            1,
            [eventSpec],
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func registerShortcut() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        registrationError = nil
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            openShortcut.keyCode,
            openShortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            hotKeyReference = reference
        } else {
            registrationError = "快捷键 \(openShortcut.displayName) 已被系统或其他应用占用"
        }
    }

    private static func loadHotKey(defaults: UserDefaults) -> HotKey? {
        guard let data = defaults.data(forKey: "openShortcut") else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }

    private static let signature: OSType = 0x434C5046 // CLPF
}
