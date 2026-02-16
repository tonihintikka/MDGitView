import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class MarkdownPreviewProvider: QLPreviewProvider {
    private let renderService = MarkdownRenderService()

    func providePreview(
        for request: QLFilePreviewRequest
    ) async throws -> QLPreviewReply {
        let html: String
        do {
            let payload = try await renderService.render(fileURL: request.fileURL)
            html = injectBaseURL(payload.htmlDocument, baseURL: payload.baseURL)
        } catch {
            html = fallbackHTML(for: request.fileURL.lastPathComponent, error: error)
        }

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 800, height: 800)
        ) { replyToUpdate in
            replyToUpdate.stringEncoding = .utf8
            return Data(html.utf8)
        }
        reply.title = request.fileURL.lastPathComponent
        return reply
    }

    private func injectBaseURL(_ html: String, baseURL: URL?) -> String {
        guard let baseURL else {
            return html
        }

        let escapedBase = baseURL.absoluteString
            .replacingOccurrences(of: "\"", with: "&quot;")

        let baseTag = "<base href=\"\(escapedBase)\">"
        if html.contains("<head>") {
            return html.replacingOccurrences(of: "<head>", with: "<head>\n  \(baseTag)")
        }

        if html.contains("<html>") {
            return html.replacingOccurrences(of: "<html>", with: "<html>\n<head>\n  \(baseTag)\n</head>")
        }

        return "<head>\(baseTag)</head>\n\(html)"
    }

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
