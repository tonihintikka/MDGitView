import Foundation

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var baseURL: URL?
    @Published var htmlDocument: String = ""
    @Published var rawMarkdown: String = ""
    @Published var diagnostics: [RenderDiagnostic] = []
    @Published var toc: [TocItem] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let renderService = MarkdownRenderService()

    func openDocument(at url: URL) {
        fileURL = url
        baseURL = nil
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let payload = try await renderService.render(fileURL: url)
                htmlDocument = payload.htmlDocument
                rawMarkdown = ""
                diagnostics = payload.diagnostics
                toc = payload.toc
                baseURL = payload.baseURL
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                rawMarkdown = renderService.rawMarkdown(fileURL: url) ?? ""
                htmlDocument = ""
                diagnostics = []
                toc = []
                baseURL = nil
                isLoading = false
            }
        }
    }
}
