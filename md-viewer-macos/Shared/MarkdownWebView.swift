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
        var lastLoadedAllowedRootURL: URL?
        var lastLoadedFileURL: URL?
        var pendingAnchor: String?
        var lastHandledAnchor: String?
        let resourceHandler = MarkdownResourceSchemeHandler()
        private var activeDocumentID: String?

        init(parent: MarkdownWebView) {
            self.parent = parent
            super.init()
            resourceHandler.onAccessDenied = { [weak self] in
                self?.parent.onRequestFolderAccess?()
            }
        }

        deinit {
            resourceHandler.unregister(identifier: activeDocumentID)
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

            if isInPageAnchor(targetURL) {
                decisionHandler(.allow)
                return
            }

            if let markdownTargetURL = markdownTargetURL(for: targetURL) {
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

            if isInPageAnchor(targetURL) {
                webView.load(navigationAction.request)
                return nil
            }

            if let markdownTargetURL = markdownTargetURL(for: targetURL) {
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

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            NSLog("Markdown preview load failed: %@", error.localizedDescription)
        }

        func loadDocument(in webView: WKWebView) {
            webView.stopLoading()
            resourceHandler.unregister(identifier: activeDocumentID)
            guard let registered = resourceHandler.register(
                html: parent.htmlDocument,
                baseDirectory: parent.baseURL,
                allowedRootDirectory: parent.allowedRootURL
            ) else {
                parent.onRequestFolderAccess?()
                return
            }

            activeDocumentID = registered.identifier
            webView.load(URLRequest(url: registered.url))
        }

        private func isInPageAnchor(_ url: URL) -> Bool {
            if resourceHandler.isDocumentURL(url, identifier: activeDocumentID),
               !(url.fragment ?? "").isEmpty {
                return true
            }
            return MarkdownLinkPolicy.isInPageAnchor(url, currentFileURL: parent.currentFileURL)
        }

        private func markdownTargetURL(for url: URL) -> URL? {
            if let localURL = resourceHandler.localFileURL(for: url) {
                return MarkdownLinkPolicy.markdownTargetURL(
                    localURL,
                    currentFileURL: parent.currentFileURL
                )
            }
            return MarkdownLinkPolicy.markdownTargetURL(
                url,
                currentFileURL: parent.currentFileURL
            )
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
        configuration.setURLSchemeHandler(
            context.coordinator.resourceHandler,
            forURLScheme: MarkdownResourceSchemeHandler.scheme
        )

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
            || context.coordinator.lastLoadedAllowedRootURL != allowedRootURL
            || context.coordinator.lastLoadedFileURL != currentFileURL

        if shouldReload {
            context.coordinator.lastLoadedHTML = htmlDocument
            context.coordinator.lastLoadedBaseURL = baseURL
            context.coordinator.lastLoadedAllowedRootURL = allowedRootURL
            context.coordinator.lastLoadedFileURL = currentFileURL
            context.coordinator.didLoadDocument = false
            context.coordinator.pendingAnchor = navigateToAnchor
            context.coordinator.lastHandledAnchor = nil

            context.coordinator.loadDocument(in: webView)
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
