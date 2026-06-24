import AppKit
import Combine
import CryptoKit
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
    private let imagesDirectory: URL
    private let maximumItems = 500

    init(pasteboard: NSPasteboard = .general, storageURL: URL? = nil, startsMonitoring: Bool = true) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.imagesDirectory = (storageURL ?? Self.defaultStorageURL)
            .deletingLastPathComponent()
            .appendingPathComponent("images", isDirectory: true)
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

        if let data = pasteboard.data(forType: .tiff), let item = persistImage(data) {
            insert(item)
            return
        }

        if let value = pasteboard.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !SensitiveContentDetector.shouldIgnore(value) else { return }
            insert(ClipboardItem(kind: value.detectedClipKind, text: value))
            return
        }

    }

    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .image:
            guard let image = image(for: item) else { return }
            pasteboard.writeObjects([image])
        case .file:
            pasteboard.writeObjects([URL(fileURLWithPath: item.text) as NSURL])
        case .text, .link:
            pasteboard.setString(item.text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let filename = item.imageFilename else { return nil }
        return NSImage(contentsOf: imagesDirectory.appendingPathComponent(filename))
    }

    func toggleFavorite(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        sortAndSave()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        removeImageIfUnused(item.imageFilename)
        save()
    }

    func clearUnpinned() {
        let removedImages = items.filter { !$0.isFavorite }.compactMap(\.imageFilename)
        items.removeAll { !$0.isFavorite }
        removedImages.forEach(removeImageIfUnused)
        save()
    }

    private func insert(_ item: ClipboardItem) {
        if let duplicate = items.firstIndex(where: { existing in
            guard existing.kind == item.kind else { return false }
            if item.kind == .image { return existing.imageFilename == item.imageFilename }
            return existing.text == item.text
        }) {
            var refreshed = items.remove(at: duplicate)
            refreshed.createdAt = .now
            items.insert(refreshed, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        if items.count > maximumItems {
            let removed = items.dropFirst(maximumItems).compactMap(\.imageFilename)
            items = Array(items.prefix(maximumItems))
            removed.forEach(removeImageIfUnused)
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

    private func persistImage(_ sourceData: Data) -> ClipboardItem? {
        guard let image = NSImage(data: sourceData),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let filename = "\(digest).png"
        let url = imagesDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try png.write(to: url, options: .atomic)
            }
        } catch {
            return nil
        }
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        return ClipboardItem(
            kind: .image,
            text: "图片 · \(width) × \(height)",
            imageFilename: filename
        )
    }

    private func removeImageIfUnused(_ filename: String?) {
        guard let filename, !items.contains(where: { $0.imageFilename == filename }) else { return }
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(filename))
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
