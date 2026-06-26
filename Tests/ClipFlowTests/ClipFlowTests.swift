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

    func testBasketEntryInitDefaults() {
        let item = ClipboardItem(kind: .text, text: "hello")
        let entry = BasketEntry(snapshot: item)
        XCTAssertFalse(entry.isPinned)
        XCTAssertEqual(entry.snapshot.text, "hello")
    }

    func testBasketEntryCodableRoundtrip() throws {
        let item = ClipboardItem(kind: .link, text: "https://example.com")
        let entry = BasketEntry(snapshot: item, isPinned: true)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(BasketEntry.self, from: data)
        XCTAssertEqual(decoded.snapshot.text, "https://example.com")
        XCTAssertTrue(decoded.isPinned)
        XCTAssertEqual(decoded.id, entry.id)
    }

    func testBasketMergeFormatAllCasesCount() {
        XCTAssertEqual(BasketMergeFormat.allCases.count, 4)
    }

    @MainActor
    func testAddToBasketAddsEntry() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        let item = ClipboardItem(kind: .text, text: "hello")
        store.addToBasket(item)
        XCTAssertEqual(store.basket.count, 1)
        XCTAssertEqual(store.basket[0].snapshot.text, "hello")
    }

    @MainActor
    func testAddToBasketDeduplicates() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        let item = ClipboardItem(kind: .text, text: "dup")
        store.addToBasket(item)
        store.addToBasket(item)
        XCTAssertEqual(store.basket.count, 1)
    }

    @MainActor
    func testRemoveFromBasket() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        let item = ClipboardItem(kind: .text, text: "bye")
        store.addToBasket(item)
        let entry = try XCTUnwrap(store.basket.first)
        store.removeFromBasket(entry)
        XCTAssertTrue(store.basket.isEmpty)
    }

    @MainActor
    func testToggleBasketPin() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        store.addToBasket(ClipboardItem(kind: .text, text: "pin me"))
        let entry = try XCTUnwrap(store.basket.first)
        XCTAssertFalse(entry.isPinned)
        store.toggleBasketPin(entry)
        XCTAssertTrue(store.basket[0].isPinned)
        store.toggleBasketPin(store.basket[0])
        XCTAssertFalse(store.basket[0].isPinned)
    }

    @MainActor
    func testClearBasketKeepsPinned() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        store.addToBasket(ClipboardItem(kind: .text, text: "a"))
        store.addToBasket(ClipboardItem(kind: .text, text: "b"))
        store.toggleBasketPin(store.basket[0])   // pin "a" (index 0 = first added)
        store.clearBasket()
        XCTAssertEqual(store.basket.count, 1)
        XCTAssertTrue(store.basket[0].isPinned)
        XCTAssertEqual(store.basket[0].snapshot.text, "a")
    }

    @MainActor
    func testPopNextFromBasketReturnsFIFO() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        store.addToBasket(ClipboardItem(kind: .text, text: "first"))
        store.addToBasket(ClipboardItem(kind: .text, text: "second"))
        let popped = store.popNextFromBasket()
        XCTAssertEqual(popped?.text, "first")
        XCTAssertEqual(store.basket.count, 1)
        XCTAssertEqual(store.basket[0].snapshot.text, "second")
    }

    @MainActor
    func testPopNextFromBasketSkipsPinned() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        store.addToBasket(ClipboardItem(kind: .text, text: "pinned"))
        store.addToBasket(ClipboardItem(kind: .text, text: "free"))
        store.toggleBasketPin(store.basket[0])   // pin "pinned"
        let popped = store.popNextFromBasket()
        XCTAssertEqual(popped?.text, "free")
        XCTAssertEqual(store.basket.count, 1)
    }

    @MainActor
    func testPopNextFromBasketReturnsNilWhenAllPinned() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        store.addToBasket(ClipboardItem(kind: .text, text: "only"))
        store.toggleBasketPin(store.basket[0])
        let popped = store.popNextFromBasket()
        XCTAssertNil(popped)
        XCTAssertEqual(store.basket.count, 1)
    }

    @MainActor
    func testMergedBasketTextAllFormats() throws {
        let store = try makeEmptyStore(pasteboard: .withUniqueName())
        store.addToBasket(ClipboardItem(kind: .text, text: "alpha"))
        store.addToBasket(ClipboardItem(kind: .text, text: "beta"))
        // basket: ["alpha", "beta"] (FIFO order)
        XCTAssertEqual(
            store.mergedBasketText(format: .plainText),
            "alpha\n\nbeta"
        )
        XCTAssertEqual(
            store.mergedBasketText(format: .markdownList),
            "- alpha\n- beta"
        )
        XCTAssertEqual(
            store.mergedBasketText(format: .blockquote),
            "> alpha\n\n> beta"
        )
        XCTAssertEqual(
            store.mergedBasketText(format: .promptContext),
            "[1]\nalpha\n\n[2]\nbeta"
        )
    }

    @MainActor
    func testBasketPersistsAcrossInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("history.json")

        let store1 = ClipboardStore(
            pasteboard: .withUniqueName(), storageURL: storageURL, startsMonitoring: false
        )
        store1.addToBasket(ClipboardItem(kind: .text, text: "persisted"))

        let store2 = ClipboardStore(
            pasteboard: .withUniqueName(), storageURL: storageURL, startsMonitoring: false
        )
        XCTAssertEqual(store2.basket.count, 1)
        XCTAssertEqual(store2.basket.first?.snapshot.text, "persisted")
    }

    // MARK: - v0.4 数据类型

    func testSourceAppCodableRoundtrip() throws {
        let app = SourceApp(bundleID: "com.example.app", name: "Example")
        let data = try JSONEncoder().encode(app)
        let decoded = try JSONDecoder().decode(SourceApp.self, from: data)
        XCTAssertEqual(decoded.bundleID, "com.example.app")
        XCTAssertEqual(decoded.name, "Example")
    }

    func testClipboardItemDecodesWithoutSourceApp() throws {
        // 旧格式 JSON 没有 sourceApp 字段，应解码为 nil，不崩溃
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"文本","text":"hello",
         "createdAt":0,"isFavorite":false}
        """
        let item = try JSONDecoder().decode(ClipboardItem.self, from: Data(json.utf8))
        XCTAssertNil(item.sourceApp)
        XCTAssertEqual(item.text, "hello")
    }

    func testTimeRangeTodayContainsNow() {
        let now = Date()          // 先捕获，确保在 range.upperBound 之前
        XCTAssertTrue(TimeRange.today.range.contains(now))
    }

    func testTimeRangeYesterdayContainsYesterdayDate() {
        let yesterday = Calendar.current.date(byAdding: .hour, value: -25, to: Date.now)!
        XCTAssertTrue(TimeRange.yesterday.range.contains(yesterday))
        XCTAssertFalse(TimeRange.today.range.contains(yesterday))
    }

    func testTimeRangeLast7DaysContainsSixDaysAgo() {
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date.now)!
        XCTAssertTrue(TimeRange.last7Days.range.contains(sixDaysAgo))
    }

    // MARK: - v0.4 ClipboardStore 过滤与来源追踪

    @MainActor
    func testFilteredItemsBySourceApp() throws {
        let pb = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pb)
        let appA = SourceApp(bundleID: "com.a", name: "AppA")
        let appB = SourceApp(bundleID: "com.b", name: "AppB")

        store.lastActiveApp = appA
        pb.clearContents(); pb.setString("from A", forType: .string)
        store.captureCurrentClipboard()

        store.lastActiveApp = appB
        pb.clearContents(); pb.setString("from B", forType: .string)
        store.captureCurrentClipboard()

        store.selectedSourceApp = "com.a"
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems.first?.text, "from A")
        store.selectedSourceApp = nil
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    @MainActor
    func testFilteredItemsByTimeRangeToday() throws {
        let pb = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pb)
        pb.clearContents(); pb.setString("today item", forType: .string)
        store.captureCurrentClipboard()
        // item.createdAt = .now，在 .today 范围内，不在 .yesterday 范围内
        store.selectedTimeRange = .today
        XCTAssertEqual(store.filteredItems.count, 1)
        store.selectedTimeRange = .yesterday
        XCTAssertEqual(store.filteredItems.count, 0)
    }

    @MainActor
    func testUniqueSourceAppsSortedByCount() throws {
        let pb = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pb)
        let appA = SourceApp(bundleID: "com.a", name: "AppA")
        let appB = SourceApp(bundleID: "com.b", name: "AppB")

        store.lastActiveApp = appA
        pb.clearContents(); pb.setString("a1", forType: .string)
        store.captureCurrentClipboard()

        store.lastActiveApp = appB
        pb.clearContents(); pb.setString("b1", forType: .string)
        store.captureCurrentClipboard()
        pb.clearContents(); pb.setString("b2", forType: .string)
        store.captureCurrentClipboard()

        let result = store.uniqueSourceApps
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].app.bundleID, "com.b")  // count=2，排在前
        XCTAssertEqual(result[0].count, 2)
        XCTAssertEqual(result[1].app.bundleID, "com.a")
        XCTAssertEqual(result[1].count, 1)
    }

    @MainActor
    func testCaptureRecordsLastActiveApp() throws {
        let pb = NSPasteboard.withUniqueName()
        let store = try makeEmptyStore(pasteboard: pb)
        store.lastActiveApp = SourceApp(bundleID: "com.test.editor", name: "Editor")
        pb.clearContents(); pb.setString("hello from editor", forType: .string)
        store.captureCurrentClipboard()
        XCTAssertEqual(store.items.first?.sourceApp?.bundleID, "com.test.editor")
        XCTAssertEqual(store.items.first?.sourceApp?.name, "Editor")
    }
}
