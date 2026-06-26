import AppKit
import Foundation

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text = "文本"
    case link = "链接"
    case image = "图片"
    case file = "文件"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

struct SourceApp: Codable, Hashable {
    let bundleID: String
    let name: String
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today      = "今天"
    case yesterday  = "昨天"
    case last7Days  = "近 7 天"

    var id: Self { self }

    var range: ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date.now
        switch self {
        case .today:
            return cal.startOfDay(for: now)...now
        case .yesterday:
            let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: now)!)
            let end   = cal.startOfDay(for: now)
            return start...end
        case .last7Days:
            return cal.date(byAdding: .day, value: -7, to: now)!...now
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: ClipKind
    var text: String
    var createdAt: Date
    var isFavorite: Bool
    var imageFilename: String?
    var sourceApp: SourceApp?

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        text: String,
        createdAt: Date = .now,
        isFavorite: Bool = false,
        imageFilename: String? = nil,
        sourceApp: SourceApp? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.imageFilename = imageFilename
        self.sourceApp = sourceApp
    }

    var title: String {
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        if kind == .link, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url.readableTitle
        }
        return compact.isEmpty ? kind.rawValue : compact
    }

    var searchableText: String {
        "\(title)\n\(text)"
    }
}

extension String {
    var detectedClipKind: ClipKind {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            return .text
        }
        return .link
    }
}

private extension URL {
    var readableTitle: String {
        let host = host?.replacingOccurrences(of: "www.", with: "") ?? absoluteString
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return host }
        return "\(host) / \(path)"
    }
}

struct BasketEntry: Identifiable, Codable {
    let id: UUID
    let snapshot: ClipboardItem
    var isPinned: Bool
    let addedAt: Date

    init(snapshot: ClipboardItem, isPinned: Bool = false) {
        self.id = UUID()
        self.snapshot = snapshot
        self.isPinned = isPinned
        self.addedAt = .now
    }
}

enum BasketMergeFormat: String, CaseIterable, Identifiable {
    case plainText     = "纯文本"
    case markdownList  = "Markdown 列表"
    case blockquote    = "引用块"
    case promptContext = "Prompt 上下文"

    var id: Self { self }
}
