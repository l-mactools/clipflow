import AppKit
import SwiftUI

@MainActor
final class QuickPanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var selectedIndex = 0
    @Published private(set) var lastAddedToBasketID: UUID?
    @Published var query = "" {
        didSet { selectedIndex = 0 }
    }

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
        // 每次打开都用最新数据重建内容视图：隐藏期间 NSHostingController 不会响应 store 的
        // 更新，复用旧视图会显示过期快照（表现为「新复制的内容要重启才出现」）。
        panel.contentViewController = NSHostingController(
            rootView: QuickPanelView(controller: self, store: store)
        )
        // 重新指定 contentViewController 会让窗口缩到新视图的 fitting size，此刻 SwiftUI 尚未布局，
        // 宽度会瞬时变小；必须显式恢复尺寸后再定位，否则面板会被推到屏幕右侧外。
        panel.setContentSize(NSSize(width: 640, height: 460))
        position(panel)
        NSRunningApplication.current.activate(options: [])
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installKeyMonitor()
    }

    var currentContextBundleID: String? {
        previousApplication?.bundleIdentifier
    }

    var visibleItems: [ClipboardItem] {
        store.recentItems(matching: query)
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

    func moveSelection(by offset: Int) {
        select(selectedIndex + offset)
    }

    func clearSearch() {
        query = ""
        selectedIndex = 0
    }

    func addCurrentToBasket() {
        let items = visibleItems
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        store.addToBasket(item)
        lastAddedToBasketID = item.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if lastAddedToBasketID == item.id { lastAddedToBasketID = nil }
        }
    }

    func popAndPasteFromBasket() {
        guard let item = store.popNextFromBasket() else {
            NSSound.beep()
            return
        }
        store.copy(item)
        let application = previousApplication
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            application?.activate(options: [.activateAllWindows])
            Self.sendPasteCommand()
        }
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

            // ⌘⇧↩：顺序粘贴篮子下一条
            if event.modifierFlags.intersection([.command, .shift]) == [.command, .shift],
               event.keyCode == 36 {
                popAndPasteFromBasket()
                return nil
            }

            // ⌘1-⌘9：直选
            guard event.modifierFlags.contains(.command),
                  let index = Self.numberIndex(for: event.keyCode) else {
                return event
            }
            selectedIndex = index
            confirmSelection()
            return nil
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
