import AppKit

enum Brand {
    static let appName = "拾笺"

    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "JianAppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.module.url(forResource: "JianAppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: appName) ?? NSImage()
    }()

    static func applyApplicationIcon() {
        NSApplication.shared.applicationIconImage = icon
    }
}
