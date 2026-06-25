import AppKit
import SwiftUI

@MainActor
final class QuickPanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var selectedIndex = 0
    @Published var query = ""

    let store: ClipboardStore
    private var panel: QuickPanel?
    private var keyMonitor: Any?
    private var previousApplication: NSRunningApplication?

    init(store: ClipboardStore) {
        self.store = store
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        guard !store.recentItems.isEmpty else {
            NSSound.beep()
            return
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        selectedIndex = 0
        query = ""
        let panel = makePanelIfNeeded()
        position(panel)
        NSRunningApplication.current.activate(options: [])
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installKeyMonitor()
    }

    var visibleItems: [ClipboardItem] {
        store.recentItems(matching: query, limit: 10)
    }

    func select(_ index: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selectedIndex = min(max(index, 0), count - 1)
    }

    func confirmSelection(pasteAfterCopy: Bool = false) {
        let items = visibleItems
        guard items.indices.contains(selectedIndex) else { return }
        store.copy(items[selectedIndex])
        let application = previousApplication
        dismiss()
        if pasteAfterCopy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                application?.activate(options: [.activateAllWindows])
                Self.sendPasteCommand()
            }
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        removeKeyMonitor()
        previousApplication?.activate(options: [.activateAllWindows])
    }

    func appendSearch(_ value: String) {
        query += value
        selectedIndex = 0
    }

    func deleteBackward() {
        guard !query.isEmpty else { return }
        query.removeLast()
        selectedIndex = 0
    }

    func clearSearch() {
        query = ""
        selectedIndex = 0
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel?.isVisible == true else { return }
        dismiss()
    }

    private func makePanelIfNeeded() -> QuickPanel {
        if let panel { return panel }
        let panel = QuickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "拾笺历史"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: 520, height: 360)
        panel.maxSize = NSSize(width: 720, height: 560)
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: QuickPanelView(controller: self, store: store)
        )
        panel.setContentSize(NSSize(width: 640, height: 460))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - panel.frame.width - 24,
            y: frame.maxY - panel.frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let usesCommand = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 126:
                select(selectedIndex - 1)
                return nil
            case 125:
                select(selectedIndex + 1)
                return nil
            case 36, 76:
                confirmSelection(pasteAfterCopy: usesCommand)
                return nil
            case 53:
                dismiss()
                return nil
            case 51:
                deleteBackward()
                return nil
            case 18, 19, 20, 21, 23, 22, 26, 28, 25:
                if usesCommand, let index = Self.numberIndex(for: event.keyCode) {
                    selectedIndex = index
                    confirmSelection()
                    return nil
                }
                if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
                    appendSearch(characters)
                    return nil
                }
                return event
            default:
                if !usesCommand,
                   event.modifierFlags.intersection([.option, .control]).isEmpty,
                   let characters = event.charactersIgnoringModifiers,
                   !characters.isEmpty {
                    appendSearch(characters)
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private static func numberIndex(for keyCode: UInt16) -> Int? {
        let keyMap: [UInt16: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
            22: 5, 26: 6, 28: 7, 25: 8
        ]
        return keyMap[keyCode]
    }

    private static func sendPasteCommand() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
