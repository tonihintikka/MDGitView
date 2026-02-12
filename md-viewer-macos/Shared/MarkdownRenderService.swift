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
        guard let data = try? Data(contentsOf: fileURL) else {
            throw MarkdownRenderServiceError.unreadableFile
        }

        guard let markdown = String(data: data, encoding: .utf8) else {
            throw MarkdownRenderServiceError.invalidUTF8
        }

        let baseDirectory = fileURL.deletingLastPathComponent()
        let options = RenderOptions.defaults(baseDirectory: baseDirectory)
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
            baseURL: baseDirectory
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
          <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data: file:; style-src 'unsafe-inline'; script-src 'unsafe-inline';\">
          <style>
          \(css)
          </style>
        </head>
        <body class=\"markdown-body \(theme)\" data-enable-mermaid=\"\(enableMermaid)\" data-enable-math=\"\(enableMath)\">
          <article>
          \(content)
          </article>
          <script>
          \(mermaidJS)
          </script>
          <script>
          \(mathJaxJS)
          </script>
          <script>
          \(shellJS)
          </script>
        </body>
        </html>
        """
    }

    private func loadResource(named: String, ext: String) -> String {
        guard let url = bundle.url(forResource: named, withExtension: ext, subdirectory: "Assets"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return text
    }
}
