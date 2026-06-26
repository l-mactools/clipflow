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
    @Published private(set) var basket: [BasketEntry] = []
    @Published var retentionPolicy: ClipboardRetentionPolicy {
        didSet {
            retentionPolicy.save(to: defaults)
            enforceRetentionPolicy()
            sortAndSave()
        }
    }

    private let pasteboard: NSPasteboard
    private let defaults: UserDefaults
    private var lastChangeCount: Int
    private var timer: Timer?
    private let storageURL: URL
    private let imagesDirectory: URL
    private let basketURL: URL

    init(
        pasteboard: NSPasteboard = .general,
        storageURL: URL? = nil,
        startsMonitoring: Bool = true,
        retentionPolicy: ClipboardRetentionPolicy? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.lastChangeCount = pasteboard.changeCount
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.imagesDirectory = (storageURL ?? Self.defaultStorageURL)
            .deletingLastPathComponent()
            .appendingPathComponent("images", isDirectory: true)
        self.basketURL = (storageURL ?? Self.defaultStorageURL)
            .deletingLastPathComponent()
            .appendingPathComponent("basket.json")
        self.retentionPolicy = retentionPolicy ?? ClipboardRetentionPolicy.load(from: defaults)
        load()
        loadBasket()
        if startsMonitoring { startMonitoring() }
    }

    deinit { timer?.invalidate() }

    var filteredItems: [ClipboardItem] {
        items.filter { item in
            let matchesKind = selectedKind == nil || item.kind == selectedKind
            let matchesSearch = searchText.isEmpty || item.matches(searchText)
            return matchesKind && matchesSearch
        }
    }

    var recentItems: [ClipboardItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    func recentItems(matching query: String, limit: Int? = nil) -> [ClipboardItem] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = value.isEmpty ? recentItems : recentItems.filter { $0.matches(value) }
        guard let limit else { return candidates }
        return Array(candidates.prefix(limit))
    }

    func captureCurrentClipboard() {
        guard isMonitoring, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // 文件 URL（如 Finder 拷贝图片文件）→ 记录为文件路径，而非图片内容
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], let first = urls.first, first.isFileURL {
            insert(ClipboardItem(kind: .file, text: first.path))
            return
        }

        // 真正的图片位图数据 → 图片（截图、从浏览器/预览复制的图片内容等）。
        // 注意：「复制图片内容」与「复制图片路径」是不同操作——前者剪贴板含 tiff 位图，应存图片；
        // 后者是纯文本路径（无 tiff），会落到下面的文本分支。某些截图工具复制图片时会附带保存
        // 路径文本，但只要存在 tiff 就应按图片处理。
        if let data = pasteboard.data(forType: .tiff), let item = persistImage(data) {
            insert(item)
            return
        }

        // 文本（含路径文本、链接）
        if let value = pasteboard.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    func updateUnifiedRetention(hours: Int) {
        var policy = retentionPolicy
        policy.unifiedHours = hours
        retentionPolicy = policy
    }

    func updateKindRetention(_ kind: ClipKind, hours: Int?) {
        var policy = retentionPolicy
        policy.perKindHours[kind] = hours
        retentionPolicy = policy
    }

    func useUnifiedRetentionForAllKinds() {
        var policy = retentionPolicy
        policy.perKindHours.removeAll()
        retentionPolicy = policy
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
        enforceRetentionPolicy()
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
        enforceRetentionPolicy()
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

    private func loadBasket() {
        guard let data = try? Data(contentsOf: basketURL),
              let decoded = try? JSONDecoder().decode([BasketEntry].self, from: data)
        else { return }
        basket = decoded
    }

    private func saveBasket() {
        guard let data = try? JSONEncoder().encode(basket) else { return }
        try? FileManager.default.createDirectory(
            at: basketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: basketURL, options: .atomic)
    }

    private func enforceRetentionPolicy(now: Date = .now) {
        let before = items
        items = items.filter { item in
            guard !item.isFavorite else { return true }
            let maxAge = retentionPolicy.maximumAge(for: item.kind)
            return now.timeIntervalSince(item.createdAt) <= maxAge
        }

        let favoriteItems = items.filter(\.isFavorite)
        let regularItems = items
            .filter { !$0.isFavorite }
            .sorted { $0.createdAt > $1.createdAt }
        let regularLimit = max(retentionPolicy.maximumItems - favoriteItems.count, 0)
        items = favoriteItems + Array(regularItems.prefix(regularLimit))

        let removedImages = before
            .filter { removed in !items.contains(where: { $0.id == removed.id }) }
            .compactMap(\.imageFilename)
        removedImages.forEach(removeImageIfUnused)
    }

    private static var defaultStorageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipFlow", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    // MARK: - Basket

    func addToBasket(_ item: ClipboardItem) {
        guard !basket.contains(where: { $0.snapshot.id == item.id }) else { return }
        basket.append(BasketEntry(snapshot: item))
        saveBasket()
    }

    func removeFromBasket(_ entry: BasketEntry) {
        basket.removeAll { $0.id == entry.id }
        saveBasket()
    }

    func moveBasket(from source: IndexSet, to destination: Int) {
        basket.move(fromOffsets: source, toOffset: destination)
        saveBasket()
    }

    func toggleBasketPin(_ entry: BasketEntry) {
        guard let index = basket.firstIndex(where: { $0.id == entry.id }) else { return }
        basket[index].isPinned.toggle()
        saveBasket()
    }

    func clearBasket() {
        basket.removeAll { !$0.isPinned }
        saveBasket()
    }

    func mergedBasketText(format: BasketMergeFormat) -> String {
        let texts = basket.map { $0.snapshot.text }
        switch format {
        case .plainText:
            return texts.joined(separator: "\n\n")
        case .markdownList:
            return texts.map { "- \($0)" }.joined(separator: "\n")
        case .blockquote:
            return texts.map { "> \($0)" }.joined(separator: "\n\n")
        case .promptContext:
            return texts.enumerated()
                .map { "[\($0.offset + 1)]\n\($0.element)" }
                .joined(separator: "\n\n")
        }
    }

    func copyMergedBasket(format: BasketMergeFormat) {
        let text = mergedBasketText(format: format)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    @discardableResult
    func popNextFromBasket() -> ClipboardItem? {
        guard let index = basket.firstIndex(where: { !$0.isPinned }) else { return nil }
        let entry = basket.remove(at: index)
        saveBasket()
        return entry.snapshot
    }
}

struct ClipboardRetentionPolicy: Codable, Equatable {
    var maximumItems: Int
    var unifiedHours: Int
    var perKindHours: [ClipKind: Int]

    func maximumAge(for kind: ClipKind) -> TimeInterval {
        TimeInterval((perKindHours[kind] ?? unifiedHours) * 60 * 60)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    static func load(from defaults: UserDefaults) -> ClipboardRetentionPolicy {
        guard let data = defaults.data(forKey: defaultsKey),
              let policy = try? JSONDecoder().decode(ClipboardRetentionPolicy.self, from: data) else {
            return .standard
        }
        return policy
    }

    static let standard = ClipboardRetentionPolicy(maximumItems: 500, unifiedHours: 24, perKindHours: [:])
    private static let defaultsKey = "retentionPolicy"
}

private extension ClipboardItem {
    func matches(_ query: String) -> Bool {
        searchableText.localizedCaseInsensitiveContains(query)
    }
}
