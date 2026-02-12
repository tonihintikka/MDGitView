import Cocoa
import QuickLookUI
import WebKit

final class MarkdownPreviewViewController: NSViewController, QLPreviewingController {
    private let renderService = MarkdownRenderService()
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    override func loadView() {
        view = NSView()
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        Task {
            do {
                let payload = try await renderService.render(fileURL: url)
                await MainActor.run {
                    self.webView.loadHTMLString(payload.htmlDocument, baseURL: payload.baseURL)
                }
                handler(nil)
            } catch {
                handler(error)
            }
        }
    }
}
