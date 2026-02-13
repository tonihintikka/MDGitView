import Cocoa
import QuickLookUI
import WebKit

final class MarkdownPreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate, WKUIDelegate {
    private let renderService = MarkdownRenderService()
    private var currentFileURL: URL?
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
        webView.navigationDelegate = self
        webView.uiDelegate = self

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        openMarkdownLink(url) { error in
            handler(error)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let targetURL = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }

        if MarkdownLinkPolicy.isInPageAnchor(targetURL, currentFileURL: currentFileURL) {
            decisionHandler(.allow)
            return
        }

        if let markdownTargetURL = MarkdownLinkPolicy.markdownTargetURL(
            targetURL,
            currentFileURL: currentFileURL
        ) {
            openMarkdownLink(markdownTargetURL)
            decisionHandler(.cancel)
            return
        }

        if MarkdownLinkPolicy.isExternalLink(targetURL) {
            // Quick Look preview runs in a constrained extension sandbox.
            // Avoid launching external URLs from here to prevent WebContent
            // launchservices denial churn and connection invalidation.
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let targetURL = navigationAction.request.url else {
            return nil
        }

        if MarkdownLinkPolicy.isInPageAnchor(targetURL, currentFileURL: currentFileURL) {
            webView.load(navigationAction.request)
            return nil
        }

        if let markdownTargetURL = MarkdownLinkPolicy.markdownTargetURL(
            targetURL,
            currentFileURL: currentFileURL
        ) {
            openMarkdownLink(markdownTargetURL)
            return nil
        }

        // Block all non-markdown popup/new-window navigations in preview extension.
        return nil
    }

    private func openMarkdownLink(_ url: URL, completion: ((Error?) -> Void)? = nil) {
        Task {
            do {
                let payload = try await renderService.render(fileURL: url)
                await MainActor.run {
                    self.currentFileURL = url
                    _ = self.webView.loadHTMLString(payload.htmlDocument, baseURL: payload.baseURL)
                    completion?(nil)
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription.replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                    let fallback = """
                    <!doctype html>
                    <html><body style="font-family: -apple-system; padding: 16px;">
                    <h3>Unable to open linked Markdown</h3>
                    <p>\(message)</p>
                    </body></html>
                    """
                    _ = self.webView.loadHTMLString(fallback, baseURL: nil)
                    completion?(error)
                }
            }
        }
    }
}
