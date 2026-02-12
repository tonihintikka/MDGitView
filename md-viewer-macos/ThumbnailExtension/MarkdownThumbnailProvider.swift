import AppKit
import QuickLookThumbnailing

final class MarkdownThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let title = extractTitle(from: request.fileURL) ?? request.fileURL.deletingPathExtension().lastPathComponent
        let subtitle = request.fileURL.lastPathComponent

        let size = request.maximumSize
        let reply = QLThumbnailReply(contextSize: size, currentContextDrawing: { () -> Bool in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            let bounds = CGRect(origin: .zero, size: size)
            context.setFillColor(NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1.0).cgColor)
            context.fill(bounds)

            let card = bounds.insetBy(dx: 18, dy: 18)
            let cardPath = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
            NSColor.white.setFill()
            cardPath.fill()

            NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
            cardPath.lineWidth = 1
            cardPath.stroke()

            draw(
                text: title,
                in: CGRect(x: card.minX + 16, y: card.maxY - 62, width: card.width - 32, height: 46),
                font: .boldSystemFont(ofSize: 18),
                color: NSColor.labelColor
            )

            draw(
                text: subtitle,
                in: CGRect(x: card.minX + 16, y: card.minY + 16, width: card.width - 32, height: 22),
                font: .systemFont(ofSize: 12, weight: .medium),
                color: NSColor.secondaryLabelColor
            )

            draw(
                text: "Markdown",
                in: CGRect(x: card.minX + 16, y: card.minY + 42, width: card.width - 32, height: 20),
                font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                color: NSColor.systemBlue
            )

            return true
        })

        handler(reply, nil)
    }

    private func extractTitle(from fileURL: URL) -> String? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            }
        }

        return content
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
    }

    private func draw(text: String, in frame: CGRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        attributed.draw(in: frame)
    }
}
