import XCTest
import Carbon
import SwiftUI
@testable import ClipFlow

final class ClipFlowTests: XCTestCase {
    func testURLDetection() {
        XCTAssertEqual("https://example.com/path".detectedClipKind, .link)
        XCTAssertEqual("ordinary text".detectedClipKind, .text)
    }

    // 「复制图片」即便剪贴板附带保存路径文本（部分截图工具如此），只要有 tiff 位图就应存为图片。
    // 这是「复制图片没显示」回归的守卫测试。
    @MainActor
    func testImageWithFilePathTextStillCapturedAsImage() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(makeTIFFData(), forType: .tiff)
        pasteboard.setString("/Users/me/photo.jpg", forType: .string)

        store.captureCurrentClipboard()

        XCTAssertEqual(store.items.first?.kind, .image)
    }

    // 「复制图片文件」（Finder ⌘C）含 file-url，应记录为文件路径而非图片内容。
    @MainActor
    func testFileURLCapturedAsFilePath() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/Users/me/photo.jpg") as NSURL])

        store.captureCurrentClipboard()

        XCTAssertEqual(store.items.first?.kind, .file)
        XCTAssertEqual(store.items.first?.text, "/Users/me/photo.jpg")
    }

    // 「复制图片路径」纯文本（无 tiff）应存为文本。
    @MainActor
    func testPlainPathTextCapturedAsText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("/Users/me/photo.jpg", forType: .string)

        store.captureCurrentClipboard()

        XCTAssertEqual(store.items.first?.kind, .text)
        XCTAssertEqual(store.items.first?.text, "/Users/me/photo.jpg")
    }

    // 部分应用（尤其 Qt/跨平台）复制图片只提供 public.png，不提供 tiff。必须也能捕获为图片。
    @MainActor
    func testPngOnlyImageCapturedAsImage() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(makePNGData(), forType: .png)

        store.captureCurrentClipboard()

        XCTAssertEqual(store.items.first?.kind, .image)
    }

    // 端到端：捕获的图片要能作为缩略图重新读回（覆盖 persistImage 落盘 + image(for:) 读取）。
    @MainActor
    func testCapturedImageCanBeReadBack() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(makeTIFFData(), forType: .tiff)

        store.captureCurrentClipboard()

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertNotNil(store.image(for: item))
    }

    @MainActor
    func testImageOnlyCapturedAsImage() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(makeTIFFData(), forType: .tiff)

        store.captureCurrentClipboard()

        XCTAssertEqual(store.items.first?.kind, .image)
    }

    @MainActor
    func testImageWithURLTextStaysImage() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(makeTIFFData(), forType: .tiff)
        pasteboard.setString("https://example.com/a.png", forType: .string)

        store.captureCurrentClipboard()

        XCTAssertEqual(store.items.first?.kind, .image)
    }

    @MainActor
    func testRecentItemsWithoutLimitReturnsAll() throws {
        let items = (0..<25).map { ClipboardItem(kind: .text, text: "note-\($0)") }
        let store = try makeStore(with: items)

        XCTAssertEqual(store.recentItems(matching: "").count, 25)
    }

    // 中文输入法把候选词「上屏」时，会把已合成的文本写入 NSTextField 的 stringValue 并触发
    // controlTextDidChange。本测试验证我们的搜索框协调器会把这段中文正确路由到 query 并据此过滤
    // ——这是我们代码负责的部分；输入法合成本身由系统 NSTextField 负责（旧代码绕过了它才打不出中文）。
    @MainActor
    func testSearchFieldCommitRoutesChineseTextToQuery() throws {
        let store = try makeStore(with: [
            ClipboardItem(kind: .text, text: "你好世界"),
            ClipboardItem(kind: .text, text: "unrelated english")
        ])
        let controller = QuickPanelController(store: store)
        let searchField = QuickSearchField(
            text: Binding(get: { controller.query }, set: { controller.query = $0 }),
            placeholder: "",
            onMoveUp: {}, onMoveDown: {}, onSubmit: { _ in }, onCancel: {}
        )
        let coordinator = searchField.makeCoordinator()

        let nsField = NSTextField()
        nsField.stringValue = "你好"
        coordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: nsField)
        )

        XCTAssertEqual(controller.query, "你好")
        XCTAssertEqual(controller.visibleItems.map(\.text), ["你好世界"])
    }

    func testFunctionModifierDisplay() {
        let shortcut = HotKey(
            keyCode: 9,
            modifiers: UInt32(kEventKeyModifierFnMask),
            keyLabel: "V"
        )
        XCTAssertEqual(shortcut.displayName, "fnV")
    }

    func testReadableURLTitle() {
        let item = ClipboardItem(kind: .link, text: "https://www.example.com/docs/install")
        XCTAssertEqual(item.title, "example.com / docs/install")
    }

    @MainActor
    func testRecentItemsSearchesTitleAndText() throws {
        let store = try makeStore(with: [
            ClipboardItem(kind: .link, text: "https://www.example.com/docs/install"),
            ClipboardItem(kind: .text, text: "ordinary note")
        ])

        XCTAssertEqual(store.recentItems(matching: "docs", limit: 10).count, 1)
        XCTAssertEqual(store.recentItems(matching: "ordinary", limit: 10).count, 1)
    }

    @MainActor
    func testDefaultRetentionKeepsOnlyRecentRegularItems() throws {
        let old = Date(timeIntervalSinceNow: -60 * 60 * 25)
        let fresh = Date()
        let favorite = ClipboardItem(kind: .text, text: "kept favorite", createdAt: old, isFavorite: true)
        let oldRegular = ClipboardItem(kind: .text, text: "dropped regular", createdAt: old)
        let freshRegular = ClipboardItem(kind: .text, text: "kept regular", createdAt: fresh)
        let store = try makeStore(with: [favorite, oldRegular, freshRegular])

        XCTAssertEqual(Set(store.items.map(\.text)), ["kept favorite", "kept regular"])
    }

    @MainActor
    func testRetentionCanBeOverriddenByKind() throws {
        let old = Date(timeIntervalSinceNow: -60 * 60 * 25)
        let text = ClipboardItem(kind: .text, text: "expired text", createdAt: old)
        let image = ClipboardItem(kind: .image, text: "kept image", createdAt: old)
        let policy = ClipboardRetentionPolicy(
            maximumItems: 10,
            unifiedHours: 24,
            perKindHours: [.image: 48]
        )
        let store = try makeStore(with: [text, image], retentionPolicy: policy)

        XCTAssertEqual(store.items.map(\.text), ["kept image"])
    }

    func testRetentionPolicyPersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let policy = ClipboardRetentionPolicy(
            maximumItems: 300,
            unifiedHours: 12,
            perKindHours: [.text: 6, .image: 72]
        )

        policy.save(to: defaults)

        XCTAssertEqual(ClipboardRetentionPolicy.load(from: defaults), policy)
    }

    @MainActor
    private func makeStore(
        with items: [ClipboardItem],
        retentionPolicy: ClipboardRetentionPolicy = .standard
    ) throws -> ClipboardStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("history.json")
        let data = try JSONEncoder().encode(items)
        try data.write(to: storageURL)
        return ClipboardStore(
            pasteboard: NSPasteboard.withUniqueName(),
            storageURL: storageURL,
            startsMonitoring: false,
            retentionPolicy: retentionPolicy
        )
    }

    @MainActor
    private func makeEmptyStore(pasteboard: NSPasteboard) throws -> ClipboardStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("history.json")
        return ClipboardStore(
            pasteboard: pasteboard,
            storageURL: storageURL,
            startsMonitoring: false
        )
    }

    private func makeTIFFData() -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return image.tiffRepresentation ?? Data()
    }

    private func makePNGData() -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}
