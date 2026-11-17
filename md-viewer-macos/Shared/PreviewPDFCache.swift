import AppKit
import CryptoKit
import Darwin
import Foundation
import WebKit

enum PreviewPDFCache {
    static let appGroup = "8C2T254JY2.mdgitview.preview"
    private static let schema = "mdgitview-pdf-v1"
    private static let maxBytes = 250 * 1024 * 1024
    private static let maxAge: TimeInterval = 300

    struct Entry: Decodable, Encodable {
        let schema: String
        let sourceDigest: String
        let rendererVersion: String
        let createdAt: Date
    }

    static func pdfURL(for sourceURL: URL, sourceData: Data) -> URL? {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }
        let directory = root.appendingPathComponent("Library/Caches/MDGitView/PreviewPDF", isDirectory: true)
        let digest = SHA256.hash(data: Data(sourceURL.standardizedFileURL.path.utf8) + sourceData)
            .map { String(format: "%02x", $0) }.joined()
        let pdf = directory.appendingPathComponent("\(digest).pdf")
        let manifest = directory.appendingPathComponent("\(digest).json")
        guard let metadata = try? Data(contentsOf: manifest),
              let entry = try? JSONDecoder().decode(Entry.self, from: metadata),
              entry.schema == schema,
              entry.sourceDigest == sourceDigest(sourceData),
              entry.rendererVersion == rendererVersion,
              Date().timeIntervalSince(entry.createdAt) <= maxAge,
              FileManager.default.fileExists(atPath: pdf.path) else { return nil }
        return pdf
    }

    static func write(_ pdfData: Data, for sourceURL: URL, sourceData: Data) throws {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { throw CacheError.groupUnavailable }
        let directory = root.appendingPathComponent("Library/Caches/MDGitView/PreviewPDF", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(sourceURL.standardizedFileURL.path.utf8) + sourceData)
            .map { String(format: "%02x", $0) }.joined()
        let pdf = directory.appendingPathComponent("\(digest).pdf")
        let manifest = directory.appendingPathComponent("\(digest).json")
        let lockURL = directory.appendingPathComponent("cache.lock")
        let lockFD = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw CacheError.lockUnavailable }
        defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }
        guard flock(lockFD, LOCK_EX) == 0 else { throw CacheError.lockUnavailable }

        let existingPDFSize = (try? pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let existingManifestSize = (try? manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let currentSize = (try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]))
            .filter { $0.lastPathComponent != "cache.lock" }
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let replacementSize = pdfData.count + 256
        guard currentSize - existingPDFSize - existingManifestSize + replacementSize <= maxBytes else {
            throw CacheError.cacheFull
        }

        try pdfData.write(to: pdf, options: .atomic)
        let entry = Entry(
            schema: schema,
            sourceDigest: sourceDigest(sourceData),
            rendererVersion: rendererVersion,
            createdAt: Date()
        )
        try JSONEncoder().encode(entry).write(to: manifest, options: .atomic)
    }

    private static func sourceDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static var rendererVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    enum CacheError: LocalizedError {
        case groupUnavailable
        case lockUnavailable
        case cacheFull
        var errorDescription: String? {
            switch self {
            case .groupUnavailable: return "The shared Quick Look cache is unavailable."
            case .lockUnavailable: return "The shared Quick Look cache could not be locked."
            case .cacheFull: return "The shared Quick Look cache has reached its 250 MiB limit."
            }
        }
    }
}

@MainActor
final class PreviewPDFRenderer: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?
    private var window: NSWindow?
    private var handler: MarkdownResourceSchemeHandler?
    private var documentID: String?
    private var payload: RenderedPayload?
    private var pollingTask: Task<Void, Never>?

    func render(_ payload: RenderedPayload) async throws -> Data {
        self.payload = payload
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let handler = MarkdownResourceSchemeHandler()
            self.handler = handler
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.setURLSchemeHandler(handler, forURLScheme: MarkdownResourceSchemeHandler.scheme)
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 900), configuration: configuration)
            view.appearance = NSAppearance(named: .aqua)
            view.navigationDelegate = self
            webView = view
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            window.setFrameOrigin(NSPoint(x: -12000, y: -12000))
            window.orderFrontRegardless()
            self.window = window
            guard let registered = handler.register(
                html: payload.htmlDocument,
                baseDirectory: payload.baseURL,
                allowedRootDirectory: payload.allowedRootURL
            ) else {
                finish(.failure(MarkdownRenderServiceError.unreadableFile))
                return
            }
            documentID = registered.identifier
            view.load(URLRequest(url: registered.url))
            pollingTask = Task { [weak self] in
                for _ in 0..<150 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard let self, self.continuation != nil else { return }
                    if (try? await self.webView?.evaluateJavaScript("window.mdgitviewRenderReady === true && document.fonts.status === 'loaded'")) as? Bool == true {
                        await self.createPDF()
                        return
                    }
                }
                self?.finish(.failure(RenderError.timeout))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    private func createPDF() async {
        guard let webView else { return }
        do {
            _ = try await webView.evaluateJavaScript("document.querySelectorAll('.mermaid-control-layer').forEach(node => node.remove())")
            guard let height = try await webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") as? Double,
                  height > 0, height < 100_000 else { throw RenderError.invalidSize }
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 900, height: height)
            finish(.success(try await webView.pdf(configuration: config)))
        } catch { finish(.failure(error)) }
    }

    private func finish(_ result: Result<Data, Error>) {
        pollingTask?.cancel()
        handler?.unregister(identifier: documentID)
        window?.orderOut(nil)
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        handler = nil
        payload = nil
        let continuation = self.continuation
        self.continuation = nil
        switch result {
        case .success(let data): continuation?.resume(returning: data)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private enum RenderError: LocalizedError {
        case timeout, invalidSize
        var errorDescription: String? {
            switch self {
            case .timeout: return "Timed out while rendering the PDF preview."
            case .invalidSize: return "The rendered PDF preview has an invalid size."
            }
        }
    }
}
