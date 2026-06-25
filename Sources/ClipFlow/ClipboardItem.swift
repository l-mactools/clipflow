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

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: ClipKind
    var text: String
    var createdAt: Date
    var isFavorite: Bool
    var imageFilename: String?

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        text: String,
        createdAt: Date = .now,
        isFavorite: Bool = false,
        imageFilename: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.imageFilename = imageFilename
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
