import AppKit
import XCTest
@testable import MDGitView

@MainActor
final class AppDelegateTests: XCTestCase {
    func testFileOpenedBeforeHandlerIsDeliveredWhenHandlerIsInstalled() {
        let delegate = AppDelegate()
        let fileURL = URL(fileURLWithPath: "/tmp/example.md")
        var openedURLs: [URL] = []

        delegate.application(NSApplication.shared, open: [fileURL])
        delegate.openFileHandler = { openedURLs.append($0) }

        XCTAssertEqual(openedURLs, [fileURL])
    }

    func testNonFileURLsAreIgnored() {
        let delegate = AppDelegate()
        var openedURLs: [URL] = []
        delegate.openFileHandler = { openedURLs.append($0) }

        delegate.application(
            NSApplication.shared,
            open: [URL(string: "https://example.com/readme.md")!]
        )

        XCTAssertTrue(openedURLs.isEmpty)
    }

    func testDuplicateStartupFileEventsAreQueuedOnlyOnce() {
        let delegate = AppDelegate()
        let fileURL = URL(fileURLWithPath: "/tmp/example.md")
        var openedURLs: [URL] = []

        delegate.application(NSApplication.shared, open: [fileURL, fileURL])
        delegate.openFileHandler = { openedURLs.append($0) }

        XCTAssertEqual(openedURLs, [fileURL])
    }
}
