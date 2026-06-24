import AppKit
import Carbon
import Foundation

struct HotKey: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        guard carbonFlags != 0,
              let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else { return nil }
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonFlags,
            keyLabel: characters.uppercased()
        )
    }

    var displayName: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyLabel
    }

    static let openPanel = HotKey(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey), keyLabel: "V")

    static let quickCopyDefaults: [HotKey] = [
        HotKey(keyCode: 18, modifiers: UInt32(cmdKey | optionKey), keyLabel: "1"),
        HotKey(keyCode: 19, modifiers: UInt32(cmdKey | optionKey), keyLabel: "2"),
        HotKey(keyCode: 20, modifiers: UInt32(cmdKey | optionKey), keyLabel: "3"),
        HotKey(keyCode: 21, modifiers: UInt32(cmdKey | optionKey), keyLabel: "4"),
        HotKey(keyCode: 23, modifiers: UInt32(cmdKey | optionKey), keyLabel: "5")
    ]
}
