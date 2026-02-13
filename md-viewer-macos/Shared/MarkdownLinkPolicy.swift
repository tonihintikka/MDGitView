import Foundation

enum MarkdownLinkPolicy {
    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdtxt", "mdtext"
    ]

    private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    /// Names to look for when a link points to a directory, checked in order.
    private static let directoryIndexNames = [
        "README.md", "readme.md", "Readme.md",
        "README.markdown", "readme.markdown",
        "INDEX.md", "index.md"
    ]

    static func markdownTargetURL(_ url: URL, currentFileURL: URL?) -> URL? {
        let resolved = resolveURL(url, currentFileURL: currentFileURL)
        guard resolved.isFileURL else { return nil }

        // Direct markdown file link
        if markdownExtensions.contains(resolved.pathExtension.lowercased()) {
            return resolved
        }

        // Directory link — look for a README inside
        if let readmeURL = resolveDirectoryIndex(resolved) {
            return readmeURL
        }

        return nil
    }

    /// If `url` points to a directory, return the first matching README/index file inside it.
    private static func resolveDirectoryIndex(_ url: URL) -> URL? {
        let manager = FileManager.default
        let path = url.path

        var isDir: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            // Path without extension might be a directory that doesn't have a trailing slash.
            // Also try appending nothing — the URL might already be correct but missing on disk.
            return nil
        }

        for name in directoryIndexNames {
            let candidate = url.appendingPathComponent(name)
            if manager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    static func isExternalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return externalSchemes.contains(scheme)
    }

    static func isInPageAnchor(_ url: URL, currentFileURL: URL?) -> Bool {
        guard let currentFileURL else { return false }
        let resolved = resolveURL(url, currentFileURL: currentFileURL)
        guard !((resolved.fragment ?? "").isEmpty) else { return false }

        // Hash-only links can appear without a resolvable file URL.
        if url.absoluteString.hasPrefix("#") {
            return true
        }

        guard resolved.isFileURL else { return false }
        return resolved.standardizedFileURL.path == currentFileURL.standardizedFileURL.path
    }

    private static func resolveURL(_ url: URL, currentFileURL: URL?) -> URL {
        if url.isFileURL {
            return url.standardizedFileURL
        }

        guard url.scheme == nil, let currentFileURL else {
            return url
        }

        let baseDirectory = currentFileURL.deletingLastPathComponent()
        if let resolved = URL(string: url.relativeString, relativeTo: baseDirectory)?.absoluteURL,
           resolved.isFileURL {
            return resolved.standardizedFileURL
        }

        return url
    }
}
