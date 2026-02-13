import Foundation

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var baseURL: URL?
    @Published var htmlDocument: String = ""
    @Published var rawMarkdown: String = ""
    @Published var diagnostics: [RenderDiagnostic] = []
    @Published var toc: [TocItem] = []
    @Published var requestedAnchor: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false

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

                self.htmlDocument = payload.htmlDocument
                self.rawMarkdown = ""
                self.diagnostics = payload.diagnostics
                self.toc = payload.toc
                self.baseURL = payload.baseURL
                self.requestedAnchor = anchor
                self.isLoading = false
            } catch {
                if Task.isCancelled { return }

                self.errorMessage = error.localizedDescription
                self.rawMarkdown = self.renderService.rawMarkdown(fileURL: normalizedURL) ?? ""
                self.htmlDocument = ""
                self.diagnostics = []
                self.toc = []
                self.baseURL = nil
                self.requestedAnchor = nil
                self.isLoading = false
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
