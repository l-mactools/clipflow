import XCTest
import Carbon
@testable import ClipFlow

final class ClipFlowTests: XCTestCase {
    func testURLDetection() {
        XCTAssertEqual("https://example.com/path".detectedClipKind, .link)
        XCTAssertEqual("ordinary text".detectedClipKind, .text)
    }

    func testSensitiveContentDetection() {
        XCTAssertTrue(SensitiveContentDetector.shouldIgnore("Authorization: Bearer abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(SensitiveContentDetector.shouldIgnore("API_KEY=super-secret-value"))
        XCTAssertFalse(SensitiveContentDetector.shouldIgnore("这是普通的剪贴板内容"))
    }

    func testFunctionModifierDisplay() {
        let shortcut = HotKey(
            keyCode: 9,
            modifiers: UInt32(kEventKeyModifierFnMask),
            keyLabel: "V"
        )
        XCTAssertEqual(shortcut.displayName, "fnV")
    }
}
