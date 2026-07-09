import XCTest
import WebKit
@testable import MDGitView

@MainActor
final class MarkdownWebViewTests: XCTestCase {
    final class SpyWebView: WKWebView {
        private(set) var lastHTMLString: String?
        private(set) var lastBaseURL: URL?
        private(set) var loadedFileURL: URL?
        private(set) var allowedReadAccessURL: URL?

        init() {
            super.init(frame: .zero, configuration: WKWebViewConfiguration())
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
            lastHTMLString = string
            lastBaseURL = baseURL
            return nil
        }

        override func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
            loadedFileURL = URL
            allowedReadAccessURL = readAccessURL
            return nil
        }
    }

    func testPreparingTempFileTwiceKeepsLatestHTMLOnDisk() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let markdownView = MarkdownWebView(
            htmlDocument: "",
            baseURL: nil,
            allowedRootURL: nil,
            currentFileURL: nil,
            navigateToAnchor: nil,
            onOpenMarkdownLink: { _ in },
            onOpenExternalLink: { _ in },
            onDidNavigateToAnchor: {}
        )
        let coordinator = markdownView.makeCoordinator()

        let firstURL = try coordinator.prepareTempFile(html: "<p>first</p>", in: rootDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        let secondURL = try coordinator.prepareTempFile(html: "<p>second</p>", in: rootDirectory)
        XCTAssertEqual(secondURL, firstURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "<p>second</p>")
    }

    func testFailedFileURLLoadFallsBackToHTMLString() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        var folderAccessRequests = 0
        let html = "<p>visible text</p>"
        let markdownView = MarkdownWebView(
            htmlDocument: html,
            baseURL: rootDirectory,
            allowedRootURL: rootDirectory.deletingLastPathComponent(),
            currentFileURL: nil,
            navigateToAnchor: nil,
            onOpenMarkdownLink: { _ in },
            onOpenExternalLink: { _ in },
            onDidNavigateToAnchor: {},
            onRequestFolderAccess: {
                folderAccessRequests += 1
            }
        )
        let coordinator = markdownView.makeCoordinator()
        let webView = SpyWebView()

        XCTAssertTrue(coordinator.loadViaFileURL(
            html: html,
            baseURL: rootDirectory,
            allowedRootURL: rootDirectory.deletingLastPathComponent(),
            in: webView
        ))
        XCTAssertNotNil(webView.loadedFileURL)

        coordinator.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNoPermissionsToReadFile)
        )

        XCTAssertEqual(webView.lastHTMLString, html)
        XCTAssertEqual(webView.lastBaseURL, rootDirectory)
        XCTAssertEqual(folderAccessRequests, 1)
    }

    func testPostLoadFailureDoesNotReplaceVisibleFileDocument() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        var folderAccessRequests = 0
        let html = "<p>visible text</p>"
        let markdownView = MarkdownWebView(
            htmlDocument: html,
            baseURL: rootDirectory,
            allowedRootURL: rootDirectory.deletingLastPathComponent(),
            currentFileURL: nil,
            navigateToAnchor: nil,
            onOpenMarkdownLink: { _ in },
            onOpenExternalLink: { _ in },
            onDidNavigateToAnchor: {},
            onRequestFolderAccess: {
                folderAccessRequests += 1
            }
        )
        let coordinator = markdownView.makeCoordinator()
        let webView = SpyWebView()

        XCTAssertTrue(coordinator.loadViaFileURL(
            html: html,
            baseURL: rootDirectory,
            allowedRootURL: rootDirectory.deletingLastPathComponent(),
            in: webView
        ))

        coordinator.webView(webView, didFinish: nil)
        coordinator.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNoPermissionsToReadFile)
        )

        XCTAssertNil(webView.lastHTMLString)
        XCTAssertEqual(folderAccessRequests, 0)
    }

    func testCancelledProvisionalNavigationDoesNotFallback() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        var folderAccessRequests = 0
        let markdownView = MarkdownWebView(
            htmlDocument: "<p>visible text</p>",
            baseURL: rootDirectory,
            allowedRootURL: rootDirectory.deletingLastPathComponent(),
            currentFileURL: nil,
            navigateToAnchor: nil,
            onOpenMarkdownLink: { _ in },
            onOpenExternalLink: { _ in },
            onDidNavigateToAnchor: {},
            onRequestFolderAccess: {
                folderAccessRequests += 1
            }
        )
        let coordinator = markdownView.makeCoordinator()
        let webView = SpyWebView()

        XCTAssertTrue(coordinator.loadViaFileURL(
            html: "<p>visible text</p>",
            baseURL: rootDirectory,
            allowedRootURL: rootDirectory.deletingLastPathComponent(),
            in: webView
        ))

        coordinator.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )

        XCTAssertNil(webView.lastHTMLString)
        XCTAssertEqual(folderAccessRequests, 0)
    }
}
