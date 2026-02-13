import Foundation

enum MarkdownLinkPolicy {
    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdtxt", "mdtext"
    ]

    private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    static func markdownTargetURL(_ url: URL, currentFileURL: URL?) -> URL? {
        let resolved = resolveURL(url, currentFileURL: currentFileURL)
        guard resolved.isFileURL else { return nil }
        guard markdownExtensions.contains(resolved.pathExtension.lowercased()) else { return nil }
        return resolved
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
