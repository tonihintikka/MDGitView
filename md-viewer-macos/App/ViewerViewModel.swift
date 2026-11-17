import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var baseURL: URL?
    @Published var allowedRootURL: URL?
    @Published var htmlDocument: String = ""
    @Published var rawMarkdown: String = ""
    @Published var diagnostics: [RenderDiagnostic] = []
    @Published var toc: [TocItem] = []
    @Published var requestedAnchor: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var needsFolderAccess = false
    @Published var showDefaultAppBanner = false

    private let renderService = MarkdownRenderService()
    private var backHistory: [URL] = []
    private var forwardHistory: [URL] = []
    private var renderTask: Task<Void, Never>?

    deinit {
        renderTask?.cancel()
    }

    func openDocument(at url: URL) {
        openDocument(at: url, historyAction: .pushCurrent)
    }

    func openDocumentFromPicker(at url: URL) {
        openDocument(at: url, historyAction: .reset)
    }

    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        if let current = fileURL {
            forwardHistory.append(current)
        }
        updateNavigationAvailability()
        openDocument(at: previous, historyAction: .preserve)
    }

    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        if let current = fileURL {
            backHistory.append(current)
        }
        updateNavigationAvailability()
        openDocument(at: next, historyAction: .preserve)
    }

    func navigateToAnchor(_ anchor: String) {
        requestedAnchor = anchor
    }

    func clearAnchorRequest() {
        requestedAnchor = nil
    }

    /// Called when the WebKit scheme handler cannot read a local preview resource.
    /// The folder chooser lets macOS request access before the document is rendered again.
    func requestFolderAccess() {
        needsFolderAccess = true
    }

    func refreshDocument() {
        guard let url = fileURL else { return }
        reloadCurrentDocument(at: url)
    }

    func openInExternalEditor() {
        guard let url = fileURL else { return }
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/open")
        task.arguments = ["-t", url.path]
        try? task.run()
    }

    func revealInFinder() {
        guard let url = fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Default App Check

    func checkIfDefaultMarkdownViewer() {
        showDefaultAppBanner = !isDefaultMarkdownViewer()
    }

    func setAsDefaultMarkdownViewer() {
        guard let markdownType = UTType("net.daringfireball.markdown") else { return }
        let appURL = Bundle.main.bundleURL

        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: appURL,
                    toOpen: markdownType
                )
                showDefaultAppBanner = false
            } catch {
                NSLog("Failed to set default app: \(error.localizedDescription)")
            }
        }
    }

    func dismissDefaultAppBanner() {
        showDefaultAppBanner = false
    }

    private func isDefaultMarkdownViewer() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let markdownType = UTType("net.daringfireball.markdown") else { return false }

        guard let defaultAppURL = NSWorkspace.shared.urlForApplication(
            toOpen: markdownType
        ) else { return false }

        let defaultBundleID = Bundle(url: defaultAppURL)?.bundleIdentifier
        return defaultBundleID == bundleID
    }

    func grantFolderAccess() {
        guard let directory = allowedRootURL ?? baseURL else { return }

        let panel = NSOpenPanel()
        panel.message = "MDGitView needs access to this folder to display images."
        panel.prompt = "Allow"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.canCreateDirectories = false

        panel.begin { [weak self] response in
            guard let self, response == .OK, let _ = panel.url else { return }
            Task { @MainActor in
                self.needsFolderAccess = false
                // Re-render to trigger a new loadFileURL attempt with the granted access
                if let fileURL = self.fileURL {
                    self.reloadCurrentDocument(at: fileURL)
                }
            }
        }
    }

    private func reloadCurrentDocument(at url: URL) {
        renderTask?.cancel()
        isLoading = true
        errorMessage = nil

        renderTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.renderService.render(fileURL: url)
                if Task.isCancelled { return }

                self.apply(payload)
                self.isLoading = false
                self.cacheQuickLookPDF(payload, for: url)
            } catch {
                if Task.isCancelled { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private enum HistoryAction {
        case pushCurrent
        case reset
        case preserve
    }

    private func openDocument(at targetURL: URL, historyAction: HistoryAction) {
        let normalizedURL = normalizedFileURL(targetURL)
        let anchor = normalizedAnchor(from: targetURL)

        if isSameDocument(lhs: normalizedURL, rhs: fileURL) {
            if let anchor {
                requestedAnchor = anchor
            }
            return
        }

        switch historyAction {
        case .pushCurrent:
            if let current = fileURL, !isSameDocument(lhs: normalizedURL, rhs: current) {
                backHistory.append(current)
            }
            forwardHistory.removeAll()
        case .reset:
            backHistory.removeAll()
            forwardHistory.removeAll()
        case .preserve:
            break
        }
        updateNavigationAvailability()

        renderTask?.cancel()
        fileURL = normalizedURL
        baseURL = nil
        requestedAnchor = nil
        isLoading = true
        errorMessage = nil

        renderTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.renderService.render(fileURL: normalizedURL)
                if Task.isCancelled { return }

                self.apply(payload)
                self.requestedAnchor = anchor
                self.isLoading = false
                self.cacheQuickLookPDF(payload, for: normalizedURL)
            } catch {
                if Task.isCancelled { return }

                self.errorMessage = error.localizedDescription
                self.rawMarkdown = self.renderService.rawMarkdown(fileURL: normalizedURL) ?? ""
                self.htmlDocument = ""
                self.diagnostics = []
                self.toc = []
                self.baseURL = nil
                self.allowedRootURL = nil
                self.requestedAnchor = nil
                self.isLoading = false
            }
        }
    }

    private func apply(_ payload: RenderedPayload) {
        htmlDocument = payload.htmlDocument
        rawMarkdown = ""
        diagnostics = payload.diagnostics
        toc = payload.toc
        baseURL = payload.baseURL
        allowedRootURL = payload.allowedRootURL
    }

    private func cacheQuickLookPDF(_ payload: RenderedPayload, for url: URL) {
        guard let sourceData = try? Data(contentsOf: url) else {
            NSLog("Quick Look PDF cache skipped: source could not be read")
            return
        }
        Task { @MainActor in
            do {
                NSLog("Quick Look PDF cache: rendering %{public}@", url.lastPathComponent)
                let pdfCacheRenderer = PreviewPDFRenderer()
                let pdf = try await pdfCacheRenderer.render(payload)
                try PreviewPDFCache.write(pdf, for: url, sourceData: sourceData)
                NSLog("Quick Look PDF cache: wrote %{public}@ (%d bytes)", url.lastPathComponent, pdf.count)
            } catch {
                NSLog("Quick Look PDF cache skipped: %{public}@", error.localizedDescription)
            }
        }
    }

    private func updateNavigationAvailability() {
        canGoBack = !backHistory.isEmpty
        canGoForward = !forwardHistory.isEmpty
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return (components?.url ?? url).standardizedFileURL
    }

    private func normalizedAnchor(from url: URL) -> String? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
              !fragment.isEmpty
        else {
            return nil
        }
        return fragment.removingPercentEncoding ?? fragment
    }

    private func isSameDocument(lhs: URL, rhs: URL?) -> Bool {
        guard let rhs else { return false }
        return lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
