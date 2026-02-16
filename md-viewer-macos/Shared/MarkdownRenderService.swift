import Foundation

enum MarkdownRenderServiceError: LocalizedError {
    case unreadableFile
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Markdown file could not be read."
        case .invalidUTF8:
            return "Markdown file is not UTF-8 encoded."
        }
    }
}

final class MarkdownRenderService {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func render(fileURL: URL) async throws -> RenderedPayload {
        let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw MarkdownRenderServiceError.unreadableFile
        }

        guard let markdown = String(data: data, encoding: .utf8) else {
            throw MarkdownRenderServiceError.invalidUTF8
        }

        let baseDirectory = fileURL.deletingLastPathComponent()
        let allowedRootDirectory = resolveAllowedRootDirectory(for: baseDirectory)
        let options = RenderOptions.defaults(
            baseDirectory: baseDirectory,
            allowedRootDirectory: allowedRootDirectory
        )
        let rendered = try RustMarkdownFFI.render(markdown: markdown, options: options)

        let htmlDocument = buildHTMLDocument(
            content: rendered.html,
            theme: options.theme,
            enableMermaid: options.enable_mermaid,
            enableMath: options.enable_math
        )

        return RenderedPayload(
            htmlDocument: htmlDocument,
            toc: rendered.toc,
            diagnostics: rendered.diagnostics,
            baseURL: baseDirectory,
            allowedRootURL: allowedRootDirectory
        )
    }

    func rawMarkdown(fileURL: URL) -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }

    private func buildHTMLDocument(
        content: String,
        theme: String,
        enableMermaid: Bool,
        enableMath: Bool
    ) -> String {
        let nonce = UUID().uuidString
        let css = loadResource(named: "github-markdown", ext: "css")
        let mermaidJS = loadResource(named: "mermaid.min", ext: "js")
        let mathJaxJS = loadResource(named: "mathjax", ext: "js")
        let shellJS = loadResource(named: "viewer-shell", ext: "js")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\">
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
          <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data: file:; style-src 'unsafe-inline'; script-src 'nonce-\(nonce)';\">
          <style>
          \(css)
          </style>
        </head>
        <body class=\"markdown-body \(theme)\" data-enable-mermaid=\"\(enableMermaid)\" data-enable-math=\"\(enableMath)\">
          <article>
          \(content)
          </article>
          <script nonce=\"\(nonce)\">
          \(mermaidJS)
          </script>
          <script nonce=\"\(nonce)\">
          \(mathJaxJS)
          </script>
          <script nonce=\"\(nonce)\">
          \(shellJS)
          </script>
        </body>
        </html>
        """
    }

    private func loadResource(named: String, ext: String) -> String {
        let candidates: [URL?] = [
            bundle.url(forResource: named, withExtension: ext, subdirectory: "Assets"),
            bundle.url(forResource: named, withExtension: ext)
        ]

        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }

        return ""
    }

    private func resolveAllowedRootDirectory(for baseDirectory: URL) -> URL {
        var cursor = baseDirectory.standardizedFileURL
        let manager = FileManager.default

        while true {
            let gitDirectory = cursor.appendingPathComponent(".git", isDirectory: true)
            if manager.fileExists(atPath: gitDirectory.path) {
                return cursor
            }

            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                return baseDirectory
            }
            cursor = parent
        }
    }
}
