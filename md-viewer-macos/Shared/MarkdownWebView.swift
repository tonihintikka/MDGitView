import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let htmlDocument: String
    let baseURL: URL?
    let allowedRootURL: URL?
    let currentFileURL: URL?
    let navigateToAnchor: String?
    let onOpenMarkdownLink: (URL) -> Void
    let onOpenExternalLink: (URL) -> Void
    let onDidNavigateToAnchor: () -> Void
    var onRequestFolderAccess: (() -> Void)?

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MarkdownWebView
        var didLoadDocument = false
        var lastLoadedHTML = ""
        var lastLoadedBaseURL: URL?
        var pendingAnchor: String?
        var lastHandledAnchor: String?
        private var tempFileURL: URL?

        init(parent: MarkdownWebView) {
            self.parent = parent
        }

        deinit {
            cleanupTempFile()
        }

        // MARK: - Temp file management

        func cleanupTempFile() {
            if let url = tempFileURL {
                try? FileManager.default.removeItem(at: url)
                tempFileURL = nil
            }
        }

        /// Write HTML to a temp file and load via loadFileURL for local image access.
        /// Returns true if successful, false if fallback is needed.
        func loadViaFileURL(html: String, baseURL: URL?, allowedRootURL: URL?, in webView: WKWebView) -> Bool {
            guard let baseURL = baseURL else {
                return false
            }

            // Determine the broadest directory the WebView may read from.
            // allowedRootURL (git repo root) covers images referenced via ../
            let readAccessURL = allowedRootURL ?? baseURL

            // Write HTML to a hidden temp file inside the baseURL directory
            let tempFile = baseURL.appendingPathComponent(".mdgitview-preview.html")
            do {
                try html.write(to: tempFile, atomically: true, encoding: .utf8)
            } catch {
                // Cannot write to the markdown directory – caller should fall back
                return false
            }

            cleanupTempFile()
            tempFileURL = tempFile
            webView.loadFileURL(tempFile, allowingReadAccessTo: readAccessURL)
            return true
        }

        // MARK: - WKNavigationDelegate

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

            if MarkdownLinkPolicy.isInPageAnchor(targetURL, currentFileURL: parent.currentFileURL) {
                decisionHandler(.allow)
                return
            }

            if let markdownTargetURL = MarkdownLinkPolicy.markdownTargetURL(
                targetURL,
                currentFileURL: parent.currentFileURL
            ) {
                parent.onOpenMarkdownLink(markdownTargetURL)
                decisionHandler(.cancel)
                return
            }

            if MarkdownLinkPolicy.isExternalLink(targetURL) {
                parent.onOpenExternalLink(targetURL)
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

            if MarkdownLinkPolicy.isInPageAnchor(targetURL, currentFileURL: parent.currentFileURL) {
                webView.load(navigationAction.request)
                return nil
            }

            if let markdownTargetURL = MarkdownLinkPolicy.markdownTargetURL(
                targetURL,
                currentFileURL: parent.currentFileURL
            ) {
                parent.onOpenMarkdownLink(markdownTargetURL)
                return nil
            }

            if MarkdownLinkPolicy.isExternalLink(targetURL) {
                parent.onOpenExternalLink(targetURL)
                return nil
            }

            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoadDocument = true
            if let anchor = pendingAnchor {
                scrollToAnchor(anchor, in: webView)
                pendingAnchor = nil
            }
        }

        // MARK: - Anchor scrolling

        func scrollToAnchor(_ anchor: String, in webView: WKWebView) {
            let escapedAnchor = anchor
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let script = """
            (function() {
              var id = "\(escapedAnchor)";
              var node = document.getElementById(id);
              if (!node) { return false; }
              node.scrollIntoView({behavior: "smooth", block: "start"});
              window.location.hash = id;
              return true;
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                if let moved = result as? Bool, moved {
                    self.lastHandledAnchor = anchor
                    self.parent.onDidNavigateToAnchor()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let shouldReload = context.coordinator.lastLoadedHTML != htmlDocument
            || context.coordinator.lastLoadedBaseURL != baseURL

        if shouldReload {
            context.coordinator.lastLoadedHTML = htmlDocument
            context.coordinator.lastLoadedBaseURL = baseURL
            context.coordinator.didLoadDocument = false
            context.coordinator.pendingAnchor = navigateToAnchor
            context.coordinator.lastHandledAnchor = nil

            // Try loadFileURL first (enables local image loading)
            let loaded = context.coordinator.loadViaFileURL(
                html: htmlDocument,
                baseURL: baseURL,
                allowedRootURL: allowedRootURL,
                in: webView
            )

            if !loaded {
                // Fallback: loadHTMLString (images won't show, but text renders)
                webView.loadHTMLString(htmlDocument, baseURL: baseURL)
                // Notify that folder access is needed
                onRequestFolderAccess?()
            }
            return
        }

        guard let anchor = navigateToAnchor else { return }
        guard context.coordinator.lastHandledAnchor != anchor else { return }

        if context.coordinator.didLoadDocument {
            context.coordinator.scrollToAnchor(anchor, in: webView)
        } else {
            context.coordinator.pendingAnchor = anchor
        }
    }
}
