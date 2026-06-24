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
        return compact.isEmpty ? kind.rawValue : compact
    }
}

extension String {
    var detectedClipKind: ClipKind {
        guard let url = URL(string: self), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            return .text
        }
        return .link
    }
}
