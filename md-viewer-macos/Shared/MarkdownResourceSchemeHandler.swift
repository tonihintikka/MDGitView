import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves generated preview documents, bundled assets, and permitted local resources
/// without writing generated HTML into the user's document directory.
final class MarkdownResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdgitview"

    private struct Document {
        let html: String
        let documentPath: String
        let allowedRootDirectory: URL
    }

    private static let runtimeAssetCache = RuntimeAssetCache()

    var onAccessDenied: (() -> Void)?

    private var documents: [String: Document] = [:]
    private let lock = NSLock()

    func register(
        html: String,
        baseDirectory: URL?,
        allowedRootDirectory: URL?
    ) -> (identifier: String, url: URL)? {
        guard let baseDirectory else { return nil }

        let identifier = UUID().uuidString.lowercased()
        let baseDir = baseDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let allowedRoot = (allowedRootDirectory ?? baseDir).standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let basePath = baseDir.path
        let rootPath = allowedRoot.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard basePath == rootPath || basePath.hasPrefix(rootPrefix) else { return nil }

        let relativeBasePath = basePath == rootPath
            ? ""
            : String(basePath.dropFirst(rootPrefix.count))
        let documentPath = ["__root__", relativeBasePath, "index.html"]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        var baseComponents = URLComponents()
        baseComponents.scheme = Self.scheme
        baseComponents.host = identifier
        baseComponents.path = "/__root__/\(relativeBasePath.isEmpty ? "" : relativeBasePath + "/")"
        guard let baseURL = baseComponents.url else { return nil }
        let baseTag = "<base href=\"\(baseURL.absoluteString)\">"
        let documentHTML = html
            .replacingOccurrences(
                of: "mdgitview://runtime/",
                with: "mdgitview://\(identifier)/__runtime/",
                options: .literal
            )
            .replacingOccurrences(
            of: "<head>",
            with: "<head>\n  \(baseTag)",
            options: .literal
        )

        lock.lock()
        documents[identifier] = Document(
            html: documentHTML,
            documentPath: documentPath,
            allowedRootDirectory: allowedRoot
        )
        lock.unlock()

        var documentComponents = baseComponents
        documentComponents.path += "index.html"
        guard let url = documentComponents.url else {
            unregister(identifier: identifier)
            return nil
        }
        return (identifier, url)
    }

    func unregister(identifier: String?) {
        guard let identifier else { return }
        lock.lock()
        documents.removeValue(forKey: identifier)
        lock.unlock()
    }

    func localFileURL(for url: URL) -> URL? {
        guard url.scheme == Self.scheme,
              let components = decodedPathComponents(for: url),
              components.count >= 2,
              components[0] == "__root__",
              let identifier = url.host,
              let document = document(identifier: identifier) else {
            return nil
        }

        let relativePath = components.dropFirst().joined(separator: "/")
        guard !relativePath.isEmpty, relativePath != document.documentPath.dropFirst("__root__/".count) else {
            return nil
        }
        return permittedFileURL(relativePath, in: document)
    }

    func isDocumentURL(_ url: URL, identifier: String?) -> Bool {
        guard let identifier,
              url.scheme == Self.scheme,
              url.host == identifier,
              let components = decodedPathComponents(for: url) else {
            return false
        }
        return components.joined(separator: "/") == identifierDocumentPath(identifier: identifier)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == Self.scheme,
              let components = decodedPathComponents(for: url) else {
            fail(urlSchemeTask, code: NSURLErrorUnsupportedURL)
            return
        }

        guard let identifier = url.host,
              let document = document(identifier: identifier) else {
            fail(urlSchemeTask, code: NSURLErrorFileDoesNotExist)
            return
        }

        if components.first == "__runtime" {
            let assetPath = components.dropFirst().joined(separator: "/")
            guard !assetPath.isEmpty,
                  let data = Self.runtimeAssetCache.data(for: assetPath) else {
                fail(urlSchemeTask, code: NSURLErrorFileDoesNotExist)
                return
            }
            respond(to: urlSchemeTask, with: data, mimeType: Self.mimeType(for: assetPath))
            return
        }

        guard components.first == "__root__" else {
            fail(urlSchemeTask, code: NSURLErrorFileDoesNotExist)
            return
        }

        let relativePath = components.dropFirst().joined(separator: "/")
        if components.joined(separator: "/") == document.documentPath {
            respond(
                to: urlSchemeTask,
                with: Data(document.html.utf8),
                mimeType: "text/html"
            )
            return
        }

        guard let fileURL = permittedFileURL(relativePath, in: document) else {
            fail(urlSchemeTask, code: NSURLErrorNoPermissionsToReadFile)
            return
        }

        let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: fileURL)
            respond(to: urlSchemeTask, with: data, mimeType: Self.mimeType(for: fileURL.lastPathComponent))
        } catch {
            if (error as NSError).code == NSFileReadNoPermissionError {
                DispatchQueue.main.async { [weak self] in
                    self?.onAccessDenied?()
                }
            }
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Resource reads are synchronous; no pending work remains to cancel.
    }

    private func document(identifier: String) -> Document? {
        lock.lock()
        defer { lock.unlock() }
        return documents[identifier]
    }

    private func decodedPathComponents(for url: URL) -> [String]? {
        guard let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              let decodedPath = encodedPath.removingPercentEncoding else {
            return nil
        }

        let components = decodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.allSatisfy({ !$0.contains("/") && !$0.contains("\\") }) else {
            return nil
        }
        return components
    }

    private func permittedFileURL(_ relativePath: String, in document: Document) -> URL? {
        let candidate = document.allowedRootDirectory
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = document.allowedRootDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let rootPrefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"

        guard resolvedCandidate.path == resolvedRoot || resolvedCandidate.path.hasPrefix(rootPrefix) else {
            return nil
        }
        return candidate
    }

    private func identifierDocumentPath(identifier: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return documents[identifier]?.documentPath ?? ""
    }

    private func respond(to task: WKURLSchemeTask, with data: Data, mimeType: String) {
        let response = URLResponse(
            url: task.request.url ?? URL(fileURLWithPath: "/"),
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, code: Int) {
        task.didFailWithError(NSError(domain: NSURLErrorDomain, code: code))
    }

    private static func mimeType(for fileName: String) -> String {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        if fileExtension == "js" { return "text/javascript" }
        return UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    private final class RuntimeAssetCache {
        private let lock = NSLock()
        private var cachedData: [String: Data] = [:]

        func data(for relativePath: String) -> Data? {
            let pathComponents = relativePath.split(separator: "/").map(String.init)
            guard !pathComponents.isEmpty,
                  pathComponents.allSatisfy({ $0 != "." && $0 != ".." }) else {
                return nil
            }

            lock.lock()
            defer { lock.unlock() }
            if let data = cachedData[relativePath] {
                return data
            }

            guard let resourcesDirectory = Bundle.main.resourceURL else {
                return nil
            }
            let assetsDirectory = resourcesDirectory.appendingPathComponent("Assets", isDirectory: true)
            let nestedFileURL = pathComponents.reduce(assetsDirectory) { directory, component in
                directory.appendingPathComponent(component)
            }
            let flatFileURL = resourcesDirectory.appendingPathComponent(pathComponents.last!)
            let fileURL = FileManager.default.fileExists(atPath: nestedFileURL.path)
                ? nestedFileURL
                : flatFileURL
            let rootPath = resourcesDirectory.standardizedFileURL.path + "/"
            guard fileURL.standardizedFileURL.path.hasPrefix(rootPath),
                  let data = try? Data(contentsOf: fileURL) else {
                return nil
            }
            cachedData[relativePath] = data
            return data
        }
    }
}
