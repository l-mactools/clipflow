import AppKit
import Combine
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var isMonitoring = true
    @Published var selectedKind: ClipKind?
    @Published var searchText = ""

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let storageURL: URL
    private let maximumItems = 500

    init(pasteboard: NSPasteboard = .general, storageURL: URL? = nil, startsMonitoring: Bool = true) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.storageURL = storageURL ?? Self.defaultStorageURL
        load()
        if startsMonitoring { startMonitoring() }
    }

    deinit { timer?.invalidate() }

    var filteredItems: [ClipboardItem] {
        items.filter { item in
            let matchesKind = selectedKind == nil || item.kind == selectedKind
            let matchesSearch = searchText.isEmpty || item.text.localizedCaseInsensitiveContains(searchText)
            return matchesKind && matchesSearch
        }
    }

    var recentItems: [ClipboardItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    func captureCurrentClipboard() {
        guard isMonitoring, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], let first = urls.first, first.isFileURL {
            insert(ClipboardItem(kind: .file, text: first.path))
            return
        }

        if let value = pasteboard.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !SensitiveContentDetector.shouldIgnore(value) else { return }
            insert(ClipboardItem(kind: value.detectedClipKind, text: value))
            return
        }

        if pasteboard.data(forType: .tiff) != nil {
            insert(ClipboardItem(kind: .image, text: "剪贴板图片"))
        }
    }

    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func toggleFavorite(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        sortAndSave()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.isFavorite }
        save()
    }

    private func insert(_ item: ClipboardItem) {
        if let duplicate = items.firstIndex(where: { $0.kind == item.kind && $0.text == item.text }) {
            var refreshed = items.remove(at: duplicate)
            refreshed.createdAt = .now
            items.insert(refreshed, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        if items.count > maximumItems {
            items = Array(items.prefix(maximumItems))
        }
        sortAndSave()
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureCurrentClipboard() }
        }
    }

    private func sortAndSave() {
        items.sort {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.createdAt > $1.createdAt
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }

    private static var defaultStorageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipFlow", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}

enum SensitiveContentDetector {
    private static let patterns = [
        #"(?i)bearer\s+[a-z0-9._-]{16,}"#,
        #"(?i)(api[_-]?key|secret|token|password)\s*[:=]\s*\S+"#,
        #"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"#
    ]

    static func shouldIgnore(_ value: String) -> Bool {
        patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }
}
