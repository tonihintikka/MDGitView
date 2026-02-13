import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let htmlDocument: String
    let baseURL: URL?
    let currentFileURL: URL?
    let navigateToAnchor: String?
    let onOpenMarkdownLink: (URL) -> Void
    let onOpenExternalLink: (URL) -> Void
    let onDidNavigateToAnchor: () -> Void

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MarkdownWebView
        var didLoadDocument = false
        var lastLoadedHTML = ""
        var lastLoadedBaseURL: URL?
        var pendingAnchor: String?
        var lastHandledAnchor: String?

        init(parent: MarkdownWebView) {
            self.parent = parent
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
            webView.loadHTMLString(htmlDocument, baseURL: baseURL)
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
