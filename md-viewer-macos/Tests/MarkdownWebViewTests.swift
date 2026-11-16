import XCTest
@testable import MDGitView

final class MarkdownWebViewTests: XCTestCase {
    func testPreviewUsesCustomSchemeWithoutWritingIntoDocumentFolder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let handler = MarkdownResourceSchemeHandler()
        let registered = try XCTUnwrap(handler.register(
            html: "<html><head></head><body>Preview</body></html>",
            baseDirectory: directory,
            allowedRootDirectory: directory
        ))
        defer { handler.unregister(identifier: registered.identifier) }

        XCTAssertEqual(registered.url.scheme, MarkdownResourceSchemeHandler.scheme)
        XCTAssertTrue(handler.isDocumentURL(registered.url, identifier: registered.identifier))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(".mdgitview-preview.html").path
        ))
    }

    func testLocalResourcesAreLimitedToAllowedRoot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let allowedRoot = directory.appendingPathComponent("repo", isDirectory: true)
        let baseDirectory = allowedRoot.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let handler = MarkdownResourceSchemeHandler()
        let registered = try XCTUnwrap(handler.register(
            html: "<html><head></head><body>Preview</body></html>",
            baseDirectory: baseDirectory,
            allowedRootDirectory: allowedRoot
        ))
        defer { handler.unregister(identifier: registered.identifier) }

        let inRootURL = try XCTUnwrap(URL(string:
            "mdgitview://\(registered.identifier)/__root__/README.md"
        ))
        let outsideRootURL = try XCTUnwrap(URL(string:
            "mdgitview://\(registered.identifier)/outside.txt"
        ))

        XCTAssertEqual(
            handler.localFileURL(for: inRootURL)?.path,
            allowedRoot.appendingPathComponent("README.md").path
        )
        XCTAssertNil(handler.localFileURL(for: outsideRootURL))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
