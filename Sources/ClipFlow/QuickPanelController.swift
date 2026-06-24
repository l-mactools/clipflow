import AppKit
import SwiftUI

@MainActor
final class QuickPanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var selectedIndex = 0

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
        let panel = makePanelIfNeeded()
        position(panel)
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [])
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installKeyMonitor()
    }

    func select(_ index: Int) {
        let count = min(store.recentItems.count, 10)
        guard count > 0 else { return }
        selectedIndex = min(max(index, 0), count - 1)
    }

    func confirmSelection() {
        let items = Array(store.recentItems.prefix(10))
        guard items.indices.contains(selectedIndex) else { return }
        store.copy(items[selectedIndex])
        dismiss()
    }

    func dismiss() {
        panel?.orderOut(nil)
        removeKeyMonitor()
        previousApplication?.activate(options: [.activateAllWindows])
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
            switch event.keyCode {
            case 126:
                select(selectedIndex - 1)
                return nil
            case 125:
                select(selectedIndex + 1)
                return nil
            case 36, 76:
                confirmSelection()
                return nil
            case 53:
                dismiss()
                return nil
            default:
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
}

private final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
