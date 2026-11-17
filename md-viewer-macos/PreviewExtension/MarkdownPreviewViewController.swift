import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class MarkdownPreviewProvider: QLPreviewProvider, QLPreviewingController {

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

            if let cachedPDF = PreviewPDFCache.pdfURL(for: fileURL, sourceData: data) {
                NSLog("Quick Look PDF cache hit for %{public}@", fileURL.lastPathComponent)
                let reply = QLPreviewReply(fileURL: cachedPDF)
                reply.title = fileURL.lastPathComponent
                return reply
            }
            NSLog("Quick Look PDF cache miss for %{public}@", fileURL.lastPathComponent)

            let baseDirectory = fileURL.deletingLastPathComponent()
            let options = RenderOptions(
                enable_gfm: true,
                enable_mermaid: false,
                enable_math: true,
                embed_local_images: true,
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
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'; object-src 'none'; img-src data:; style-src 'unsafe-inline';">
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
          .ql-preview-notice, .ql-remote-image {
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 8px 12px;
            font-size: 12px;
            color: var(--muted);
            margin: 8px 0;
            overflow-wrap: anywhere;
          }
          </style>
        </head>
        <body class="markdown-body">
          <article>
          \(previewSourceContent(from: content))
          </article>
        </body>
        </html>
        """
    }

    private func previewSourceContent(from content: String) -> String {
        let mermaidPattern = #"(?s)(<pre><code class="language-mermaid">.*?</code></pre>)"#
        let mermaidNotice = #"$1<div class="ql-mermaid-notice">Diagram rendered in MDGitView app</div>"#
        let withMermaidNotices = content.replacingOccurrences(
            of: mermaidPattern,
            with: mermaidNotice,
            options: .regularExpression
        )

        guard let mathRegex = try? NSRegularExpression(
            pattern: #"(?s)<span class="math math-(inline|display)">(.*?)</span>"#
        ) else {
            return withMermaidNotices
        }

        let range = NSRange(withMermaidNotices.startIndex..., in: withMermaidNotices)
        let matches = mathRegex.matches(in: withMermaidNotices, range: range).reversed()
        var output = withMermaidNotices
        for match in matches {
            guard let kindRange = Range(match.range(at: 1), in: output),
                  let sourceRange = Range(match.range(at: 2), in: output),
                  let fullRange = Range(match.range, in: output) else { continue }
            let kind = String(output[kindRange])
            let source = String(output[sourceRange])
            let sourceBlock = kind == "display"
                ? "<pre><code class=\"ql-math-source\">\(source)</code></pre>"
                : "<code class=\"ql-math-source\">\(source)</code>"
            let notice = "<div class=\"ql-preview-notice\">Math rendered in MDGitView app</div>"
            output.replaceSubrange(fullRange, with: sourceBlock + notice)
        }
        return output
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
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'; object-src 'none'; img-src data:; style-src 'unsafe-inline';">
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
