import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class MarkdownPreviewProvider: QLPreviewProvider {

    func providePreview(
        for request: QLFilePreviewRequest
    ) async throws -> QLPreviewReply {
        let fileURL = request.fileURL

        let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let html: String
        do {
            guard let data = try? Data(contentsOf: fileURL),
                  let markdown = String(data: data, encoding: .utf8) else {
                throw MarkdownRenderServiceError.unreadableFile
            }

            let baseDirectory = fileURL.deletingLastPathComponent()
            let options = RenderOptions(
                enable_gfm: true,
                enable_mermaid: false,
                enable_math: false,
                base_dir: baseDirectory.path,
                allowed_root_dir: baseDirectory.path,
                theme: "github-light"
            )

            let rendered = try RustMarkdownFFI.render(markdown: markdown, options: options)
            html = buildPreviewHTML(content: rendered.html, title: fileURL.lastPathComponent)
        } catch {
            html = fallbackHTML(for: fileURL.lastPathComponent, error: error)
        }

        let htmlData = Data(html.utf8)
        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 1200, height: 2400)
        ) { _ in
            htmlData
        }
        reply.stringEncoding = .utf8
        reply.title = fileURL.lastPathComponent
        return reply
    }

    // MARK: - HTML Builder

    private func buildPreviewHTML(content: String, title: String) -> String {
        let css = loadCSS()
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedTitle)</title>
          <style>
          \(css)
          .ql-mermaid-notice {
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 8px 12px;
            font-size: 12px;
            color: var(--muted);
            margin-bottom: 8px;
          }
          </style>
        </head>
        <body class="markdown-body">
          <article>
          \(content)
          </article>
        </body>
        </html>
        """
    }

    private func loadCSS() -> String {
        let bundle = Bundle(for: type(of: self))
        let candidates: [URL?] = [
            bundle.url(forResource: "github-markdown", withExtension: "css", subdirectory: "Assets"),
            bundle.url(forResource: "github-markdown", withExtension: "css")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }

        return ""
    }

    // MARK: - Fallback

    private func fallbackHTML(for fileName: String, error: Error) -> String {
        let escapedMessage = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let escapedFileName = fileName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body style="font-family: -apple-system; padding: 20px;">
          <h3>Preview unavailable</h3>
          <p><strong>File:</strong> \(escapedFileName)</p>
          <p>\(escapedMessage)</p>
        </body>
        </html>
        """
    }
}
