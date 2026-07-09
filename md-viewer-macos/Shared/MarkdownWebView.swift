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
        private var isUsingFileURLLoad = false
        private var didFallbackToHTMLString = false

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

            do {
                let tempFile = try prepareTempFile(html: html, in: baseURL)
                isUsingFileURLLoad = true
                didFallbackToHTMLString = false
                webView.loadFileURL(tempFile, allowingReadAccessTo: readAccessURL)
                return true
            } catch {
                // Cannot write to the markdown directory – caller should fall back
                isUsingFileURLLoad = false
                didFallbackToHTMLString = false
                return false
            }
        }

        func prepareTempFile(html: String, in baseURL: URL) throws -> URL {
            cleanupTempFile()

            let tempFile = baseURL.appendingPathComponent(".mdgitview-preview.html")
            try html.write(to: tempFile, atomically: true, encoding: .utf8)
            tempFileURL = tempFile
            return tempFile
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
            isUsingFileURLLoad = false
            if let anchor = pendingAnchor {
                scrollToAnchor(anchor, in: webView)
                pendingAnchor = nil
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            fallbackToHTMLStringIfNeeded(in: webView, error: error)
        }

        func fallbackToHTMLStringIfNeeded(in webView: WKWebView, error: Error) {
            guard isUsingFileURLLoad, !didFallbackToHTMLString else { return }
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            didFallbackToHTMLString = true
            isUsingFileURLLoad = false
            webView.loadHTMLString(parent.htmlDocument, baseURL: parent.baseURL)
            parent.onRequestFolderAccess?()
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
        view.allowsLinkPreview = false
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
