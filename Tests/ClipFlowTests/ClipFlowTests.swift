import XCTest
import Carbon
@testable import ClipFlow

final class ClipFlowTests: XCTestCase {
    func testURLDetection() {
        XCTAssertEqual("https://example.com/path".detectedClipKind, .link)
        XCTAssertEqual("ordinary text".detectedClipKind, .text)
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
}
